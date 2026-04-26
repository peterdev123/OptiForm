class EventFlag {
  final bool flag;
  final int? torsoHip;
  final int? ankle;
  final int? heel;

  const EventFlag({
    required this.flag,
    this.torsoHip,
    this.ankle,
    this.heel,
  });

  Map<String, dynamic> toJson() {
    return {
      'flag': flag,
      if (torsoHip != null) 'torso_hip': torsoHip,
      if (ankle != null) 'ankle': ankle,
      if (heel != null) 'heel': heel,
    };
  }
}

class ElbowFlaringFlag {
  final bool flag;
  final int? minAngle;

  const ElbowFlaringFlag({
    required this.flag,
    this.minAngle,
  });

  Map<String, dynamic> toJson() {
    return {
      'flag': flag,
      if (minAngle != null) 'min_angle': minAngle,
    };
  }
}

class SquatPromptInput {
  final int repNumber;
  final String bodyType;
  final EventFlag heelsLifting;
  final EventFlag torsoForward;
  final EventFlag kneesForward;
  final ElbowFlaringFlag elbowFlaring;
  final int depth;
  final bool acceptable;
  final String summaryText;

  const SquatPromptInput({
    required this.repNumber,
    required this.bodyType,
    required this.heelsLifting,
    required this.torsoForward,
    required this.kneesForward,
    required this.elbowFlaring,
    required this.depth,
    required this.acceptable,
    required this.summaryText,
  });

  Map<String, dynamic> toJson() {
    return {
      'rep_number': repNumber,
      'body_type': bodyType,
      'heels_lifting': heelsLifting.toJson(),
      'torso_forward': torsoForward.toJson(),
      'knees_forward': kneesForward.toJson(),
      'elbow_flaring': elbowFlaring.toJson(),
      'depth': depth,
      'acceptable': acceptable,
      'summary_text': summaryText,
    };
  }
}
