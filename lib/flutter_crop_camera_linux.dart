import 'flutter_crop_camera_platform_interface.dart';

class FlutterCropCameraLinux extends FlutterCropCameraPlatform {
  static void registerWith() {
    FlutterCropCameraPlatform.instance = FlutterCropCameraLinux();
  }

  @override
  Future<String?> getPlatformVersion() async => 'Linux';
}
