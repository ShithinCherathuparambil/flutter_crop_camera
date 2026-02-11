import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_crop_camera/flutter_crop_camera_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MethodChannelFlutterCropCamera', () {
    late MethodChannelFlutterCropCamera platform;
    const MethodChannel channel = MethodChannel('flutter_crop_camera');
    final List<MethodCall> log = <MethodCall>[];

    setUp(() {
      platform = MethodChannelFlutterCropCamera();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            log.add(methodCall);
            if (methodCall.method == 'getPlatformVersion') {
              return '42';
            }
            return null;
          });
      log.clear();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('getPlatformVersion returns expected value', () async {
      final version = await platform.getPlatformVersion();
      expect(version, '42');
      expect(log.length, 1);
      expect(log.first.method, 'getPlatformVersion');
    });
  });
}
