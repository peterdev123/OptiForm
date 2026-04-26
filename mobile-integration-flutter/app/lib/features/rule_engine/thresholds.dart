class ThresholdProfile {
  const ThresholdProfile({
    required this.hipKneeVertNormal,
    required this.hipKneeVertTrans,
    required this.hipKneeVertPass,
    required this.hipThresh,
    required this.ankleThresh,
    required this.kneeThresh,
  });

  final (int, int) hipKneeVertNormal;
  final (int, int) hipKneeVertTrans;
  final (int, int) hipKneeVertPass;
  final List<int> hipThresh;
  final int ankleThresh;
  final List<int> kneeThresh;
}

const beginnerThresholds = ThresholdProfile(
  hipKneeVertNormal: (0, 32),
  hipKneeVertTrans: (35, 65),
  hipKneeVertPass: (65, 95),
  hipThresh: [10, 50],
  ankleThresh: 45,
  kneeThresh: [50, 70, 95],
);

const proThresholds = ThresholdProfile(
  hipKneeVertNormal: (0, 32),
  hipKneeVertTrans: (35, 65),
  hipKneeVertPass: (80, 95),
  hipThresh: [15, 50],
  ankleThresh: 30,
  kneeThresh: [50, 80, 95],
);
