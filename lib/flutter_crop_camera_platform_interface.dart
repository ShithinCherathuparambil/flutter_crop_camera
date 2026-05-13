import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_crop_camera_method_channel.dart';

abstract class FlutterCropCameraPlatform extends PlatformInterface {
  /// Constructs a FlutterCropCameraPlatform.
  FlutterCropCameraPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterCropCameraPlatform _instance = MethodChannelFlutterCropCamera();

  /// The default instance of [FlutterCropCameraPlatform] to use.
  ///
  /// By default, this uses the [MethodChannelFlutterCropCamera] implementation,
  /// but it can be overridden by platform-specific plugins (like web/macOS)
  /// during their registration phase.
  static FlutterCropCameraPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterCropCameraPlatform] when
  /// they register themselves.
  static set instance(FlutterCropCameraPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Retrieves the platform version (debug/info utility).
  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  /// Starts the camera with the specified configuration.
  Future<int?> startCamera({
    double quality = 1.0,
    String facing = 'back',
    String aspectRatio = '3:4',
  }) {
    throw UnimplementedError('startCamera() has not been implemented.');
  }

  /// Stops the camera and releases resources.
  Future<void> stopCamera() {
    throw UnimplementedError('stopCamera() has not been implemented.');
  }

  /// Toggles between front and rear cameras.
  Future<int?> switchCamera() {
    throw UnimplementedError('switchCamera() has not been implemented.');
  }

  /// Sets the digital zoom level.
  Future<void> setZoom(double zoom) {
    throw UnimplementedError('setZoom() has not been implemented.');
  }

  /// Sets the flash mode.
  Future<void> setFlashMode(String mode) {
    throw UnimplementedError('setFlashMode() has not been implemented.');
  }

  /// Gets the maximum supported zoom level.
  Future<double> getMaxZoom() {
    throw UnimplementedError('getMaxZoom() has not been implemented.');
  }

  /// Captures a static image and returns its path.
  Future<String?> takePicture() {
    throw UnimplementedError('takePicture() has not been implemented.');
  }

  /// Picks a single image from the gallery.
  Future<String?> pickImage() {
    throw UnimplementedError('pickImage() has not been implemented.');
  }

  /// Picks multiple images from the gallery.
  Future<List<String>?> pickImages() {
    throw UnimplementedError('pickImages() has not been implemented.');
  }

  /// Crops, rotates, and flips an image.
  Future<String?> cropImage({
    required String path,
    required int x,
    required int y,
    required int width,
    required int height,
    int rotationDegrees = 0,
    bool flipX = false,
    int quality = 100,
  }) {
    throw UnimplementedError('cropImage() has not been implemented.');
  }
}
