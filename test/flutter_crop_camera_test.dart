import 'package:flutter/services.dart';
import 'package:flutter_crop_camera/flutter_crop_camera_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const MethodChannel channel = MethodChannel('flutter_crop_camera');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          return '42'; // Mock return value
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('startCamera', () async {
    final controller = FlutterCropCameraController();
    // Verify that calling startCamera invokes the platform channel
    // In a real test we'd mock the channel and verify call.method == 'startCamera'
    // For now we just ensure no exception is thrown
    await controller.startCamera();
    // Note: startCamera returns void, but we can check if textureId is handled if we mock the return to be an int
  });
}
