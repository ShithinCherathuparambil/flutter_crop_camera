# Flutter Crop Camera

A high-performance Flutter camera plugin with a built-in, Instagram-inspired cropping editor. Designed for visual excellence and native performance using CameraX on Android and AVFoundation on iOS.

## Features

- 📸 **Native Camera Preview**: High-resolution preview using native platform integrations.
- ✂️ **Advanced Cropping**: Integrated crop editor with support for:
  - Custom aspect ratios (1:1, 4:5, 16:9, etc.).
  - Free cropping and aspect ratio locking.
  - Rotation (90° steps) and horizontal flipping (mirroring).
  - Rule-of-thirds grid overlay.
- 🔍 **Zoom Control**: Smooth digital zoom (1x, 2x, 3x).
- ⚡ **Flash Modes**: Support for Off, Auto, and On.
- 🔄 **Camera Switching**: Toggle between front and rear cameras.
- 📱 **Orientation Locking**: Force camera and editor screens into specific orientations (e.g., Portrait only).
- 🎨 **Premium UI**: Sleek, dark-themed interface with micro-animations.

## Installation

Add `flutter_crop_camera` to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_crop_camera: ^0.0.3
```

## Usage

### 1. Request Permissions

Ensure you have camera permissions handled. You can use a package like `permission_handler`.

### 2. Launch Camera

```dart
import 'package:flutter_crop_camera/flutter_crop_camera.dart';

// ... inside your widget ...

ElevatedButton(
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          body: FlutterCropCamera(
            cropEnabled: true, // Enable the cropping step
            onImageCaptured: (File imageFile) {
              // Handle the resulting cropped image
              print("Cropped image path: ${imageFile.path}");
              Navigator.pop(context);
            },
            screenOrientations: [DeviceOrientation.portraitUp], // Lock to portrait
          ),
        ),
      ),
    );
  },
  child: Text("Open Camera"),
)
```

## Platform Setup

### Android
Min SDK version: **24**

Add the following to your `AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-feature android:name="android.hardware.camera" />
<uses-feature android:name="android.hardware.camera.autofocus" />
```

### iOS
Requires **iOS 13.0** or higher.

1. Add the following keys to your `Info.plist` file:
```xml
<key>NSCameraUsageDescription</key>
<string>This app needs camera access to take and crop photos</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>This app needs photo library access to save photos</string>
```

2. Add this `post_install` script to your `Podfile` to ensure permissions are handled correctly:
```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',
        'PERMISSION_CAMERA=1',
        'PERMISSION_PHOTOS=1',
      ]
    end
  end
end
```

## License

MIT
