import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'shared_crop_widgets.dart';
import 'filters.dart';
import 'overlays.dart';

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
  late List<CropEditorState> _states;
  bool _isDragging = false;
  EditorMode _mode = EditorMode.ratio; // Current active tab

  @override
  void initState() {
    super.initState();
    _states = List.generate(widget.files.length, (index) => CropEditorState());
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

  void _reset() {
    setState(() {
      final state = _states[_currentIndex];
      state.reset();
      // Recalculate crop rect for the initial state
      state.cropRect = Rect.fromLTWH(
        0,
        0,
        state.baseSize.width,
        state.baseSize.height,
      );
    });
  }

  void _onDone() async {
    setState(() => _currentIndex = 0); // Reset or show global loader

    // Show a global loading dialog if many images
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final List<Future<File>> processingFutures = [];

      for (int i = 0; i < widget.files.length; i++) {
        processingFutures.add(_processImage(i));
      }

      final List<File> processedFiles = await Future.wait(processingFutures);

      if (mounted) {
        Navigator.pop(context); // Pop loading dialog
        widget.onImagesCropped(processedFiles);
      }
    } catch (e) {
      debugPrint("Error in multi-save: $e");
      if (mounted) {
        Navigator.pop(context); // Pop loading dialog
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error saving images: $e")));
      }
    }
  }

  // Helper: identity filter matrix (no color change)
  static const List<double> _identityMatrix = [
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];

  bool _isIdentityFilter(Filter filter) {
    final m = filter.matrix;
    for (int j = 0; j < _identityMatrix.length; j++) {
      if ((m[j] - _identityMatrix[j]).abs() > 0.001) return false;
    }
    return true;
  }

  Future<File> _processImage(int i) async {
    final state = _states[i];
    final file = widget.files[i];

    if (!state.hasChanges) return file;

    try {
      final rect = state.cropRect;
      final base = state.baseSize;

      if (rect == Rect.zero || base == Size.zero) return file;

      // OPT 1: Use ImageDescriptor to read dimensions without full image decode.
      // This reads only the image header, ~10x faster for large images.
      final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
        await file.readAsBytes(),
      );
      final ui.ImageDescriptor descriptor = await ui.ImageDescriptor.encoded(
        buffer,
      );
      final int srcW = descriptor.width;
      final int srcH = descriptor.height;
      buffer.dispose();

      final bool isRotated = state.rotation % 2 != 0;
      final double realImgW = isRotated ? srcH.toDouble() : srcW.toDouble();
      final double realImgH = isRotated ? srcW.toDouble() : srcH.toDouble();

      final double scaleX = realImgW / base.width;
      final double scaleY = realImgH / base.height;

      final int cropX = (rect.left * scaleX).round();
      final int cropY = (rect.top * scaleY).round();
      final int cropWidth = (rect.width * scaleX).round();
      final int cropHeight = (rect.height * scaleY).round();

      // Convert rotation step (0-3) to actual degrees (0, 90, 180, 270)
      final int rotationDegrees = state.rotation * 90;
      final String? croppedPath = await widget.cropNative(
        file.path,
        cropX,
        cropY,
        cropWidth,
        cropHeight,
        rotationDegrees,
        state.flipX,
      );

      if (croppedPath == null) throw Exception("Native crop failed for $i");

      final double fineRot = state.fineRotation;
      final bool hasFineRotation = fineRot.abs() > 0.001;
      final bool hasOverlays = state.overlays.isNotEmpty;
      final bool hasFilter = !_isIdentityFilter(state.activeFilter);

      // OPT 2: FAST PATH — no Flutter canvas needed at all.
      // Native already produced a correctly cropped+rotated+flipped JPEG.
      // If there's nothing else to apply, return it directly.
      if (!hasFineRotation && !hasFilter && !hasOverlays) {
        return File(croppedPath);
      }

      // SLOW PATH: We have fine rotation, filters, or overlays.
      late ui.Picture pictureFinal;
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);

      if (hasFineRotation) {
        // Must load FULL image to rotate properly before cropping.
        final bytes = await file.readAsBytes();
        final ui.Image fullImage = await decodeImageFromList(bytes);

        final recorderFull = ui.PictureRecorder();
        final canvasFull = Canvas(recorderFull);
        final Paint paint = Paint()
          ..colorFilter = state.activeFilter.colorFilter;

        canvasFull.save();

        if (state.rotation == 1) {
          canvasFull.translate(srcH.toDouble(), 0);
          canvasFull.rotate(math.pi / 2);
        } else if (state.rotation == 2) {
          canvasFull.translate(srcW.toDouble(), srcH.toDouble());
          canvasFull.rotate(math.pi);
        } else if (state.rotation == 3) {
          canvasFull.translate(0, srcW.toDouble());
          canvasFull.rotate(3 * math.pi / 2);
        }

        if (hasFineRotation) {
          canvasFull.translate(realImgW / 2, realImgH / 2);
          canvasFull.rotate(fineRot);
          canvasFull.translate(-realImgW / 2, -realImgH / 2);
        }

        if (state.flipX) {
          canvasFull.translate(realImgW, 0);
          canvasFull.scale(-1, 1);
        }

        canvasFull.drawImage(fullImage, Offset.zero, paint);
        canvasFull.restore();
        fullImage.dispose();

        if (hasOverlays) {
          final double overlayScale = realImgW / base.width;
          for (var item in state.overlays) {
            if (item is TextOverlay) {
              _drawTextOverlay(canvasFull, item, overlayScale);
            } else if (item is StickerOverlay) {
              _drawStickerOverlay(canvasFull, item, overlayScale);
            }
          }
        }

        final pictureFull = recorderFull.endRecording();

        // Shift canvas to extract crop box
        canvas.translate(-cropX.toDouble(), -cropY.toDouble());
        canvas.drawPicture(pictureFull);
        pictureFinal = recorder.endRecording();
      } else {
        // If NO fine rotation, Native Crop perfectly handled the geometry!
        final File croppedFile = File(croppedPath);
        final Uint8List croppedBytes = await croppedFile.readAsBytes();
        final ui.Image croppedImage = await decodeImageFromList(croppedBytes);

        final Paint paint = Paint()
          ..colorFilter = state.activeFilter.colorFilter;
        canvas.drawImage(croppedImage, Offset.zero, paint);

        if (hasOverlays) {
          canvas.save();
          canvas.translate(-cropX.toDouble(), -cropY.toDouble());
          final double overlayScale = realImgW / base.width;
          for (var item in state.overlays) {
            if (item is TextOverlay) {
              _drawTextOverlay(canvas, item, overlayScale);
            } else if (item is StickerOverlay) {
              _drawStickerOverlay(canvas, item, overlayScale);
            }
          }
          canvas.restore();
        }

        croppedImage.dispose();
        pictureFinal = recorder.endRecording();
      }

      final ui.Image imgFinal = await pictureFinal.toImage(
        cropWidth,
        cropHeight,
      );

      final ByteData? pngBytes = await imgFinal.toByteData(
        format: ui.ImageByteFormat.png,
      );
      imgFinal.dispose();

      if (pngBytes == null) throw Exception("Failed to encode image $i");

      final tempDir = await getTemporaryDirectory();
      final File savedFile = File(
        '${tempDir.path}/edited_${i}_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await savedFile.writeAsBytes(pngBytes.buffer.asUint8List());
      return savedFile;
    } catch (e) {
      debugPrint("Error processing image $i: $e");
      return file;
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
                  IconButton(
                    icon: const Icon(Icons.check, color: Color(0xFFFF5722)),
                    onPressed: _onDone,
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
                  if (_mode == EditorMode.ratio) ...[
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
                  ] else if (_mode == EditorMode.rotate) ...[
                    // Rotations
                    _buildRotationDialArea(),
                  ] else if (_mode == EditorMode.filter) ...[
                    // Filters
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
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildTabItem(
                          Icons.crop,
                          "Crop",
                          _mode == EditorMode.ratio,
                          () => setState(() {
                            _mode = EditorMode.ratio;
                            _states[_currentIndex].selectedOverlayId = null;
                          }),
                        ),
                        _buildTabItem(
                          Icons.rotate_90_degrees_ccw_outlined,
                          "Rotate",
                          _mode == EditorMode.rotate,
                          () => setState(() {
                            _mode = EditorMode.rotate;
                            _states[_currentIndex].selectedOverlayId = null;
                          }),
                        ),
                        _buildTabItem(
                          Icons.filter_vintage_outlined,
                          "Filter",
                          _mode == EditorMode.filter,
                          () => setState(() {
                            _mode = EditorMode.filter;
                            _states[_currentIndex].selectedOverlayId = null;
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
                        _buildTabItem(Icons.refresh, "Reset", false, _reset),
                        _buildTabItem(
                          Icons.delete_outline,
                          "Delete",
                          false,
                          _deleteCurrentImage,
                          color: Colors.redAccent.withValues(alpha: 0.8),
                        ),
                      ],
                    ),
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
          child: RotationDial(
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

  Widget _buildFilterItem(Filter filter) {
    final state = _states[_currentIndex];
    final bool isSelected = state.activeFilter.name == filter.name;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: () => setState(() {
          state.activeFilter = filter;
          state.hasChanges = true;
        }),
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
                  child: Image.file(
                    widget.files[_currentIndex],
                    fit: BoxFit.cover,
                  ),
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

  void _addText() {
    setState(() => _mode = EditorMode.text);
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
                    final state = _states[_currentIndex];
                    state.overlays.add(
                      TextOverlay(
                        id: DateTime.now().toString(),
                        text: text,
                        position: Offset(
                          state.baseSize.width / 2,
                          state.baseSize.height / 2,
                        ),
                      ),
                    );
                    state.selectedOverlayId = null;
                    state.hasChanges = true;
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
    setState(() => _mode = EditorMode.sticker);
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
                    final state = _states[_currentIndex];
                    state.overlays.add(
                      StickerOverlay(
                        id: DateTime.now().toString(),
                        text: emojis[index],
                        position: Offset(
                          state.baseSize.width / 2,
                          state.baseSize.height / 2,
                        ),
                      ),
                    );
                    state.selectedOverlayId = null;
                    state.hasChanges = true;
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

  void _drawTextOverlay(
    ui.Canvas canvas,
    TextOverlay item,
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
    ui.Canvas canvas,
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

class _SingleImageEditor extends StatefulWidget {
  final File file;
  final CropEditorState state;
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
      final buffer = await ui.ImmutableBuffer.fromUint8List(data);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);

      // Downsample for preview UI (max 1280px)
      const double maxPreviewSize = 1280.0;
      int? targetWidth;
      int? targetHeight;

      if (descriptor.width > maxPreviewSize ||
          descriptor.height > maxPreviewSize) {
        if (descriptor.width > descriptor.height) {
          targetWidth = maxPreviewSize.toInt();
        } else {
          targetHeight = maxPreviewSize.toInt();
        }
      }

      final codec = await descriptor.instantiateCodec(
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;

      if (mounted) {
        setState(() {
          _image = image;
          _loading = false;
        });
      } else {
        image.dispose();
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
              CropBox(
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
              // Overlays
              ...widget.state.overlays.map(
                (item) => DraggableOverlay(
                  item: item,
                  isSelected: widget.state.selectedOverlayId == item.id,
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
                  onTap: () =>
                      setState(() => widget.state.selectedOverlayId = item.id),
                  onDelete: () => setState(() {
                    widget.state.overlays.remove(item);
                    widget.state.selectedOverlayId = null;
                  }),
                  onUpdate: (updated) => setState(() {}),
                ),
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
            child: ColorFiltered(
              colorFilter: widget.state.activeFilter.colorFilter,
              child: Image.file(
                widget.file,
                width: w,
                height: h,
                fit: BoxFit.fill,
              ),
            ),
          ),
        );
      },
    );
  }
}
