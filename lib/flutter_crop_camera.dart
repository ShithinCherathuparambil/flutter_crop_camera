import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/image_source_picker_screen.dart';
import 'src/shared_crop_widgets.dart';

// Export enums so users can use them
export 'src/image_source_picker_screen.dart'
    show PickSource, PickerMode, CamPreference;
export 'src/shared_crop_widgets.dart'
    show EditorFeatureToggles, EditorAppBarStyle, EditorStyle, CamRatio;

// Re-export XFile so callers don't need to import cross_file directly
export 'package:cross_file/cross_file.dart' show XFile;

// Export core classes
export 'flutter_crop_camera_platform_interface.dart';
export 'flutter_crop_camera_controller.dart';
export 'flutter_crop_camera_linux.dart';
export 'flutter_crop_camera_macos.dart';
export 'flutter_crop_camera_windows.dart';

// Export platform implementations
// Web: conditional export prevents dart:io from bleeding onto web
export 'flutter_crop_camera_web_stub.dart'
    if (dart.library.js_interop) 'flutter_crop_camera_web.dart';

class ImageSourcePicker {
  /// Opens the camera and returns the captured (and optionally cropped) image.
  ///
  /// Returns an [XFile] on success, or `null` if the user cancelled.
  Future<XFile?> openCamera({
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
    return result is XFile ? result : null;
  }

  /// Opens the gallery to pick a single image.
  ///
  /// Returns an [XFile] on success, or `null` if the user cancelled.
  Future<XFile?> pickImage({
    required BuildContext context,
    bool enableEdit = false,
    double quality = 1.0,
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
      source: PickSource.gallery,
      enableEdit: enableEdit,
      quality: quality,
      aspectRatio: aspectRatio,
      lockAspectRatio: lockAspectRatio,
      featureToggles: featureToggles,
      appBarStyle: appBarStyle,
      editorStyle: editorStyle,
      screenOrientations: screenOrientations,
      pickerMode: PickerMode.single,
    );
    return result is XFile ? result : null;
  }

  /// Opens the gallery to pick multiple images.
  ///
  /// Returns a list of [XFile] objects (may be empty if user cancelled).
  Future<List<XFile>> pickMultipleImages({
    required BuildContext context,
    bool enableEdit = false,
    double quality = 1.0,
    CamRatio aspectRatio = CamRatio.ratio3x4,
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
      aspectRatio: aspectRatio,
      featureToggles: featureToggles,
      appBarStyle: appBarStyle,
      editorStyle: editorStyle,
      screenOrientations: screenOrientations,
      pickerMode: PickerMode.multiple,
    );

    if (result is List<XFile>) {
      return result;
    } else if (result is List<dynamic>) {
      return result.whereType<XFile>().toList();
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
          onImageCaptured: (xfile) {
            Navigator.pop(context, xfile);
          },
          onImagesCaptured: (xfiles) {
            Navigator.pop(context, xfiles);
          },
        ),
      ),
    );
  }
}
