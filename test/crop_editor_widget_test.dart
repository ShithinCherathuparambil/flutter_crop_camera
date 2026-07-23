import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_crop_camera/src/crop_editor.dart';

void main() {
  late XFile testFile;

  setUpAll(() async {
    // Generate a valid 1x1 PNG dynamically
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 1, 1),
      Paint()..color = Colors.black,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(1, 1);
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    final Uint8List bytes = byteData!.buffer.asUint8List();

    final path = '${io.Directory.systemTemp.path}/test_crop_editor.png';
    final file = io.File(path);
    await file.writeAsBytes(bytes);
    testFile = XFile(file.path);
  });

  tearDownAll(() async {
    try {
      final f = io.File(testFile.path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  });

  Widget buildTestWidget({bool lockAspectRatio = false}) {
    return MaterialApp(
      home: CropEditor(
        xfile: testFile,
        onImageSaved: (xfile) {},
        cropNative: (path, x, y, width, height, rotation, flipX) async => '',
        lockAspectRatio: lockAspectRatio,
        screenOrientations: const [],
      ),
    );
  }

  group('CropEditor Widget Tests', () {
    testWidgets('shows loading indicator initially', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // Verify loader shows up initially
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('widget builds without errors', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // Verify the widget builds
      expect(find.byType(CropEditor), findsOneWidget);
    });

    testWidgets('accepts different parameters', (tester) async {
      await tester.pumpWidget(buildTestWidget(lockAspectRatio: true));

      // Verify the widget builds with different parameters
      expect(find.byType(CropEditor), findsOneWidget);
    });
  });
}
