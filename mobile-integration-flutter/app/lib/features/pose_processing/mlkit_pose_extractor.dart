import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class MlkitPoseExtractor {
  MlkitPoseExtractor()
    : _poseDetector = PoseDetector(
        options: PoseDetectorOptions(
          model: PoseDetectionModel.base,
          mode: PoseDetectionMode.single,
        ),
      );

  final PoseDetector _poseDetector;

  Future<Pose?> extractPoseFromImagePath(String imagePath) async {
    final input = InputImage.fromFilePath(imagePath);
    return extractPoseFromInputImage(input);
  }

  Future<Pose?> extractPoseFromInputImage(InputImage input) async {
    final poses = await _poseDetector.processImage(input);
    if (poses.isEmpty) return null;
    return poses.first;
  }

  Future<void> dispose() async {
    await _poseDetector.close();
  }
}
