import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum _EditorMode { ratio, rotate }

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
  late List<_EditorState> _states;
  bool _isDragging = false;
  _EditorMode _mode = _EditorMode.ratio; // Current active tab

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
        Navigator.pop(context, null);
      } else {
        if (_currentIndex >= widget.files.length) {
          _currentIndex = widget.files.length - 1;
        }
      }
    });
  }

  void _onDone() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(
        child: CircularProgressIndicator(color: Colors.cyanAccent),
      ),
    );

    List<File> resultFiles = [];

    for (int i = 0; i < widget.files.length; i++) {
      final state = _states[i];
      final file = widget.files[i];

      if (!state.hasChanges) {
        resultFiles.add(file);
        continue;
      }

      try {
        final data = await file.readAsBytes();
        final image = await decodeImageFromList(data);

        // We use the cropRect which is relative to baseSize
        final rect = state.cropRect;
        final base = state.baseSize;

        if (rect == Rect.zero || base == Size.zero) {
          resultFiles.add(file);
          image.dispose();
          continue;
        }

        final bool isRotated = state.rotation % 2 != 0;
        final double realImgW = isRotated
            ? image.height.toDouble()
            : image.width.toDouble();
        final double realImgH = isRotated
            ? image.width.toDouble()
            : image.height.toDouble();

        final double scaleX = realImgW / base.width;
        final double scaleY = realImgH / base.height;

        final int cropX = (rect.left * scaleX).round();
        final int cropY = (rect.top * scaleY).round();
        final int cropWidth = (rect.width * scaleX).round();
        final int cropHeight = (rect.height * scaleY).round();

        image.dispose();

        final int totalRotation =
            (state.rotation * 90 + (state.fineRotation * 180 / math.pi))
                .round();

        final croppedPath = await widget.cropNative(
          file.path,
          cropX,
          cropY,
          cropWidth,
          cropHeight,
          totalRotation,
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
      backgroundColor: const Color(0xFF000000),
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Text(
                    "EDIT IMAGE",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      letterSpacing: 1.5,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: _onDone,
                    child: const Text(
                      "DONE",
                      style: TextStyle(
                        color: Color(0xFFFF5722),
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                physics: _isDragging
                    ? const NeverScrollableScrollPhysics()
                    : const BouncingScrollPhysics(),
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
                    onDragStart: () => setState(() => _isDragging = true),
                    onDragEnd: () => setState(() => _isDragging = false),
                  );
                },
              ),
            ),
            // Bottom Panel
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A0A),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              padding: const EdgeInsets.only(top: 16, bottom: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_mode == _EditorMode.ratio) ...[
                    // Ratios
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          _buildRatioBtn("FREE", null),
                          _buildRatioBtn("1:1", 1.0),
                          _buildRatioBtn("4:5", 4 / 5),
                          _buildRatioBtn("3:4", 3 / 4),
                          _buildRatioBtn("16:9", 16 / 9),
                          _buildRatioBtn("9:16", 9 / 16),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ] else if (_mode == _EditorMode.rotate) ...[
                    _buildRotationDialArea(),
                  ],

                  // Thumbnails (condensed)
                  if (widget.files.length > 1) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 40,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: widget.files.length,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemBuilder: (context, index) {
                          final isSelected = index == _currentIndex;
                          return GestureDetector(
                            onTap: () {
                              _pageController.animateToPage(
                                index,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(right: 8),
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFFFF5722)
                                      : Colors.white10,
                                  width: 1.5,
                                ),
                                image: DecorationImage(
                                  image: FileImage(widget.files[index]),
                                  fit: BoxFit.cover,
                                  colorFilter: isSelected
                                      ? null
                                      : ColorFilter.mode(
                                          Colors.black.withValues(alpha: 0.3),
                                          BlendMode.multiply,
                                        ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  // Tab Navigation
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildTabItem(
                        Icons.crop,
                        "Crop",
                        _mode == _EditorMode.ratio,
                        () => setState(() => _mode = _EditorMode.ratio),
                      ),
                      _buildTabItem(
                        Icons.rotate_90_degrees_ccw_outlined,
                        "Rotate",
                        _mode == _EditorMode.rotate,
                        () => setState(() => _mode = _EditorMode.rotate),
                      ),
                      _buildTabItem(
                        _states[_currentIndex].showGrid
                            ? Icons.grid_on
                            : Icons.grid_off,
                        "Grid",
                        false,
                        () {
                          setState(() {
                            _states[_currentIndex].showGrid =
                                !_states[_currentIndex].showGrid;
                          });
                        },
                      ),
                      _buildTabItem(Icons.flip, "Flip", false, () {
                        setState(() {
                          _states[_currentIndex].flipX =
                              !_states[_currentIndex].flipX;
                          _states[_currentIndex].hasChanges = true;
                        });
                      }),
                      _buildTabItem(
                        Icons.delete_outline,
                        "Delete",
                        false,
                        _deleteCurrentImage,
                        color: Colors.redAccent.withValues(alpha: 0.8),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabItem(
    IconData icon,
    String label,
    bool isSelected,
    VoidCallback onTap, {
    Color? color,
  }) {
    final activeColor = color ?? const Color(0xFFFF5722);
    final inactiveColor = Colors.white54;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? activeColor : inactiveColor,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? activeColor : inactiveColor,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRotationDialArea() {
    final state = _states[_currentIndex];
    return Column(
      children: [
        Text(
          "${(state.fineRotation * 180 / math.pi).toStringAsFixed(1)}°",
          style: const TextStyle(
            color: Color(0xFFFF5722),
            fontSize: 12,
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 60,
          child: _RotationDial(
            value: state.fineRotation,
            onChanged: (val) {
              setState(() {
                state.fineRotation = val;
                state.hasChanges = true;
              });
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.history, color: Colors.white54),
              onPressed: () {
                setState(() {
                  state.fineRotation = 0;
                  state.hasChanges = true;
                });
              },
            ),
            const SizedBox(width: 20),
            IconButton(
              icon: const Icon(Icons.rotate_right, color: Colors.white54),
              onPressed: () {
                setState(() {
                  state.rotation = (state.rotation + 1) % 4;
                  state.hasChanges = true;
                });
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRatioBtn(String label, double? ratio) {
    final currentRatio = _states[_currentIndex].aspectRatio;
    final bool isSelected =
        (ratio == null && currentRatio == null) ||
        (ratio != null &&
            currentRatio != null &&
            (ratio - currentRatio).abs() < 0.001);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: () {
          setState(() {
            _states[_currentIndex].aspectRatio = ratio;
            _states[_currentIndex].hasChanges = true;
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFFF5722).withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFFFF5722) : Colors.white24,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? const Color(0xFFFF5722) : Colors.white70,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }
}

class _EditorState {
  int rotation = 0;
  double fineRotation = 0.0; // In radians
  bool flipX = false;
  double? aspectRatio;
  bool showGrid = true;
  bool hasChanges = false;

  // These are calculated/updated by the editor
  Size baseSize = Size.zero;
  Rect cropRect = Rect.zero;

  void reset() {
    rotation = 0;
    fineRotation = 0.0;
    flipX = false;
    aspectRatio = null;
    showGrid = true;
    hasChanges = false;
    cropRect = Rect.zero;
  }
}

class _SingleImageEditor extends StatefulWidget {
  final File file;
  final _EditorState state;
  final bool showGrid;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;

  const _SingleImageEditor({
    required this.file,
    required this.state,
    required this.showGrid,
    required this.onDragStart,
    required this.onDragEnd,
  });

  @override
  State<_SingleImageEditor> createState() => _SingleImageEditorState();
}

class _SingleImageEditorState extends State<_SingleImageEditor>
    with TickerProviderStateMixin {
  ui.Image? _image;
  bool _loading = true;
  bool _isDragging = false;

  late AnimationController _rotationController;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _loadImage();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _rotationAnimation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _rotationController, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _image?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _SingleImageEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.rotation != oldWidget.state.rotation) {
      _animateRotation();
    }
  }

  void _animateRotation() {
    final double targetAngle = widget.state.rotation * math.pi / 2;
    _rotationAnimation =
        Tween<double>(
          begin: _rotationAnimation.value,
          end: targetAngle,
        ).animate(
          CurvedAnimation(
            parent: _rotationController,
            curve: Curves.easeOutQuart,
          ),
        );
    _rotationController.forward(from: 0);
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

  @override
  Widget build(BuildContext context) {
    if (_loading || _image == null) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF5722)),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxWidth = constraints.maxWidth - 40;
        final double maxHeight = constraints.maxHeight - 40;

        final bool isRotated = widget.state.rotation % 2 != 0;
        final double imgW = isRotated
            ? _image!.height.toDouble()
            : _image!.width.toDouble();
        final double imgH = isRotated
            ? _image!.width.toDouble()
            : _image!.height.toDouble();
        final double imgRatio = imgW / imgH;

        double baseW, baseH;
        if (imgRatio > maxWidth / maxHeight) {
          baseW = maxWidth;
          baseH = maxWidth / imgRatio;
        } else {
          baseH = maxHeight;
          baseW = maxHeight * imgRatio;
        }

        widget.state.baseSize = Size(baseW, baseH);

        // Initialize cropRect if zero
        if (widget.state.cropRect == Rect.zero) {
          widget.state.cropRect = Rect.fromLTWH(0, 0, baseW, baseH);
        }

        // Apply aspect ratio constraint if needed
        if (widget.state.aspectRatio != null) {
          _applyAspectRatio(widget.state.aspectRatio!, baseW, baseH);
        }

        return Center(
          child: Stack(
            children: [
              // Non-cropped background (dimmed)
              SizedBox(
                width: baseW,
                height: baseH,
                child: Opacity(opacity: 0.3, child: _buildImage(baseW, baseH)),
              ),
              // Crop Box with visible image
              _CropBox(
                image: _buildImage(baseW, baseH),
                state: widget.state,
                availableSize: Size(baseW, baseH),
                showGrid: widget.state.showGrid || _isDragging,
                onChanged: (rect) {
                  setState(() {
                    widget.state.cropRect = rect;
                    widget.state.hasChanges = true;
                  });
                },
                onDragStart: () {
                  _isDragging = true;
                  widget.onDragStart();
                  setState(() {});
                },
                onDragEnd: () {
                  _isDragging = false;
                  widget.onDragEnd();
                  setState(() {});
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _applyAspectRatio(double ratio, double baseW, double baseH) {
    Rect rect = widget.state.cropRect;
    double currentW = rect.width;
    double currentH = rect.height;

    double targetW, targetH;
    if (ratio > currentW / currentH) {
      targetW = currentW;
      targetH = currentW / ratio;
      if (targetH > baseH) {
        targetH = baseH;
        targetW = targetH * ratio;
      }
    } else {
      targetH = currentH;
      targetW = targetH * ratio;
      if (targetW > baseW) {
        targetW = baseW;
        targetH = targetW / ratio;
      }
    }

    double left = rect.left + (currentW - targetW) / 2;
    double top = rect.top + (currentH - targetH) / 2;

    // Clamp
    if (left < 0) left = 0;
    if (top < 0) top = 0;
    if (left + targetW > baseW) left = baseW - targetW;
    if (top + targetH > baseH) top = baseH - targetH;

    widget.state.cropRect = Rect.fromLTWH(left, top, targetW, targetH);
  }

  Widget _buildImage(double w, double h) {
    return AnimatedBuilder(
      animation: _rotationAnimation,
      builder: (context, child) {
        return Transform.scale(
          scaleX: widget.state.flipX ? -1 : 1,
          child: Transform.rotate(
            angle: _rotationAnimation.value + widget.state.fineRotation,
            child: Image.file(
              widget.file,
              width: w,
              height: h,
              fit: BoxFit.fill,
            ),
          ),
        );
      },
    );
  }
}

class _CropBox extends StatelessWidget {
  final Widget image;
  final _EditorState state;
  final Size availableSize;
  final bool showGrid;
  final Function(Rect) onChanged;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;

  const _CropBox({
    required this.image,
    required this.state,
    required this.availableSize,
    required this.showGrid,
    required this.onChanged,
    required this.onDragStart,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final rect = state.cropRect;

    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The visible part of the image
          Positioned.fill(
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.center,
                minWidth: availableSize.width,
                maxWidth: availableSize.width,
                minHeight: availableSize.height,
                maxHeight: availableSize.height,
                child: Transform.translate(
                  offset: Offset(
                    (availableSize.width / 2) - (rect.left + rect.width / 2),
                    (availableSize.height / 2) - (rect.top + rect.height / 2),
                  ),
                  child: image,
                ),
              ),
            ),
          ),
          // Grid
          if (showGrid)
            Positioned.fill(
              child: IgnorePointer(child: CustomPaint(painter: _GridPainter())),
            ),
          // Border
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
          // Draggable central area
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => onDragStart(),
              onPanEnd: (_) => onDragEnd(),
              onPanUpdate: (details) {
                double newLeft = rect.left + details.delta.dx;
                double newTop = rect.top + details.delta.dy;

                newLeft = newLeft.clamp(0, availableSize.width - rect.width);
                newTop = newTop.clamp(0, availableSize.height - rect.height);

                onChanged(
                  Rect.fromLTWH(newLeft, newTop, rect.width, rect.height),
                );
              },
            ),
          ),
          // Handles
          ..._buildHandles(),
        ],
      ),
    );
  }

  List<Widget> _buildHandles() {
    return [
      _handle(Alignment.topLeft, (d) => _resize(d, top: true, left: true)),
      _handle(Alignment.topRight, (d) => _resize(d, top: true, right: true)),
      _handle(
        Alignment.bottomLeft,
        (d) => _resize(d, bottom: true, left: true),
      ),
      _handle(
        Alignment.bottomRight,
        (d) => _resize(d, bottom: true, right: true),
      ),
      _handle(Alignment.topCenter, (d) => _resize(d, top: true)),
      _handle(Alignment.bottomCenter, (d) => _resize(d, bottom: true)),
      _handle(Alignment.centerLeft, (d) => _resize(d, left: true)),
      _handle(Alignment.centerRight, (d) => _resize(d, right: true)),
    ];
  }

  Widget _handle(Alignment alignment, Function(DragUpdateDetails) onUpdate) {
    return Positioned.fill(
      child: Align(
        alignment: alignment,
        child: GestureDetector(
          onPanStart: (_) => onDragStart(),
          onPanEnd: (_) => onDragEnd(),
          onPanUpdate: onUpdate,
          child: Container(
            width: 25,
            height: 25,
            color: Colors.transparent,
            child: Center(
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _resize(
    DragUpdateDetails details, {
    bool top = false,
    bool bottom = false,
    bool left = false,
    bool right = false,
  }) {
    Rect rect = state.cropRect;
    double? ratio = state.aspectRatio;

    double dx = details.delta.dx;
    double dy = details.delta.dy;

    double newLeft = rect.left;
    double newTop = rect.top;
    double newWidth = rect.width;
    double newHeight = rect.height;

    if (left) {
      newLeft += dx;
      newWidth -= dx;
    } else if (right) {
      newWidth += dx;
    }

    if (top) {
      newTop += dy;
      newHeight -= dy;
    } else if (bottom) {
      newHeight += dy;
    }

    // Min size
    const minSize = 40.0;
    if (newWidth < minSize) {
      newWidth = minSize;
      if (left) newLeft = rect.right - minSize;
    }
    if (newHeight < minSize) {
      newHeight = minSize;
      if (top) newTop = rect.bottom - minSize;
    }

    // Aspect ratio enforcement
    if (ratio != null) {
      if (left || right) {
        newHeight = newWidth / ratio;
      } else {
        newWidth = newHeight * ratio;
      }

      // Re-adjust top/left if they were changed
      if (top) newTop = rect.bottom - newHeight;
      if (left) newLeft = rect.right - newWidth;
    }

    // Boundary clamp
    if (newLeft < 0) {
      if (ratio != null) {
        newWidth = rect.right;
        newHeight = newWidth / ratio;
        if (top) newTop = rect.bottom - newHeight;
      } else {
        newWidth = rect.right;
      }
      newLeft = 0;
    }
    if (newTop < 0) {
      if (ratio != null) {
        newHeight = rect.bottom;
        newWidth = newHeight * ratio;
        if (left) newLeft = rect.right - newWidth;
      } else {
        newHeight = rect.bottom;
      }
      newTop = 0;
    }
    if (newLeft + newWidth > availableSize.width) {
      newWidth = availableSize.width - newLeft;
      if (ratio != null) newHeight = newWidth / ratio;
    }
    if (newTop + newHeight > availableSize.height) {
      newHeight = availableSize.height - newTop;
      if (ratio != null) newWidth = newHeight * ratio;
    }

    onChanged(Rect.fromLTWH(newLeft, newTop, newWidth, newHeight));
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    for (int i = 1; i < 3; i++) {
      canvas.drawLine(
        Offset(size.width * i / 3, 0),
        Offset(size.width * i / 3, size.height),
        paint,
      );
      canvas.drawLine(
        Offset(0, size.height * i / 3),
        Offset(size.width, size.height * i / 3),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RotationDial extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _RotationDial({required this.value, required this.onChanged});

  @override
  State<_RotationDial> createState() => _RotationDialState();
}

class _RotationDialState extends State<_RotationDial> {
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _dragOffset = widget.value * 200; // Scale for dragging
  }

  @override
  void didUpdateWidget(covariant _RotationDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging) {
      _dragOffset = widget.value * 200;
    }
  }

  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (_) => _isDragging = true,
      onPanEnd: (_) {
        _isDragging = false;
        widget.onChanged(_dragOffset / 200);
      },
      onPanUpdate: (details) {
        setState(() {
          _dragOffset -= details.delta.dx;
          _dragOffset = _dragOffset.clamp(
            -math.pi / 4 * 200,
            math.pi / 4 * 200,
          );
          widget.onChanged(_dragOffset / 200);
        });
      },
      child: CustomPaint(
        size: const Size(double.infinity, 60),
        painter: _RotationDialPainter(offset: _dragOffset),
      ),
    );
  }
}

class _RotationDialPainter extends CustomPainter {
  final double offset;
  _RotationDialPainter({required this.offset});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1.0;

    final center = size.width / 2;
    const spacing = 10.0;

    for (double i = -1000; i <= 1000; i += spacing) {
      final x = center + (i - offset);
      if (x < 0 || x > size.width) continue;

      double height = 10;
      if ((i / spacing).round() % 5 == 0) {
        height = 20;
        paint.color = Colors.white54;
      } else {
        paint.color = Colors.white24;
      }

      canvas.drawLine(
        Offset(x, size.height / 2 - height / 2),
        Offset(x, size.height / 2 + height / 2),
        paint,
      );
    }

    // Indicator
    paint.color = const Color(0xFFFF5722);
    paint.strokeWidth = 2.0;
    canvas.drawLine(
      Offset(center, size.height / 2 - 25),
      Offset(center, size.height / 2 + 25),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _RotationDialPainter oldDelegate) =>
      oldDelegate.offset != offset;
}
