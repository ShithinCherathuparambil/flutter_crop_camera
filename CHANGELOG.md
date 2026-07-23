## 0.6.0

### Full Desktop & Web Production Support

**macOS**
* **Camera** (new): Full `AVFoundation` live-preview and photo capture via `FlutterTexture` in Swift. Registers `AVCaptureSession` on a background thread; frames are streamed via `AVCaptureVideoDataOutputSampleBufferDelegate` → `copyPixelBuffer`. Works with built-in FaceTime HD camera and external USB webcams.
* **Gallery** (new): `pickImage` / `pickImages` use `package:file_selector` (native `NSOpenPanel`) — no native Swift code needed.
* **Crop** (new): Pure-Dart `dart:ui` Canvas pipeline (identical to Web) writes result to temp file.
* **Switch camera**: Supported via session teardown + restart with toggled `frontCamera` flag.
* **Zoom / Flash**: Silently no-op (webcams don't expose these APIs).
* Added `AVFoundation` framework to `flutter_crop_camera.podspec`.
* Bumped minimum macOS target to `10.15` (Catalina) for full AVFoundation parity.

**Windows**
* **Camera** (new): C++/WinRT `Windows.Media.Capture.MediaCapture` with `MediaFrameReader` for live BGRA frame streaming into `FlutterDesktopPixelBuffer` texture.
* **Gallery** (new): `pickImage` / `pickImages` use `package:file_selector` (native `IFileOpenDialog`) in Dart.
* **Crop** (new): Pure-Dart `dart:ui` Canvas pipeline.
* **takePicture**: Captures JPEG via `CapturePhotoToStreamAsync`, writes to `%LOCALAPPDATA%\Temp`.
* **Switch camera**: Cycles device by index from `DeviceInformation::FindAllAsync`.
* New `windows/` native directory (`CMakeLists.txt`, `flutter_crop_camera_plugin.h/.cpp`, C API shim).

**Linux**
* **Camera** (new): GStreamer 1.0 pipeline (`v4l2src ! videoconvert ! video/x-raw,format=BGRA ! appsink`) feeding a `FlPixelBufferTexture`.
* **Gallery** (new): `pickImage` / `pickImages` use `package:file_selector` (native GTK chooser) in Dart.
* **Crop** (new): Pure-Dart `dart:ui` Canvas pipeline.
* **takePicture**: Captures current frame buffer and saves as PNG via `GdkPixbuf`.
* Graceful `MissingPluginException` handling if GStreamer is unavailable at runtime.
* New `linux/` native directory (`CMakeLists.txt`, `flutter_crop_camera_plugin.h/.cc`).

**All Desktop Platforms**
* `pubspec.yaml`: Added `dartPluginClass` to macOS & Windows; added `pluginClass` to Linux so native method channels are wired correctly.
* Fixed `SystemChrome.setPreferredOrientations` guards to only run on Android/iOS — calling it on desktop caused a crash on some configurations.
* New `lib/src/desktop_crop_utils.dart`: shared pure-Dart crop pipeline for all desktop platforms.
* New `lib/src/desktop_file_picker.dart`: shared `file_selector` wrapper for all desktop gallery operations.

## 0.4.0

* **Migration**: Migrated to Flutter's built-in Kotlin support and the new Kotlin compiler options DSL.
* **Dependencies**: Bumped minimum supported Flutter version to `3.44.0` and Dart SDK to `3.12.0`.

## 0.3.1
* **Fix**: Exported platform-specific implementation classes (`FlutterCropCameraLinux`, etc.) from the main library. This resolves the `Undefined name` compilation errors in `dart_plugin_registrant.dart` for desktop and web platforms.

## 0.3.0
* **Multi-Platform Support**: Refactored the plugin to a **Federated Architecture**, enabling support for all 6 Flutter platforms.
* **Web, MacOS, Windows, Linux**: Added initial (placeholder) implementations for desktop and web.
* **Architecture**: Migrated to `FlutterCropCameraPlatform` interface for future-proof multi-platform extensions.

## 0.2.2
* **iOS**: Added support for **Swift Package Manager (SPM)**.
* **Maintenance**: Synced iOS podspec version and internal structure for better compatibility.

## 0.2.1
* **Fix**: Resolved `switchCamera` method signature mismatch on iOS.
* **Fix**: Improved aspect ratio persistence when switching cameras or re-initializing.

## 0.2.0
* **Major Feature**: Achieved full feature parity between Single Image and Multi-Image cropping editors.
* **New UI**: Separated Aspect Ratio cropping and Rotation controls into dedicated, intuitive tabs (`Crop` and `Rotate`).
* **Overlays**: Added Draggable, Scalable, and Rotatable **Text** and **Sticker (Emoji)** overlays to both editors.
* **Filters**: Integrated multiple professional Instagram-style photo color filters (Grayscale, Sepia, Pop, Vintage, Cool, etc.).
* **Baking Pipeline**: Implemented a standalone Flutter `Canvas`-based image baking pipeline to successfully merge filters, custom overlays, and rotation adjustments directly into the final output image natively.
* **Optimizations**: Added UI image downsampling for high-resolution images to prevent memory exhaustion and `PageView` gesture improvements.
* **Fixes**: Fixed `CamRatio.ratio1x1` not being respected in editors or for auto-cropping when editing is disabled.
* **Fixes**: Resolved `PlatformException` caused by simultaneous permission requests or picker activations.
- **iOS Enhancements**: Camera now automatically selects appropriate session presets based on the requested aspect ratio (e.g., 16:9 HD).
* **Stability**: Fixed all static analysis issues and improved `BuildContext` usage across async gaps.

## 0.1.11
* Optimized APK size by removing unused CameraX dependencies (`camera-view` and `camera-extensions`).
* Fixed layout crash in example app when no images are captured.
* Updated example widget tests to match current UI.

## 0.1.10
* Added comprehensive `EditorStyle` customization for crop handles, borders, grid, and navigation item colors.
* Fixed bug where `EditorStyle` was not propagated to editor widgets from the picker screen.
* Resolved hardcoded colors in aspect ratio buttons and rotation dial to respect `EditorStyle`.
* Optimized image saving using native-first cropping and parallel processing for multi-image editor.
* Fixed overlay rendering issues in single-image editor.
* UI improvements: Moved Save button to top bar and Reset button to bottom navigation bar.
* Improved iOS camera selection and zoom reliability.
* Updated documentation for better clarity on permissions and setup.

## 0.1.9
* Added comprehensive `EditorStyle` customization for crop handles, borders, grid, and navigation item colors.
* Added `editorStyle` parameter to `openCamera`, `pickImage`, and `pickMultipleImages`.
* Fixed bug where `EditorStyle` was not propagated to editor widgets from the picker screen.
* Fixed hardcoded colors in aspect ratio buttons and rotation dial to respect `EditorStyle`.
* Renamed `showCropUI` to `enableEdit` for better API clarity.

## 0.1.8
* Documentation alignment: updated release notes and README to match 0.1.8 feature set.

## 0.1.7
* Prevented multi-picker editor from crashing when picked files disappear by filtering missing files and notifying the user.

## 0.1.6
* Added Android runtime camera permission handling and documentation.

## 0.1.5
* Added safe fallback for temp directory lookup when path_provider isn’t registered.
* Documented MissingPluginException troubleshooting steps in README.

## 0.1.4
* Guarded `getMaxZoom` against MissingPluginException to avoid crash on older builds.

## 0.1.3
* Prevented Android crop OOMs by downsampling extremely large images during native crop.
* Android picker/crop temp files now use internal cache for better reliability.

## 0.1.2
* Fixed iOS gallery picker to preserve original image quality by copying the source file when available.
* Fixed single-image editor overlay export transforms to match multi-image editor.
* Added Android-safe overlay export path to prevent quality compression from stripping overlays.

## 0.1.1
* Fixed README.md image paths for pub.dev display.

## 0.1.0
* Refactored API: Introduced `ImageSourcePicker` class for method-based access.
* Added support for picking multiple images from gallery (`pickMultipleImages`).
* Added `pickImage` for single image selection from gallery.
* Replaced direct widget usage with `await`-based calls (`openCamera`).
* Updated documentation and screenshots.

## 0.0.7
* Added `camera_main.jpg` to screenshots.
* Updated `README.md` to display screenshots in description.

## 0.0.6
* Added missing screenshots to `pubspec.yaml`.

## 0.0.5
* Added `screenshots` configuration to `pubspec.yaml` for better pub.dev display.

## 0.0.4
* Added screenshot to README.md.

## 0.0.3
* Fixed Android build error: Removed deprecated `package` attribute from `AndroidManifest.xml`.
* Updated Android `minSdkVersion` to 24.
* improved documentation for platform-specific configuration.

## 0.0.2
* Fixed iOS crash on startup (MissingPluginException).
* Fixed iOS camera preview orientation issue in portrait mode.
* Fixed iOS camera preview orientation issue in portrait mode.
* Fixed iOS crop aspect ratio issue (images were always square).
* Updated Android package name to `com.crop.camera`.

## 0.0.1
* Initial release of Flutter Crop Camera.
* Native CameraX (Android) and AVFoundation (iOS) support.
* Integrated Instagram-style crop editor.
* Custom aspect ratios and aspect ratio locking.
* Camera controls: zoom, flash, front/rear toggle.
* Screen orientation locking support.
