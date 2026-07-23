import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../flutter_crop_camera_controller.dart';
import 'web_camera_view.dart'
    if (dart.library.io) 'web_camera_view_stub.dart';

/// [CameraPreview] displays the camera feed.
///
/// - On **Android/iOS**: renders the native texture via [Texture].
/// - On **Web**: embeds the `<video>` element via [HtmlElementView].
/// - On **macOS/Windows**: renders the native texture via [Texture].
class CameraPreview extends StatelessWidget {
  final FlutterCropCameraController controller;

  const CameraPreview({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      // Web: the video element was registered by FlutterCropCameraWeb.startCamera
      return const WebCameraView();
    }

    if (controller.textureId == null) {
      return const Center(
        child: Text(
          'Camera not initialized',
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    return Texture(textureId: controller.textureId!);
  }
}
