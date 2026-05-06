# Backend (Deployable Unit)

This folder is now organized as a standalone backend deployment unit for the
mobile app.

## Files

- `app.py` - stable ASGI entrypoint (`app:app`) used by uvicorn/systemd/docker.
- `dev_api.py` - current implementation of API routes and inference behavior.
- `requirements.txt` - backend-only dependency list.
- `.env.example` - starter environment variables for deployment.
- `Dockerfile` - container entrypoint for backend service.

## API Endpoints

- `GET /health` - process is up (responds immediately).
- `GET /health/ready` - default model finished loading (503 until ready, unless warmup skipped).
- `POST /api/v1/feedback/generate`
- `POST /api/v1/chat`

## Local Run

From this directory:

```bash
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate
pip install -r requirements.txt
uvicorn app:app --host 0.0.0.0 --port 8000
```

## Deployment Start Command

```bash
uvicorn app:app --host 0.0.0.0 --port 8000
```

## Environment Variables

Set these in your deployment environment:

- `SQUAT_QWEN_BASE_MODEL` (optional; falls back to `SQUAT_BASE_MODEL` then a default HF id)
- `SQUAT_DEFAULT_MODEL_VARIANT` (`finetuned` or `base`; default `finetuned`)
- `SQUAT_FINETUNED_MODEL_PATH` (path from repository root to LoRA checkpoint)
- `SKIP_MODEL_WARMUP` (`true` / `1` to disable startup preload; first request loads the model)
- `MODEL_WARMUP_BLOCKING` (`true` / `1` to block server readiness until load finishes; use with care for health probes)
- `ALLOWED_ORIGINS` (comma-separated origins; use `*` only for development)
- `RATE_LIMIT_PER_MINUTE` (set `0` to disable)
- `RATE_LIMIT_WINDOW_SECONDS`

## Notes

- Ensure finetuned checkpoint files exist on the server before starting.
- By default the server **preloads** the default variant in a background thread when the process starts, so the first mobile analysis is not paying full load time.
- For orchestrators that must wait for the GPU model, poll `GET /health/ready` until it returns 200.
- Inference uses **Qwen** only (`finetuned` with LoRA, or `base` without).
- Protected endpoints enforce rate limiting (per client IP).
- The mobile app expects this backend base URL plus:
  - `/api/v1/feedback/generate`
  - `/api/v1/chat`
- For RunPod deployment steps and service setup, see `DEPLOYMENT.md`.
