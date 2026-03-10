import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_crop_camera/src/multi_crop_editor.dart';
import 'package:flutter_crop_camera/src/shared_crop_widgets.dart';

void main() {
  late List<File> testFiles;

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

    final file1 = File('${Directory.systemTemp.path}/test_multi_1.png');
    final file2 = File('${Directory.systemTemp.path}/test_multi_2.png');
    await file1.writeAsBytes(bytes);
    await file2.writeAsBytes(bytes);
    testFiles = [file1, file2];
  });

  tearDownAll(() async {
    for (var file in testFiles) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  });

  Widget buildTestWidget() {
    return MaterialApp(
      theme: ThemeData(useMaterial3: false),
      home: MultiCropEditor(
        files: testFiles,
        onImagesCropped: (files) {},
        cropNative: (path, x, y, w, h, rot, flip) async {},
      ),
    );
  }

  group('MultiCropEditor Widget Tests', () {
    testWidgets('renders all navigation tabs', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      // Wait for images to load (don't use pumpAndSettle due to spinner)
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('Crop'), findsOneWidget);
      expect(find.text('Rotate'), findsOneWidget);
      expect(find.text('Filter'), findsOneWidget);
      expect(find.text('Text'), findsOneWidget);
      expect(find.text('Sticker'), findsOneWidget);
      expect(find.text('Grid'), findsOneWidget);
      expect(find.text('Flip'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('switches between Crop and Rotate modes', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Initially in Crop mode (shows ratios)
      expect(find.text('FREE'), findsOneWidget);
      expect(find.byType(RotationDial), findsNothing);

      // Switch to Rotate mode
      await tester.tap(find.text('Rotate'));
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('FREE'), findsNothing);
      expect(find.byType(RotationDial), findsOneWidget);
    });

    testWidgets('reset button appears and works', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final resetBtn = find.byIcon(Icons.refresh);
      expect(resetBtn, findsOneWidget);

      // Simulate a change
      await tester.tap(find.text('Flip'));
      await tester.pump();

      // Tap reset
      await tester.tap(resetBtn);
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Verify reset logic (this is more unit-y but we check UI doesn't crash)
      expect(find.byType(MultiCropEditor), findsOneWidget);
    });

    testWidgets('can switch between images', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Swipe the PageView
      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Hard to check internal state directly, but we verify it didn't crash.
      expect(find.byType(MultiCropEditor), findsOneWidget);
    });
  });
}
