"""
LLM Feedback Generator for Streamlit Integration
Loads the fine-tuned model and generates feedback from form summaries
"""

import os
import sys
import torch
from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig
from peft import PeftModel
from peft import __version__ as peft_version

# Add Fine-Tuning directory to path
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

FINE_TUNING_DIR = os.path.join(SCRIPT_DIR, "Fine-Tuning")
sys.path.append(FINE_TUNING_DIR)

# Mistral 7B base model and QLoRA adapter (new fine-tuned squat coach)
BASE_MODEL = "mistralai/Mistral-7B-Instruct-v0.2"
MISTRAL_ADAPTER_DIR = os.path.join(
    SCRIPT_DIR,
    "Fine-Tuning",
    "mistral-7b-squat-lora-main",
    "mistral-7b-squat-lora",
)
LORA_WEIGHTS = MISTRAL_ADAPTER_DIR

# Global model instance (singleton pattern)
_model = None
_tokenizer = None

def load_llm_model():
    global _model, _tokenizer
    
    if _model is not None and _tokenizer is not None:
        return _model, _tokenizer
    
    try:
        # Adapter was produced with newer PEFT; older PEFT can't parse fields like
        # `alora_invocation_tokens` and will crash with a TypeError.
        try:
            from packaging.version import Version
            if Version(peft_version) < Version("0.18.1"):
                raise RuntimeError(
                    f"peft>={ '0.18.1' } is required for this adapter, but found peft=={peft_version}. "
                    f"Upgrade: pip install -U peft"
                )
        except Exception:
            # If packaging isn't available, we just proceed and let PEFT raise.
            pass

        print("Loading Mistral 7B squat-coach QLoRA model...")
        # Load tokenizer from the base model repo.
        # The adapter folder may include a tokenizer.json that is not compatible with the
        # local `tokenizers` build (can error with "ModelWrapper").
        tokenizer = AutoTokenizer.from_pretrained(BASE_MODEL, trust_remote_code=True)

        if tokenizer.pad_token is None:
            tokenizer.pad_token = tokenizer.eos_token
            tokenizer.pad_token_id = tokenizer.eos_token_id

        if torch.cuda.is_available():
            device = "cuda"
            dtype = torch.float16
        else:
            device = "cpu"
            dtype = torch.float32

        # Use 4-bit on GPU for lower VRAM. If VRAM is still insufficient, allow disk offload.
        offload_dir = os.path.join(SCRIPT_DIR, ".hf_offload")
        os.makedirs(offload_dir, exist_ok=True)

        quant_config = None
        if device == "cuda":
            quant_config = BitsAndBytesConfig(
                load_in_4bit=True,
                bnb_4bit_quant_type="nf4",
                bnb_4bit_compute_dtype=torch.float16,
                bnb_4bit_use_double_quant=True,
            )

        model = AutoModelForCausalLM.from_pretrained(
            BASE_MODEL,
            quantization_config=quant_config,
            torch_dtype=dtype,
            device_map="auto" if device == "cuda" else None,
            offload_folder=offload_dir if device == "cuda" else None,
            low_cpu_mem_usage=True,
            trust_remote_code=True,
        )
        model = PeftModel.from_pretrained(model, LORA_WEIGHTS)
        if device == "cpu":
            model.to(device)
        model.eval()

        _model = model
        _tokenizer = tokenizer

        print(f"Model loaded successfully on {device.upper()}")
        return model, tokenizer
    except Exception as e:
        print(f"Error loading model: {e}")
        return None, None

def format_prompt(instruction, input_text):
    """
    Format prompt using the Alpaca-style template used for Qwen fine-tuning:

    ### Instruction:
    {instruction}

    ### Input:
    {input}

    ### Response:
    """
    instruction = instruction.strip()
    if instruction.startswith('"') and instruction.endswith('"'):
        instruction = instruction[1:-1]
    elif instruction.startswith("'") and instruction.endswith("'"):
        instruction = instruction[1:-1]

    input_text = input_text.strip()

    prompt = f"""### Instruction:
{instruction}

### Input:
{input_text}

### Response:
"""
    return prompt

def generate_feedback(form_summary_text, model=None, tokenizer=None):
    """
    Generate LLM feedback from form summary text (optimized for speed)
    
    Args:
        form_summary_text: The text summary from process_frame (e.g., "Body Type: ...")
        model: Pre-loaded model (optional, will load if not provided)
        tokenizer: Pre-loaded tokenizer (optional, will load if not provided)
    
    Returns:
        str: Generated feedback text, or None if model not available
    """
    if model is None or tokenizer is None:
        model, tokenizer = load_llm_model()
    
    if model is None or tokenizer is None:
        return None
    
    instruction = (
        "You are an expert back squat coach. Using only the squat data "
        "(body type, heels, torso, knees, elbows, depth, acceptable), "
        "reply in exactly this format and nothing else:\n\n"
        "Overall: <short sentence about whether the squat is acceptable or needs work>\n\n"
        "Issues:\n"
        "- <issue 1>\n"
        "- <issue 2>\n"
        "(use 'Issues:\\n- None' if there are no issues)\n\n"
        "Tips:\n"
        "- <tip 1>\n"
        "- <tip 2>\n"
        "(use 'Tips:\\n- None' if there are no tips)."
    )
    
    prompt = format_prompt(instruction, form_summary_text)
    
    try:
        inputs = tokenizer(prompt, return_tensors="pt").to(model.device)
        
        with torch.no_grad():
            # Faster generation settings for speed
            outputs = model.generate(
                **inputs,
                max_new_tokens=128,
                temperature=0.3,
                top_p=0.8,
                do_sample=False,
                pad_token_id=tokenizer.eos_token_id,
                eos_token_id=tokenizer.eos_token_id,
                use_cache=True,
                num_beams=1,
            )
        
        # Decode only the new tokens (response part)
        input_length = inputs.input_ids.shape[1]
        response = tokenizer.decode(outputs[0][input_length:], skip_special_tokens=True)
        
        # Clean up any incomplete sentences at the end
        response = response.strip()
        
        # If response ends abruptly, try to find the last complete sentence
        if response and not response.endswith(('.', '!', '?')):
            # Find last complete sentence
            last_period = response.rfind('.')
            last_exclamation = response.rfind('!')
            last_question = response.rfind('?')
            last_sentence_end = max(last_period, last_exclamation, last_question)
            
            if last_sentence_end > len(response) * 0.5:  # Only truncate if we have at least 50% of response
                response = response[:last_sentence_end + 1]
        
        return response
    except Exception as e:
        print(f"Error generating feedback: {e}")
        return None

def generate_feedback_batch(summaries, model=None, tokenizer=None):
    """
    Generate feedback for multiple summaries (can be faster with batching)
    
    Args:
        summaries: List of summary texts
        model: Pre-loaded model (optional)
        tokenizer: Pre-loaded tokenizer (optional)
    
    Returns:
        list: List of feedback strings
    """
    if model is None or tokenizer is None:
        model, tokenizer = load_llm_model()
    
    if model is None or tokenizer is None:
        return [None] * len(summaries)
    
    feedbacks = []
    for summary in summaries:
        feedback = generate_feedback(summary, model, tokenizer)
        feedbacks.append(feedback)
    
    return feedbacks

