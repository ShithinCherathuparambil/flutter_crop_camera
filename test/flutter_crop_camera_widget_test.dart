import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_crop_camera/flutter_crop_camera.dart';

void main() {
  const MethodChannel channel = MethodChannel('flutter_crop_camera');
  final List<MethodCall> log = <MethodCall>[];

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          log.add(methodCall);
          if (methodCall.method == 'startCamera') {
            return 123; // textureId
          }
          if (methodCall.method == 'takePicture') {
            return '/tmp/test_image.jpg';
          }
          if (methodCall.method == 'cropImage') {
            return '/tmp/cropped_image.jpg';
          }
          return null;
        });
    log.clear();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Widget buildTestWidget({
    bool cropEnabled = false,
    Function(dynamic)? onImageCaptured,
  }) {
    return MaterialApp(
      home: FlutterCropCamera(
        onImageCaptured: onImageCaptured ?? (file) {},
        cropEnabled: cropEnabled,
      ),
    );
  }

  group('FlutterCropCamera Widget Tests', () {
    testWidgets('initializes and starts camera', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(
        log,
        contains(
          isA<MethodCall>().having((c) => c.method, 'method', 'startCamera'),
        ),
      );

      expect(find.byIcon(Icons.flash_off), findsOneWidget);
      expect(find.byKey(const Key('switch_camera_button')), findsOneWidget);
      expect(find.byKey(const Key('zoom_1x')), findsOneWidget);
      expect(find.byKey(const Key('zoom_2x')), findsOneWidget);
      expect(find.byKey(const Key('zoom_3x')), findsOneWidget);
    });

    testWidgets('toggle flash updates icons and calls native method', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();
      log.clear();

      // Off -> Auto
      await tester.tap(find.byKey(const Key('flash_button')));
      await tester.pump();
      expect(find.byIcon(Icons.flash_auto), findsOneWidget);
      expect(log.last.arguments, {'mode': 'auto'});

      // Auto -> On
      await tester.tap(find.byKey(const Key('flash_button')));
      await tester.pump();
      expect(find.byIcon(Icons.flash_on), findsOneWidget);
      expect(log.last.arguments, {'mode': 'on'});

      // On -> Off
      await tester.tap(find.byKey(const Key('flash_button')));
      await tester.pump();
      expect(find.byIcon(Icons.flash_off), findsOneWidget);
      expect(log.last.arguments, {'mode': 'off'});
    });

    testWidgets('zoom buttons call setZoom', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();
      log.clear();

      await tester.tap(find.byKey(const Key('zoom_2x')));
      await tester.pump();
      expect(log.last.method, 'setZoom');
      expect(log.last.arguments, {'zoom': 2.0});

      await tester.tap(find.byKey(const Key('zoom_3x')));
      await tester.pump();
      expect(log.last.arguments, {'zoom': 3.0});
    });

    testWidgets('switch camera button calls switchCamera', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();
      log.clear();

      await tester.tap(find.byKey(const Key('switch_camera_button')));
      await tester.pump();
      expect(log.any((call) => call.method == 'switchCamera'), isTrue);
    });

    testWidgets('shutter button triggers capture', (tester) async {
      bool captured = false;
      await tester.pumpWidget(
        buildTestWidget(onImageCaptured: (_) => captured = true),
      );
      await tester.pump();
      log.clear();

      await tester.tap(find.byKey(const Key('shutter_button')));
      await tester.pumpAndSettle();

      expect(log.any((call) => call.method == 'takePicture'), isTrue);
      expect(captured, isTrue);
    });
  });
}
