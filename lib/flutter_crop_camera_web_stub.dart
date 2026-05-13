/// Stub for VM/mobile targets so `flutter_crop_camera.dart` does not pull
/// `flutter_web_plugins` / `dart:ui_web` (only valid on web).
///
/// The real implementation is selected via conditional export when
/// `dart.library.html` is available.
class FlutterCropCameraWeb {
  static void registerWith([Object? _]) {}
}
