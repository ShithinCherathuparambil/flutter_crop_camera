import 'dart:io';
import 'package:flutter/material.dart';
import 'flutter_crop_camera_controller.dart';
import 'src/camera_preview.dart';
import 'src/crop_editor.dart';

enum CamPreference { front, rear }

enum CamRatio { ratio3x4, ratio4x3, ratio9x16, ratio16x9, ratio1x1 }

class FlutterCropCamera extends StatefulWidget {
  /// **Enable Cropping**
  ///
  /// If set to `true`, the user will be navigated to a crop editor screen
  /// immediately after capturing an image. This allows them to adjust the
  /// frame using pan, zoom, and rotation controls before confirming the
  /// final image.
  ///
  /// Defaults to `false`.
  final bool cropEnabled;

  /// **Image Capture Callback**
  ///
  /// A callback function that is triggered when the final image is ready.
  /// - If [cropEnabled] is `false`, this returns the raw captured image [File].
  /// - If [cropEnabled] is `true`, this returns the cropped and processed image [File].
  ///
  /// This is where you should handle the resulting image, such as displaying it,
  /// uploading it to a server, or saving it to the gallery.
  final Function(File) onImageCaptured;

  /// **Image Quality**
  ///
  /// Defines the compression quality of the captured image.
  /// - Range: `0.0` (lowest quality) to `1.0` (highest quality).
  /// - A value of `1.0` means no compression (original quality).
  /// - Lower values reduce file size but may introduce artifacts.
  ///
  /// Defaults to `1.0`.
  final double quality;

  /// **Initial Camera Lens**
  ///
  /// Specifies which camera to open by default when the widget initializes.
  /// - [CamPreference.rear]: Starts with the back-facing camera.
  /// - [CamPreference.front]: Starts with the front-facing (selfie) camera.
  ///
  /// Users can still switch cameras manually using the UI toggle.
  /// Defaults to [CamPreference.rear].
  final CamPreference initialCamera;

  /// **Camera Aspect Ratio**
  ///
  /// Sets the initial aspect ratio for the camera preview and capture.
  /// This determines the shape of the viewfinder.
  ///
  /// Available options:
  /// - [CamRatio.ratio3x4]: Standard portrait photography (3:4)
  /// - [CamRatio.ratio4x3]: Standard landscape photography (4:3)
  /// - [CamRatio.ratio9x16]: Cinematic full-screen portrait (9:16)
  /// - [CamRatio.ratio16x9]: Cinematic full-screen landscape (16:9)
  /// - [CamRatio.ratio1x1]: Square format (1:1), ideal for social media.
  ///
  /// Defaults to [CamRatio.ratio3x4].
  final CamRatio aspectRatio;

  /// **Show/Hide Grid**
  ///
  /// Controls the visibility of the grid overlay in the **Crop Editor**.
  ///
  /// - `true`: Displays a 3x3 rule-of-thirds grid to assist with composition.
  /// - `false`: Hides the grid for a cleaner view.
  ///
  /// Users can toggle this manually in the crop editor UI.
  /// Defaults to `true`.
  final bool showGrid;

  /// **Lock Aspect Ratio**
  ///
  /// Determines whether the user can change the aspect ratio in the **Crop Editor**.
  ///
  /// - `true`: The aspect ratio selection toolbar is hidden in the crop editor.
  ///   The user is forced to crop maintaining the ratio defined by [aspectRatio].
  /// - `false`: The aspect ratio toolbar is visible, allowing the user to
  ///   choose freely between different ratios (Original, 1:1, 4:5, etc.).
  ///
  /// Defaults to `false`.
  final bool lockAspectRatio;

  const FlutterCropCamera({
    super.key,
    this.cropEnabled = false,
    required this.onImageCaptured,
    this.quality = 1.0,
    this.initialCamera = CamPreference.rear,
    this.aspectRatio = CamRatio.ratio3x4,
    this.showGrid = true,
    this.lockAspectRatio = false,
  });

  @override
  State<FlutterCropCamera> createState() => _FlutterCropCameraState();
}

class _FlutterCropCameraState extends State<FlutterCropCamera> {
  final FlutterCropCameraController _controller = FlutterCropCameraController();
  bool _isInit = false;
  double _currentZoom = 1.0;
  String _flashMode = "off"; // off, auto, on
  String _selectedMode = "PHOTO"; // PHOTO, PORTRAIT

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  @override
  void didUpdateWidget(covariant FlutterCropCamera oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.quality != widget.quality ||
        oldWidget.initialCamera != widget.initialCamera ||
        oldWidget.aspectRatio != widget.aspectRatio) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    await _controller.startCamera(
      quality: widget.quality,
      cameraPreference: widget.initialCamera,
      aspectRatio: widget.aspectRatio,
    );
    // Set initial flash mode
    await _controller.setFlashMode(_flashMode);
    if (mounted) {
      setState(() {
        _isInit = true;
      });
    }
  }

  void _onModeSelected(String mode) {
    setState(() {
      _selectedMode = mode;
      if (mode == "PORTRAIT") {
        _currentZoom = 2.0;
      } else {
        _currentZoom = 1.0;
      }
    });
    _controller.setZoom(_currentZoom);
  }

  void _toggleFlash() {
    String newMode;
    if (_flashMode == "off") {
      newMode = "auto";
    } else if (_flashMode == "auto") {
      newMode = "on";
    } else {
      newMode = "off";
    }

    setState(() {
      _flashMode = newMode;
    });
    _controller.setFlashMode(newMode);
  }

  IconData _getFlashIcon() {
    switch (_flashMode) {
      case "auto":
        return Icons.flash_auto;
      case "on":
        return Icons.flash_on;
      default:
        return Icons.flash_off;
    }
  }

  double _getAspectRatio(CamRatio ratio) {
    switch (ratio) {
      case CamRatio.ratio3x4:
        return 3 / 4;
      case CamRatio.ratio4x3:
        return 4 / 3;
      case CamRatio.ratio9x16:
        return 9 / 16;
      case CamRatio.ratio16x9:
        return 16 / 9;
      case CamRatio.ratio1x1:
        return 1.0;
    }
  }

  @override
  void dispose() {
    _controller.stopCamera();
    super.dispose();
  }

  Future<void> _capture() async {
    try {
      final path = await _controller.takePicture();
      if (path != null) {
        final file = File(path);
        if (widget.cropEnabled) {
          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CropEditor(
                file: file,
                showGrid: widget.showGrid,
                lockAspectRatio: widget.lockAspectRatio,
                onCrop: (x, y, width, height, rotation, flipX) async {
                  final croppedPath = await _controller.cropImage(
                    path: file.path,
                    x: x,
                    y: y,
                    width: width,
                    height: height,
                    rotationDegrees: rotation,
                    flipX: flipX,
                    quality: (widget.quality * 100).toInt(),
                  );
                  if (croppedPath != null) {
                    widget.onImageCaptured(File(croppedPath));
                    if (!context.mounted) return;
                    Navigator.pop(context); // Close Editor
                  }
                },
              ),
            ),
          );
        } else {
          widget.onImageCaptured(file);
        }
      }
    } catch (e) {
      debugPrint("Error capturing: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInit) {
      return const Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Camera Preview
          Center(
            child: AspectRatio(
              aspectRatio: _getAspectRatio(widget.aspectRatio),
              child: CameraPreview(controller: _controller),
            ),
          ),

          // 2. Top Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                color: Colors.black.withValues(alpha: 0.3), // Semi-transparent
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      key: const Key('flash_button'),
                      onTap: _toggleFlash,
                      child: Icon(_getFlashIcon(), color: Colors.white),
                    ),
                    const Spacer(), // To keep flash on left
                  ],
                ),
              ),
            ),
          ),

          // 3. Bottom Area
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                bottom: 30 + MediaQuery.of(context).padding.bottom,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black, Colors.transparent],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Zoom Pill
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [1, 2, 3].map((zoom) {
                        final isSelected = _currentZoom == zoom.toDouble();
                        return GestureDetector(
                          key: Key('zoom_${zoom}x'),
                          onTap: () {
                            setState(() {
                              _currentZoom = zoom.toDouble();
                            });
                            _controller.setZoom(_currentZoom);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              "${zoom}x",
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.yellow
                                    : Colors.white,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  // Mode Selector
                  SizedBox(
                    height: 40,
                    child: Center(
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        shrinkWrap: true,
                        children: [
                          _ModeItem(
                            key: const Key('mode_photo'),
                            text: "PHOTO",
                            isSelected: _selectedMode == "PHOTO",
                            onTap: () => _onModeSelected("PHOTO"),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ... (keep remaining controls)

                  // Shutter and Controls
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Gallery Preview
                        SizedBox(width: 50, height: 50),

                        // Shutter Button
                        GestureDetector(
                          key: const Key('shutter_button'),
                          onTap: _capture,
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                              color: Colors.transparent,
                            ),
                            child: Center(
                              child: Container(
                                width: 70,
                                height: 70,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Switch Camera
                        GestureDetector(
                          key: const Key('switch_camera_button'),
                          onTap: () async {
                            await _controller.switchCamera();
                            setState(() {
                              _currentZoom = 1.0;
                            });
                          },
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.grey[800]?.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.cameraswitch_outlined,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeItem extends StatelessWidget {
  final String text;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeItem({
    super.key,
    required this.text,
    this.isSelected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              color: isSelected ? Colors.yellow : Colors.white54,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}
