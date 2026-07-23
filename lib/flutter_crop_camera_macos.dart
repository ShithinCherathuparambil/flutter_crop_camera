import 'package:flutter/services.dart';

import 'flutter_crop_camera_platform_interface.dart';
import 'src/desktop_crop_utils.dart';
import 'src/desktop_file_picker.dart';

/// macOS implementation of [FlutterCropCameraPlatform].
///
/// Camera preview and capture use a native AVFoundation method channel
/// (Swift [FlutterCropCameraPlugin]) which registers a [FlutterTexture].
///
/// Gallery picking is handled entirely in Dart via `package:file_selector`
/// (NSOpenPanel) so no native code is needed for that.
///
/// Image cropping is done in pure Dart via `dart:ui` Canvas — identical to
/// the Web implementation, but the result is written to a temp file.
class FlutterCropCameraMacOS extends FlutterCropCameraPlatform {
  /// Called automatically by Flutter's generated dart_plugin_registrant.dart.
  static void registerWith() {
    FlutterCropCameraPlatform.instance = FlutterCropCameraMacOS();
  }

  /// Method channel to the native Swift [FlutterCropCameraPlugin] registered
  /// under the `flutter_crop_camera` channel.
  static const _channel = MethodChannel('flutter_crop_camera');

  // ── Platform version ──────────────────────────────────────────────────────

  @override
  Future<String?> getPlatformVersion() async {
    try {
      return await _channel.invokeMethod<String>('getPlatformVersion');
    } catch (_) {
      return 'macOS';
    }
  }

  // ── Camera (native Swift via method channel) ───────────────────────────────

  @override
  Future<int?> startCamera({
    double quality = 1.0,
    String facing = 'back',
    String aspectRatio = '3:4',
  }) async {
    try {
      return await _channel.invokeMethod<int>('startCamera', {
        'quality': quality,
        'facing': facing,
        'frontCamera': facing == 'front',
        'aspectRatio': aspectRatio,
      });
    } on PlatformException catch (e) {
      throw PlatformException(
        code: e.code,
        message: 'macOS camera error: ${e.message}',
        details: e.details,
      );
    }
  }

  @override
  Future<void> stopCamera() async {
    try {
      await _channel.invokeMethod<void>('stopCamera');
    } catch (_) {
      // Silently ignore: camera may already be stopped.
    }
  }

  @override
  Future<int?> switchCamera() async {
    try {
      return await _channel.invokeMethod<int>('switchCamera');
    } on PlatformException {
      return null;
    }
  }

  /// Zoom is not supported on macOS webcams — silently ignored.
  @override
  Future<void> setZoom(double zoom) async {}

  /// Flash is not supported on macOS webcams — silently ignored.
  @override
  Future<void> setFlashMode(String mode) async {}

  @override
  Future<double> getMaxZoom() async => 1.0;

  @override
  Future<String?> takePicture() async {
    try {
      return await _channel.invokeMethod<String>('takePicture');
    } on PlatformException catch (e) {
      throw PlatformException(
        code: e.code,
        message: 'macOS takePicture error: ${e.message}',
        details: e.details,
      );
    }
  }

  // ── Gallery (pure Dart — NSOpenPanel via file_selector) ───────────────────

  @override
  Future<String?> pickImage() => desktopPickImage();

  @override
  Future<List<String>?> pickImages() => desktopPickImages();

  // ── Crop (pure Dart — dart:ui Canvas pipeline) ────────────────────────────

  @override
  Future<String?> cropImage({
    required String path,
    required int x,
    required int y,
    required int width,
    required int height,
    int rotationDegrees = 0,
    bool flipX = false,
    int quality = 100,
  }) =>
      desktopCropImage(
        path: path,
        x: x,
        y: y,
        width: width,
        height: height,
        rotationDegrees: rotationDegrees,
        flipX: flipX,
        quality: quality,
      );
}
