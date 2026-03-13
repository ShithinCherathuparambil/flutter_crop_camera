import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/image_source_picker_screen.dart';
import 'src/shared_crop_widgets.dart';

// Export enums so users can use them
export 'src/image_source_picker_screen.dart'
    show PickSource, PickerMode, CamPreference, CamRatio;
export 'src/shared_crop_widgets.dart'
    show EditorFeatureToggles, EditorAppBarStyle, EditorStyle;

class ImageSourcePicker {
  /// Opens the camera and returns the captured (and optionally cropped) image.
  Future<File?> openCamera({
    required BuildContext context,
    bool enableEdit = false,
    double quality = 1.0,
    CamPreference initialCamera = CamPreference.rear,
    CamRatio aspectRatio = CamRatio.ratio3x4,
    bool lockAspectRatio = false,
    EditorFeatureToggles featureToggles = const EditorFeatureToggles(),
    EditorAppBarStyle appBarStyle = const EditorAppBarStyle(),
    EditorStyle editorStyle = const EditorStyle(),
    List<DeviceOrientation> screenOrientations = const [
      DeviceOrientation.portraitUp,
    ],
  }) async {
    final result = await _pushPicker(
      context,
      source: PickSource.camera,
      enableEdit: enableEdit,
      quality: quality,
      initialCamera: initialCamera,
      aspectRatio: aspectRatio,
      lockAspectRatio: lockAspectRatio,
      featureToggles: featureToggles,
      appBarStyle: appBarStyle,
      editorStyle: editorStyle,
      screenOrientations: screenOrientations,
      pickerMode: PickerMode.single,
    );
    return result is File ? result : null;
  }

  /// Opens the gallery to pick a single image.
  Future<File?> pickImage({
    required BuildContext context,
    bool enableEdit = false,
    double quality = 1.0,
    bool lockAspectRatio = false,
    EditorFeatureToggles featureToggles = const EditorFeatureToggles(),
    EditorAppBarStyle appBarStyle = const EditorAppBarStyle(),
    EditorStyle editorStyle = const EditorStyle(),
    List<DeviceOrientation> screenOrientations = const [
      DeviceOrientation.portraitUp,
    ],
  }) async {
    final result = await _pushPicker(
      context,
      source: PickSource.gallery,
      enableEdit: enableEdit,
      quality: quality,
      lockAspectRatio: lockAspectRatio,
      featureToggles: featureToggles,
      appBarStyle: appBarStyle,
      editorStyle: editorStyle,
      screenOrientations: screenOrientations,
      pickerMode: PickerMode.single,
    );
    return result is File ? result : null;
  }

  /// Opens the gallery to pick multiple images.
  Future<List<File>> pickMultipleImages({
    required BuildContext context,
    bool enableEdit = false,
    double quality = 1.0,
    EditorFeatureToggles featureToggles = const EditorFeatureToggles(),
    EditorAppBarStyle appBarStyle = const EditorAppBarStyle(),
    EditorStyle editorStyle = const EditorStyle(),
    List<DeviceOrientation> screenOrientations = const [
      DeviceOrientation.portraitUp,
    ],
  }) async {
    final result = await _pushPicker(
      context,
      source: PickSource.gallery,
      enableEdit: enableEdit,
      quality: quality,
      featureToggles: featureToggles,
      appBarStyle: appBarStyle,
      editorStyle: editorStyle,
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
    bool enableEdit = false,
    double quality = 1.0,
    CamPreference initialCamera = CamPreference.rear,
    CamRatio aspectRatio = CamRatio.ratio3x4,
    bool lockAspectRatio = false,
    EditorFeatureToggles featureToggles = const EditorFeatureToggles(),
    EditorAppBarStyle appBarStyle = const EditorAppBarStyle(),
    EditorStyle editorStyle = const EditorStyle(),
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
          enableEdit: enableEdit,
          quality: quality,
          initialCamera: initialCamera,
          aspectRatio: aspectRatio,
          lockAspectRatio: lockAspectRatio,
          featureToggles: featureToggles,
          appBarStyle: appBarStyle,
          editorStyle: editorStyle,
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
