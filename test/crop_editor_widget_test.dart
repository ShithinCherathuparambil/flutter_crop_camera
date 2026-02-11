import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_crop_camera/src/crop_editor.dart';

void main() {
  late File testFile;

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

    testFile = File('${Directory.systemTemp.path}/test_crop_editor.png');
    await testFile.writeAsBytes(bytes);
  });

  tearDownAll(() async {
    try {
      if (await testFile.exists()) await testFile.delete();
    } catch (_) {}
  });

  Widget buildTestWidget({bool showGrid = true, bool lockAspectRatio = false}) {
    return MaterialApp(
      home: CropEditor(
        file: testFile,
        onCrop: (x, y, w, h, roll, flip) {},
        showGrid: showGrid,
        lockAspectRatio: lockAspectRatio,
        screenOrientations: const [], // Empty or any list for test
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
      await tester.pumpWidget(
        buildTestWidget(showGrid: false, lockAspectRatio: true),
      );

      // Verify the widget builds with different parameters
      expect(find.byType(CropEditor), findsOneWidget);
    });
  });
}
