import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

// Conditional import: dart:io File is only available on non-web
import 'platform_io_web.dart'
    if (dart.library.io) 'platform_io_native.dart';

/// Cross-platform image provider builder.
/// On web: returns a NetworkImage for data: URIs, or a fallback.
/// On native: returns a FileImage.
ImageProvider buildXFileImageProvider(XFile xfile) {
  return buildImageProviderImpl(xfile.path);
}

/// Cross-platform write bytes to a path.
/// On web: no-op (web doesn't have a writable fs for data: URIs).
/// On native: writes bytes to the file at [path].
Future<void> writeBytesToPath(String path, Uint8List bytes) async {
  await writeBytesImpl(path, bytes);
}

/// Cross-platform delete a file at [path].
Future<void> deleteFilePath(String path) async {
  await deleteFileImpl(path);
}

/// Resolves the temporary directory path.
Future<String> resolveTempDirPath() async {
  if (kIsWeb) return '/tmp';
  try {
    final dir = await getTemporaryDirectory();
    return dir.path;
  } on MissingPluginException {
    return '/tmp';
  } on PlatformException {
    return '/tmp';
  }
}
