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

  Future<void> waitForImage(WidgetTester tester) async {
    // Initial pump to trigger initState
    await tester.pump();

    // decodeImageFromList is async and platform-bound.
    // We use runAsync to let it progress.
    await tester.runAsync(() async {
      // 2 seconds delay to be extra safe for platform-bound decoding
      await Future.delayed(const Duration(seconds: 2));
    });

    // Pump to process potential setState
    await tester.pump();

    // Verification: if it's still loading, try pumping more frames
    for (int i = 0; i < 20; i++) {
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('CropEditor Widget Tests', () {
    testWidgets('renders toolbar after loading', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // Verify loader shows up first
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await waitForImage(tester);

      // Verify toolbar buttons
      expect(find.byKey(const Key('crop_reset_button')), findsOneWidget);
      expect(find.byKey(const Key('crop_grid_button')), findsOneWidget);
      expect(find.byKey(const Key('crop_rotate_button')), findsOneWidget);
      expect(find.byKey(const Key('crop_mirror_button')), findsOneWidget);
    });

    testWidgets('toggle grid updates icon', (tester) async {
      await tester.pumpWidget(buildTestWidget(showGrid: true));
      await waitForImage(tester);

      // Initially grid_on
      expect(find.byIcon(Icons.grid_on), findsOneWidget);

      await tester.tap(find.byKey(const Key('crop_grid_button')));
      await tester.pump();

      expect(find.byIcon(Icons.grid_off), findsOneWidget);
    });

    testWidgets('lockAspectRatio hides ratio buttons', (tester) async {
      await tester.pumpWidget(buildTestWidget(lockAspectRatio: true));
      await waitForImage(tester);

      expect(find.text('Original'), findsNothing);
      expect(find.text('1:1'), findsNothing);
    });

    testWidgets('rotate button interaction', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await waitForImage(tester);

      await tester.tap(find.byKey(const Key('crop_rotate_button')));
      await tester.pump();
    });
  });
}
