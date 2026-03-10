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
        shadows: [
          Shadow(
            offset: const Offset(1, 1),
            blurRadius: 2,
            color: Colors.black.withValues(alpha: 0.5),
          ),
        ],
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
                if (widget.isSelected)
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
