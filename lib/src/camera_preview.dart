import 'package:flutter/material.dart';
import '../flutter_crop_camera_controller.dart';

/// [CameraPreview] is a simple wrapper around the Flutter [Texture] widget.
/// It displays the raw camera feed provided by the native side using a [textureId].
class CameraPreview extends StatelessWidget {
  /// The controller that holds the current [textureId].
  final FlutterCropCameraController controller;

  const CameraPreview({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    // If the camera is not yet initialized or has been stopped,
    // we show a simple placeholder text.
    if (controller.textureId == null) {
      return const Center(
        child: Text(
          "Camera not initialized",
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    // The Texture widget renders a hardware-backed buffer (the camera feed)
    // onto the Flutter screen using the ID mapping to the native texture.
    return Texture(textureId: controller.textureId!);
  }
}
