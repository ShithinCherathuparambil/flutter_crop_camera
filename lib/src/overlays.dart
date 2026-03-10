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
  final Function(OverlayItem) onUpdate;
  final bool isSelected;
  final VoidCallback onTap;

  const DraggableOverlay({
    super.key,
    required this.item,
    required this.onDelete,
    required this.onUpdate,
    this.isSelected = false,
    required this.onTap,
  });

  @override
  DraggableOverlayState createState() => DraggableOverlayState();
}

class DraggableOverlayState extends State<DraggableOverlay> {
  late OverlayItem _item;
  double _initialScale = 1.0;
  double _initialRotation = 0.0;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _item.position.dx,
      top: _item.position.dy,
      child: GestureDetector(
        onTap: widget.onTap,
        onScaleStart: (details) {
          widget.onTap();
          _initialScale = _item.scale;
          _initialRotation = _item.rotation;
        },
        onScaleUpdate: (details) {
          setState(() {
            // Move: focalPointDelta gives the movement since previous update
            _item.position += details.focalPointDelta;

            // Scale: details.scale is relative to the start of the gesture (1.0)
            _item.scale = (_initialScale * details.scale).clamp(0.5, 5.0);

            // Rotate: details.rotation is relative to the start of the gesture (0.0)
            _item.rotation = _initialRotation + details.rotation;
          });
          widget.onUpdate(_item);
        },
        child: Transform(
          transform: Matrix4.identity()
            ..scale(_item.scale)
            ..rotateZ(_item.rotation),
          alignment: Alignment.center,
          child: Container(
            decoration: widget.isSelected
                ? BoxDecoration(
                    border: Border.all(
                      color: Colors.cyanAccent,
                      width: 2 / _item.scale,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  )
                : null,
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.isSelected)
                  GestureDetector(
                    onTap: widget.onDelete,
                    child: Icon(
                      Icons.cancel,
                      color: Colors.redAccent,
                      size: 20 / _item.scale,
                    ),
                  ),
                _item.buildWidget(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
