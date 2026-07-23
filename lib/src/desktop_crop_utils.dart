import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';

import 'platform_io.dart';

/// Pure-Dart image crop implementation for desktop platforms (macOS, Windows, Linux).
///
/// Uses [dart:ui] Canvas for pixel-perfect rotate / flip / crop operations and
/// writes the result to a temp file via [platform_io].  This is functionally
/// identical to the Web implementation but stores output on the filesystem
/// instead of returning a data URI.
Future<String?> desktopCropImage({
  required String path,
  required int x,
  required int y,
  required int width,
  required int height,
  int rotationDegrees = 0,
  bool flipX = false,
  int quality = 100,
}) async {
  try {
    // ── 1. Read bytes (XFile works on all platforms) ──────────────────────────
    final bytes = await XFile(path).readAsBytes();

    // ── 2. Decode image ───────────────────────────────────────────────────────
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final srcImage = frame.image;

    // ── 3. Apply rotation + horizontal flip ───────────────────────────────────
    final rotRad = rotationDegrees * 3.141592653589793 / 180.0;
    int dstW = srcImage.width;
    int dstH = srcImage.height;
    if (rotationDegrees == 90 || rotationDegrees == 270) {
      dstW = srcImage.height;
      dstH = srcImage.width;
    }

    final rotRecorder = ui.PictureRecorder();
    final rotCanvas = ui.Canvas(
      rotRecorder,
      ui.Rect.fromLTWH(0, 0, dstW.toDouble(), dstH.toDouble()),
    );
    rotCanvas.translate(dstW / 2, dstH / 2);
    rotCanvas.rotate(rotRad);
    if (flipX) rotCanvas.scale(-1, 1);
    rotCanvas.drawImage(
      srcImage,
      ui.Offset(-srcImage.width / 2.0, -srcImage.height / 2.0),
      ui.Paint(),
    );
    final transformed =
        await rotRecorder.endRecording().toImage(dstW, dstH);

    // ── 4. Crop the transformed image ─────────────────────────────────────────
    final cropRecorder = ui.PictureRecorder();
    final cropRect = ui.Rect.fromLTWH(
      x.toDouble(),
      y.toDouble(),
      width.toDouble(),
      height.toDouble(),
    );
    final cropCanvas = ui.Canvas(cropRecorder, cropRect);
    cropCanvas.drawImage(
      transformed,
      ui.Offset(-x.toDouble(), -y.toDouble()),
      ui.Paint(),
    );
    final cropped =
        await cropRecorder.endRecording().toImage(width, height);

    // ── 5. Encode to PNG bytes ────────────────────────────────────────────────
    final byteData =
        await cropped.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;
    final pngBytes = byteData.buffer.asUint8List();

    // ── 6. Write to temp file ─────────────────────────────────────────────────
    final tempDir = await resolveTempDirPath();
    final outPath =
        '$tempDir/cropped_${DateTime.now().millisecondsSinceEpoch}.png';
    await writeBytesToPath(outPath, pngBytes);
    return outPath;
  } catch (e, st) {
    debugPrint('desktopCropImage error: $e\n$st');
    return null;
  }
}

/// Reads raw image bytes from [path] and returns them as [Uint8List].
/// Uses [XFile] for cross-platform compatibility.
Future<Uint8List> readImageBytes(String path) async {
  return XFile(path).readAsBytes();
}
