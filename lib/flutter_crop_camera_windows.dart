import 'flutter_crop_camera_platform_interface.dart';

class FlutterCropCameraWindows extends FlutterCropCameraPlatform {
  static void registerWith() {
    FlutterCropCameraPlatform.instance = FlutterCropCameraWindows();
  }

  @override
  Future<String?> getPlatformVersion() async => 'Windows';
}
