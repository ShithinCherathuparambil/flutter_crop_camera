import 'dart:async';
import 'package:flutter/services.dart';

class FlutterCamCropperController {
  static const MethodChannel _channel = MethodChannel('flutter_cam_cropper');

  int? textureId;

  Future<void> startCamera({
    double quality = 1.0,
    dynamic cameraPreference, // CamPreference enum
    dynamic aspectRatio, // CamRatio enum
  }) async {
    String facing = 'back';
    if (cameraPreference.toString().toLowerCase().contains('front')) {
      facing = 'front';
    }

    final payload = {
      'quality': quality,
      'facing': facing,
      'frontCamera': facing == 'front', // Legacy/Fallback compatibility
      'aspectRatio': _getRatioString(aspectRatio),
    };
    final int? id = await _channel.invokeMethod('startCamera', payload);
    textureId = id;
  }

  Future<void> stopCamera() async {
    await _channel.invokeMethod('stopCamera');
    textureId = null;
  }

  Future<void> switchCamera() async {
    final int? id = await _channel.invokeMethod('switchCamera');
    if (id != null) {
      textureId = id;
    }
  }

  Future<void> setZoom(double zoom) async {
    await _channel.invokeMethod('setZoom', {'zoom': zoom});
  }

  Future<void> setFlashMode(String mode) async {
    await _channel.invokeMethod('setFlashMode', {'mode': mode});
  }

  Future<String?> takePicture() async {
    final String? path = await _channel.invokeMethod('takePicture');
    return path;
  }

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

  String _getRatioString(dynamic aspectRatio) {
    // If it's already a string (backward compatibility or raw value)
    if (aspectRatio is String) return aspectRatio;

    // Assuming it's CamRatio enum
    final String enumStr = aspectRatio.toString();
    if (enumStr.contains('ratio3x4')) return '3:4';
    if (enumStr.contains('ratio4x3')) return '4:3';
    if (enumStr.contains('ratio9x16')) return '9:16';
    if (enumStr.contains('ratio16x9')) return '16:9';
    if (enumStr.contains('ratio1x1')) return '1:1';
    return '3:4'; // Default
  }
}
