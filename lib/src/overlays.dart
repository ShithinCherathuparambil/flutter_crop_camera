import 'package:flutter/material.dart';

enum OverlayType { text, sticker }

abstract class OverlayItem {
  final String id;
  Offset position;
  double scale;
  double rotation;

  OverlayItem({
    required this.id,
    this.position = Offset.zero,
    this.scale = 1.0,
    this.rotation = 0.0,
  });

  Widget buildWidget();
}

class TextOverlay extends OverlayItem {
  String text;
  Color color;
  double fontSize;

  TextOverlay({
    required super.id,
    required this.text,
    this.color = Colors.white,
    this.fontSize = 24.0,
    super.position,
    super.scale,
    super.rotation,
  });

  @override
  Widget buildWidget() {
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

class StickerOverlay extends OverlayItem {
  String text; // Using emoji as sticker for now
  double fontSize;

  StickerOverlay({
    required super.id,
    required this.text,
    this.fontSize = 50.0,
    super.position,
    super.scale,
    super.rotation,
  });

  @override
  Widget buildWidget() {
    return Text(text, style: TextStyle(fontSize: fontSize));
  }
}

class DraggableOverlay extends StatefulWidget {
  final OverlayItem item;
  final VoidCallback onDelete;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final Function(OverlayItem) onUpdate;
  final bool isSelected;
  final VoidCallback onTap;

  const DraggableOverlay({
    super.key,
    required this.item,
    required this.onDelete,
    required this.onUpdate,
    required this.onDragStart,
    required this.onDragEnd,
    this.isSelected = false,
    required this.onTap,
  });

  @override
  State<DraggableOverlay> createState() => _DraggableOverlayState();
}

class _DraggableOverlayState extends State<DraggableOverlay> {
  double _initialScale = 1.0;
  double _initialRotation = 0.0;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return Positioned(
      left: item.position.dx,
      top: item.position.dy,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onScaleStart: (details) {
            widget.onTap();
            widget.onDragStart();
            _initialScale = item.scale;
            _initialRotation = item.rotation;
          },
          onScaleUpdate: (details) {
            item.position += details.focalPointDelta;
            item.scale = (_initialScale * details.scale).clamp(0.5, 5.0);
            item.rotation = _initialRotation + details.rotation;
            widget.onUpdate(item);
          },
          onScaleEnd: (details) {
            widget.onDragEnd();
          },
          child: Transform(
            transform: Matrix4.diagonal3Values(item.scale, item.scale, 1.0)
              ..rotateZ(item.rotation),
            alignment: Alignment.center,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  decoration: widget.isSelected
                      ? BoxDecoration(
                          border: Border.all(
                            color: const Color(0xFFFF5722),
                            width: 2 / item.scale,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        )
                      : null,
                  padding: const EdgeInsets.all(8),
                  child: item.buildWidget(),
                ),
                if (widget.isSelected) ...[
                  // Delete Button
                  Positioned(
                    top: -12 / item.scale,
                    right: -12 / item.scale,
                    child: GestureDetector(
                      onTap: widget.onDelete,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.cancel,
                          color: Colors.redAccent,
                          size: 20 / item.scale,
                        ),
                      ),
                    ),
                  ),
                  // Resize Handle
                  Positioned(
                    bottom: -12 / item.scale,
                    right: -12 / item.scale,
                    child: GestureDetector(
                      onPanStart: (details) {
                        _initialScale = item.scale;
                      },
                      onPanUpdate: (details) {
                        setState(() {
                          // More intuitive distance-based scaling from center
                          // Since we are in a stack/transform, global vs local can be tricky
                          // but the delta is relative and reliable.
                          // Let's use a simpler but more robust accumulated delta approach
                          final double delta =
                              details.delta.dx + details.delta.dy;
                          item.scale = (item.scale + delta * 0.01).clamp(
                            0.5,
                            8.0,
                          );
                          widget.onUpdate(item);
                        });
                      },
                      onPanEnd: (details) {
                        widget.onDragEnd();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.open_in_full,
                          color: const Color(0xFFFF5722),
                          size: 18 / item.scale,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
