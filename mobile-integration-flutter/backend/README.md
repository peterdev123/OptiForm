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

- `GET /health`
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

- `SQUAT_QWEN_BASE_MODEL`
- `SQUAT_MISTRAL_BASE_MODEL`
- `SQUAT_MISTRAL_LORA_PATH` (optional path from repository root)
- `SQUAT_DEFAULT_MODEL_VARIANT` (`model_1` for Qwen, `model_2` for Mistral7B)
- `SQUAT_FINETUNED_MODEL_PATH` (path from repository root)
- `ALLOWED_ORIGINS` (comma-separated origins; use `*` only for development)
- `RATE_LIMIT_PER_MINUTE` (set `0` to disable)
- `RATE_LIMIT_WINDOW_SECONDS`

## Notes

- Ensure finetuned checkpoint files exist on the server before starting.
- Health checks should target `GET /health` for quick deployment validation.
- Protected endpoints enforce rate limiting (per client IP).
- Mobile model choices:
  - `model_1` -> Qwen 2.5 (with LoRA path if available)
  - `model_2` -> Mistral 7B (uses `SQUAT_MISTRAL_LORA_PATH` when set)
- The mobile app expects this backend base URL plus:
  - `/api/v1/feedback/generate`
  - `/api/v1/chat`
- For RunPod deployment steps and service setup, see `DEPLOYMENT.md`.
