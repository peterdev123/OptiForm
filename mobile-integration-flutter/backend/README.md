# Backend Integration Notes

For MVP, keep heavy language model inference outside mobile.

## Endpoint Contract

- Input: structured payload that conforms to `contracts/squat_prompt_input_schema.json`.
- Output: generated coaching feedback text and optional issue tags.

## Recommended Endpoint Shape

- `POST /api/v1/feedback/generate`
- Request body:
  - `instruction`
  - `input_summary` (from structured payload)
  - `model_variant` (base or finetuned)
- Response body:
  - `feedback_text`
  - `model_name`
  - `latency_ms`

## Reliability Requirements

- Timeout handling in mobile client.
- Fallback to rule-based text if API fails.
- Basic request/response logging for debugging.
