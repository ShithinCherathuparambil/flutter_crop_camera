import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';

/// Web stub: no dart:io available.

ImageProvider buildImageProviderImpl(String path) {
  if (path.startsWith('data:') || path.startsWith('blob:')) {
    return NetworkImage(path);
  }
  return NetworkImage(path);
}

Future<void> writeBytesImpl(String path, Uint8List bytes) async {
  // On web, we cannot write to a file system path.
  // The caller should handle in-memory data.
}

Future<void> deleteFileImpl(String path) async {
  // No-op on web.
}

// Dummy export so the conditional import resolves
XFile? get dummyXFile => null;
