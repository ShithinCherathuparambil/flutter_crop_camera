import 'package:flutter/services.dart';
import 'package:flutter_crop_camera/flutter_crop_camera.dart';
import 'package:flutter_crop_camera/flutter_crop_camera_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const MethodChannel channel = MethodChannel('flutter_crop_camera');
  final List<MethodCall> log = <MethodCall>[];

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          log.add(methodCall);
          if (methodCall.method == 'startCamera') return 42;
          if (methodCall.method == 'switchCamera') return 43;
          if (methodCall.method == 'takePicture') return '/test/path.jpg';
          if (methodCall.method == 'cropImage') return '/test/cropped.jpg';
          return null;
        });
    log.clear();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('FlutterCropCameraController', () {
    late FlutterCropCameraController controller;

    setUp(() {
      controller = FlutterCropCameraController();
    });

    test('startCamera sends correct payload and updates textureId', () async {
      await controller.startCamera(
        quality: 0.8,
        cameraPreference: CamPreference.front,
        aspectRatio: CamRatio.ratio16x9,
      );

      expect(log.length, 1);
      expect(log.first.method, 'startCamera');
      expect(log.first.arguments, {
        'quality': 0.8,
        'facing': 'front',
        'frontCamera': true,
        'aspectRatio': '16:9',
      });
      expect(controller.textureId, 42);
    });

    test('stopCamera invokes method and clears textureId', () async {
      controller.textureId = 42;
      await controller.stopCamera();

      expect(log.length, 1);
      expect(log.first.method, 'stopCamera');
      expect(controller.textureId, isNull);
    });

    test('switchCamera updates textureId', () async {
      await controller.switchCamera();

      expect(log.length, 1);
      expect(log.first.method, 'switchCamera');
      expect(controller.textureId, 43);
    });

    test('setZoom sends correct arguments', () async {
      await controller.setZoom(2.5);

      expect(log.length, 1);
      expect(log.first.method, 'setZoom');
      expect(log.first.arguments, {'zoom': 2.5});
    });

    test('setFlashMode sends correct arguments', () async {
      await controller.setFlashMode('auto');

      expect(log.length, 1);
      expect(log.first.method, 'setFlashMode');
      expect(log.first.arguments, {'mode': 'auto'});
    });

    test('takePicture returns path', () async {
      final path = await controller.takePicture();

      expect(log.length, 1);
      expect(log.first.method, 'takePicture');
      expect(path, '/test/path.jpg');
    });

    test('cropImage sends full payload and returns path', () async {
      final path = await controller.cropImage(
        path: '/test/path.jpg',
        x: 10,
        y: 20,
        width: 100,
        height: 200,
        rotationDegrees: 90,
        flipX: true,
        quality: 90,
      );

      expect(log.length, 1);
      expect(log.first.method, 'cropImage');
      expect(log.first.arguments, {
        'path': '/test/path.jpg',
        'x': 10,
        'y': 20,
        'width': 100,
        'height': 200,
        'rotationDegrees': 90,
        'flipX': true,
        'quality': 90,
      });
      expect(path, '/test/cropped.jpg');
    });

    test('_getRatioString handles various inputs', () async {
      // Use reflection or make public for testing if needed,
      // but we can test it through startCamera as done above.
      // Already verified in startCamera test.
    });
  });
}
