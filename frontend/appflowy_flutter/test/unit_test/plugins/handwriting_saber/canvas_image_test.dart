import 'dart:typed_data';

import 'package:appflowy/plugins/handwriting_saber/presentation/widgets/canvas_image.dart';
import 'package:appflowy/plugins/handwriting_saber/third_party/saber_core/components/canvas/image/editor_image.dart';
import 'package:defer_pointer/defer_pointer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('image position follows page scale and centering offset',
      (tester) async {
    final image = PngEditorImage(
      id: 'image',
      imageBytes: Uint8List(0),
      extension: '.png',
      pageIndex: 0,
      pageSize: const Size(600, 800),
      dstRect: const Rect.fromLTWH(50, 30, 200, 200),
      newImage: false,
    );

    Future<void> pumpImage(double scale, Offset pageOffset) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeferredPointerHandler(
              child: Stack(
                children: [
                  CanvasImage(
                    image: image,
                    pageSize: image.pageSize,
                    scale: scale,
                    pageOffset: pageOffset,
                    readOnly: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    await pumpImage(0.5, const Offset(100, 20));
    var positioned = tester.widget<Positioned>(find.byType(Positioned).first);
    expect(positioned.left, 125);
    expect(positioned.top, 35);

    await pumpImage(1, Offset.zero);
    positioned = tester.widget<Positioned>(find.byType(Positioned).first);
    expect(positioned.left, 50);
    expect(positioned.top, 30);
  });

  testWidgets('image options sheet fits its action buttons', (tester) async {
    final image = PngEditorImage(
      id: 'image',
      imageBytes: Uint8List(0),
      extension: '.png',
      pageIndex: 0,
      pageSize: const Size(600, 800),
      dstRect: const Rect.fromLTWH(50, 30, 200, 200),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeferredPointerHandler(
            child: Stack(
              children: [
                CanvasImage(
                  image: image,
                  pageSize: image.pageSize,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final optionsGesture = find.descendant(
      of: find.byType(CanvasImage),
      matching: find.byWidgetPredicate(
        (widget) => widget is GestureDetector && widget.onLongPress != null,
      ),
    );
    await tester.longPress(optionsGesture);
    await tester.pumpAndSettle();

    expect(find.text('删除'), findsOneWidget);
    expect(find.text('旋转90°'), findsOneWidget);
    expect(find.text('重置旋转'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
