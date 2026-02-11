import 'package:flutter/material.dart';
import '../flutter_crop_camera_controller.dart';

class CameraPreview extends StatelessWidget {
  final FlutterCropCameraController controller;

  const CameraPreview({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    if (controller.textureId == null) {
      return const Center(child: Text("Camera not initialized"));
    }
    return Texture(textureId: controller.textureId!);
  }
}
