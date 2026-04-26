import '../../domain/models/squat_prompt_input.dart';
import '../feature_engineering/squat_input_mapper.dart';
import 'mlkit_pose_extractor.dart';

enum OnDeviceDemoScenario {
  torsoAndKneesForward,
  heelsLiftShallowDepth,
  elbowFlaring,
  cleanRep,
}

class OnDevicePosePipeline {
  OnDevicePosePipeline({
    MlkitPoseExtractor? extractor,
    SquatInputMapper? mapper,
  }) : _extractor = extractor ?? MlkitPoseExtractor(),
       _mapper = mapper ?? SquatInputMapper();

  final MlkitPoseExtractor _extractor;
  final SquatInputMapper _mapper;

  /// Final target architecture:
  /// 1) Extract landmarks on-device with MediaPipe.
  /// 2) Run feature engineering/rules on-device.
  /// 3) Return structured inputs for backend AI feedback.
  ///
  /// Current implementation keeps deterministic demo scenarios so the rest of
  /// the mobile-to-backend contract can be exercised while pose extraction is
  /// integrated in native/mobile layers.
  Future<SquatPromptInput> buildRepInput({
    required OnDeviceDemoScenario scenario,
    int repNumber = 1,
    String bodyType = 'average',
  }) async {
    switch (scenario) {
      case OnDeviceDemoScenario.torsoAndKneesForward:
        return SquatPromptInput(
          repNumber: repNumber,
          bodyType: bodyType,
          heelsLifting: const EventFlag(flag: false),
          torsoForward: const EventFlag(flag: true, torsoHip: 28),
          kneesForward: const EventFlag(flag: true, ankle: 20, heel: 7),
          elbowFlaring: const ElbowFlaringFlag(flag: false),
          depth: 80,
          acceptable: false,
          summaryText:
              'Rep $repNumber: torso leans forward and knees track too far ahead.',
        );
      case OnDeviceDemoScenario.heelsLiftShallowDepth:
        return SquatPromptInput(
          repNumber: repNumber,
          bodyType: bodyType,
          heelsLifting: const EventFlag(flag: true, ankle: 24, heel: 15),
          torsoForward: const EventFlag(flag: false),
          kneesForward: const EventFlag(flag: false),
          elbowFlaring: const ElbowFlaringFlag(flag: false),
          depth: 48,
          acceptable: false,
          summaryText:
              'Rep $repNumber: heels rise and squat is too shallow; balance shifts forward.',
        );
      case OnDeviceDemoScenario.elbowFlaring:
        return SquatPromptInput(
          repNumber: repNumber,
          bodyType: bodyType,
          heelsLifting: const EventFlag(flag: false),
          torsoForward: const EventFlag(flag: false),
          kneesForward: const EventFlag(flag: false),
          elbowFlaring: const ElbowFlaringFlag(flag: true, minAngle: 19),
          depth: 92,
          acceptable: false,
          summaryText: 'Rep $repNumber: depth is good but elbows flare out.',
        );
      case OnDeviceDemoScenario.cleanRep:
        return SquatPromptInput(
          repNumber: repNumber,
          bodyType: bodyType,
          heelsLifting: const EventFlag(flag: false),
          torsoForward: const EventFlag(flag: false),
          kneesForward: const EventFlag(flag: false),
          elbowFlaring: const ElbowFlaringFlag(flag: false),
          depth: 96,
          acceptable: true,
          summaryText:
              'Rep $repNumber: stable torso, proper depth, and balanced knee tracking.',
        );
    }
  }

  Future<SquatPromptInput> buildRepInputFromImagePath({
    required String imagePath,
    int repNumber = 1,
    String bodyType = 'average',
  }) async {
    final pose = await _extractor.extractPoseFromImagePath(imagePath);
    if (pose == null) {
      throw StateError('No person pose detected in the selected image.');
    }
    return _mapper.fromPose(
      pose: pose,
      repNumber: repNumber,
      bodyType: bodyType,
    );
  }

  Future<void> dispose() => _extractor.dispose();
}
