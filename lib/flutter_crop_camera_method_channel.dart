import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_crop_camera_platform_interface.dart';

/// An implementation of [FlutterCropCameraPlatform] that uses method channels.
class MethodChannelFlutterCropCamera extends FlutterCropCameraPlatform {
  /// The [MethodChannel] used to interact with the native side (Android/iOS).
  /// This must match the channel name defined in the native code.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_crop_camera');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  @override
  Future<int?> startCamera({
    double quality = 1.0,
    String facing = 'back',
    String aspectRatio = '3:4',
  }) async {
    final payload = {
      'quality': quality,
      'facing': facing,
      'frontCamera': facing == 'front',
      'aspectRatio': aspectRatio,
    };
    return await methodChannel.invokeMethod<int>('startCamera', payload);
  }

  @override
  Future<void> stopCamera() async {
    await methodChannel.invokeMethod('stopCamera');
  }

  @override
  Future<int?> switchCamera() async {
    return await methodChannel.invokeMethod<int>('switchCamera');
  }

  @override
  Future<void> setZoom(double zoom) async {
    await methodChannel.invokeMethod('setZoom', {'zoom': zoom});
  }

  @override
  Future<void> setFlashMode(String mode) async {
    await methodChannel.invokeMethod('setFlashMode', {'mode': mode});
  }

  @override
  Future<double> getMaxZoom() async {
    try {
      final double? max = await methodChannel.invokeMethod<double>('getMaxZoom');
      return max ?? 1.0;
    } on PlatformException {
      return 1.0;
    } on MissingPluginException {
      return 1.0;
    }
  }

  @override
  Future<String?> takePicture() async {
    return await methodChannel.invokeMethod<String>('takePicture');
  }

  @override
  Future<String?> pickImage() async {
    return await methodChannel.invokeMethod<String>('pickImage');
  }

  @override
  Future<List<String>?> pickImages() async {
    try {
      final List<dynamic>? paths =
          await methodChannel.invokeMethod<List<dynamic>>('pickImages');
      return paths?.cast<String>();
    } on PlatformException {
      return [];
    }
  }

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
  }) async {
    return await methodChannel.invokeMethod<String>('cropImage', {
      'path': path,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'rotationDegrees': rotationDegrees,
      'flipX': flipX,
      'quality': quality,
    });
  }
}
