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

- `SQUAT_BASE_MODEL`
- `SQUAT_DEFAULT_MODEL_VARIANT` (e.g. `finetuned` or `base`)
- `SQUAT_FINETUNED_MODEL_PATH` (path from repository root)
- `ALLOWED_ORIGINS` (comma-separated origins; use `*` only for development)
- `API_KEY` (optional but recommended in production)
- `API_KEY_HEADER` (default: `x-api-key`)
- `RATE_LIMIT_PER_MINUTE` (set `0` to disable)
- `RATE_LIMIT_WINDOW_SECONDS`

## Notes

- Ensure finetuned checkpoint files exist on the server before starting.
- Health checks should target `GET /health` for quick deployment validation.
- Protected endpoints enforce optional API key and rate limiting:
  - if `API_KEY` is set, clients must send it in `API_KEY_HEADER`.
- The mobile app expects this backend base URL plus:
  - `/api/v1/feedback/generate`
  - `/api/v1/chat`
- For RunPod deployment steps and service setup, see `DEPLOYMENT.md`.
