import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'filters.dart';
import 'overlays.dart';

enum EditorMode { ratio, rotate, filter, text, sticker }

class CropEditorState {
  int rotation = 0;
  double fineRotation = 0.0; // In radians
  bool flipX = false;
  double? aspectRatio;
  bool showGrid = true;
  bool hasChanges = false;
  Filter activeFilter = PresetFilters.list.first;
  List<OverlayItem> overlays = [];
  String? selectedOverlayId;

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
    activeFilter = PresetFilters.list.first;
    overlays = [];
    selectedOverlayId = null;
    cropRect = Rect.zero;
  }
}

class GridPainter extends CustomPainter {
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

class RotationDial extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const RotationDial({super.key, required this.value, required this.onChanged});

  @override
  State<RotationDial> createState() => _RotationDialState();
}

class _RotationDialState extends State<RotationDial> {
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _dragOffset = widget.value * 200; // Scale for dragging
  }

  @override
  void didUpdateWidget(covariant RotationDial oldWidget) {
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
          _dragOffset = _dragOffset.clamp(-math.pi * 200, math.pi * 200);
          widget.onChanged(_dragOffset / 200);
        });
      },
      child: CustomPaint(
        size: const Size(double.infinity, 60),
        painter: RotationDialPainter(offset: _dragOffset),
      ),
    );
  }
}

class RotationDialPainter extends CustomPainter {
  final double offset;
  RotationDialPainter({required this.offset});

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
  bool shouldRepaint(covariant RotationDialPainter oldDelegate) =>
      oldDelegate.offset != offset;
}

class CropBox extends StatelessWidget {
  final Widget image;
  final CropEditorState state;
  final Size availableSize;
  final bool showGrid;
  final Function(Rect) onChanged;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;

  const CropBox({
    super.key,
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
              child: IgnorePointer(child: CustomPaint(painter: GridPainter())),
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

                newLeft = newLeft.clamp(
                  0,
                  math.max(0.0, availableSize.width - rect.width),
                );
                newTop = newTop.clamp(
                  0,
                  math.max(0.0, availableSize.height - rect.height),
                );

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
