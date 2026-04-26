import 'dart:math' as math;
import 'dart:ui';

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class PoseFrameMetrics {
  static const double _kneeToeOffsetRatio = 0.04;
  static const int _kneeToeMinPx = 15;
  static const double _shoulderKneeOffsetRatio = 0.06;
  static const int _shoulderKneeMinPx = 17;

  const PoseFrameMetrics({
    required this.side,
    required this.hipVerticalAngle,
    required this.kneeVerticalAngle,
    required this.ankleVerticalAngle,
    required this.heelLiftDistance,
    required this.heelLiftAngle,
    required this.elbowHorizAngle,
    required this.torsoForward,
    required this.kneePastToes,
    required this.heelsLifting,
  });

  final String side;
  final int hipVerticalAngle;
  final int kneeVerticalAngle;
  final int ankleVerticalAngle;
  final int heelLiftDistance;
  final int heelLiftAngle;
  final int elbowHorizAngle;
  final bool torsoForward;
  final bool kneePastToes;
  final bool heelsLifting;

  static PoseFrameMetrics? fromPose(
    Pose pose, {
    String? preferredSide,
    double? frameWidthPx,
  }) {
    final l = pose.landmarks;
    Offset? p(PoseLandmarkType t) {
      final lm = l[t];
      return lm == null ? null : Offset(lm.x, lm.y);
    }

    final ls = p(PoseLandmarkType.leftShoulder);
    final lh = p(PoseLandmarkType.leftHip);
    final lk = p(PoseLandmarkType.leftKnee);
    final la = p(PoseLandmarkType.leftAnkle);
    final lheel = p(PoseLandmarkType.leftHeel);
    final lfoot = p(PoseLandmarkType.leftFootIndex);
    final lelbow = p(PoseLandmarkType.leftElbow);

    final rs = p(PoseLandmarkType.rightShoulder);
    final rh = p(PoseLandmarkType.rightHip);
    final rk = p(PoseLandmarkType.rightKnee);
    final ra = p(PoseLandmarkType.rightAnkle);
    final rheel = p(PoseLandmarkType.rightHeel);
    final rfoot = p(PoseLandmarkType.rightFootIndex);
    final relbow = p(PoseLandmarkType.rightElbow);

    final leftReady = [ls, lh, lk, la, lheel, lfoot].every((e) => e != null);
    final rightReady = [rs, rh, rk, ra, rheel, rfoot].every((e) => e != null);
    if (!leftReady && !rightReady) return null;

    final side = _resolveSide(
      preferredSide: preferredSide,
      leftReady: leftReady,
      rightReady: rightReady,
    );
    if (side == null) return null;
    final shoulder = side == 'right' ? rs! : ls!;
    final hip = side == 'right' ? rh! : lh!;
    final knee = side == 'right' ? rk! : lk!;
    final ankle = side == 'right' ? ra! : la!;
    final heel = side == 'right' ? rheel! : lheel!;
    final foot = side == 'right' ? rfoot! : lfoot!;
    final elbow = side == 'right' ? relbow : lelbow;

    final hipVerticalAngle = _vertAngle(shoulder, hip);
    final kneeVerticalAngle = _vertAngle(hip, knee);
    final ankleVerticalAngle = _vertAngle(knee, ankle);
    final heelToToeLength = (foot - heel).distance;
    final heelLiftDistance = (heel.dy - foot.dy).abs().round();
    final heelLiftAngle = heelToToeLength < 10 ? 0 : _heelLiftAngle(heel, foot);
    final elbowHorizAngle = elbow == null ? 90 : _horizAngleFromShoulder(elbow, shoulder);
    final kneeToeOffsetPx = math.max(
      _kneeToeMinPx.toDouble(),
      (frameWidthPx ?? 0) * _kneeToeOffsetRatio,
    );
    final shoulderKneeOffsetPx = math.max(
      _shoulderKneeMinPx.toDouble(),
      (frameWidthPx ?? 0) * _shoulderKneeOffsetRatio,
    );
    final shoulderPastKnee = side == 'right'
        ? shoulder.dx > knee.dx + shoulderKneeOffsetPx
        : shoulder.dx < knee.dx - shoulderKneeOffsetPx;

    // Reduce false positives by requiring clear forward shoulder travel too.
    final torsoForward = hipVerticalAngle >= 45 && shoulderPastKnee;
    final kneePastToes = side == 'right'
        ? knee.dx > foot.dx + kneeToeOffsetPx
        : knee.dx < foot.dx - kneeToeOffsetPx;
    final heelsLifting = heelLiftAngle > 25;

    return PoseFrameMetrics(
      side: side,
      hipVerticalAngle: hipVerticalAngle,
      kneeVerticalAngle: kneeVerticalAngle,
      ankleVerticalAngle: ankleVerticalAngle,
      heelLiftDistance: heelLiftDistance,
      heelLiftAngle: heelLiftAngle,
      elbowHorizAngle: elbowHorizAngle,
      torsoForward: torsoForward,
      kneePastToes: kneePastToes,
      heelsLifting: heelsLifting,
    );
  }

  static String? _resolveSide({
    required String? preferredSide,
    required bool leftReady,
    required bool rightReady,
  }) {
    if (preferredSide == 'right' && rightReady) return 'right';
    if (preferredSide == 'left' && leftReady) return 'left';
    if (preferredSide != null) return null;
    if (rightReady) return 'right';
    if (leftReady) return 'left';
    return null;
  }

  static int _vertAngle(Offset upper, Offset joint) {
    final a = upper - joint;
    final b = Offset(0, -1);
    final cos = ((a.dx * b.dx) + (a.dy * b.dy)) /
        ((math.sqrt(a.dx * a.dx + a.dy * a.dy) * math.sqrt(b.dx * b.dx + b.dy * b.dy))
            .clamp(1e-6, double.infinity));
    return (math.acos(cos.clamp(-1, 1)) * 180 / math.pi).round();
  }

  static int _horizAngleFromShoulder(Offset elbow, Offset shoulder) {
    final v = elbow - shoulder;
    final angleRad = math.atan2(v.dy.abs(), v.dx.abs().clamp(1e-6, double.infinity));
    return (angleRad * 180 / math.pi).round();
  }

  static int _heelLiftAngle(Offset heel, Offset foot) {
    final basePoint = Offset(heel.dx + 10, heel.dy);
    final v1 = foot - heel;
    final v2 = basePoint - heel;
    final mag1 = math.sqrt(v1.dx * v1.dx + v1.dy * v1.dy).clamp(1e-6, double.infinity);
    final mag2 = math.sqrt(v2.dx * v2.dx + v2.dy * v2.dy).clamp(1e-6, double.infinity);
    final cos = ((v1.dx * v2.dx) + (v1.dy * v2.dy)) / (mag1 * mag2);
    final raw = math.acos(cos.clamp(-1, 1)) * 180 / math.pi;
    final folded = math.min(raw, 180 - raw);
    return folded.round();
  }
}
