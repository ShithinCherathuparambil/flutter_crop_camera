// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_crop_camera_example/main.dart';

void main() {
  testWidgets('Verify app UI elements', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that the app title is displayed.
    expect(find.text('Flutter Cam Cropper Example'), findsOneWidget);

    // Verify that the "Open Camera" button is present.
    expect(find.text('Open Camera'), findsOneWidget);

    // Verify that the crop settings switches are present.
    expect(find.text('Enable Cropping'), findsOneWidget);
  });
}
