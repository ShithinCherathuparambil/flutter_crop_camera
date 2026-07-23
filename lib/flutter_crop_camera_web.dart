import 'dart:async';
import 'dart:js_interop';
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

import 'flutter_crop_camera_platform_interface.dart';

/// The web implementation of [FlutterCropCameraPlatform].
/// Uses the browser MediaDevices API for camera access and
/// <input type="file"> for gallery picking.
class FlutterCropCameraWeb extends FlutterCropCameraPlatform {
  static void registerWith(Registrar registrar) {
    FlutterCropCameraPlatform.instance = FlutterCropCameraWeb();
  }

  // MediaStream currently active
  web.MediaStream? _mediaStream;

  // Hidden video element used for camera frame capture
  web.HTMLVideoElement? _videoElement;

  // Constraints used to start the camera
  String _facing = 'user'; // 'user' = front, 'environment' = back
  String _aspectRatio = '3:4';
  double _quality = 1.0;

  @override
  Future<String?> getPlatformVersion() async => 'Web';

  // ---------------------------------------------------------------------------
  // Camera
  // ---------------------------------------------------------------------------

  @override
  Future<int?> startCamera({
    double quality = 1.0,
    String facing = 'back',
    String aspectRatio = '3:4',
  }) async {
    _quality = quality;
    _aspectRatio = aspectRatio;
    _facing = facing == 'front' ? 'user' : 'environment';

    await _stopCurrentStream();

    // Build MediaStreamConstraints
    final videoConstraints = {
      'facingMode': _facing,
      'aspectRatio': _parseAspectRatioDouble(aspectRatio),
    }.jsify();

    final constraints = web.MediaStreamConstraints(
      video: videoConstraints as JSAny,
      audio: false.toJS,
    );

    try {
      _mediaStream = await web.window.navigator.mediaDevices
          .getUserMedia(constraints)
          .toDart;
    } catch (e) {
      debugPrint('flutter_crop_camera_web: getUserMedia error: $e');
      return null;
    }

    // Build a video element and attach the stream
    final video = web.HTMLVideoElement();
    video.autoplay = true;
    video.muted = true;
    video.srcObject = _mediaStream;
    video.style.width = '100%';
    video.style.height = '100%';
    video.style.objectFit = 'cover';
    _videoElement = video;

    // Register the platform view so CameraPreview can embed it
    const viewType = 'flutter_crop_camera_web_view';
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int id) => video);

    // Texture id is unused on web; return 0 as sentinel
    return 0;
  }

  @override
  Future<void> stopCamera() async {
    await _stopCurrentStream();
  }

  @override
  Future<int?> switchCamera() async {
    _facing = (_facing == 'user') ? 'environment' : 'user';
    return startCamera(
      quality: _quality,
      facing: _facing == 'user' ? 'front' : 'back',
      aspectRatio: _aspectRatio,
    );
  }

  @override
  Future<void> setZoom(double zoom) async {
    // MediaDevices zoom is behind a browser flag on most platforms; silently ignore.
  }

  @override
  Future<void> setFlashMode(String mode) async {
    // Flash/torch via MediaDevices.applyConstraints — not universally supported; silently ignore.
  }

  @override
  Future<double> getMaxZoom() async => 8.0;

  // ---------------------------------------------------------------------------
  // Capture
  // ---------------------------------------------------------------------------

  @override
  Future<String?> takePicture() async {
    if (_videoElement == null) return null;
    final video = _videoElement!;

    // Draw the current video frame onto a canvas
    final canvas = web.HTMLCanvasElement();
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;

    final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D?;
    if (ctx == null) return null;
    ctx.drawImage(video, 0, 0);

    // Export as data URL → convert to XFile-friendly blob URL
    final quality = (_quality * 100).round() / 100;
    final dataUrl = canvas.toDataURL('image/jpeg', quality.toJS);
    return dataUrl; // On web we return a data: URI as the "path"
  }

  // ---------------------------------------------------------------------------
  // Gallery picking
  // ---------------------------------------------------------------------------

  @override
  Future<String?> pickImage() async {
    final files = await _pickFiles(multiple: false);
    if (files == null || files.isEmpty) return null;
    return _blobUrlFromFile(files.first);
  }

  @override
  Future<List<String>?> pickImages() async {
    final files = await _pickFiles(multiple: true);
    if (files == null || files.isEmpty) return [];
    return Future.wait(files.map(_blobUrlFromFile));
  }

  // ---------------------------------------------------------------------------
  // Crop — pure Dart via dart:ui
  // ---------------------------------------------------------------------------

  @override
  Future<String?> cropImage({
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
      // Load image bytes
      Uint8List bytes;
      if (path.startsWith('data:')) {
        bytes = _dataUriToBytes(path);
      } else if (path.startsWith('blob:')) {
        bytes = await _fetchBlobBytes(path);
      } else {
        bytes = await XFile(path).readAsBytes();
      }

      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final srcImage = frame.image;

      // Rotate + flip via Picture/Canvas
      final recorder = ui.PictureRecorder();
      final rotRad = rotationDegrees * 3.141592653589793 / 180.0;
      int dstW = srcImage.width;
      int dstH = srcImage.height;
      if (rotationDegrees == 90 || rotationDegrees == 270) {
        dstW = srcImage.height;
        dstH = srcImage.width;
      }

      final canvas = ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, dstW.toDouble(), dstH.toDouble()));
      canvas.translate(dstW / 2, dstH / 2);
      canvas.rotate(rotRad);
      if (flipX) canvas.scale(-1, 1);
      canvas.drawImage(srcImage, ui.Offset(-srcImage.width / 2, -srcImage.height / 2), ui.Paint());

      final transformed = await recorder.endRecording().toImage(dstW, dstH);

      // Crop region
      final cropRect = ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), width.toDouble(), height.toDouble());
      final cropRecorder = ui.PictureRecorder();
      final cropCanvas = ui.Canvas(cropRecorder, cropRect);
      cropCanvas.drawImage(transformed, ui.Offset(-x.toDouble(), -y.toDouble()), ui.Paint());
      final cropped = await cropRecorder.endRecording().toImage(width, height);

      final byteData = await cropped.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return path;

      final pngBytes = byteData.buffer.asUint8List();

      // Return as data URI
      final base64 = _uint8ListToBase64(pngBytes);
      return 'data:image/png;base64,$base64';
    } catch (e) {
      debugPrint('flutter_crop_camera_web: cropImage error: $e');
      return path;
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<void> _stopCurrentStream() async {
    _mediaStream?.getTracks().toDart.forEach((t) => t.stop());
    _mediaStream = null;
    _videoElement = null;
  }

  double _parseAspectRatioDouble(String ratio) {
    final parts = ratio.split(':');
    if (parts.length == 2) {
      final a = double.tryParse(parts[0]);
      final b = double.tryParse(parts[1]);
      if (a != null && b != null && b != 0) return a / b;
    }
    return 3 / 4;
  }

  Future<List<web.File>?> _pickFiles({required bool multiple}) {
    final completer = Completer<List<web.File>?>();
    final input = web.HTMLInputElement();
    input.type = 'file';
    input.accept = 'image/*';
    input.multiple = multiple;
    input.style.display = 'none';
    web.document.body!.append(input);

    input.onchange = (web.Event _) {
      final fileList = input.files;
      if (fileList == null || fileList.length == 0) {
        completer.complete(null);
      } else {
        final files = <web.File>[];
        for (var i = 0; i < fileList.length; i++) {
          files.add(fileList.item(i)!);
        }
        completer.complete(files);
      }
      input.remove();
    }.toJS;

    input.oncancel = (web.Event _) {
      completer.complete(null);
      input.remove();
    }.toJS;

    input.click();
    return completer.future;
  }

  Future<String> _blobUrlFromFile(web.File file) {
    final completer = Completer<String>();
    final reader = web.FileReader();
    reader.onload = (web.ProgressEvent _) {
      final result = reader.result;
      if (result == null) {
        completer.completeError('FileReader result was empty');
        return;
      }
      completer.complete((result as JSString).toDart);
    }.toJS;
    reader.onerror = (web.ProgressEvent _) {
      completer.completeError('FileReader error');
    }.toJS;
    reader.readAsDataURL(file);
    return completer.future;
  }

  Uint8List _dataUriToBytes(String dataUri) {
    final comma = dataUri.indexOf(',');
    final base64Str = dataUri.substring(comma + 1);
    return base64Decode(base64Str);
  }

  Future<Uint8List> _fetchBlobBytes(String url) async {
    final response = await web.window.fetch(url.toJS).toDart;
    final buffer = await response.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  }

  String _uint8ListToBase64(Uint8List bytes) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    final result = StringBuffer();
    for (var i = 0; i < bytes.length; i += 3) {
      final b0 = bytes[i];
      final b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
      final b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;
      result.write(chars[(b0 >> 2) & 0x3F]);
      result.write(chars[((b0 << 4) | (b1 >> 4)) & 0x3F]);
      result.write(i + 1 < bytes.length ? chars[((b1 << 2) | (b2 >> 6)) & 0x3F] : '=');
      result.write(i + 2 < bytes.length ? chars[b2 & 0x3F] : '=');
    }
    return result.toString();
  }
}

// ---------------------------------------------------------------------------
// Internal helper — mirrors dart:convert base64 but avoids the import conflict
// ---------------------------------------------------------------------------
Uint8List base64Decode(String input) {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  final lookup = <int, int>{};
  for (var i = 0; i < chars.length; i++) {
    lookup[chars.codeUnitAt(i)] = i;
  }
  final src = input.replaceAll(RegExp(r'[^A-Za-z0-9+/=]'), '');
  final len = src.length;
  final outputLen = (len * 3 ~/ 4) - (src.endsWith('==') ? 2 : src.endsWith('=') ? 1 : 0);
  final out = Uint8List(outputLen);
  var j = 0;
  for (var i = 0; i < len; i += 4) {
    final n0 = lookup[src.codeUnitAt(i)] ?? 0;
    final n1 = lookup[src.codeUnitAt(i + 1)] ?? 0;
    final n2 = i + 2 < len ? (lookup[src.codeUnitAt(i + 2)] ?? 0) : 0;
    final n3 = i + 3 < len ? (lookup[src.codeUnitAt(i + 3)] ?? 0) : 0;
    if (j < outputLen) out[j++] = (n0 << 2) | (n1 >> 4);
    if (j < outputLen) out[j++] = ((n1 & 0xF) << 4) | (n2 >> 2);
    if (j < outputLen) out[j++] = ((n2 & 0x3) << 6) | n3;
  }
  return out;
}
