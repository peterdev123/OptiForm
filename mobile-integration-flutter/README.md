# Mobile Integration (Flutter)

This folder is a clean workspace for the mobile version of the squat analysis system.

## Purpose

The mobile implementation must preserve the same snapshot-based pose estimation and structured prompt input format used in the current project. This keeps the AI feedback logic compatible with existing prompt templates and fine-tuned behavior.

## High-Level Scope

- Recorded video input (not live real-time).
- Frame-by-frame pose extraction using MediaPipe.
- Same feature engineering and threshold logic as desktop pipeline.
- Same structured prompt input schema for LLM feedback.
- AI feedback integrated through API (recommended MVP path).

## Folder Structure

- `docs/` methodology, parity checklist, and implementation plan.
- `contracts/` shared schemas for structured data exchange.
- `app/` Flutter app workspace notes and setup.
- `backend/` API integration notes.

## Suggested First Implementation Order

1. Define and lock structured schema in `contracts/`.
2. Build Flutter video import + frame extraction.
3. Integrate MediaPipe pose and per-frame landmark capture.
4. Port feature calculations and rule thresholds.
5. Produce prompt-ready structured payload.
6. Connect to LLM endpoint and show feedback.
7. Run parity tests against desktop outputs.
