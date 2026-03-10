import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_crop_camera/src/overlays.dart';

void main() {
  group('OverlayItem Tests', () {
    test('TextOverlay creation and defaults', () {
      final overlay = TextOverlay(id: '1', text: 'Test');
      expect(overlay.id, '1');
      expect(overlay.text, 'Test');
      expect(overlay.position, Offset.zero);
      expect(overlay.scale, 1.0);
      expect(overlay.rotation, 0.0);
      expect(overlay.color, Colors.white);
      expect(overlay.fontSize, 24.0);
    });

    test('StickerOverlay creation and defaults', () {
      final overlay = StickerOverlay(id: '2', text: '😀');
      expect(overlay.id, '2');
      expect(overlay.text, '😀');
      expect(overlay.position, Offset.zero);
      expect(overlay.scale, 1.0);
      expect(overlay.fontSize, 50.0);
    });
  });

  group('DraggableOverlay Widget Tests', () {
    testWidgets('DraggableOverlay renders correctly', (
      WidgetTester tester,
    ) async {
      final overlay = TextOverlay(id: '1', text: 'Hello');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                DraggableOverlay(
                  item: overlay,
                  onDelete: () {},
                  onDragStart: () {},
                  onDragEnd: () {},
                  onUpdate: (_) {},
                  onTap: () {},
                  isSelected: false,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Hello'), findsOneWidget);
      expect(find.byType(DraggableOverlay), findsOneWidget);
    });

    testWidgets('DraggableOverlay shows border and delete icon when selected', (
      WidgetTester tester,
    ) async {
      final overlay = TextOverlay(id: '1', text: 'Hello');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                DraggableOverlay(
                  item: overlay,
                  onDelete: () {},
                  onDragStart: () {},
                  onDragEnd: () {},
                  onUpdate: (_) {},
                  onTap: () {},
                  isSelected: true, // Selected
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.cancel), findsOneWidget);
      // Verify border exists by finding the decorated Container
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(DraggableOverlay),
          matching: find.byType(Container).first,
        ),
      );
      final decoration = container.decoration as BoxDecoration?;
      expect(decoration?.border, isNotNull);
    });
  });
}
