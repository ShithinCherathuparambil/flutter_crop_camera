import 'package:file_selector/file_selector.dart';

/// Type group accepted by the desktop file picker (common image formats).
const _imageTypeGroup = XTypeGroup(
  label: 'Images',
  extensions: <String>[
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'bmp',
    'heic',
    'heif',
    'tiff',
    'tif',
  ],
  mimeTypes: <String>[
    'image/jpeg',
    'image/png',
    'image/gif',
    'image/webp',
    'image/bmp',
    'image/heic',
    'image/tiff',
  ],
);

/// Opens a native OS file-picker dialog and returns the selected image path,
/// or `null` if the user cancelled.
///
/// Backed by `package:file_selector` which uses the correct native dialog on
/// macOS (NSOpenPanel), Windows (IFileOpenDialog) and Linux (Zenity/GTK).
Future<String?> desktopPickImage() async {
  final XFile? file = await openFile(acceptedTypeGroups: [_imageTypeGroup]);
  return file?.path;
}

/// Opens a native OS file-picker dialog allowing multiple selections.
///
/// Returns a list of paths (possibly empty if the user cancelled or selected
/// nothing), or `null` if the picker itself failed.
Future<List<String>?> desktopPickImages() async {
  final List<XFile> files =
      await openFiles(acceptedTypeGroups: [_imageTypeGroup]);
  if (files.isEmpty) return null;
  return files.map((f) => f.path).toList();
}
