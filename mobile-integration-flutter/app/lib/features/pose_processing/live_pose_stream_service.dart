import 'dart:async';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

import '../../domain/models/squat_prompt_input.dart';
import '../feature_engineering/pose_frame_metrics.dart';
import '../feature_engineering/squat_input_mapper.dart';
import '../rule_engine/squat_rep_engine.dart';
import '../rule_engine/thresholds.dart';
import 'mlkit_pose_extractor.dart';

class LivePoseStreamService {
  LivePoseStreamService({
    MlkitPoseExtractor? extractor,
    SquatInputMapper? mapper,
  }) : _extractor = extractor ?? MlkitPoseExtractor(),
       _mapper = mapper ?? SquatInputMapper();

  final MlkitPoseExtractor _extractor;
  final SquatInputMapper _mapper;
  SquatRepEngine? _repEngine;

  CameraController? _controller;
  bool _isBusy = false;
  int _frameCounter = 0;

  SquatPromptInput? lastInput;
  SquatPromptInput? lastFinalizedRepInput;

  CameraController? get controller => _controller;
  bool get isStreaming => _controller?.value.isStreamingImages ?? false;

  Future<void> start({
    int processEveryNthFrame = 8,
    String bodyType = 'average',
    ThresholdProfile thresholds = beginnerThresholds,
    void Function(SquatPromptInput input)? onInputUpdated,
    void Function(SquatPromptInput input)? onRepFinalized,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError(
        'Live camera pose streaming is intended for Android/iOS targets.',
      );
    }
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw StateError('No available camera found on this device.');
    }

    final preferred = cameras.firstWhere(
      (cam) => cam.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      preferred,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await controller.initialize();
    _controller = controller;
    _repEngine = SquatRepEngine(
      bodyType: bodyType,
      thresholds: thresholds,
    );

    await controller.startImageStream((image) async {
      if (_isBusy) return;
      _frameCounter++;
      if (_frameCounter % processEveryNthFrame != 0) return;
      _isBusy = true;
      try {
        final input = _cameraImageToInputImage(image, preferred);
        if (input == null) return;
        final pose = await _extractor.extractPoseFromInputImage(input);
        if (pose == null) return;
        final mappedCurrent = _mapper.fromPose(
          pose: pose,
          repNumber: 1,
          bodyType: bodyType,
        );
        lastInput = mappedCurrent;
        onInputUpdated?.call(mappedCurrent);

        final frameMetrics = PoseFrameMetrics.fromPose(pose);
        if (frameMetrics != null && _repEngine != null) {
          final finalized = _repEngine!.ingest(frameMetrics);
          if (finalized != null) {
            lastFinalizedRepInput = finalized;
            onRepFinalized?.call(finalized);
          }
        }
      } finally {
        _isBusy = false;
      }
    });
  }

  Future<void> stop() async {
    final controller = _controller;
    if (controller != null) {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      await controller.dispose();
      _controller = null;
    }
    _repEngine = null;
  }

  Future<void> dispose() async {
    await stop();
    await _extractor.dispose();
  }

  InputImage? _cameraImageToInputImage(
    CameraImage image,
    CameraDescription camera,
  ) {
    final rotation =
        InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    if (image.planes.isEmpty) return null;
    final bytes = _concatenatePlanes(image.planes);

    final metadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes.first.bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  Uint8List _concatenatePlanes(List<Plane> planes) {
    final allBytes = WriteBuffer();
    for (final plane in planes) {
      allBytes.putUint8List(plane.bytes);
    }
    return allBytes.done().buffer.asUint8List();
  }
}
