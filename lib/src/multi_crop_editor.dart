import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MultiCropEditor extends StatefulWidget {
  final List<File> files;
  final Function(List<File> files) onImagesCropped;
  final bool showGrid;
  final List<DeviceOrientation> screenOrientations;
  final Function(
    String path,
    int x,
    int y,
    int width,
    int height,
    int rotation,
    bool flipX,
  )
  cropNative;

  const MultiCropEditor({
    super.key,
    required this.files,
    required this.onImagesCropped,
    required this.cropNative,
    this.showGrid = true,
    this.screenOrientations = const [DeviceOrientation.portraitUp],
  });

  @override
  State<MultiCropEditor> createState() => _MultiCropEditorState();
}

class _MultiCropEditorState extends State<MultiCropEditor> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  // Store state for each image: rotation, flip, cropRect (optional if we want to restore crop)
  // For simplicity, we'll store rotation and flip.
  // We need to keep track of transformations for each file index.
  late List<_EditorState> _states;

  @override
  void initState() {
    super.initState();
    _states = List.generate(widget.files.length, (index) => _EditorState());
    SystemChrome.setPreferredOrientations(widget.screenOrientations);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _deleteCurrentImage() {
    if (widget.files.isEmpty) return;

    setState(() {
      widget.files.removeAt(_currentIndex);
      _states.removeAt(_currentIndex);

      if (widget.files.isEmpty) {
        // No images left, cancel edits
        Navigator.pop(context, null);
      } else {
        // Adjust current index if needed
        if (_currentIndex >= widget.files.length) {
          _currentIndex = widget.files.length - 1;
        }
      }
    });
  }

  void _onDone() async {
    // Process all images
    // We need to iterate through all states and apply crops.
    // However, the crop calculation requires the loaded ui.Image and layout info.
    // If we haven't loaded/viewed an image, we can't calculate its crop rect easily unless we assume full image.
    // Strategy:
    // 1. For visited images (where we have user edits), apply the edit.
    // 2. For unvisited images, return original file (or 0,0,w,h crop if needed).

    // BUT: The current _SingleImageEditor calculates crop rect based on on-screen layout.
    // This implies we can only crop what has been laid out.
    // To support "Crop All", we might need to load each image.

    // Simpler approach for v1: Only crop the ones the user actually edited?
    // Or, we force layout?

    // Better approach: _SingleImageEditor exposes a "getCropParams" method.
    // But since they are inside a PageView, they might not be mounted.

    // Let's rely on the _states list.
    // The _SingleImageEditor will update the _states[_currentIndex] when interactions happen.
    // _states will hold: rotation, flip.
    // What about ZOOM/PAN? That's in TransformationController.

    // If we want WhatsApp style:
    // User edits image 1 -> sets zoom/rotation.
    // User swipes to image 2.
    // User hits Done.
    // Image 1 should be cropped as edited. Image 2 as is (or edited if visited).

    // Problem: TransformationController state is lost if widget unmounts (PageView).
    // Solution: We must hoist the TransformationController or its value (Matrix4) into _states.

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator()),
    );

    List<File> resultFiles = [];

    for (int i = 0; i < widget.files.length; i++) {
      final state = _states[i];
      final file = widget.files[i];

      // If no changes, return original
      if (!state.hasChanges) {
        resultFiles.add(file);
        continue;
      }

      // If changes, we need to crop.
      // We need image dimensions to calculate crop rect from Matrix4.
      // This is expensive if we have to decode valid images now.
      // But we have to.

      try {
        final data = await file.readAsBytes();
        final image = await decodeImageFromList(data);

        // Calculate crop params from state.matrix
        // Logic same as CropEditor._onCropPressed
        final matrix = state.matrix;
        final double tx = matrix.getRow(0).w;
        final double ty = matrix.getRow(1).w;
        final double scale = matrix.getRow(0).x;

        // We need the "viewport" size and "base" size used during editing.
        // This is tricky because it depends on screen layout.
        // We stored viewportSize and baseSize in state during 'build' or 'layout'.

        if (state.viewportSize == Size.zero || state.baseSize == Size.zero) {
          // Fallback: full image
          resultFiles.add(file);
          image.dispose();
          continue;
        }

        final double viewportWidth = state.viewportSize.width;
        final double viewportHeight = state.viewportSize.height;
        final double baseWidth = state.baseSize.width;
        final double baseHeight = state.baseSize.height;

        final double renderX = (-tx / scale).clamp(0.0, baseWidth);
        final double renderY = (-ty / scale).clamp(0.0, baseHeight);
        final double renderW = (viewportWidth / scale);
        final double renderH = (viewportHeight / scale);

        final bool isRotated = state.rotation % 2 != 0;
        final double realImgW = isRotated
            ? image.height.toDouble()
            : image.width.toDouble();
        final double realImgH = isRotated
            ? image.width.toDouble()
            : image.height.toDouble();

        final double scaleX = realImgW / baseWidth;
        final double scaleY = realImgH / baseHeight;

        final int cropX = (renderX * scaleX).round();
        final int cropY = (renderY * scaleY).round();
        final int cropWidth = (renderW * scaleX).round();
        final int cropHeight = (renderH * scaleY).round();

        image.dispose();

        final croppedPath = await widget.cropNative(
          file.path,
          cropX,
          cropY,
          cropWidth,
          cropHeight,
          state.rotation * 90,
          state.flipX,
        );

        if (croppedPath != null) {
          resultFiles.add(File(croppedPath));
        } else {
          resultFiles.add(file);
        }
      } catch (e) {
        debugPrint("Error cropping image $i: $e");
        resultFiles.add(file);
      }
    }

    if (mounted) {
      Navigator.pop(context); // Pop dialog
      widget.onImagesCropped(resultFiles);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.files.isEmpty) return const SizedBox();
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.files.length,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              itemBuilder: (context, index) {
                return _SingleImageEditor(
                  file: widget.files[index],
                  state: _states[index],
                  showGrid: widget.showGrid,
                );
              },
            ),
          ),
          // Thumbnail Strip & Controls
          Container(
            padding: const EdgeInsets.only(top: 10, bottom: 20),
            color: const Color(0xFF121212),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Aspect Ratio Selector
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
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
                const SizedBox(height: 10),

                // 2. Thumbnails
                SizedBox(
                  height: 60,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.files.length,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    itemBuilder: (context, index) {
                      final isSelected = index == _currentIndex;
                      return GestureDetector(
                        onTap: () {
                          _pageController.jumpToPage(index);
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            border: isSelected
                                ? Border.all(color: Colors.cyanAccent, width: 2)
                                : null,
                          ),
                          child: Stack(
                            children: [
                              Image.file(
                                widget.files[index],
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                              ),
                              if (isSelected)
                                Positioned.fill(
                                  child: Container(
                                    color: Colors.white.withValues(alpha: 0.1),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 10),
                const Divider(color: Colors.white24, height: 1),
                const SizedBox(height: 5),

                // 3. Bottom Controls (Delete, Reset, Grid, Rotate, Flip, Done)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // DELETE
                      IconButton(
                        tooltip: "Delete Image",
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.redAccent,
                        ),
                        onPressed: _deleteCurrentImage,
                      ),
                      // RESET
                      IconButton(
                        tooltip: "Reset",
                        icon: const Icon(Icons.refresh, color: Colors.white54),
                        onPressed: () {
                          setState(() {
                            final state = _states[_currentIndex];
                            state.rotation = 0;
                            state.flipX = false;
                            state.matrix = Matrix4.identity();
                            state.aspectRatio = null;
                            state.hasChanges = false;
                          });
                        },
                      ),
                      // GRID
                      IconButton(
                        tooltip: "Toggle Grid",
                        icon: Icon(
                          _states[_currentIndex].showGrid
                              ? Icons.grid_on
                              : Icons.grid_off,
                          color: Colors.white,
                        ),
                        onPressed: () {
                          setState(() {
                            _states[_currentIndex].showGrid =
                                !_states[_currentIndex].showGrid;
                          });
                        },
                      ),
                      // ROTATE
                      IconButton(
                        tooltip: "Rotate",
                        icon: const Icon(
                          Icons.rotate_left,
                          color: Colors.white,
                        ),
                        onPressed: () {
                          setState(() {
                            _states[_currentIndex].rotation =
                                (_states[_currentIndex].rotation - 1) % 4;
                            if (_states[_currentIndex].rotation < 0) {
                              _states[_currentIndex].rotation += 4;
                            }
                            _states[_currentIndex].matrix = Matrix4.identity();
                            _states[_currentIndex].hasChanges = true;
                          });
                        },
                      ),
                      // FLIP
                      IconButton(
                        tooltip: "Flip",
                        icon: const Icon(Icons.flip, color: Colors.white),
                        onPressed: () {
                          setState(() {
                            _states[_currentIndex].flipX =
                                !_states[_currentIndex].flipX;
                            _states[_currentIndex].hasChanges = true;
                          });
                        },
                      ),
                      const SizedBox(width: 10),
                      // DONE
                      TextButton(
                        onPressed: _onDone,
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.cyanAccent,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 8,
                          ),
                        ),
                        child: const Text(
                          "Done",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                  ),
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
    final currentRatio = _states[_currentIndex].aspectRatio;
    final bool isSelected =
        (ratio == null && currentRatio == null) ||
        (ratio != null &&
            currentRatio != null &&
            (ratio - currentRatio).abs() < 0.001);

    return Padding(
      padding: const EdgeInsets.only(right: 15),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _states[_currentIndex].aspectRatio = ratio;
            _states[_currentIndex].matrix =
                Matrix4.identity(); // Reset Zoom on ratio change
            _states[_currentIndex].hasChanges = true;
          });
        },
        child: Container(
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
}

class _EditorState {
  int rotation = 0;
  bool flipX = false;
  Matrix4 matrix = Matrix4.identity();
  Size viewportSize = Size.zero;
  Size baseSize = Size.zero;
  bool hasChanges = false;
  double? aspectRatio; // null = Original
  bool showGrid = true;
}

class _SingleImageEditor extends StatefulWidget {
  final File file;
  final _EditorState state;
  final bool showGrid;

  const _SingleImageEditor({
    required this.file,
    required this.state,
    required this.showGrid,
  });

  @override
  State<_SingleImageEditor> createState() => _SingleImageEditorState();
}

class _SingleImageEditorState extends State<_SingleImageEditor> {
  ui.Image? _image;
  bool _loading = true;
  final TransformationController _transformationController =
      TransformationController();

  @override
  void initState() {
    super.initState();
    _loadImage();
    _transformationController.value = widget.state.matrix;
    _transformationController.addListener(_onTransformChange);
  }

  void _onTransformChange() {
    widget.state.matrix = _transformationController.value;
    widget.state.hasChanges = true;
  }

  @override
  void didUpdateWidget(covariant _SingleImageEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.file != oldWidget.file) {
      _loadImage();
    }
    // Update controller if state changed externally (e.g. rotation reset)
    if (widget.state.matrix != _transformationController.value) {
      _transformationController.value = widget.state.matrix;
    }
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onTransformChange);
    _transformationController.dispose();
    _image?.dispose();
    super.dispose();
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
      debugPrint("Error loading image: $e");
    }
  }

  void _calculateLayout(BoxConstraints constraints) {
    if (_image == null) return;

    final double maxWidth = constraints.maxWidth;
    final double maxHeight = constraints.maxHeight;

    double viewportWidth, viewportHeight;

    // 1. Calculate Viewport Size (the cropping box)
    if (widget.state.aspectRatio == null) {
      // Original Ratio (of the transformed image).
      // If rotated 90 or 270 degrees, we swap Width/Height logic.
      final bool isRotated = widget.state.rotation % 2 != 0;
      final double w = isRotated
          ? _image!.height.toDouble()
          : _image!.width.toDouble();
      final double h = isRotated
          ? _image!.width.toDouble()
          : _image!.height.toDouble();
      final double ratio = w / h;

      if (ratio > 1) {
        // Landscape image: fill width, scale height down.
        viewportWidth = maxWidth;
        viewportHeight = maxWidth / ratio;
      } else {
        // Portrait image: fill height (capped by width), scale width down.
        viewportHeight = maxWidth; // initial probe
        viewportWidth = viewportHeight * ratio;
      }
    } else {
      // Fixed Ratios (1:1, 4:5, etc.)
      if (widget.state.aspectRatio! >= 1) {
        viewportWidth = maxWidth;
        viewportHeight = maxWidth / widget.state.aspectRatio!;
      } else {
        viewportHeight = maxWidth;
        viewportWidth = viewportHeight * widget.state.aspectRatio!;
      }
    }

    if (viewportHeight > maxHeight) {
      final double scale = maxHeight / viewportHeight;
      viewportHeight = maxHeight;
      viewportWidth = viewportWidth * scale;
    }

    widget.state.viewportSize = Size(viewportWidth, viewportHeight);

    // Base Image Size
    final bool isRotated = widget.state.rotation % 2 != 0;
    final double realImgW = isRotated
        ? _image!.height.toDouble()
        : _image!.width.toDouble();
    final double realImgH = isRotated
        ? _image!.width.toDouble()
        : _image!.height.toDouble();

    final double imgRatio = realImgW / realImgH; // transformed aspect ratio
    final double viewportRatio = viewportWidth / viewportHeight;

    double baseWidth, baseHeight;

    if (imgRatio > viewportRatio) {
      baseHeight = viewportHeight;
      baseWidth = baseHeight * imgRatio;
    } else {
      baseWidth = viewportWidth;
      baseHeight = baseWidth / imgRatio;
    }

    widget.state.baseSize = Size(baseWidth, baseHeight);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _image == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.cyanAccent),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _calculateLayout(constraints);

        final viewportWidth = widget.state.viewportSize.width;
        final viewportHeight = widget.state.viewportSize.height;
        final baseWidth = widget.state.baseSize.width;
        final baseHeight = widget.state.baseSize.height;

        return Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: viewportWidth,
                height: viewportHeight,
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
                        width: baseWidth,
                        height: baseHeight,
                        child: Transform.scale(
                          scaleX: widget.state.flipX ? -1 : 1,
                          child: Transform.rotate(
                            angle: widget.state.rotation * math.pi / 2,
                            child: Image.file(widget.file, fit: BoxFit.fill),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.state.showGrid)
                IgnorePointer(
                  child: Container(
                    width: viewportWidth,
                    height: viewportHeight,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.white30),
                    ),
                    // We can reuse GridPainter from crop_editor.dart if made public, or duplicate.
                    // Duplicating for now for isolation.
                    child: CustomPaint(painter: _MultiGridPainter()),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MultiGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
