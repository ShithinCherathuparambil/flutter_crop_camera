import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'filters.dart';
import 'overlays.dart';
import 'shared_crop_widgets.dart';

class CropEditor extends StatefulWidget {
  final File file;
  final Function(File file) onImageSaved;
  final bool showGrid;
  final bool lockAspectRatio;
  final List<DeviceOrientation> screenOrientations;

  const CropEditor({
    super.key,
    required this.file,
    required this.onImageSaved,
    this.showGrid = true,
    this.lockAspectRatio = false,
    this.screenOrientations = const [DeviceOrientation.portraitUp],
  });

  @override
  State<CropEditor> createState() => _CropEditorState();
}

class _CropEditorState extends State<CropEditor> {
  ui.Image? _image;
  final CropEditorState _state = CropEditorState();
  EditorMode _mode = EditorMode.ratio;
  bool _isSaving = false;
  bool _isDragging = false;

  Filter get _activeFilter => _state.activeFilter;
  set _activeFilter(Filter f) => _state.activeFilter = f;
  List<OverlayItem> get _overlays => _state.overlays;
  String? get _selectedOverlayId => _state.selectedOverlayId;
  set _selectedOverlayId(String? id) => _state.selectedOverlayId = id;

  bool _loading = true;

  // Image Dimensions
  int _imgWidth = 0;
  int _imgHeight = 0;

  @override
  void initState() {
    super.initState();
    _state.showGrid = widget.showGrid;
    _loadDimensionsAndImage();
    SystemChrome.setPreferredOrientations(widget.screenOrientations);
  }

  Future<void> _loadDimensionsAndImage() async {
    try {
      final data = await widget.file.readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(data);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);

      _imgWidth = descriptor.width;
      _imgHeight = descriptor.height;

      // Downsample for preview UI (e.g., max 1280px in either dimension)
      const double maxPreviewSize = 1280.0;
      int? targetWidth;
      int? targetHeight;

      if (_imgWidth > maxPreviewSize || _imgHeight > maxPreviewSize) {
        if (_imgWidth > _imgHeight) {
          targetWidth = maxPreviewSize.toInt();
        } else {
          targetHeight = maxPreviewSize.toInt();
        }
      }

      if (mounted) {
        setState(() {
          _loading = false;
        });
      }

      final codec = await descriptor.instantiateCodec(
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() {
          _image = frame.image;
        });
      } else {
        frame.image.dispose();
      }
    } catch (e) {
      debugPrint("CropEditor: Error loading image: $e");
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _state.reset();
      _state.aspectRatio = null;
      _activeFilter = PresetFilters.list.first;
      _overlays.clear();
      _selectedOverlayId = null;
    });
  }

  void _calculateLayout(BoxConstraints constraints) {
    if (_imgWidth == 0 || _imgHeight == 0) return;

    final double maxWidth = constraints.maxWidth - 40;
    final double maxHeight = constraints.maxHeight - 40;

    final bool isRotated = _state.rotation % 2 != 0;
    final double imgW = isRotated
        ? _imgHeight.toDouble()
        : _imgWidth.toDouble();
    final double imgH = isRotated
        ? _imgWidth.toDouble()
        : _imgHeight.toDouble();
    final double imgRatio = imgW / imgH;

    double baseW, baseH;
    if (imgRatio > maxWidth / maxHeight) {
      baseW = maxWidth;
      baseH = maxWidth / imgRatio;
    } else {
      baseH = maxHeight;
      baseW = maxHeight * imgRatio;
    }

    _state.baseSize = Size(baseW, baseH);

    if (_state.cropRect == Rect.zero) {
      _state.cropRect = Rect.fromLTWH(0, 0, baseW, baseH);
    }

    if (_state.aspectRatio != null) {
      _applyAspectRatio(_state.aspectRatio!, baseW, baseH);
    }
  }

  void _applyAspectRatio(double ratio, double baseW, double baseH) {
    Rect rect = _state.cropRect;
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

    if (left < 0) left = 0;
    if (top < 0) top = 0;
    if (left + targetW > baseW) left = baseW - targetW;
    if (top + targetH > baseH) top = baseH - targetH;

    _state.cropRect = Rect.fromLTWH(left, top, targetW, targetH);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFFF5722)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.white54),
                    onPressed: _reset,
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _calculateLayout(constraints);
                  final baseW = _state.baseSize.width;
                  final baseH = _state.baseSize.height;

                  return Center(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Main Editor Content (Image + Overlays)
                        Center(
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              // Dimmed background Image
                              Opacity(
                                opacity: 0.3,
                                child: _buildMainContent(baseW, baseH),
                              ),
                              // Crop Box
                              CropBox(
                                image: _buildMainContent(baseW, baseH),
                                state: _state,
                                availableSize: Size(baseW, baseH),
                                showGrid: _state.showGrid || _isDragging,
                                onChanged: (rect) {
                                  setState(() {
                                    _state.cropRect = rect;
                                    _state.hasChanges = true;
                                  });
                                },
                                onDragStart: () =>
                                    setState(() => _isDragging = true),
                                onDragEnd: () =>
                                    setState(() => _isDragging = false),
                              ),
                              // Overlays (Tied to image coordinates) - Drawn ON TOP
                              ..._overlays.map(
                                (item) => DraggableOverlay(
                                  item: item,
                                  isSelected: _selectedOverlayId == item.id,
                                  onDragStart: () =>
                                      setState(() => _isDragging = true),
                                  onDragEnd: () =>
                                      setState(() => _isDragging = false),
                                  onTap: () => setState(
                                    () => _selectedOverlayId = item.id,
                                  ),
                                  onDelete: () => setState(() {
                                    _overlays.remove(item);
                                    _selectedOverlayId = null;
                                  }),
                                  onUpdate: (updated) => setState(() {}),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_isSaving)
                          Positioned.fill(
                            child: Container(
                              color: Colors.black54,
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFFFF5722),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            _buildBottomPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent(double w, double h) {
    return SizedBox(
      width: w,
      height: h,
      child: Transform.scale(
        scaleX: _state.flipX ? -1 : 1,
        child: Transform.rotate(
          angle: _state.rotation * math.pi / 2 + _state.fineRotation,
          child: ColorFiltered(
            colorFilter: _activeFilter.colorFilter,
            child: Image.file(widget.file, fit: BoxFit.fill),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
          if (_mode == EditorMode.ratio) ...[
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
          ] else if (_mode == EditorMode.rotate) ...[
            _buildRotationDialArea(),
          ] else if (_mode == EditorMode.filter) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: PresetFilters.list
                    .map((f) => _buildFilterItem(f))
                    .toList(),
              ),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildTabItem(
                Icons.crop,
                "Crop",
                _mode == EditorMode.ratio,
                () => setState(() {
                  _mode = EditorMode.ratio;
                  _selectedOverlayId = null;
                }),
              ),
              _buildTabItem(
                Icons.rotate_90_degrees_ccw_outlined,
                "Rotate",
                _mode == EditorMode.rotate,
                () => setState(() {
                  _mode = EditorMode.rotate;
                  _selectedOverlayId = null;
                }),
              ),
              _buildTabItem(
                Icons.filter_vintage_outlined,
                "Filter",
                _mode == EditorMode.filter,
                () => setState(() {
                  _mode = EditorMode.filter;
                  _selectedOverlayId = null;
                }),
              ),
              _buildTabItem(
                Icons.text_fields,
                "Text",
                _mode == EditorMode.text,
                _addText,
              ),
              _buildTabItem(
                Icons.emoji_emotions_outlined,
                "Sticker",
                _mode == EditorMode.sticker,
                _addSticker,
              ),
              _buildTabItem(
                _state.showGrid ? Icons.grid_on : Icons.grid_off,
                "Grid",
                false,
                () => setState(() => _state.showGrid = !_state.showGrid),
              ),
              _buildTabItem(Icons.flip, "Flip", false, () {
                setState(() {
                  _state.flipX = !_state.flipX;
                  _state.hasChanges = true;
                });
              }),
              _buildTabItem(
                Icons.delete_outline,
                "Delete",
                false,
                () {
                  // Simply pop if it's the single editor, or call a specific reset if needed
                  Navigator.pop(context);
                },
                color: Colors.redAccent.withValues(alpha: 0.8),
              ),
              _buildTabItem(
                Icons.check_circle_outline,
                "Save",
                false,
                _isSaving ? () {} : _saveImage,
                color: const Color(0xFFFF5722),
              ),
            ],
          ),
        ],
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
    return Column(
      children: [
        Text(
          "${(_state.fineRotation * 180 / math.pi).toStringAsFixed(1)}°",
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
          child: RotationDial(
            value: _state.fineRotation,
            onChanged: (val) {
              setState(() {
                _state.fineRotation = val;
                _state.hasChanges = true;
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
                  _state.fineRotation = 0;
                  _state.hasChanges = true;
                });
              },
            ),
            const SizedBox(width: 20),
            IconButton(
              icon: const Icon(Icons.rotate_right, color: Colors.white54),
              onPressed: () {
                setState(() {
                  _state.rotation = (_state.rotation + 1) % 4;
                  _state.hasChanges = true;
                });
              },
            ),
            const SizedBox(width: 20),
            IconButton(
              icon: const Icon(Icons.flip, color: Colors.white54),
              onPressed: () {
                setState(() {
                  _state.flipX = !_state.flipX;
                  _state.hasChanges = true;
                });
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFilterItem(Filter filter) {
    final bool isSelected = _activeFilter.name == filter.name;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: () => setState(() => _activeFilter = filter),
        child: Column(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                border: isSelected
                    ? Border.all(color: const Color(0xFFFF5722), width: 2)
                    : null,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: ColorFiltered(
                  colorFilter: filter.colorFilter,
                  child: Image.file(widget.file, fit: BoxFit.cover),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              filter.name,
              style: TextStyle(
                color: isSelected ? const Color(0xFFFF5722) : Colors.white70,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRatioBtn(String label, double? ratio) {
    final bool isSelected =
        (ratio == null && _state.aspectRatio == null) ||
        (ratio != null &&
            _state.aspectRatio != null &&
            (ratio - _state.aspectRatio!).abs() < 0.001);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: () {
          setState(() {
            _state.aspectRatio = ratio;
            _state.hasChanges = true;
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

  void _addText() {
    setState(() {
      _mode = EditorMode.text;
      _selectedOverlayId = null;
    });
    showDialog(
      context: context,
      builder: (context) {
        String text = "";
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text("Add Text", style: TextStyle(color: Colors.white)),
          content: TextField(
            style: const TextStyle(color: Colors.white),
            autofocus: true,
            onChanged: (val) => text = val,
            decoration: const InputDecoration(
              hintText: "Enter text...",
              hintStyle: TextStyle(color: Colors.white54),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFFF5722)),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "Cancel",
                style: TextStyle(color: Colors.white54),
              ),
            ),
            TextButton(
              onPressed: () {
                if (text.isNotEmpty) {
                  setState(() {
                    _overlays.add(
                      TextOverlay(
                        id: DateTime.now().toString(),
                        text: text,
                        position: Offset(
                          _state.baseSize.width / 2,
                          _state.baseSize.height / 2,
                        ),
                      ),
                    );
                    _selectedOverlayId = null;
                  });
                }
                Navigator.pop(context);
              },
              child: const Text(
                "Add",
                style: TextStyle(color: Color(0xFFFF5722)),
              ),
            ),
          ],
        );
      },
    );
  }

  void _addSticker() {
    setState(() {
      _mode = EditorMode.sticker;
      _selectedOverlayId = null;
    });
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      builder: (context) {
        final List<String> emojis = [
          "😀",
          "😎",
          "😍",
          "🥳",
          "🔥",
          "🎉",
          "❤️",
          "🚀",
          "💯",
          "🌟",
          "👻",
          "👍",
          "👑",
          "⚽️",
          "🐶",
          "🍕",
        ];
        return Container(
          padding: const EdgeInsets.all(20),
          height: 300,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
            ),
            itemCount: emojis.length,
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _overlays.add(
                      StickerOverlay(
                        id: DateTime.now().toString(),
                        text: emojis[index],
                        position: Offset(
                          _state.baseSize.width / 2,
                          _state.baseSize.height / 2,
                        ),
                      ),
                    );
                    _selectedOverlayId = null;
                  });
                  Navigator.pop(context);
                },
                child: Center(
                  child: Text(
                    emojis[index],
                    style: const TextStyle(fontSize: 40),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _saveImage() async {
    if (_isSaving) return;
    if (_image == null) return;

    setState(() => _isSaving = true);

    try {
      final rect = _state.cropRect;
      final base = _state.baseSize;

      final bool isRotated = _state.rotation % 2 != 0;
      final double realImgW = isRotated
          ? _imgHeight.toDouble()
          : _imgWidth.toDouble();
      final double realImgH = isRotated
          ? _imgWidth.toDouble()
          : _imgHeight.toDouble();

      final double scaleX = realImgW / base.width;
      final double scaleY = realImgH / base.height;

      // Final crop area in original image pixels
      final int cropX = (rect.left * scaleX).round();
      final int cropY = (rect.top * scaleY).round();
      final int cropWidth = (rect.width * scaleX).round();
      final int cropHeight = (rect.height * scaleY).round();

      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);

      if (cropWidth <= 0 || cropHeight <= 0) {
        throw Exception("Invalid crop dimensions");
      }

      // 1. Draw transformed image + overlays onto a "full" canvas of the original size
      final recorderFull = ui.PictureRecorder();
      final canvasFull = Canvas(recorderFull);
      final Paint paint = Paint()..colorFilter = _activeFilter.colorFilter;

      final bytes = await widget.file.readAsBytes();
      final ui.Image fullImage = await decodeImageFromList(bytes);

      canvasFull.save();

      // ROTATION & FLIP
      if (_state.rotation == 1) {
        canvasFull.translate(_imgHeight.toDouble(), 0);
        canvasFull.rotate(math.pi / 2);
      } else if (_state.rotation == 2) {
        canvasFull.translate(_imgWidth.toDouble(), _imgHeight.toDouble());
        canvasFull.rotate(math.pi);
      } else if (_state.rotation == 3) {
        canvasFull.translate(0, _imgWidth.toDouble());
        canvasFull.rotate(3 * math.pi / 2);
      }

      // FINE ROTATION
      if (_state.fineRotation != 0) {
        canvasFull.translate(realImgW / 2, realImgH / 2);
        canvasFull.rotate(_state.fineRotation);
        canvasFull.translate(-realImgW / 2, -realImgH / 2);
      }

      // FLIP
      if (_state.flipX) {
        canvasFull.translate(realImgW, 0);
        canvasFull.scale(-1, 1);
      }

      // Draw the image with filter
      canvasFull.drawImage(fullImage, Offset.zero, paint);
      canvasFull.restore();
      fullImage.dispose();

      // 2. Draw Overlays on top (untransformed by image rotation/flip but scaled)
      final double overlayScale = realImgW / base.width;
      for (var item in _overlays) {
        if (item is TextOverlay) {
          _drawTextOverlay(canvasFull, item, overlayScale);
        } else if (item is StickerOverlay) {
          _drawStickerOverlay(canvasFull, item, overlayScale);
        }
      }

      final pictureFull = recorderFull.endRecording();

      // 3. Move the canvas to the crop start and draw the full picture
      canvas.translate(-cropX.toDouble(), -cropY.toDouble());
      canvas.drawPicture(pictureFull);

      final pictureFinal = recorder.endRecording();
      final ui.Image imgFinal = await pictureFinal.toImage(
        cropWidth,
        cropHeight,
      );
      final ByteData? pngBytes = await imgFinal.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (pngBytes == null) throw Exception("Failed to encode image");

      final tempDir = await getTemporaryDirectory();
      final File savedFile = File(
        '${tempDir.path}/edited_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await savedFile.writeAsBytes(pngBytes.buffer.asUint8List());

      if (mounted) {
        widget.onImageSaved(savedFile);
      }
    } catch (e) {
      debugPrint("Save Error: $e");
      setState(() => _isSaving = false);
    }
  }

  void _drawTextOverlay(Canvas canvas, TextOverlay item, double scaleFactor) {
    canvas.save();
    canvas.translate(
      item.position.dx * scaleFactor,
      item.position.dy * scaleFactor,
    );
    canvas.rotate(item.rotation);
    canvas.scale(item.scale * scaleFactor);
    final textPainter = TextPainter(
      text: TextSpan(
        text: item.text,
        style: TextStyle(
          color: item.color,
          fontSize: item.fontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(-textPainter.width / 2, -textPainter.height / 2),
    );
    canvas.restore();
  }

  void _drawStickerOverlay(
    Canvas canvas,
    StickerOverlay item,
    double scaleFactor,
  ) {
    canvas.save();
    canvas.translate(
      item.position.dx * scaleFactor,
      item.position.dy * scaleFactor,
    );
    canvas.rotate(item.rotation);
    canvas.scale(item.scale * scaleFactor);
    final textPainter = TextPainter(
      text: TextSpan(
        text: item.text,
        style: TextStyle(fontSize: item.fontSize),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(-textPainter.width / 2, -textPainter.height / 2),
    );
    canvas.restore();
  }
}
