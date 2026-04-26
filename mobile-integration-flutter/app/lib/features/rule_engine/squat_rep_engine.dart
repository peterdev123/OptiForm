import '../../domain/models/squat_prompt_input.dart';
import '../feature_engineering/pose_frame_metrics.dart';
import 'thresholds.dart';

class SquatRepEngine {
  SquatRepEngine({
    this.bodyType = 'N/A',
    this.thresholds = beginnerThresholds,
  });

  final String bodyType;
  final ThresholdProfile thresholds;

  String? _prevState;
  final List<String> _stateSeq = [];
  int _repIndex = 0;

  int _maxBack = 0;
  int _maxKnee = 0;
  int _maxAnkle = 0;
  int _maxHeel = 0;
  int? _minElbow;
  int _heelLiftCandidateStreak = 0;
  static const int _heelLiftDebounceFrames = 2;
  static const int _heelLiftMinDistancePx = 8;
  static const int _elbowFlaringThresholdDeg = 30;

  bool _torsoForward = false;
  bool _kneesForward = false;
  bool _heelsLifting = false;
  bool _elbowFlaring = false;
  _EventSnapshot? _torsoForwardSnapshot;
  _EventSnapshot? _kneesForwardSnapshot;
  _EventSnapshot? _heelsLiftingSnapshot;

  SquatPromptInput? ingest(PoseFrameMetrics m) {
    final state = _stateFromKnee(m.kneeVerticalAngle);
    if (_prevState == 's1' && state == 's2') {
      _resetRepFlagsOnly();
    }
    _updateStateSequence(state);
    _updateFlagsAndMaxima(m, state);

    SquatPromptInput? finalized;
    if (_prevState == 's2' && state == 's1') {
      finalized = _finalizeRep();
      _resetRepState();
    }
    _prevState = state;
    return finalized;
  }

  String currentStateFromFrame(PoseFrameMetrics m) {
    return _stateFromKnee(m.kneeVerticalAngle);
  }

  String _stateFromKnee(int kneeAngle) {
    final (_, normalHi) = thresholds.hipKneeVertNormal;
    final (_, transHi) = thresholds.hipKneeVertTrans;
    if (kneeAngle <= normalHi) return 's1';
    if (kneeAngle <= transHi) return 's2';
    return 's3';
  }

  void _updateStateSequence(String state) {
    if (state == 's2') {
      if ((!_stateSeq.contains('s3') && _stateSeq.where((e) => e == 's2').isEmpty) ||
          (_stateSeq.contains('s3') && _stateSeq.where((e) => e == 's2').length == 1)) {
        _stateSeq.add(state);
      }
    } else if (state == 's3') {
      if (!_stateSeq.contains('s3') && _stateSeq.contains('s2')) {
        _stateSeq.add(state);
      }
    }
  }

  void _updateFlagsAndMaxima(PoseFrameMetrics m, String state) {
    if (state != 's2' && state != 's3') return;
    _maxBack = m.hipVerticalAngle > _maxBack ? m.hipVerticalAngle : _maxBack;
    _maxKnee = m.kneeVerticalAngle > _maxKnee ? m.kneeVerticalAngle : _maxKnee;
    _maxAnkle = m.ankleVerticalAngle > _maxAnkle ? m.ankleVerticalAngle : _maxAnkle;
    _maxHeel = m.heelLiftAngle > _maxHeel ? m.heelLiftAngle : _maxHeel;
    if (_minElbow == null || m.elbowHorizAngle < _minElbow!) {
      _minElbow = m.elbowHorizAngle;
    }

    _torsoForward = _torsoForward || m.torsoForward;
    _kneesForward = _kneesForward || m.kneePastToes;
    final heelsLiftCandidate =
        m.heelsLifting && m.heelLiftDistance > _heelLiftMinDistancePx;
    if (heelsLiftCandidate) {
      _heelLiftCandidateStreak += 1;
    } else {
      _heelLiftCandidateStreak = 0;
    }
    final heelsLiftingNow = _heelLiftCandidateStreak >= _heelLiftDebounceFrames;
    _heelsLifting = _heelsLifting || heelsLiftingNow;
    _elbowFlaring = _elbowFlaring || ((_minElbow ?? 90) < _elbowFlaringThresholdDeg);

    final current = _EventSnapshot(
      torsoHipAngle: m.hipVerticalAngle,
      ankleAngle: m.ankleVerticalAngle,
      heelDistance: m.heelLiftDistance,
    );
    if (heelsLiftingNow) {
      _heelsLiftingSnapshot = _pickHigherHeel(_heelsLiftingSnapshot, current);
      if (m.ankleVerticalAngle > 40) {
        _kneesForward = true;
        _kneesForwardSnapshot = _pickStrongerPosture(_kneesForwardSnapshot, current);
      }
    }
    if (m.torsoForward) {
      _torsoForwardSnapshot = _pickStrongerPosture(_torsoForwardSnapshot, current);
    }
    if (m.kneePastToes && !(heelsLiftingNow && m.ankleVerticalAngle > 40)) {
      _kneesForwardSnapshot = _pickStrongerPosture(_kneesForwardSnapshot, current);
    }
  }

  SquatPromptInput _finalizeRep() {
    _repIndex += 1;
    final depth = _maxKnee;
    final depthReached = depth >= 75 && depth <= 90;
    final acceptable = !(_torsoForward || _kneesForward || _heelsLifting || _elbowFlaring || !depthReached);

    return SquatPromptInput(
      repNumber: _repIndex,
      bodyType: bodyType,
      heelsLifting: EventFlag(
        flag: _heelsLifting,
        torsoHip: _maxBack,
        ankle: _maxAnkle,
        heel: _maxHeel,
      ),
      torsoForward: EventFlag(
        flag: _torsoForward,
        torsoHip: _maxBack,
        ankle: _maxAnkle,
        heel: _maxHeel,
      ),
      kneesForward: EventFlag(
        flag: _kneesForward,
        torsoHip: _maxBack,
        ankle: _maxAnkle,
        heel: _maxHeel,
      ),
      elbowFlaring: ElbowFlaringFlag(
        flag: _elbowFlaring,
        minAngle: _minElbow,
      ),
      depth: depth,
      acceptable: acceptable,
      summaryText: _summaryText(acceptable),
    );
  }

  String _summaryText(bool acceptable) {
    final lines = <String>[];
    lines.add('Rep Number: $_repIndex');
    lines.add('Body Type: ${_formatBodyType(bodyType)}');

    final heels = _heelsLiftingSnapshot;
    if (_heelsLifting && heels != null) {
      lines.add(
        'Heels Lifting: TRUE (torso-hip: ${heels.torsoHipAngle}, ankle: ${heels.ankleAngle}, heel: ${_heelDisplay(heels.heelDistance)})',
      );
    } else {
      lines.add('Heels Lifting: FALSE');
    }

    final torso = _torsoForwardSnapshot;
    if (_torsoForward && torso != null) {
      lines.add(
        'Torso Forward: TRUE (torso-hip: ${torso.torsoHipAngle}, ankle: ${torso.ankleAngle}, heel: ${_heelDisplay(torso.heelDistance)})',
      );
    } else {
      lines.add('Torso Forward: FALSE');
    }

    final knee = _kneesForwardSnapshot;
    if (_kneesForward && knee != null) {
      lines.add(
        'Knees Forward: TRUE (torso-hip: ${knee.torsoHipAngle}, ankle: ${knee.ankleAngle}, heel: ${_heelDisplay(knee.heelDistance)})',
      );
    } else if (_kneesForward) {
      lines.add('Knees Forward: TRUE');
    } else {
      lines.add('Knees Forward: FALSE');
    }

    if (_elbowFlaring && _minElbow != null) {
      lines.add('Elbow Flaring: TRUE (${_minElbow!})');
    } else {
      lines.add('Elbow Flaring: FALSE');
    }

    lines.add('Depth: $_maxKnee');
    lines.add('Acceptable: ${acceptable ? 'TRUE' : 'FALSE'}');
    return lines.join('\n');
  }

  void _resetRepState() {
    _stateSeq.clear();
    _maxBack = 0;
    _maxKnee = 0;
    _maxAnkle = 0;
    _maxHeel = 0;
    _minElbow = null;
    _torsoForward = false;
    _kneesForward = false;
    _heelsLifting = false;
    _elbowFlaring = false;
    _torsoForwardSnapshot = null;
    _kneesForwardSnapshot = null;
    _heelsLiftingSnapshot = null;
    _heelLiftCandidateStreak = 0;
  }

  void _resetRepFlagsOnly() {
    _torsoForward = false;
    _kneesForward = false;
    _heelsLifting = false;
    _elbowFlaring = false;
    _minElbow = null;
    _torsoForwardSnapshot = null;
    _kneesForwardSnapshot = null;
    _heelsLiftingSnapshot = null;
    _heelLiftCandidateStreak = 0;
  }

  _EventSnapshot? _pickHigherHeel(_EventSnapshot? current, _EventSnapshot candidate) {
    if (current == null) return candidate;
    if (candidate.heelDistance > current.heelDistance) return candidate;
    return current;
  }

  _EventSnapshot? _pickStrongerPosture(
    _EventSnapshot? current,
    _EventSnapshot candidate,
  ) {
    if (current == null) return candidate;
    if (candidate.torsoHipAngle > 45 &&
        (current.torsoHipAngle <= 45 || candidate.torsoHipAngle > current.torsoHipAngle)) {
      return candidate;
    }
    if (current.torsoHipAngle <= 45 && candidate.torsoHipAngle > current.torsoHipAngle) {
      return candidate;
    }
    return current;
  }

  int _heelDisplay(int rawHeelDistance) {
    final v = rawHeelDistance - 20;
    return v < 0 ? 0 : v;
  }

  String _formatBodyType(String value) {
    switch (value) {
      case 'LONGER_LEGS':
      case 'longer_legs':
      case 'longer-legs':
        return 'Longer Legs';
      case 'LONGER_TORSO':
      case 'longer_torso':
      case 'longer-torso':
        return 'Longer Torso';
      case 'BALANCED':
      case 'balanced':
        return 'Balanced';
      default:
        if (value.toLowerCase() == 'average') return 'Balanced';
        return 'N/A';
    }
  }
}

class _EventSnapshot {
  const _EventSnapshot({
    required this.torsoHipAngle,
    required this.ankleAngle,
    required this.heelDistance,
  });

  final int torsoHipAngle;
  final int ankleAngle;
  final int heelDistance;
}
