import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'filters.dart';
import 'overlays.dart';

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
  final TransformationController _transformationController =
      TransformationController();

  // --- State Variables ---
  int _rotation = 0;
  bool _flipX = false;
  double? _aspectRatio;
  late bool _showGrid;
  Filter _activeFilter = PresetFilters.list.first; // Default no filter
  bool _isFilterMode = false; // Toggle between Crop and Filter mode
  bool _isSaving = false;

  // Overlays
  final List<OverlayItem> _overlays = [];
  String? _selectedOverlayId;

  //  // Rendered/Calculated Properties
  double _viewportWidth = 0;
  double _viewportHeight = 0;
  double _baseWidth = 0;
  double _baseHeight = 0;
  bool _loading = true;

  // Image Dimensions (Pre-loaded)
  int _imgWidth = 0;
  int _imgHeight = 0;

  @override
  void initState() {
    super.initState();
    _showGrid = widget.showGrid;
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

      // Update UI with dimensions immediately
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }

      // Decode full image in background for saving later
      descriptor
          .instantiateCodec()
          .then((codec) {
            return codec.getNextFrame();
          })
          .then((frame) {
            if (mounted) {
              _image = frame.image;
            } else {
              frame.image.dispose();
            }
          });
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
      _activeFilter = PresetFilters.list.first;
      _transformationController.value = Matrix4.identity();
      _overlays.clear();
      _selectedOverlayId = null;
    });
  }

  void _calculateLayout(BoxConstraints constraints) {
    if (_imgWidth == 0 || _imgHeight == 0) return;

    final double maxWidth = constraints.maxWidth;
    final double maxHeight = constraints.maxHeight;

    // 1. Calculate Viewport Size
    if (_aspectRatio == null) {
      final bool isRotated = _rotation % 2 != 0;
      final double w = isRotated ? _imgHeight.toDouble() : _imgWidth.toDouble();
      final double h = isRotated ? _imgWidth.toDouble() : _imgHeight.toDouble();
      final double ratio = w / h;

      if (ratio > 1) {
        _viewportWidth = maxWidth;
        _viewportHeight = maxWidth / ratio;
      } else {
        _viewportHeight = maxWidth;
        _viewportWidth = _viewportHeight * ratio;
      }
    } else {
      if (_aspectRatio! >= 1) {
        _viewportWidth = maxWidth;
        _viewportHeight = maxWidth / _aspectRatio!;
      } else {
        _viewportHeight = maxWidth;
        _viewportWidth = _viewportHeight * _aspectRatio!;
      }
    }

    if (_viewportHeight > maxHeight) {
      final double scale = maxHeight / _viewportHeight;
      _viewportHeight = maxHeight;
      _viewportWidth = _viewportWidth * scale;
    }

    // 2. Calculate Base Image Size
    final bool isRotated = _rotation % 2 != 0;
    final double realImgW = isRotated
        ? _imgHeight.toDouble()
        : _imgWidth.toDouble();
    final double realImgH = isRotated
        ? _imgWidth.toDouble()
        : _imgHeight.toDouble();

    final double imgRatio = realImgW / realImgH;
    final double viewportRatio = _viewportWidth / _viewportHeight;

    if (imgRatio > viewportRatio) {
      _baseHeight = _viewportHeight;
      _baseWidth = _baseHeight * imgRatio;
    } else {
      _baseWidth = _viewportWidth;
      _baseHeight = _baseWidth / imgRatio;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.cyanAccent),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
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
                              child: Stack(
                                children: [
                                  // 1. The Image (Rotated & Flipped)
                                  Positioned.fill(
                                    child: Transform.scale(
                                      scaleX: _flipX ? -1 : 1,
                                      child: Transform.rotate(
                                        angle: _rotation * math.pi / 2,
                                        child: ColorFiltered(
                                          colorFilter:
                                              _activeFilter.colorFilter,
                                          child: Image.file(
                                            widget.file,
                                            fit: BoxFit.fill,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  // 2. Overlays
                                  ..._overlays.map(
                                    (item) => DraggableOverlay(
                                      item: item,
                                      isSelected: _selectedOverlayId == item.id,
                                      onTap: () => setState(
                                        () => _selectedOverlayId = item.id,
                                      ),
                                      onDelete: () => setState(() {
                                        _overlays.remove(item);
                                        _selectedOverlayId = null;
                                      }),
                                      onUpdate: (updated) {
                                        // Trigger repaint/update if needed
                                        setState(() {});
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Grid Overlay (Only in Crop Mode)
                    if (_showGrid &&
                        !_isFilterMode &&
                        _selectedOverlayId == null)
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

                    // Saving Indicator
                    if (_isSaving)
                      Container(
                        color: Colors.black54,
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: Colors.cyanAccent,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),

          // Toolbar
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
                // Mode Tabs
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildModeTab(
                        "Crop",
                        !_isFilterMode && _selectedOverlayId == null,
                      ),
                      const SizedBox(width: 20),
                      _buildModeTab("Filters", _isFilterMode),
                      const SizedBox(width: 20),
                      GestureDetector(
                        onTap: _addText,
                        child: Column(
                          children: [
                            const Icon(Icons.text_fields, color: Colors.white),
                            const SizedBox(height: 4),
                            const Text(
                              "Text",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      GestureDetector(
                        onTap: _addSticker,
                        child: Column(
                          children: [
                            const Icon(
                              Icons.emoji_emotions_outlined,
                              color: Colors.white,
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              "Sticker",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 15),

                // Content based on Mode
                if (_isFilterMode)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: PresetFilters.list
                          .map((f) => _buildFilterItem(f))
                          .toList(),
                    ),
                  )
                else if (_selectedOverlayId == null)
                  // Crop Controls (Ratios) - Only show if no overlay selected
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

                const SizedBox(height: 20),

                // Bottom Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white54),
                      onPressed: _reset,
                      tooltip: "Reset",
                    ),
                    if (!_isFilterMode && _selectedOverlayId == null) ...[
                      IconButton(
                        icon: Icon(
                          _showGrid ? Icons.grid_on : Icons.grid_off,
                          color: Colors.white,
                        ),
                        onPressed: () => setState(() => _showGrid = !_showGrid),
                        tooltip: "Toggle Grid",
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.rotate_left,
                          color: Colors.white,
                        ),
                        onPressed: () {
                          setState(() {
                            _rotation = (_rotation - 1) % 4;
                            if (_rotation < 0) _rotation += 4;
                            _transformationController.value =
                                Matrix4.identity();
                          });
                        },
                        tooltip: "Rotate",
                      ),
                      IconButton(
                        icon: const Icon(Icons.flip, color: Colors.white),
                        onPressed: () => setState(() => _flipX = !_flipX),
                        tooltip: "Mirror",
                      ),
                    ],
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.redAccent,
                        size: 30,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.check,
                        color: Colors.cyanAccent,
                        size: 30,
                      ),
                      onPressed: _isSaving ? null : _saveImage,
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

  Widget _buildModeTab(String label, bool isActive) {
    return GestureDetector(
      onTap: () {
        setState(() {
          if (label == "Crop") {
            _isFilterMode = false;
            _selectedOverlayId = null;
          } else if (label == "Filters") {
            _isFilterMode = true;
            _selectedOverlayId = null;
          }
        });
      },
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.cyanAccent : Colors.white54,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          if (isActive)
            Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                color: Colors.cyanAccent,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
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
                    ? Border.all(color: Colors.cyanAccent, width: 2)
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
                color: isSelected ? Colors.cyanAccent : Colors.white70,
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
        (ratio == null && _aspectRatio == null) ||
        (ratio != null &&
            _aspectRatio != null &&
            (ratio - _aspectRatio!).abs() < 0.001);

    return Padding(
      padding: const EdgeInsets.only(right: 15),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _aspectRatio = ratio;
            _transformationController.value = Matrix4.identity();
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

  void _addText() {
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
                borderSide: BorderSide(color: Colors.cyanAccent),
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
                        position: Offset(_baseWidth / 2, _baseHeight / 2),
                      ),
                    );
                    _selectedOverlayId = null; // Deselect others
                  });
                }
                Navigator.pop(context);
              },
              child: const Text(
                "Add",
                style: TextStyle(color: Colors.cyanAccent),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveImage() async {
    if (_isSaving) return;

    // Wait for background image loading if it hasn't finished yet
    if (_image == null) {
      setState(() => _isSaving = true);
      // Poll check for image
      int retries = 0;
      while (_image == null && retries < 20) {
        // Max 2 seconds wait
        await Future.delayed(const Duration(milliseconds: 100));
        retries++;
      }
      if (_image == null) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Image still loading, please wait...")),
        );
        return;
      }
    } else {
      setState(() => _isSaving = true);
    }

    try {
      // 1. Calculate Crop Rect on Original Image
      final Matrix4 matrix = _transformationController.value;
      final double tx = matrix.getRow(0).w;
      final double ty = matrix.getRow(1).w;
      final double scale = matrix.getRow(0).x;

      final double renderX = (-tx / scale).clamp(0.0, _baseWidth);
      final double renderY = (-ty / scale).clamp(0.0, _baseHeight);
      final double renderW = (_viewportWidth / scale);
      final double renderH = (_viewportHeight / scale);

      final bool isRotated = _rotation % 2 != 0;
      final double realImgW = isRotated
          ? _imgHeight.toDouble()
          : _imgWidth.toDouble();
      final double realImgH = isRotated
          ? _imgWidth.toDouble()
          : _imgHeight.toDouble();

      final double scaleX = realImgW / _baseWidth;
      final double scaleY = realImgH / _baseHeight;

      final int cropX = (renderX * scaleX).round();
      final int cropY = (renderY * scaleY).round();
      final int cropWidth = (renderW * scaleX).round();
      final int cropHeight = (renderH * scaleY).round();

      // 2. Setup Recording Pipeline
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);

      // Target dimensions for the final file
      final int targetW = cropWidth;
      final int targetH = cropHeight;

      if (targetW <= 0 || targetH <= 0)
        throw Exception("Invalid crop dimensions");

      // Shift canvas so that the crop area is at 0,0
      canvas.translate(-cropX.toDouble(), -cropY.toDouble());

      // 3. Draw Full Image
      final recorderFull = ui.PictureRecorder();
      final canvasFull = Canvas(recorderFull);

      final Paint paint = Paint()..colorFilter = _activeFilter.colorFilter;

      canvasFull.save();

      if (_rotation == 1) {
        // 90
        canvasFull.translate(_image!.height.toDouble(), 0);
        canvasFull.rotate(math.pi / 2);
      } else if (_rotation == 2) {
        // 180
        canvasFull.translate(
          _image!.width.toDouble(),
          _image!.height.toDouble(),
        );
        canvasFull.rotate(math.pi);
      } else if (_rotation == 3) {
        // 270
        canvasFull.translate(0, _image!.width.toDouble());
        canvasFull.rotate(3 * math.pi / 2);
      }

      if (_flipX) {
        canvasFull.translate(realImgW, 0);
        canvasFull.scale(-1, 1);
      }

      // Draw original image
      canvasFull.drawImage(_image!, Offset.zero, paint);

      // Draw Overlays
      // IMPORTANT: Overlays coordinates are relative to the _baseWidth/_baseHeight.
      // But we are drawing into a canvas of size (realImgW, realImgH).
      // So we need to SCALE the overlay coordinates.

      // Ratio between real image size and screen base size.
      // _baseWidth covers viewport. realImgW is the actual transformed image width.
      final double overlayScaleX = realImgW / _baseWidth;
      // Note: scaleX and scaleY should be identical because aspect ratio is preserved.

      for (var item in _overlays) {
        if (item is TextOverlay) {
          _drawTextOverlay(canvasFull, item, overlayScaleX);
        } else if (item is StickerOverlay) {
          _drawStickerOverlay(canvasFull, item, overlayScaleX);
        }
      }

      canvasFull.restore();

      final pictureFull = recorderFull.endRecording();

      // 4. Draw the cropped portion
      canvas.drawPicture(pictureFull);

      final pictureFinal = recorder.endRecording();
      final ui.Image imgFinal = await pictureFinal.toImage(
        cropWidth,
        cropHeight,
      );

      // 5. Encode and Save
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

    // Position (Scaled)
    canvas.translate(
      item.position.dx * scaleFactor,
      item.position.dy * scaleFactor,
    );

    // Rotate
    canvas.rotate(item.rotation);

    // Scale (User Scale * Image Scale Factor)
    canvas.scale(item.scale * scaleFactor);

    final textSpan = TextSpan(
      text: item.text,
      style: TextStyle(
        color: item.color,
        fontSize: item.fontSize,
        fontWeight: FontWeight.bold,
        shadows: [
          Shadow(
            offset: const Offset(1, 1),
            blurRadius: 2,
            color: Colors.black.withOpacity(0.5),
          ),
        ],
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();

    // Center text at position
    final offset = Offset(-textPainter.width / 2, -textPainter.height / 2);
    textPainter.paint(canvas, offset);

    canvas.restore();
  }

  void _addSticker() {
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
                        position: Offset(_baseWidth / 2, _baseHeight / 2),
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

  void _drawStickerOverlay(
    Canvas canvas,
    StickerOverlay item,
    double scaleFactor,
  ) {
    canvas.save();

    // Position (Scaled)
    canvas.translate(
      item.position.dx * scaleFactor,
      item.position.dy * scaleFactor,
    );

    // Rotate
    canvas.rotate(item.rotation);

    // Scale (User Scale * Image Scale Factor)
    canvas.scale(item.scale * scaleFactor);

    final textSpan = TextSpan(
      text: item.text,
      style: TextStyle(fontSize: item.fontSize),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();

    // Center text at position
    final offset = Offset(-textPainter.width / 2, -textPainter.height / 2);
    textPainter.paint(canvas, offset);

    canvas.restore();
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.5)
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
