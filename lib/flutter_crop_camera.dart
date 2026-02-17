import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/image_source_picker_screen.dart';

// Export enums so users can use them
export 'src/image_source_picker_screen.dart'
    show PickSource, PickerMode, CamPreference, CamRatio;

class ImageSourcePicker {
  /// Opens the camera and returns the captured (and optionally cropped) image.
  Future<File?> openCamera({
    required BuildContext context,
    bool cropEnabled = false,
    double quality = 1.0,
    CamPreference initialCamera = CamPreference.rear,
    CamRatio aspectRatio = CamRatio.ratio3x4,
    bool showGrid = true,
    bool lockAspectRatio = false,
    List<DeviceOrientation> screenOrientations = const [
      DeviceOrientation.portraitUp,
    ],
  }) async {
    final result = await _pushPicker(
      context,
      source: PickSource.camera,
      cropEnabled: cropEnabled,
      quality: quality,
      initialCamera: initialCamera,
      aspectRatio: aspectRatio,
      showGrid: showGrid,
      lockAspectRatio: lockAspectRatio,
      screenOrientations: screenOrientations,
      pickerMode: PickerMode.single,
    );
    return result is File ? result : null;
  }

  /// Opens the gallery to pick a single image.
  Future<File?> pickImage({
    required BuildContext context,
    bool cropEnabled = false,
    double quality = 1.0,
    bool showGrid = true,
    bool lockAspectRatio = false,
    List<DeviceOrientation> screenOrientations = const [
      DeviceOrientation.portraitUp,
    ],
  }) async {
    final result = await _pushPicker(
      context,
      source: PickSource.gallery,
      cropEnabled: cropEnabled,
      quality: quality,
      showGrid: showGrid,
      lockAspectRatio: lockAspectRatio,
      screenOrientations: screenOrientations,
      pickerMode: PickerMode.single,
    );
    return result is File ? result : null;
  }

  /// Opens the gallery to pick multiple images.
  Future<List<File>> pickMultipleImages({
    required BuildContext context,
    bool cropEnabled = false,
    double quality = 1.0,
    bool showGrid = true,
    List<DeviceOrientation> screenOrientations = const [
      DeviceOrientation.portraitUp,
    ],
  }) async {
    final result = await _pushPicker(
      context,
      source: PickSource.gallery,
      cropEnabled: cropEnabled,
      quality: quality,
      showGrid: showGrid,
      screenOrientations: screenOrientations,
      pickerMode: PickerMode.multiple,
    );

    if (result is List<File>) {
      return result;
    } else if (result is List<dynamic>) {
      // Safety check if dynamic list returned
      return result.map((e) => e as File).toList();
    }
    return [];
  }

  Future<dynamic> _pushPicker(
    BuildContext context, {
    required PickSource source,
    required PickerMode pickerMode,
    bool cropEnabled = false,
    double quality = 1.0,
    CamPreference initialCamera = CamPreference.rear,
    CamRatio aspectRatio = CamRatio.ratio3x4,
    bool showGrid = true,
    bool lockAspectRatio = false,
    List<DeviceOrientation> screenOrientations = const [
      DeviceOrientation.portraitUp,
    ],
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ImageSourcePickerScreen(
          source: source,
          pickerMode: pickerMode,
          cropEnabled: cropEnabled,
          quality: quality,
          initialCamera: initialCamera,
          aspectRatio: aspectRatio,
          showGrid: showGrid,
          lockAspectRatio: lockAspectRatio,
          screenOrientations: screenOrientations,
          onImageCaptured: (file) {
            Navigator.pop(context, file);
          },
          onImagesCaptured: (files) {
            Navigator.pop(context, files);
          },
        ),
      ),
    );
  }
}
