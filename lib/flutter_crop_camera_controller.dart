import 'dart:async';
import 'package:flutter/services.dart';

/// [FlutterCropCameraController] acts as the bridge between the Flutter UI
/// and the native platform implementations (Android CameraX / iOS AVFoundation).
class FlutterCropCameraController {
  /// The [MethodChannel] used for communicating with native code.
  static const MethodChannel _channel = MethodChannel('flutter_crop_camera');

  /// The unique ID of the camera preview texture provided by the native side.
  /// This ID is passed to the [Texture] widget to render the camera feed.
  int? textureId;

  /// Starts the camera on the native platform with the specified configuration.
  /// Returns the texture ID required for the preview.
  Future<void> startCamera({
    double quality = 1.0,
    dynamic cameraPreference, // CamPreference enum
    dynamic aspectRatio, // CamRatio enum
  }) async {
    String facing = 'back';
    // Determine if we should start with front or rear camera.
    if (cameraPreference.toString().toLowerCase().contains('front')) {
      facing = 'front';
    }

    final payload = {
      'quality': quality,
      'facing': facing,
      'frontCamera': facing == 'front', // Fallback for various native versions
      'aspectRatio': _getRatioString(aspectRatio),
    };

    // Invoke 'startCamera' and receive the platform-side texture ID.
    final int? id = await _channel.invokeMethod('startCamera', payload);
    textureId = id;
  }

  /// Stops the camera and releases all native resources.
  Future<void> stopCamera() async {
    await _channel.invokeMethod('stopCamera');
    textureId = null;
  }

  /// Toggles between the front and rear cameras.
  Future<void> switchCamera() async {
    final int? id = await _channel.invokeMethod('switchCamera');
    if (id != null) {
      textureId = id;
    }
  }

  /// Sets the digital zoom level.
  Future<void> setZoom(double zoom) async {
    await _channel.invokeMethod('setZoom', {'zoom': zoom});
  }

  /// Sets the camera flash mode ("off", "auto", "on").
  Future<void> setFlashMode(String mode) async {
    await _channel.invokeMethod('setFlashMode', {'mode': mode});
  }

  /// Captures a static image and saves it to the temporary directory.
  /// Returns the file path of the captured image.
  Future<String?> takePicture() async {
    final String? path = await _channel.invokeMethod('takePicture');
    return path;
  }

  /// Launches the native gallery picker and returns the path of the selected image.
  Future<String?> pickImage() async {
    final String? path = await _channel.invokeMethod('pickImage');
    return path;
  }

  /// Launches the native gallery picker and returns the paths of the selected images.
  Future<List<String>> pickImages() async {
    try {
      final List<dynamic>? paths = await _channel.invokeMethod('pickImages');
      if (paths == null) return [];
      return paths.cast<String>();
    } on PlatformException {
      // debugPrint("Error picking images: ${e.message}");
      return [];
    }
  }

  /// Performs cropping, rotation, and flipping on a saved image bitmap.
  /// This operation is performed on the native side for performance.
  Future<String?> cropImage({
    required String path,
    required int x,
    required int y,
    required int width,
    required int height,
    int rotationDegrees = 0,
    bool flipX = false,
    int quality = 100,
  }) async {
    final String? resultPath = await _channel.invokeMethod('cropImage', {
      'path': path,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'rotationDegrees': rotationDegrees,
      'flipX': flipX,
      'quality': quality,
    });
    return resultPath;
  }

  /// Helper to convert the [CamRatio] enum into a protocol string for the native side.
  String _getRatioString(dynamic aspectRatio) {
    if (aspectRatio is String) return aspectRatio;

    final String enumStr = aspectRatio.toString();
    if (enumStr.contains('ratio3x4')) return '3:4';
    if (enumStr.contains('ratio4x3')) return '4:3';
    if (enumStr.contains('ratio9x16')) return '9:16';
    if (enumStr.contains('ratio16x9')) return '16:9';
    if (enumStr.contains('ratio1x1')) return '1:1';
    return '3:4'; // Fallback default
  }
}
