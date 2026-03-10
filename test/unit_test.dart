import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_crop_camera/src/shared_crop_widgets.dart';
import 'package:flutter_crop_camera/src/filters.dart';
import 'package:flutter_crop_camera/src/overlays.dart';

void main() {
  group('CropEditorState Tests', () {
    late CropEditorState state;

    setUp(() {
      state = CropEditorState();
    });

    test('initial state is correct', () {
      expect(state.rotation, 0);
      expect(state.fineRotation, 0.0);
      expect(state.flipX, false);
      expect(state.aspectRatio, isNull);
      expect(state.showGrid, true);
      expect(state.hasChanges, false);
      expect(state.activeFilter.name, 'Normal');
      expect(state.overlays, isEmpty);
      expect(state.selectedOverlayId, isNull);
      expect(state.baseSize, Size.zero);
      expect(state.cropRect, Rect.zero);
    });

    test('reset() clears state correctly', () {
      state.rotation = 1;
      state.fineRotation = 0.5;
      state.flipX = true;
      state.aspectRatio = 1.0;
      state.hasChanges = true;
      state.activeFilter = PresetFilters.list[1];
      state.overlays.add(TextOverlay(id: '1', text: 'test'));
      state.selectedOverlayId = '1';
      state.cropRect = const Rect.fromLTWH(0, 0, 100, 100);

      state.reset();

      expect(state.rotation, 0);
      expect(state.fineRotation, 0.0);
      expect(state.flipX, false);
      expect(state.aspectRatio, isNull);
      expect(state.hasChanges, false);
      expect(state.activeFilter.name, 'Normal');
      expect(state.overlays, isEmpty);
      expect(state.selectedOverlayId, isNull);
      expect(state.cropRect, Rect.zero);
    });

    test('hasChanges update', () {
      expect(state.hasChanges, false);
      state.hasChanges = true;
      expect(state.hasChanges, true);
    });
  });

  group('Filter Tests', () {
    test('PresetFilters contains expected filters', () {
      final filters = PresetFilters.list;
      expect(filters.any((f) => f.name == 'Normal'), true);
      expect(filters.any((f) => f.name == 'B&W'), true);
      expect(filters.any((f) => f.name == 'Sepia'), true);
    });

    test('Filter colorFilter is non-null', () {
      for (var filter in PresetFilters.list) {
        expect(filter.colorFilter, isNotNull);
      }
    });
  });

  group('Overlay Tests', () {
    test('TextOverlay initialization', () {
      final overlay = TextOverlay(
        id: 'test_id',
        text: 'Hello',
        position: const Offset(10, 20),
        scale: 2.0,
        rotation: 0.5,
      );

      expect(overlay.id, 'test_id');
      expect(overlay.text, 'Hello');
      expect(overlay.position, const Offset(10, 20));
      expect(overlay.scale, 2.0);
      expect(overlay.rotation, 0.5);
    });
  });
}
