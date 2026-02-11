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
}
