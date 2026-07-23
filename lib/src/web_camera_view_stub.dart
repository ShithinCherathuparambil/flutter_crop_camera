import 'package:flutter/material.dart';

/// Stub used on non-web targets so the conditional import in camera_preview.dart
/// still resolves without importing dart:html / package:web.
class WebCameraView extends StatelessWidget {
  const WebCameraView({super.key});

  @override
  Widget build(BuildContext context) =>
      const SizedBox.shrink(); // Never reached on non-web
}
