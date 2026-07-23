import 'dart:io';
import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';

/// Native implementation using dart:io.

ImageProvider buildImageProviderImpl(String path) {
  return FileImage(File(path));
}

Future<void> writeBytesImpl(String path, Uint8List bytes) async {
  await File(path).writeAsBytes(bytes);
}

Future<void> deleteFileImpl(String path) async {
  try {
    final f = File(path);
    if (await f.exists()) {
      await f.delete();
    }
  } catch (_) {}
}

// Dummy export for symmetry
XFile? get dummyXFile => null;
