import 'package:flutter/material.dart';

/// On web, the camera preview is rendered as a platform view embedding
/// the `<video>` element registered by [FlutterCropCameraWeb.startCamera].
/// The view-factory is registered with the id 'flutter_crop_camera_web_view'.
class WebCameraView extends StatelessWidget {
  const WebCameraView({super.key});

  @override
  Widget build(BuildContext context) {
    return const HtmlElementView(viewType: 'flutter_crop_camera_web_view');
  }
}
