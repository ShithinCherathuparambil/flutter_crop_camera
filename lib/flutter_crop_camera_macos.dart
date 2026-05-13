import 'flutter_crop_camera_platform_interface.dart';

class FlutterCropCameraMacOS extends FlutterCropCameraPlatform {
  static void registerWith() {
    FlutterCropCameraPlatform.instance = FlutterCropCameraMacOS();
  }

  @override
  Future<String?> getPlatformVersion() async => 'macOS';
}
