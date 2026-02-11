import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_crop_camera_method_channel.dart';

abstract class FlutterCropCameraPlatform extends PlatformInterface {
  /// Constructs a FlutterCropCameraPlatform.
  FlutterCropCameraPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterCropCameraPlatform _instance = MethodChannelFlutterCropCamera();

  /// The default instance of [FlutterCropCameraPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterCropCamera].
  static FlutterCropCameraPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterCropCameraPlatform] when
  /// they register themselves.
  static set instance(FlutterCropCameraPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
