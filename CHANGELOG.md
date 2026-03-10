## 0.2.0
* **Major Feature**: Achieved full feature parity between Single Image and Multi-Image cropping editors.
* **New UI**: Separated Aspect Ratio cropping and Rotation controls into dedicated, intuitive tabs (`Crop` and `Rotate`).
* **Overlays**: Added Draggable, Scalable, and Rotatable **Text** and **Sticker (Emoji)** overlays to both editors.
* **Filters**: Integrated multiple professional Instagram-style photo color filters (Grayscale, Sepia, Pop, Vintage, Cool, etc.).
* **Baking Pipeline**: Implemented a standalone Flutter `Canvas`-based image baking pipeline to successfully merge filters, custom overlays, and rotation adjustments directly into the final output image natively.
* **Optimizations**: Added UI image downsampling for high-resolution images to prevent memory exhaustion and `PageView` gesture improvements.
* **Testing**: Added comprehensive automated Widget and Unit testing coverage.

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
* Fixed iOS crop aspect ratio issue (images were always square).
* Updated Android package name to `com.crop.camera`.

## 0.0.1

* Initial release of Flutter Crop Camera.
* Native CameraX (Android) and AVFoundation (iOS) support.
* Integrated Instagram-style crop editor.
* Custom aspect ratios and aspect ratio locking.
* Camera controls: zoom, flash, front/rear toggle.
* Screen orientation locking support.
