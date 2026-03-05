import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CameraService {
  CameraController? cameraController;

  /// [resolutionPreset] — defaults to [ResolutionPreset.high] (1280×720).
  ///   'medium' (640×480) was the old default; it produces blurry previews
  ///   and degrades ML Kit accuracy because faces are too small in the frame.
  ///
  /// [lensDirection] — front for registration, front/back for recognition.
  Future<void> initialize({
    ResolutionPreset resolutionPreset = ResolutionPreset.high,
    CameraLensDirection lensDirection = CameraLensDirection.front,
  }) async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        debugPrint("CameraService: no cameras found");
        return;
      }

      final CameraDescription camera = cameras.firstWhere(
            (c) => c.lensDirection == lensDirection,
        orElse: () => cameras.first,
      );

      // ── BUG FIX: ImageFormatGroup ──────────────────────────────────────
      // ImageFormatGroup.jpeg DISABLES startImageStream on Android — the
      // plugin returns an empty or null stream, causing the spinner to spin
      // forever with zero frames processed.
      //
      // Correct values:
      //   Android → yuv420   (native sensor format; Y-plane used for ML Kit)
      //   iOS     → bgra8888 (Flutter camera plugin always delivers this)
      //
      // Using the platform-correct format also avoids a hidden re-encode
      // from YUV → JPEG → YUV on every frame, saving ~30ms per frame.
      final ImageFormatGroup formatGroup = Platform.isIOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.yuv420;

      cameraController = CameraController(
        camera,
        resolutionPreset,
        enableAudio: false,
        imageFormatGroup: formatGroup,
      );

      await cameraController!.initialize();

      await cameraController!.setFocusMode(FocusMode.auto).catchError((_) {});
      await cameraController!.setExposureMode(ExposureMode.auto).catchError((_) {});
    } catch (e) {
      debugPrint("CameraService init error: $e");
    }
  }

  void dispose() {
    cameraController?.dispose();
    cameraController = null;
  }
}