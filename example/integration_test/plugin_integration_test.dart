// This is a basic Flutter integration test.
//
// Since integration tests run in a full Flutter application, they can interact
// with the host side of a plugin implementation, unlike Dart unit tests.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_crop_camera/flutter_crop_camera.dart';
import 'package:flutter/material.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FlutterCropCamera initialization test', (
    WidgetTester tester,
  ) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FlutterCropCamera(
            onImageCaptured: (file) {
              // Callback
            },
          ),
        ),
      ),
    );

    // Wait for camera initialization (async)
    await tester.pumpAndSettle();

    // Just verify the widget is present
    expect(find.byType(FlutterCropCamera), findsOneWidget);
  });
}
