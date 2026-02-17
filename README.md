# Flutter Crop Camera

A high-performance Flutter camera plugin with a built-in, Instagram-inspired cropping editor. Designed for visual excellence and native performance using CameraX on Android and AVFoundation on iOS.

## Screenshots

<h3>Launch Camera</h3>
<p align="center">
  <img src="https://raw.githubusercontent.com/ShithinCherathuparambil/flutter_crop_camera/main/doc/screenshots/launch_camera_1.png" width="200" alt="Launch Camera 1" />
  <img src="https://raw.githubusercontent.com/ShithinCherathuparambil/flutter_crop_camera/main/doc/screenshots/launch_camera_2.png" width="200" alt="Launch Camera 2" />
  <img src="https://raw.githubusercontent.com/ShithinCherathuparambil/flutter_crop_camera/main/doc/screenshots/launch_camera_3.png" width="200" alt="Launch Camera 3" />
</p>

<h3>Pick from Gallery</h3>
<p align="center">
  <img src="https://raw.githubusercontent.com/ShithinCherathuparambil/flutter_crop_camera/main/doc/screenshots/gallery_picker_1.png" width="200" alt="Gallery Picker 1" />
  <img src="https://raw.githubusercontent.com/ShithinCherathuparambil/flutter_crop_camera/main/doc/screenshots/gallery_picker_2.png" width="200" alt="Gallery Picker 2" />
  <img src="https://raw.githubusercontent.com/ShithinCherathuparambil/flutter_crop_camera/main/doc/screenshots/gallery_picker_3.png" width="200" alt="Gallery Picker 3" />
</p>

<h3>Pick Multiple Images</h3>
<p align="center">
  <img src="https://raw.githubusercontent.com/ShithinCherathuparambil/flutter_crop_camera/main/doc/screenshots/multi_picker_1.png" width="200" alt="Multi Picker 1" />
  <img src="https://raw.githubusercontent.com/ShithinCherathuparambil/flutter_crop_camera/main/doc/screenshots/multi_picker_2.png" width="200" alt="Multi Picker 2" />
  <img src="https://raw.githubusercontent.com/ShithinCherathuparambil/flutter_crop_camera/main/doc/screenshots/multi_picker_3.png" width="200" alt="Multi Picker 3" />
</p>

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
  flutter_crop_camera: ^0.1.1
```

## Usage

### 1. Request Permissions

Ensure you have camera permissions handled. You can use a package like `permission_handler`.

### 2. Launch Camera

```dart
import 'package:flutter_crop_camera/flutter_crop_camera.dart';

// ... inside your widget ...

ElevatedButton(
  onPressed: () async {
    final ImageSourcePicker picker = ImageSourcePicker();
    
    // Open Camera
    final File? file = await picker.openCamera(
      context: context,
      cropEnabled: true, // Enable the cropping step
      screenOrientations: [DeviceOrientation.portraitUp], // Lock to portrait
    );

    if (file != null) {
      // Handle the resulting cropped image
      print("Cropped image path: ${file.path}");
    }
  },
  child: Text("Open Camera"),
)
```

### 3. Pick from Gallery

```dart
ElevatedButton(
  onPressed: () async {
    final ImageSourcePicker picker = ImageSourcePicker();
    
    // Pick single image from gallery
    final File? file = await picker.pickImage(
      context: context,
      cropEnabled: true, // Enable cropping for gallery image too
    );

    if (file != null) {
      print("Picked image path: ${file.path}");
    }
  },
  child: Text("Pick from Gallery"),
)
```

### 4. Pick Multiple Images from Gallery

```dart
ElevatedButton(
  onPressed: () async {
    final ImageSourcePicker picker = ImageSourcePicker();
    
    // Pick multiple images
    final List<File> files = await picker.pickMultipleImages(
      context: context,
      cropEnabled: true, // Enable cropping for all images
    );

    if (files.isNotEmpty) {
      // Handle the list of files
      for (var file in files) {
        print("Picked image: ${file.path}");
      }
    }
  },
  child: Text("Pick Multiple Images"),
)
```

## Migration Guide (0.0.x -> 0.1.1)

Version `0.1.1` introduces a cleaner, method-based API using `ImageSourcePicker`, replacing the direct usage of the `FlutterCropCamera` widget.

### Old Code (v0.0.x)
```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => Scaffold(
      body: FlutterCropCamera(
        cropEnabled: true,
        onImageCaptured: (file) {
          // Handle result
        },
      ),
    ),
  ),    
);
```

### New Code (v0.1.1)
```dart
final file = await ImageSourcePicker().openCamera(
  context: context,
  cropEnabled: true,
);
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
