import os
import re
import sys
import tempfile
import time
from collections import defaultdict, deque
from pathlib import Path
from threading import Lock
from typing import Any, Dict, List, Optional, Tuple

import cv2
from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

DEFAULT_MODEL_VARIANT = os.getenv("SQUAT_DEFAULT_MODEL_VARIANT", "finetuned")
FINETUNED_MODEL_RELATIVE_PATH = os.getenv(
    "SQUAT_FINETUNED_MODEL_PATH",
    "Fine-Tuning/qwen2p5-3b-squat-lora/qwen2p5-3b-squat-lora/checkpoint-450",
)
ALLOWED_ORIGINS_RAW = os.getenv("ALLOWED_ORIGINS", "*")
ALLOWED_ORIGINS = [
    origin.strip() for origin in ALLOWED_ORIGINS_RAW.split(",") if origin.strip()
]
if not ALLOWED_ORIGINS:
    ALLOWED_ORIGINS = ["*"]
API_KEY = os.getenv("API_KEY", "").strip()
RATE_LIMIT_PER_MINUTE = int(os.getenv("RATE_LIMIT_PER_MINUTE", "30"))
RATE_LIMIT_WINDOW_SECONDS = int(os.getenv("RATE_LIMIT_WINDOW_SECONDS", "60"))
API_KEY_HEADER = os.getenv("API_KEY_HEADER", "x-api-key").strip().lower()
_rate_limit_hits: Dict[str, deque[float]] = defaultdict(deque)
_rate_limit_lock = Lock()

app = FastAPI()
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

BASE_MODEL = os.getenv(
    "SQUAT_BASE_MODEL",
    "unsloth/qwen2.5-3b-instruct-unsloth-bnb-4bit",
)
MODEL_VARIANTS = {
    "finetuned": FINETUNED_MODEL_RELATIVE_PATH,
    "base": None,
}
DATASET_STYLE_INSTRUCTION = """You are an expert back squat coach. Using only the squat data (body type, heels, torso, knees, elbows, depth, acceptable), reply in exactly this format and nothing else:

Overall: <short sentence whether it is acceptable or needs work>

Issues:
- <issue 1>
- <issue 2>

Tips:
- <tip 1>
- <tip 2>"""

_model_cache: Dict[str, Tuple[Any, Any]] = {}
_model_lock = Lock()


@app.get("/health")
def health() -> Dict[str, str]:
    return {"status": "ok"}


def _require_api_key(request: Request) -> None:
    if not API_KEY:
        return
    provided = request.headers.get(API_KEY_HEADER)
    if provided == API_KEY:
        return
    raise HTTPException(status_code=401, detail="Invalid API key.")


def _enforce_rate_limit(request: Request) -> None:
    if RATE_LIMIT_PER_MINUTE <= 0:
        return
    now = time.time()
    client_host = request.client.host if request.client else "unknown"
    with _rate_limit_lock:
        window = _rate_limit_hits[client_host]
        while window and now - window[0] > RATE_LIMIT_WINDOW_SECONDS:
            window.popleft()
        if len(window) >= RATE_LIMIT_PER_MINUTE:
            raise HTTPException(
                status_code=429,
                detail="Rate limit exceeded. Try again shortly.",
            )
        window.append(now)


class FeedbackRequest(BaseModel):
    instruction: str
    input_summary: str
    model_variant: str = DEFAULT_MODEL_VARIANT
    structured_input: Dict[str, Any]


class ChatRequest(BaseModel):
    question: str
    model_variant: str = DEFAULT_MODEL_VARIANT
    body_type: str = "N/A"
    recent_rep_summaries: List[str] = []


def _project_root() -> Path:
    # backend/dev_api.py -> mobile-integration-flutter -> repository root
    return Path(__file__).resolve().parents[2]


PROJECT_ROOT = _project_root()
if str(PROJECT_ROOT) not in sys.path:
    sys.path.append(str(PROJECT_ROOT))


def _format_structured_input(data: Dict[str, Any]) -> str:
    lines = []
    for key, value in data.items():
        label = key.replace("_", " ").title()
        lines.append(f"{label}: {value}")
    return "\n".join(lines)


def _flag_text(value: Any) -> str:
    return "TRUE" if bool(value) else "FALSE"


def _dataset_style_input(data: Dict[str, Any]) -> str:
    body_type = str(data.get("body_type", "Unknown")).replace("_", " ").title()
    heels_lifting = _flag_text((data.get("heels_lifting") or {}).get("flag"))
    torso_forward = _flag_text((data.get("torso_forward") or {}).get("flag"))
    knees_forward = _flag_text((data.get("knees_forward") or {}).get("flag"))
    elbow_flaring = _flag_text((data.get("elbow_flaring") or {}).get("flag"))
    depth = data.get("depth", "Unknown")
    acceptable = _flag_text(data.get("acceptable"))

    return (
        f"Body Type: {body_type}\n"
        f"Heels Lifting: {heels_lifting}\n"
        f"Torso Forward: {torso_forward}\n"
        f"Knees Forward: {knees_forward}\n"
        f"Elbow Flaring: {elbow_flaring}\n"
        f"Depth: {depth}\n"
        f"Acceptable: {acceptable}"
    )


def _coerce_output_format(text: str) -> str:
    if "Overall:" in text and "Issues:" in text and "Tips:" in text:
        return text.strip()

    cleaned = text.strip() or "Needs work - form issues detected."
    return (
        f"Overall: {cleaned}\n\n"
        "Issues:\n"
        "- Form deviations detected from the provided squat input.\n"
        "- Review torso, knees, heels, elbows, and depth cues.\n\n"
        "Tips:\n"
        "- Keep your chest up, stay balanced over mid-foot, and control descent.\n"
        "- Focus on depth consistency and smooth, stable reps."
    )


def _parse_event_flag(value: str) -> Dict[str, Any]:
    cleaned = value.strip()
    if cleaned.startswith("TRUE"):
        match = re.search(r"torso-hip:\s*(-?\d+),\s*ankle:\s*(-?\d+),\s*heel:\s*(-?\d+)", cleaned)
        if match:
            return {
                "flag": True,
                "torso_hip": int(match.group(1)),
                "ankle": int(match.group(2)),
                "heel": int(match.group(3)),
            }
        return {"flag": True}
    return {"flag": False}


def _parse_elbow_flag(value: str) -> Dict[str, Any]:
    cleaned = value.strip()
    if cleaned.startswith("TRUE"):
        match = re.search(r"\((\-?\d+)\)", cleaned)
        if match:
            return {"flag": True, "min_angle": int(match.group(1))}
        return {"flag": True}
    return {"flag": False}


def _summary_to_structured_input(summary: str) -> Dict[str, Any]:
    parsed: Dict[str, str] = {}
    for line in summary.splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        parsed[key.strip()] = value.strip()

    return {
        "rep_number": int(parsed.get("Rep Number", "0") or 0),
        "body_type": parsed.get("Body Type", "N/A"),
        "heels_lifting": _parse_event_flag(parsed.get("Heels Lifting", "FALSE")),
        "torso_forward": _parse_event_flag(parsed.get("Torso Forward", "FALSE")),
        "knees_forward": _parse_event_flag(parsed.get("Knees Forward", "FALSE")),
        "elbow_flaring": _parse_elbow_flag(parsed.get("Elbow Flaring", "FALSE")),
        "depth": int(parsed.get("Depth", "0") or 0),
        "acceptable": parsed.get("Acceptable", "FALSE").upper().startswith("TRUE"),
        "summary_text": summary.replace("\n", " | "),
    }


def _resolve_lora_path(model_variant: str) -> Optional[str]:
    fallback_variant = (
        DEFAULT_MODEL_VARIANT
        if DEFAULT_MODEL_VARIANT in MODEL_VARIANTS
        else "finetuned"
    )
    relative_path = MODEL_VARIANTS.get(model_variant, MODEL_VARIANTS[fallback_variant])
    if relative_path is None:
        return None
    absolute_path = (_project_root() / relative_path).resolve()
    return str(absolute_path)


def _resolve_variant_or_default(requested_variant: str) -> str:
    if requested_variant in MODEL_VARIANTS:
        return requested_variant
    if DEFAULT_MODEL_VARIANT in MODEL_VARIANTS:
        return DEFAULT_MODEL_VARIANT
    return "finetuned"


def _load_runtime_model(model_variant: str) -> Tuple[Any, Any]:
    with _model_lock:
        if model_variant in _model_cache:
            return _model_cache[model_variant]

        from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig
        from peft import PeftModel
        import torch

        tokenizer = AutoTokenizer.from_pretrained(BASE_MODEL, trust_remote_code=True)
        if tokenizer.pad_token is None:
            tokenizer.pad_token = tokenizer.eos_token
            tokenizer.pad_token_id = tokenizer.eos_token_id

        bnb_config = BitsAndBytesConfig(
            load_in_4bit=True,
            bnb_4bit_quant_type="nf4",
            bnb_4bit_compute_dtype=torch.float16,
            bnb_4bit_use_double_quant=True,
        )
        model = AutoModelForCausalLM.from_pretrained(
            BASE_MODEL,
            quantization_config=bnb_config,
            device_map="auto",
            trust_remote_code=True,
            torch_dtype=torch.float16,
        )

        lora_path = _resolve_lora_path(model_variant)
        if lora_path:
            model = PeftModel.from_pretrained(model, lora_path)

        model.eval()
        _model_cache[model_variant] = (model, tokenizer)
        return model, tokenizer


def _run_inference(
    instruction: str,
    input_summary: str,
    structured_input: Dict[str, Any],
    model_variant: str,
) -> str:
    model, tokenizer = _load_runtime_model(model_variant)
    prompt_input = _dataset_style_input(structured_input)
    messages = [
        {
            "role": "system",
            "content": DATASET_STYLE_INSTRUCTION,
        },
        {"role": "user", "content": prompt_input},
    ]
    prompt = tokenizer.apply_chat_template(
        messages,
        tokenize=False,
        add_generation_prompt=True,
    )

    import torch

    inputs = tokenizer(prompt, return_tensors="pt").to(model.device)
    with torch.no_grad():
        outputs = model.generate(
            **inputs,
            max_new_tokens=220,
            do_sample=False,
            pad_token_id=tokenizer.eos_token_id,
        )
    generated = tokenizer.decode(
        outputs[0][inputs.input_ids.shape[1]:],
        skip_special_tokens=True,
    ).strip()
    return _coerce_output_format(generated)


def _run_chat_inference(
    question: str,
    body_type: str,
    recent_rep_summaries: List[str],
    model_variant: str,
) -> str:
    model, tokenizer = _load_runtime_model(model_variant)
    recent_text = "\n\n".join(
        f"Rep Context {idx + 1}:\n{summary}"
        for idx, summary in enumerate(recent_rep_summaries[:5])
    ) or "No rep history was provided."
    system_instruction = (
        "You are OptiForm Coach, an expert squat coach assistant. "
        "Use the provided squat history context when available. "
        "Give concise, practical, and safe guidance. "
        "If context is missing, clearly say so and give general best-practice tips."
    )
    user_prompt = (
        f"Body Type: {body_type}\n\n"
        f"Recent Squat Rep Context:\n{recent_text}\n\n"
        f"User Question:\n{question}\n\n"
        "Respond with:\n"
        "1) Direct answer\n"
        "2) Why (based on context)\n"
        "3) 2-3 actionable cues"
    )
    messages = [
        {"role": "system", "content": system_instruction},
        {"role": "user", "content": user_prompt},
    ]
    prompt = tokenizer.apply_chat_template(
        messages,
        tokenize=False,
        add_generation_prompt=True,
    )

    import torch

    inputs = tokenizer(prompt, return_tensors="pt").to(model.device)
    with torch.no_grad():
        outputs = model.generate(
            **inputs,
            max_new_tokens=300,
            do_sample=False,
            pad_token_id=tokenizer.eos_token_id,
        )
    generated = tokenizer.decode(
        outputs[0][inputs.input_ids.shape[1]:],
        skip_special_tokens=True,
    ).strip()
    return generated or "I need a bit more session context to answer precisely."


@app.post("/api/v1/pose/analyze")
async def analyze_pose_video(
    video: UploadFile = File(...),
    mode: str = Form("beginner"),
    body_type: str = Form("N/A"),
):
    from process_frame import ProcessFrame
    from thresholds import get_thresholds_beginner, get_thresholds_pro
    from utils import get_mediapipe_pose

    started = time.perf_counter()
    selected_mode = mode.lower().strip()
    thresholds = get_thresholds_pro() if selected_mode == "pro" else get_thresholds_beginner()

    suffix = Path(video.filename or "uploaded.mp4").suffix or ".mp4"
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    temp_path = temp_file.name

    try:
        temp_file.write(await video.read())
        temp_file.close()

        capture = cv2.VideoCapture(temp_path)
        if not capture.isOpened():
            raise HTTPException(status_code=400, detail="Unable to open uploaded video.")

        processor = ProcessFrame(thresholds=thresholds, body_type=body_type)
        pose = get_mediapipe_pose()

        frame_count = 0
        while True:
            ok, frame = capture.read()
            if not ok:
                break
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            processor.process(rgb, pose)
            frame_count += 1

        capture.release()
        if hasattr(pose, "close"):
            pose.close()

        rep_summaries: List[str] = list(processor.rep_summaries)
        structured_inputs = [_summary_to_structured_input(summary) for summary in rep_summaries]
        latency_ms = int((time.perf_counter() - started) * 1000)

        return {
            "mode": selected_mode,
            "body_type": body_type,
            "frame_count": frame_count,
            "rep_count": len(rep_summaries),
            "rep_summaries": rep_summaries,
            "structured_inputs": structured_inputs,
            "latency_ms": latency_ms,
        }
    finally:
        try:
            os.remove(temp_path)
        except OSError:
            pass

@app.post("/api/v1/feedback/generate")
def generate_feedback(req: FeedbackRequest, request: Request):
    _require_api_key(request)
    _enforce_rate_limit(request)
    started = time.perf_counter()
    variant = _resolve_variant_or_default(req.model_variant)

    try:
        feedback_text = _run_inference(
            instruction=req.instruction,
            input_summary=req.input_summary,
            structured_input=req.structured_input,
            model_variant=variant,
        )
        model_name = f"qwen2.5-3b-{variant}"
    except Exception as exc:
        # Keep mobile integration stable while surfacing useful context for debugging.
        feedback_text = f"Fallback coaching: {req.input_summary}"
        model_name = f"fallback-{variant}"
        print(f"[dev_api] inference failed: {exc}")

    latency_ms = int((time.perf_counter() - started) * 1000)
    return {
        "feedback_text": feedback_text,
        "model_name": model_name,
        "latency_ms": latency_ms,
    }


@app.post("/api/v1/chat")
def chat_coach(req: ChatRequest, request: Request):
    _require_api_key(request)
    _enforce_rate_limit(request)
    started = time.perf_counter()
    variant = _resolve_variant_or_default(req.model_variant)

    try:
        answer_text = _run_chat_inference(
            question=req.question,
            body_type=req.body_type,
            recent_rep_summaries=req.recent_rep_summaries,
            model_variant=variant,
        )
        model_name = f"qwen2.5-3b-{variant}"
    except Exception as exc:
        answer_text = (
            "I could not access the fine-tuned coach right now. "
            "Fallback tip: focus on stable mid-foot balance, controlled depth, and neutral torso."
        )
        model_name = f"fallback-{variant}"
        print(f"[dev_api] chat inference failed: {exc}")

    latency_ms = int((time.perf_counter() - started) * 1000)
    return {
        "answer_text": answer_text,
        "model_name": model_name,
        "latency_ms": latency_ms,
    }