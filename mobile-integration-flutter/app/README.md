# Flutter App Workspace

This directory will hold the mobile app.

## Phase 1 Setup (Windows)

1. Install Flutter SDK and add it to PATH.
2. Run:
   - `flutter doctor`
   - `flutter doctor --android-licenses`
3. In this folder, initialize the app:
   - `flutter create .`
4. Add required dependencies:
   - `flutter pub add image_picker`
   - `flutter pub add video_player`
   - `flutter pub add http`
   - `flutter pub add json_annotation`
   - `flutter pub add path_provider`
   - `flutter pub add permission_handler`
5. Add dev dependencies:
   - `flutter pub add --dev build_runner`
   - `flutter pub add --dev json_serializable`
   - `flutter pub add --dev flutter_lints`

## Recommended Module Structure

- `lib/features/video_input/`
- `lib/features/pose_processing/`
- `lib/features/feature_engineering/`
- `lib/features/rule_engine/`
- `lib/features/ai_feedback/`
- `lib/features/results_view/`
- `lib/shared/`

Keep logic separated:

- `lib/domain/` models and interfaces
- `lib/data/` adapters and repositories
- `lib/presentation/` screens and widgets

## Notes

- MediaPipe integration can be done through a native Android bridge first, then exposed to Flutter via platform channels.
- Keep output format aligned with `../contracts/squat_prompt_input_schema.json`.
