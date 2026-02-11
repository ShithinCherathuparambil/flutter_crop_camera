import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CropEditor extends StatefulWidget {
  final File file;
  final Function(int x, int y, int width, int height, int rotation, bool flipX)
  onCrop;
  final bool showGrid;
  final bool lockAspectRatio;
  final List<DeviceOrientation> screenOrientations;

  const CropEditor({
    super.key,
    required this.file,
    required this.onCrop,
    this.showGrid = true,
    this.lockAspectRatio = false,
    this.screenOrientations = const [DeviceOrientation.portraitUp],
  });

  @override
  State<CropEditor> createState() => _CropEditorState();
}

class _CropEditorState extends State<CropEditor> {
  /// The decoded image used for calculating dimensions and aspect ratios.
  ui.Image? _image;

  /// Controls the zoom, pan, and translation of the image within the viewport.
  final TransformationController _transformationController =
      TransformationController();

  // --- State Variables ---

  /// Current rotation in 90-degree steps (0 = 0°, 1 = 90°, 2 = 180°, 3 = 270°).
  int _rotation = 0;

  /// Horizontal flip state.
  bool _flipX = false;

  /// Selected aspect ratio for the crop viewport. null means "Original".
  double? _aspectRatio;

  /// Local copy of the grid visibility setting.
  late bool _showGrid;

  // --- Rendered/Calculated Properties ---

  /// The width of the "crop window" or viewport on the screen.
  double _viewportWidth = 0;

  /// The height of the "crop window" or viewport on the screen.
  double _viewportHeight = 0;

  /// The base width of the image as it appears on screen (before zoom).
  /// This is calculated to "cover" or "contain" the viewport.
  double _baseWidth = 0;

  /// The base height of the image as it appears on screen (before zoom).
  double _baseHeight = 0;

  /// tracks if the image is still being loaded and decoded.
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _showGrid = widget.showGrid;
    _loadImage();
    // Ensure orientation is locked as per preferences.
    SystemChrome.setPreferredOrientations(widget.screenOrientations);
  }

  Future<void> _loadImage() async {
    try {
      final data = await widget.file.readAsBytes();
      final image = await decodeImageFromList(data);
      if (mounted) {
        setState(() {
          _image = image;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint("CropEditor: Error loading image: $e");
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _image?.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _rotation = 0;
      _flipX = false;
      _aspectRatio = 1.0;
      _transformationController.value = Matrix4.identity();
    });
  }

  /// Logic to determine how the image and viewport should be sized given the screen constraints.
  void _calculateLayout(BoxConstraints constraints) {
    if (_image == null) return;

    final double maxWidth = constraints.maxWidth;
    final double maxHeight = constraints.maxHeight;

    // 1. Calculate Viewport Size (the cropping box)
    if (_aspectRatio == null) {
      // Original Ratio (of the transformed image).
      // If rotated 90 or 270 degrees, we swap Width/Height logic.
      final bool isRotated = _rotation % 2 != 0;
      final double w = isRotated
          ? _image!.height.toDouble()
          : _image!.width.toDouble();
      final double h = isRotated
          ? _image!.width.toDouble()
          : _image!.height.toDouble();
      final double ratio = w / h;

      if (ratio > 1) {
        // Landscape image: fill width, scale height down.
        _viewportWidth = maxWidth;
        _viewportHeight = maxWidth / ratio;
      } else {
        // Portrait image: fill height (capped by width), scale width down.
        _viewportHeight = maxWidth; // initial probe
        _viewportWidth = _viewportHeight * ratio;
      }
    } else {
      // Fixed Ratios (1:1, 4:5, etc.)
      if (_aspectRatio! >= 1) {
        _viewportWidth = maxWidth;
        _viewportHeight = maxWidth / _aspectRatio!;
      } else {
        _viewportHeight = maxWidth;
        _viewportWidth = _viewportHeight * _aspectRatio!;
      }
    }

    // Ensure the calculated viewport does not overflow the available vertical height.
    if (_viewportHeight > maxHeight) {
      final double scale = maxHeight / _viewportHeight;
      _viewportHeight = maxHeight;
      _viewportWidth = _viewportWidth * scale;
    }

    // 2. Calculate Base Image Size (Visual) to COVER the viewport.
    // This is the size of the box we put in the InteractiveViewer.
    final bool isRotated = _rotation % 2 != 0;
    final double realImgW = isRotated
        ? _image!.height.toDouble()
        : _image!.width.toDouble();
    final double realImgH = isRotated
        ? _image!.width.toDouble()
        : _image!.height.toDouble();

    final double imgRatio = realImgW / realImgH;
    final double viewportRatio = _viewportWidth / _viewportHeight;

    if (imgRatio > viewportRatio) {
      // Image is wider than the viewport: Height determines the base scale.
      _baseHeight = _viewportHeight;
      _baseWidth = _baseHeight * imgRatio;
    } else {
      // Image is taller or perfectly matched: Width determines the base scale.
      _baseWidth = _viewportWidth;
      _baseHeight = _baseWidth / imgRatio;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _image == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.cyanAccent),
        ),
      );
    }

    // Layout logic moved to LayoutBuilder

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // Editor Area
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Calculate Layout based on available space
                _calculateLayout(constraints);

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: _viewportWidth,
                      height: _viewportHeight,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: ClipRect(
                          child: InteractiveViewer(
                            transformationController: _transformationController,
                            minScale: 1.0,
                            maxScale: 3.0,
                            constrained: false,
                            boundaryMargin: EdgeInsets.zero,
                            child: SizedBox(
                              width: _baseWidth,
                              height: _baseHeight,
                              child: Transform.scale(
                                scaleX: _flipX ? -1 : 1,
                                child: Transform.rotate(
                                  angle: _rotation * math.pi / 2,
                                  child: Image.file(
                                    widget.file,
                                    fit: BoxFit
                                        .fill, // We force it to fill our calculated base box
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Grid Overlay
                    if (_showGrid)
                      IgnorePointer(
                        child: Container(
                          width: _viewportWidth,
                          height: _viewportHeight,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: CustomPaint(painter: GridPainter()),
                        ),
                      ),
                    // Viewport Border
                    IgnorePointer(
                      child: Container(
                        width: _viewportWidth,
                        height: _viewportHeight,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.5),
                            width: 2,
                          ),
                          // boxShadow: [
                          //   BoxShadow(
                          //     color: Colors.white.withValues(alpha:0.2),
                          //     blurRadius: 10,
                          //     spreadRadius: 1,
                          //   ),
                          // ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // Futuristic Toolbar
          Container(
            padding: const EdgeInsets.only(bottom: 30, top: 20),
            decoration: const BoxDecoration(
              color: Color(0xFF121212),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 10,
                  offset: Offset(0, -5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Aspect Ratios
                if (!widget.lockAspectRatio)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        _buildRatioBtn("Original", null),
                        _buildRatioBtn("1:1", 1.0),
                        _buildRatioBtn("4:5", 4 / 5),
                        _buildRatioBtn("16:9", 16 / 9),
                        _buildRatioBtn("9:16", 9 / 16),
                        _buildRatioBtn("3:4", 3 / 4),
                      ],
                    ),
                  ),
                if (widget.lockAspectRatio) const SizedBox(height: 20),
                // Controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      key: const Key('crop_reset_button'),
                      icon: const Icon(Icons.refresh, color: Colors.white54),
                      onPressed: _reset,
                      tooltip: "Reset",
                    ),
                    IconButton(
                      key: const Key('crop_grid_button'),
                      icon: Icon(
                        _showGrid ? Icons.grid_on : Icons.grid_off,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        setState(() {
                          _showGrid = !_showGrid;
                        });
                      },
                      tooltip: "Toggle Grid",
                    ),
                    IconButton(
                      key: const Key('crop_rotate_button'),
                      icon: const Icon(Icons.rotate_left, color: Colors.white),
                      onPressed: () {
                        setState(() {
                          _rotation = (_rotation - 1) % 4;
                          if (_rotation < 0) _rotation += 4;
                          _transformationController.value = Matrix4.identity();
                        });
                      },
                      tooltip: "Rotate",
                    ),
                    IconButton(
                      key: const Key('crop_mirror_button'),
                      icon: const Icon(Icons.flip, color: Colors.white),
                      onPressed: () {
                        setState(() {
                          _flipX = !_flipX;
                        });
                      },
                      tooltip: "Mirror",
                    ),
                    IconButton(
                      key: const Key('crop_close_button'),
                      icon: const Icon(
                        Icons.close,
                        color: Colors.redAccent,
                        size: 30,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    IconButton(
                      key: const Key('crop_check_button'),
                      icon: const Icon(
                        Icons.check,
                        color: Colors.cyanAccent,
                        size: 30,
                      ),
                      onPressed: _onCropPressed,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatioBtn(String label, double? ratio) {
    // Check equality with tolerance
    final bool isSelected =
        (ratio == null && _aspectRatio == null) ||
        (ratio != null &&
            _aspectRatio != null &&
            (ratio - _aspectRatio!).abs() < 0.001);

    return Padding(
      padding: const EdgeInsets.only(right: 15),
      child: GestureDetector(
        key: Key('ratio_$label'),
        onTap: () {
          setState(() {
            _aspectRatio = ratio;
            _transformationController.value =
                Matrix4.identity(); // Reset Zoom on ratio change
          });
        },
        child: Container(
          key: Key('ratio_$label'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? Colors.cyanAccent : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? Colors.cyanAccent : Colors.white30,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.black : Colors.white70,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  /// Translates the UI transformations (pan, zoom, rotation) into actual bitmap coordinates.
  void _onCropPressed() {
    if (_image == null) return;

    // 1. Extract transformation matrix data.
    final Matrix4 matrix = _transformationController.value;
    final double tx = matrix.getRow(0).w; // Translation X
    final double ty = matrix.getRow(1).w; // Translation Y
    final double scale = matrix.getRow(0).x; // Final Scale (includes user zoom)

    // 2. Map Viewport to coordinates relative to the base image box (before matrix).
    // renderX/Y/W/H represent the area currently visible inside the viewport,
    // expressed in the coordinate system of the 'base image box' (the sized child of InteractiveViewer).
    final double renderX = (-tx / scale).clamp(0.0, _baseWidth);
    final double renderY = (-ty / scale).clamp(0.0, _baseHeight);
    final double renderW = (_viewportWidth / scale);
    final double renderH = (_viewportHeight / scale);

    // 3. Map Rendered Child coordinates to Transformed Image coordinates.
    // The "Transformed Image" is the hypothetical bitmap after rotation/flip.
    final bool isRotated = _rotation % 2 != 0;
    final double realImgW = isRotated
        ? _image!.height.toDouble()
        : _image!.width.toDouble();
    final double realImgH = isRotated
        ? _image!.width.toDouble()
        : _image!.height.toDouble();

    // Scale factors between the on-screen rendered box and the actual bitmap pixels.
    final double scaleX = realImgW / _baseWidth;
    final double scaleY = realImgH / _baseHeight;

    // Convert screen-units to pixel-units.
    final int cropX = (renderX * scaleX).round();
    final int cropY = (renderY * scaleY).round();
    final int cropWidth = (renderW * scaleX).round();
    final int cropHeight = (renderH * scaleY).round();

    // 4. Safety/Boundary checks to ensure we don't request a crop outside the bitmap.
    final int finalX = cropX.clamp(0, realImgW.toInt());
    final int finalY = cropY.clamp(0, realImgH.toInt());
    final int finalWidth = (cropWidth + finalX > realImgW)
        ? (realImgW.toInt() - finalX)
        : cropWidth;
    final int finalHeight = (cropHeight + finalY > realImgH)
        ? (realImgH.toInt() - finalY)
        : cropHeight;

    // 5. Fire callback with coordinates valid for the POST-transfomation bitmap.
    widget.onCrop(
      finalX,
      finalY,
      finalWidth,
      finalHeight,
      _rotation * 90,
      _flipX,
    );
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Vertical lines
    canvas.drawLine(
      Offset(size.width / 3, 0),
      Offset(size.width / 3, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(2 * size.width / 3, 0),
      Offset(2 * size.width / 3, size.height),
      paint,
    );

    // Horizontal lines
    canvas.drawLine(
      Offset(0, size.height / 3),
      Offset(size.width, size.height / 3),
      paint,
    );
    canvas.drawLine(
      Offset(0, 2 * size.height / 3),
      Offset(size.width, 2 * size.height / 3),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}
