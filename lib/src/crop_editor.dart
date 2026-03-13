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
  final bool lockAspectRatio;
  final List<DeviceOrientation> screenOrientations;
  final EditorFeatureToggles featureToggles;
  final EditorAppBarStyle appBarStyle;
  final EditorStyle editorStyle;

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
  final int quality;

  const CropEditor({
    super.key,
    required this.file,
    required this.onImageSaved,
    required this.cropNative,
    this.lockAspectRatio = false,
    this.screenOrientations = const [DeviceOrientation.portraitUp],
    this.quality = 90,
    this.featureToggles = const EditorFeatureToggles(),
    this.appBarStyle = const EditorAppBarStyle(),
    this.editorStyle = const EditorStyle(),
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
    _state.showGrid = true;
    _mode = _firstEnabledMode(widget.featureToggles);
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

  EditorMode _firstEnabledMode(EditorFeatureToggles toggles) {
    if (toggles.enableCrop) return EditorMode.ratio;
    if (toggles.enableRotate) return EditorMode.rotate;
    if (toggles.enableFilter) return EditorMode.filter;
    if (toggles.enableText) return EditorMode.text;
    if (toggles.enableSticker) return EditorMode.sticker;
    return EditorMode.ratio;
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
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(widget.appBarStyle.height),
        child: AppBar(
          title: widget.appBarStyle.title,
          actions: [
            IconButton(
              icon: Icon(
                widget.appBarStyle.doneIcon,
                color: widget.appBarStyle.doneIconColor,
              ),
              onPressed: _isSaving ? () {} : _saveImage,
            ),
          ],
          leading: IconButton(
            icon: Icon(
              widget.appBarStyle.closeIcon,
              color: widget.appBarStyle.closeIconColor,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          centerTitle: widget.appBarStyle.centerTitle,
          elevation: widget.appBarStyle.elevation,
          backgroundColor: widget.appBarStyle.backgroundColor,
          shadowColor: widget.appBarStyle.shadowColor,
          surfaceTintColor: widget.appBarStyle.surfaceTintColor,
          iconTheme: widget.appBarStyle.iconTheme,
          toolbarHeight: widget.appBarStyle.height,
          titleSpacing: widget.appBarStyle.titleSpacing,
          systemOverlayStyle: widget.appBarStyle.systemOverlayStyle,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              top: false,
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
                                editorStyle: widget.editorStyle,
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
          ),
          _buildBottomPanel(),
        ],
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
          if (_mode == EditorMode.ratio &&
              widget.featureToggles.enableCrop) ...[
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
          ] else if (_mode == EditorMode.rotate &&
              widget.featureToggles.enableRotate) ...[
            _buildRotationDialArea(),
          ] else if (_mode == EditorMode.filter &&
              widget.featureToggles.enableFilter) ...[
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.featureToggles.enableCrop)
                  _buildTabItem(
                    Icons.crop,
                    "Crop",
                    _mode == EditorMode.ratio,
                    () => setState(() {
                      _mode = EditorMode.ratio;
                      _selectedOverlayId = null;
                    }),
                    selectedColor:
                        widget.editorStyle.bottomNavSelectedItemColor,
                    unselectedColor:
                        widget.editorStyle.bottomNavUnSelectedItemColor,
                  ),
                if (widget.featureToggles.enableRotate)
                  _buildTabItem(
                    Icons.rotate_90_degrees_ccw_outlined,
                    "Rotate",
                    _mode == EditorMode.rotate,
                    () => setState(() {
                      _mode = EditorMode.rotate;
                      _selectedOverlayId = null;
                    }),
                    selectedColor:
                        widget.editorStyle.bottomNavSelectedItemColor,
                    unselectedColor:
                        widget.editorStyle.bottomNavUnSelectedItemColor,
                  ),
                if (widget.featureToggles.enableFilter)
                  _buildTabItem(
                    Icons.filter_vintage_outlined,
                    "Filter",
                    _mode == EditorMode.filter,
                    () => setState(() {
                      _mode = EditorMode.filter;
                      _selectedOverlayId = null;
                    }),
                    selectedColor:
                        widget.editorStyle.bottomNavSelectedItemColor,
                    unselectedColor:
                        widget.editorStyle.bottomNavUnSelectedItemColor,
                  ),
                if (widget.featureToggles.enableText)
                  _buildTabItem(
                    Icons.text_fields,
                    "Text",
                    _mode == EditorMode.text,
                    _addText,
                    selectedColor:
                        widget.editorStyle.bottomNavSelectedItemColor,
                    unselectedColor:
                        widget.editorStyle.bottomNavUnSelectedItemColor,
                  ),
                if (widget.featureToggles.enableSticker)
                  _buildTabItem(
                    Icons.emoji_emotions_outlined,
                    "Sticker",
                    _mode == EditorMode.sticker,
                    _addSticker,
                    selectedColor:
                        widget.editorStyle.bottomNavSelectedItemColor,
                    unselectedColor:
                        widget.editorStyle.bottomNavUnSelectedItemColor,
                  ),
                if (widget.featureToggles.enableFlip)
                  _buildTabItem(Icons.flip, "Flip", false, () {
                    setState(() {
                      _state.flipX = !_state.flipX;
                      _state.hasChanges = true;
                    });
                  }),
                if (widget.featureToggles.enableReset)
                  _buildTabItem(
                    Icons.refresh,
                    "Reset",
                    false,
                    _reset,
                    selectedColor:
                        widget.editorStyle.bottomNavSelectedItemColor,
                    unselectedColor:
                        widget.editorStyle.bottomNavUnSelectedItemColor,
                  ),
                if (widget.featureToggles.enableDelete)
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabItem(
    IconData icon,
    String label,
    bool selected,
    VoidCallback onTap, {
    Color? color,
    Color? selectedColor,
    Color? unselectedColor,
  }) {
    final activeColor =
        selectedColor ?? widget.editorStyle.bottomNavSelectedItemColor;
    final inactiveColor =
        unselectedColor ??
        (color ?? widget.editorStyle.bottomNavUnSelectedItemColor);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: selected ? activeColor : inactiveColor, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: selected ? activeColor : inactiveColor,
                fontSize: 10,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
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
          style: TextStyle(
            color: widget.editorStyle.bottomNavSelectedItemColor,
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
            indicatorColor: widget.editorStyle.bottomNavSelectedItemColor,
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
                    ? Border.all(
                        color: widget.editorStyle.bottomNavSelectedItemColor,
                        width: 2,
                      )
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
                color: isSelected
                    ? widget.editorStyle.bottomNavSelectedItemColor
                    : Colors.white70,
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
                ? widget.editorStyle.bottomNavSelectedItemColor.withValues(
                    alpha: 0.1,
                  )
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? widget.editorStyle.bottomNavSelectedItemColor
                  : Colors.white24,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected
                  ? widget.editorStyle.bottomNavSelectedItemColor
                  : Colors.white70,
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
            decoration: InputDecoration(
              hintText: "Enter text...",
              hintStyle: TextStyle(color: Colors.white54),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                  color: widget.editorStyle.bottomNavSelectedItemColor,
                ),
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
              child: Text(
                "Add",
                style: TextStyle(
                  color: widget.editorStyle.bottomNavSelectedItemColor,
                ),
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

  // Helper: check if the active filter is the identity (no-op)
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

      // Final crop area in original image pixels (using rotated dimensions)
      final int cropX = (rect.left * scaleX).round();
      final int cropY = (rect.top * scaleY).round();
      final int cropWidth = (rect.width * scaleX).round();
      final int cropHeight = (rect.height * scaleY).round();

      final double fineRot = _state.fineRotation;
      final bool hasFineRotation = fineRot.abs() > 0.001;
      final bool hasOverlays = _overlays.isNotEmpty;
      final bool hasFilter = !_isIdentityFilter(_activeFilter);

      if (!hasFineRotation) {
        // FAST PATH: Native crop can perfectly handle base rotation and flip.
        final int rotationDegrees = _state.rotation * 90;
        final String? croppedPath = await widget.cropNative(
          widget.file.path,
          cropX,
          cropY,
          cropWidth,
          cropHeight,
          rotationDegrees,
          _state.flipX,
        );

        if (croppedPath == null) throw Exception("Native crop failed");

        if (!hasFilter && !hasOverlays) {
          final File nativeResult = File(croppedPath);
          if (mounted) widget.onImageSaved(nativeResult);
          return;
        }

        // We have filters or overlays, but native crop handled the geometry safely.
        final File croppedFile = File(croppedPath);
        final Uint8List croppedBytes = await croppedFile.readAsBytes();
        final ui.Image croppedImage = await decodeImageFromList(croppedBytes);

        final ui.PictureRecorder recorder = ui.PictureRecorder();
        final Canvas canvas = Canvas(recorder);

        final Paint paint = Paint()..colorFilter = _activeFilter.colorFilter;
        canvas.drawImage(croppedImage, Offset.zero, paint);

        if (hasOverlays) {
          canvas.save();
          canvas.translate(-cropX.toDouble(), -cropY.toDouble());
          final double overlayScale = realImgW / base.width;
          for (var item in _overlays) {
            if (item is TextOverlay) {
              _drawTextOverlay(canvas, item, overlayScale);
            } else if (item is StickerOverlay) {
              _drawStickerOverlay(canvas, item, overlayScale);
            }
          }
          canvas.restore();
        }

        final ui.Picture pictureFinal = recorder.endRecording();
        final ui.Image imgFinal = await pictureFinal.toImage(
          cropWidth,
          cropHeight,
        );
        croppedImage.dispose();

        final ByteData? pngBytes = await imgFinal.toByteData(
          format: ui.ImageByteFormat.png,
        );
        imgFinal.dispose();

        if (pngBytes == null) throw Exception("Encode failed");
        final tempDir = await _resolveTempDir();
        final pngFile = File(
          '${tempDir.path}/edited_tmp_${DateTime.now().millisecondsSinceEpoch}.png',
        );
        await pngFile.writeAsBytes(pngBytes.buffer.asUint8List());

        // On Android, native re-compress can drop overlay content in some builds.
        // If overlays are present, keep the Flutter-rendered PNG to preserve them.
        if (Platform.isAndroid && hasOverlays) {
          if (mounted) widget.onImageSaved(pngFile);
          return;
        }

        // Re-compress the PNG through the native layer to produce a JPEG at the target quality
        final String? finalPath = await widget.cropNative(
          pngFile.path,
          0,
          0,
          cropWidth,
          cropHeight,
          0, // no rotation
          false, // no flip
        );
        pngFile.deleteSync(recursive: false);
        final File savedFile = finalPath != null ? File(finalPath) : pngFile;
        if (mounted) widget.onImageSaved(savedFile);
        return;
      }

      // SLOW PATH: We have fine rotation, we CANNOT crop FIRST! We must render the whole image.
      final bytes = await widget.file.readAsBytes();
      final ui.Image fullImage = await decodeImageFromList(bytes);

      final recorderFull = ui.PictureRecorder();
      final canvasFull = Canvas(recorderFull);
      final Paint paint = Paint()..colorFilter = _activeFilter.colorFilter;

      canvasFull.save();

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

      canvasFull.translate(realImgW / 2, realImgH / 2);
      canvasFull.rotate(fineRot);
      canvasFull.translate(-realImgW / 2, -realImgH / 2);

      if (_state.flipX) {
        canvasFull.translate(realImgW, 0);
        canvasFull.scale(-1, 1);
      }

      canvasFull.drawImage(fullImage, Offset.zero, paint);
      canvasFull.restore();
      fullImage.dispose();

      if (hasOverlays) {
        final double overlayScale = realImgW / base.width;
        for (var item in _overlays) {
          if (item is TextOverlay) {
            _drawTextOverlay(canvasFull, item, overlayScale);
          } else if (item is StickerOverlay) {
            _drawStickerOverlay(canvasFull, item, overlayScale);
          }
        }
      }

      final pictureFull = recorderFull.endRecording();

      final ui.PictureRecorder recorderFinal = ui.PictureRecorder();
      final Canvas canvasFinal = Canvas(recorderFinal);
      canvasFinal.translate(-cropX.toDouble(), -cropY.toDouble());
      canvasFinal.drawPicture(pictureFull);

      final ui.Picture pictureFinal = recorderFinal.endRecording();
      final ui.Image imgFinal = await pictureFinal.toImage(
        cropWidth,
        cropHeight,
      );

      final ByteData? pngBytes = await imgFinal.toByteData(
        format: ui.ImageByteFormat.png,
      );
      imgFinal.dispose();

      if (pngBytes == null) throw Exception("Encode failed");
      final tempDir = await _resolveTempDir();
      final pngFile = File(
        '${tempDir.path}/edited_tmp_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await pngFile.writeAsBytes(pngBytes.buffer.asUint8List());

      // On Android, native re-compress can drop overlay content in some builds.
      // If overlays are present, keep the Flutter-rendered PNG to preserve them.
      if (Platform.isAndroid && hasOverlays) {
        if (mounted) widget.onImageSaved(pngFile);
        return;
      }

      // Re-compress the PNG through the native layer to produce a JPEG at the target quality
      final String? finalPath = await widget.cropNative(
        pngFile.path,
        0,
        0,
        cropWidth,
        cropHeight,
        0, // no rotation
        false, // no flip
      );
      pngFile.deleteSync(recursive: false);
      final File savedFile = finalPath != null ? File(finalPath) : pngFile;
      if (mounted) {
        widget.onImageSaved(savedFile);
      }
    } catch (e) {
      debugPrint("Save Error: $e");
      setState(() => _isSaving = false);
    }
  }

  // Called with canvas already translated to overlay center and rotated.
  // scaleFactor = realImgW / base.width (widget→image-pixel conversion).
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

  // Called with canvas already translated to overlay center and rotated.
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

  Future<Directory> _resolveTempDir() async {
    try {
      return await getTemporaryDirectory();
    } on MissingPluginException {
      return Directory.systemTemp;
    } on PlatformException {
      return Directory.systemTemp;
    }
  }
}
