import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../domain/models/squat_prompt_input.dart';
import '../feature_engineering/pose_frame_metrics.dart';
import '../rule_engine/squat_rep_engine.dart';
import '../rule_engine/thresholds.dart';
import 'mlkit_pose_extractor.dart';

class PoseDebugSnapshot {
  const PoseDebugSnapshot({
    required this.repNumber,
    required this.timeMs,
    required this.side,
    required this.imageBytes,
    required this.imageSize,
    required this.joints,
    required this.connections,
    required this.metricLabels,
  });

  final int repNumber;
  final int timeMs;
  final String side;
  final Uint8List imageBytes;
  final Size imageSize;
  final Map<String, Offset> joints;
  final List<List<String>> connections;
  final Map<String, String> metricLabels;
}

class VideoPoseAnalysisResult {
  const VideoPoseAnalysisResult({
    required this.reps,
    required this.debugSnapshots,
  });

  final List<SquatPromptInput> reps;
  final List<PoseDebugSnapshot> debugSnapshots;
}

class VideoPoseAnalyzer {
  VideoPoseAnalyzer({MlkitPoseExtractor? extractor})
    : _extractor = extractor ?? MlkitPoseExtractor();

  final MlkitPoseExtractor _extractor;

  Future<VideoPoseAnalysisResult> analyzeVideo({
    required String videoPath,
    String bodyType = 'N/A',
    ThresholdProfile thresholds = beginnerThresholds,
    int sampleEveryMs = 300,
    int? maxDebugSnapshots,
    void Function(double progress)? onProgress,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Video file pose analysis currently targets Android/iOS.');
    }

    final controller = VideoPlayerController.file(File(videoPath));
    await controller.initialize();
    final durationMs = controller.value.duration.inMilliseconds;
    final frameWidthPx = controller.value.size.width > 0 ? controller.value.size.width : null;
    await controller.dispose();

    if (durationMs <= 0) {
      return const VideoPoseAnalysisResult(reps: [], debugSnapshots: []);
    }

    final repEngine = SquatRepEngine(
      bodyType: bodyType,
      thresholds: thresholds,
    );
    final outputs = <SquatPromptInput>[];
    final debugSnapshots = <PoseDebugSnapshot>[];
    final generatedThumbs = <String>[];
    final pendingS2Frames = <_PendingSnapshotFrame>[];
    final pendingRepFrames = <_PendingSnapshotFrame>[];
    _PendingSnapshotFrame? bestKneesForwardFrame;
    _PendingSnapshotFrame? bestTorsoForwardFrame;
    _PendingSnapshotFrame? bestHeelsLiftingFrame;
    const framesPerRep = 3;
    String? lockedSide;
    var leftVotes = 0;
    var rightVotes = 0;
    const sideWarmupVotes = 6;

    try {
      for (var t = 0; t <= durationMs; t += sampleEveryMs) {
        onProgress?.call((t / durationMs).clamp(0, 1));
        final thumbPath = await VideoThumbnail.thumbnailFile(
          video: videoPath,
          imageFormat: ImageFormat.JPEG,
          timeMs: t,
          quality: 60,
        );
        if (thumbPath == null) continue;
        generatedThumbs.add(thumbPath);

        final pose = await _extractor.extractPoseFromImagePath(thumbPath);
        if (pose == null) continue;

        if (lockedSide == null) {
          final votedSide = _resolveVisibleSide(pose);
          if (votedSide == 'left') {
            leftVotes += 1;
          } else {
            rightVotes += 1;
          }
          if (leftVotes + rightVotes >= sideWarmupVotes) {
            lockedSide = leftVotes > rightVotes ? 'left' : 'right';
          } else {
            // Avoid mixed-side ingestion before we confidently lock side.
            continue;
          }
        }
        final frame = PoseFrameMetrics.fromPose(
          pose,
          preferredSide: lockedSide,
          frameWidthPx: frameWidthPx,
        );
        if (frame == null) continue;
        final state = repEngine.currentStateFromFrame(frame);
        final imageBytes = await File(thumbPath).readAsBytes();
        final imageSize = await _decodeImageSize(imageBytes);
        final pendingFrame = _PendingSnapshotFrame(
          pose: pose,
          frame: frame,
          timeMs: t,
          imageBytes: imageBytes,
          imageSize: imageSize,
          side: lockedSide!,
          state: state,
        );
        pendingRepFrames.add(pendingFrame);
        if (state == 's2') {
          pendingS2Frames.add(pendingFrame);
          if (frame.kneePastToes) {
            bestKneesForwardFrame = _pickStrongerFrame(
              current: bestKneesForwardFrame,
              candidate: pendingFrame,
              scoreOf: (f) => f.frame.ankleVerticalAngle,
            );
          }
          if (frame.torsoForward) {
            bestTorsoForwardFrame = _pickStrongerFrame(
              current: bestTorsoForwardFrame,
              candidate: pendingFrame,
              scoreOf: (f) => f.frame.hipVerticalAngle,
            );
          }
          if (frame.heelsLifting) {
            bestHeelsLiftingFrame = _pickStrongerFrame(
              current: bestHeelsLiftingFrame,
              candidate: pendingFrame,
              scoreOf: (f) => f.frame.heelLiftDistance,
            );
          }
        }

        final finalized = repEngine.ingest(frame);
        if (finalized != null) {
          outputs.add(finalized);
          final selectedTaggedFrames = <_TaggedPendingFrame>[];
          _addTaggedUniqueFrame(
            selectedTaggedFrames,
            bestKneesForwardFrame,
            tag: 's2 | knees-forward',
          );
          _addTaggedUniqueFrame(
            selectedTaggedFrames,
            bestTorsoForwardFrame,
            tag: 's2 | torso-forward',
          );
          _addTaggedUniqueFrame(
            selectedTaggedFrames,
            bestHeelsLiftingFrame,
            tag: 's2 | heels-lifting',
          );
          final fallbackS2Frames = _selectFramesForRep(
            candidates: pendingS2Frames,
            targetCount: framesPerRep,
          );
          for (final fallback in fallbackS2Frames) {
            if (selectedTaggedFrames.length >= framesPerRep) break;
            _addTaggedUniqueFrame(
              selectedTaggedFrames,
              fallback,
              tag: 's2 | sampled',
            );
          }
          if (selectedTaggedFrames.isEmpty) {
            final repWindowFallbackFrames = _selectFramesForRep(
              candidates: pendingRepFrames,
              targetCount: framesPerRep,
            );
            for (final fallback in repWindowFallbackFrames) {
              if (selectedTaggedFrames.length >= framesPerRep) break;
              _addTaggedUniqueFrame(
                selectedTaggedFrames,
                fallback,
                tag: '${fallback.state} | rep-window-fallback',
              );
            }
          }

          for (final candidate in selectedTaggedFrames) {
            if (!_canCaptureMoreSnapshots(
              currentCount: debugSnapshots.length,
              maxDebugSnapshots: maxDebugSnapshots,
            )) {
              break;
            }
            final snapshot = _buildDebugSnapshot(
              repNumber: finalized.repNumber,
              pose: candidate.frame.pose,
              frame: candidate.frame.frame,
              timeMs: candidate.frame.timeMs,
              imageBytes: candidate.frame.imageBytes,
              imageSize: candidate.frame.imageSize,
              side: candidate.frame.side,
              stateTag: candidate.tag,
            );
            if (snapshot != null) {
              debugSnapshots.add(snapshot);
            }
          }
          pendingS2Frames.clear();
          pendingRepFrames.clear();
          bestKneesForwardFrame = null;
          bestTorsoForwardFrame = null;
          bestHeelsLiftingFrame = null;
        }
      }
      onProgress?.call(1);
      return VideoPoseAnalysisResult(
        reps: outputs,
        debugSnapshots: debugSnapshots,
      );
    } finally {
      for (final path in generatedThumbs) {
        try {
          final f = File(path);
          if (await f.exists()) {
            await f.delete();
          }
        } catch (_) {}
      }
    }
  }

  Future<void> dispose() async {
    await _extractor.dispose();
  }

  PoseDebugSnapshot? _buildDebugSnapshot({
    required int repNumber,
    required Pose pose,
    required PoseFrameMetrics frame,
    required int timeMs,
    required Uint8List imageBytes,
    required Size imageSize,
    required String side,
    required String stateTag,
  }) {
    final joints = _extractSideJoints(pose: pose, side: side);
    if (!joints.containsKey('shoulder') ||
        !joints.containsKey('hip') ||
        !joints.containsKey('knee') ||
        !joints.containsKey('ankle') ||
        !joints.containsKey('heel')) {
      return null;
    }

    return PoseDebugSnapshot(
      repNumber: repNumber,
      timeMs: timeMs,
      side: '$side | $stateTag',
      imageBytes: imageBytes,
      imageSize: imageSize,
      joints: joints,
      connections: const [
        ['shoulder', 'elbow'],
        ['shoulder', 'hip'],
        ['hip', 'knee'],
        ['knee', 'ankle'],
        ['ankle', 'heel'],
        ['ankle', 'foot'],
      ],
      metricLabels: {
        'hip': 'hip: ${frame.hipVerticalAngle}',
        'knee': 'knee: ${frame.kneeVerticalAngle}',
        'ankle': 'ankle: ${frame.ankleVerticalAngle}',
        'elbow': 'elbow: ${frame.elbowHorizAngle}',
        'heel': 'heel-gnd: ${_heelDisplay(frame.heelLiftDistance)}',
      },
    );
  }

  String _resolveVisibleSide(Pose pose) {
    Offset? pt(PoseLandmarkType t) {
      final lm = pose.landmarks[t];
      return lm == null ? null : Offset(lm.x, lm.y);
    }

    final lShoulder = pt(PoseLandmarkType.leftShoulder);
    final lFoot = pt(PoseLandmarkType.leftFootIndex);
    final rShoulder = pt(PoseLandmarkType.rightShoulder);
    final rFoot = pt(PoseLandmarkType.rightFootIndex);

    final leftDist = (lShoulder != null && lFoot != null)
        ? (lFoot.dy - lShoulder.dy).abs()
        : -1.0;
    final rightDist = (rShoulder != null && rFoot != null)
        ? (rFoot.dy - rShoulder.dy).abs()
        : -1.0;
    return leftDist > rightDist ? 'left' : 'right';
  }

  Map<String, Offset> _extractSideJoints({
    required Pose pose,
    required String side,
  }) {
    Offset? pt(PoseLandmarkType t) {
      final lm = pose.landmarks[t];
      return lm == null ? null : Offset(lm.x, lm.y);
    }

    final isRight = side == 'right';
    final shoulder = pt(
      isRight ? PoseLandmarkType.rightShoulder : PoseLandmarkType.leftShoulder,
    );
    final elbow = pt(isRight ? PoseLandmarkType.rightElbow : PoseLandmarkType.leftElbow);
    final hip = pt(isRight ? PoseLandmarkType.rightHip : PoseLandmarkType.leftHip);
    final knee = pt(isRight ? PoseLandmarkType.rightKnee : PoseLandmarkType.leftKnee);
    final ankle = pt(
      isRight ? PoseLandmarkType.rightAnkle : PoseLandmarkType.leftAnkle,
    );
    final heel = pt(isRight ? PoseLandmarkType.rightHeel : PoseLandmarkType.leftHeel);
    final foot = pt(
      isRight ? PoseLandmarkType.rightFootIndex : PoseLandmarkType.leftFootIndex,
    );

    return {
      if (shoulder != null) 'shoulder': shoulder,
      if (elbow != null) 'elbow': elbow,
      if (hip != null) 'hip': hip,
      if (knee != null) 'knee': knee,
      if (ankle != null) 'ankle': ankle,
      if (heel != null) 'heel': heel,
      if (foot != null) 'foot': foot,
    };
  }

  Future<Size> _decodeImageSize(Uint8List bytes) async {
    final codec = await instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    return Size(image.width.toDouble(), image.height.toDouble());
  }

  int _heelDisplay(int rawHeelDistance) {
    final v = rawHeelDistance - 20;
    return v < 0 ? 0 : v;
  }

  List<_PendingSnapshotFrame> _selectFramesForRep({
    required List<_PendingSnapshotFrame> candidates,
    required int targetCount,
  }) {
    if (candidates.isEmpty || targetCount <= 0) return const [];
    if (candidates.length <= targetCount) {
      return List<_PendingSnapshotFrame>.from(candidates);
    }

    final selected = <_PendingSnapshotFrame>[];
    final lastIndex = candidates.length - 1;
    for (var i = 0; i < targetCount; i++) {
      final ratio = targetCount == 1 ? 0.0 : i / (targetCount - 1);
      final idx = (ratio * lastIndex).round();
      selected.add(candidates[idx]);
    }
    return selected;
  }

  _PendingSnapshotFrame _pickStrongerFrame({
    required _PendingSnapshotFrame? current,
    required _PendingSnapshotFrame candidate,
    required int Function(_PendingSnapshotFrame frame) scoreOf,
  }) {
    if (current == null) return candidate;
    return scoreOf(candidate) > scoreOf(current) ? candidate : current;
  }

  void _addTaggedUniqueFrame(
    List<_TaggedPendingFrame> selected,
    _PendingSnapshotFrame? candidate, {
    required String tag,
  }) {
    if (candidate == null) return;
    final alreadyIncluded = selected.any((e) => e.frame.timeMs == candidate.timeMs);
    if (alreadyIncluded) return;
    selected.add(_TaggedPendingFrame(frame: candidate, tag: tag));
  }

  bool _canCaptureMoreSnapshots({
    required int currentCount,
    required int? maxDebugSnapshots,
  }) {
    if (maxDebugSnapshots == null || maxDebugSnapshots <= 0) {
      return true;
    }
    return currentCount < maxDebugSnapshots;
  }
}

class _PendingSnapshotFrame {
  const _PendingSnapshotFrame({
    required this.pose,
    required this.frame,
    required this.timeMs,
    required this.imageBytes,
    required this.imageSize,
    required this.side,
    required this.state,
  });

  final Pose pose;
  final PoseFrameMetrics frame;
  final int timeMs;
  final Uint8List imageBytes;
  final Size imageSize;
  final String side;
  final String state;
}

class _TaggedPendingFrame {
  const _TaggedPendingFrame({
    required this.frame,
    required this.tag,
  });

  final _PendingSnapshotFrame frame;
  final String tag;
}
