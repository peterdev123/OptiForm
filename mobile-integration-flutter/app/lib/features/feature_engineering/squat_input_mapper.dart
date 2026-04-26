import 'dart:math' as math;
import 'dart:ui';

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../domain/models/squat_prompt_input.dart';

class SquatInputMapper {
  SquatPromptInput fromPose({
    required Pose pose,
    required int repNumber,
    required String bodyType,
  }) {
    final landmarks = pose.landmarks;

    Offset? landmarkPoint(PoseLandmarkType type) {
      final lm = landmarks[type];
      if (lm == null) return null;
      return Offset(lm.x, lm.y);
    }

    final leftShoulder = landmarkPoint(PoseLandmarkType.leftShoulder);
    final rightShoulder = landmarkPoint(PoseLandmarkType.rightShoulder);
    final leftHip = landmarkPoint(PoseLandmarkType.leftHip);
    final rightHip = landmarkPoint(PoseLandmarkType.rightHip);
    final leftKnee = landmarkPoint(PoseLandmarkType.leftKnee);
    final rightKnee = landmarkPoint(PoseLandmarkType.rightKnee);
    final leftAnkle = landmarkPoint(PoseLandmarkType.leftAnkle);
    final rightAnkle = landmarkPoint(PoseLandmarkType.rightAnkle);
    final leftHeel = landmarkPoint(PoseLandmarkType.leftHeel);
    final rightHeel = landmarkPoint(PoseLandmarkType.rightHeel);
    final leftFoot = landmarkPoint(PoseLandmarkType.leftFootIndex);
    final rightFoot = landmarkPoint(PoseLandmarkType.rightFootIndex);
    final leftElbow = landmarkPoint(PoseLandmarkType.leftElbow);
    final rightElbow = landmarkPoint(PoseLandmarkType.rightElbow);

    final side = _resolveSide(
      leftHip: leftHip,
      leftKnee: leftKnee,
      leftAnkle: leftAnkle,
      rightHip: rightHip,
      rightKnee: rightKnee,
      rightAnkle: rightAnkle,
    );

    final shoulder = side == _Side.left ? leftShoulder : rightShoulder;
    final hip = side == _Side.left ? leftHip : rightHip;
    final knee = side == _Side.left ? leftKnee : rightKnee;
    final ankle = side == _Side.left ? leftAnkle : rightAnkle;
    final heel = side == _Side.left ? leftHeel : rightHeel;
    final foot = side == _Side.left ? leftFoot : rightFoot;
    final elbow = side == _Side.left ? leftElbow : rightElbow;

    if ([shoulder, hip, knee, ankle, heel, foot].any((e) => e == null)) {
      throw StateError('Insufficient landmarks detected for squat mapping.');
    }

    final sh = shoulder!;
    final hp = hip!;
    final kn = knee!;
    final an = ankle!;
    final hl = heel!;
    final ft = foot!;
    final eb = elbow;

    final kneeAngle = _angleDeg(hp, kn, an);
    final depth = (180 - kneeAngle).clamp(0, 140).round();
    final torsoHipAngle = _angleDeg(sh, hp, kn).round();
    final ankleAngle = _angleDeg(kn, an, ft).round();
    final heelLift = (hl.dy - ft.dy).abs().round();

    final torsoForward = torsoHipAngle < 140;
    final kneesForward = _isKneesForward(kn, ft, side);
    final heelsLifting = heelLift > 12;

    int? elbowMinAngle;
    bool elbowFlaring = false;
    if (eb != null) {
      elbowMinAngle = _angleDeg(eb, sh, hp).round();
      elbowFlaring = elbowMinAngle < 35;
    }

    final acceptable =
        !torsoForward &&
        !kneesForward &&
        !heelsLifting &&
        !elbowFlaring &&
        depth >= 75 &&
        depth <= 100;

    final summary = _buildSummary(
      repNumber: repNumber,
      torsoForward: torsoForward,
      kneesForward: kneesForward,
      heelsLifting: heelsLifting,
      elbowFlaring: elbowFlaring,
      acceptable: acceptable,
    );

    return SquatPromptInput(
      repNumber: repNumber,
      bodyType: bodyType,
      heelsLifting: EventFlag(
        flag: heelsLifting,
        torsoHip: torsoHipAngle,
        ankle: ankleAngle,
        heel: heelLift,
      ),
      torsoForward: EventFlag(
        flag: torsoForward,
        torsoHip: torsoHipAngle,
        ankle: ankleAngle,
        heel: heelLift,
      ),
      kneesForward: EventFlag(
        flag: kneesForward,
        torsoHip: torsoHipAngle,
        ankle: ankleAngle,
        heel: heelLift,
      ),
      elbowFlaring: ElbowFlaringFlag(flag: elbowFlaring, minAngle: elbowMinAngle),
      depth: depth,
      acceptable: acceptable,
      summaryText: summary,
    );
  }

  _Side _resolveSide({
    required Offset? leftHip,
    required Offset? leftKnee,
    required Offset? leftAnkle,
    required Offset? rightHip,
    required Offset? rightKnee,
    required Offset? rightAnkle,
  }) {
    final leftReady = leftHip != null && leftKnee != null && leftAnkle != null;
    final rightReady =
        rightHip != null && rightKnee != null && rightAnkle != null;
    if (leftReady && !rightReady) return _Side.left;
    if (rightReady && !leftReady) return _Side.right;
    return _Side.right;
  }

  bool _isKneesForward(Offset knee, Offset foot, _Side side) {
    const tolerancePx = 12.0;
    if (side == _Side.right) {
      return knee.dx > foot.dx + tolerancePx;
    }
    return knee.dx < foot.dx - tolerancePx;
  }

  double _angleDeg(Offset a, Offset b, Offset c) {
    final ab = a - b;
    final cb = c - b;
    final dot = ab.dx * cb.dx + ab.dy * cb.dy;
    final magAb = math.sqrt(ab.dx * ab.dx + ab.dy * ab.dy);
    final magCb = math.sqrt(cb.dx * cb.dx + cb.dy * cb.dy);
    if (magAb == 0 || magCb == 0) return 0;
    final cos = (dot / (magAb * magCb)).clamp(-1.0, 1.0);
    return math.acos(cos) * 180 / math.pi;
  }

  String _buildSummary({
    required int repNumber,
    required bool torsoForward,
    required bool kneesForward,
    required bool heelsLifting,
    required bool elbowFlaring,
    required bool acceptable,
  }) {
    if (acceptable) {
      return 'Rep $repNumber: stable torso, balanced knees and heels, acceptable depth.';
    }
    final issues = <String>[];
    if (torsoForward) issues.add('torso leans forward');
    if (kneesForward) issues.add('knees track too far ahead');
    if (heelsLifting) issues.add('heels lift from the floor');
    if (elbowFlaring) issues.add('elbows flare');
    return 'Rep $repNumber: ${issues.join(', ')}.';
  }
}

enum _Side { left, right }
