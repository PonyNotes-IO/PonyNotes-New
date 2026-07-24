import 'package:appflowy/shared/text_field/text_filed_with_metric_lines.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('fires one full-selection callback for a double tap', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Document title');
    var doubleTapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextFieldWithMetricLines(
            controller: controller,
            onDoubleTap: () {
              doubleTapCount++;
              controller.selection = TextSelection(
                baseOffset: 0,
                extentOffset: controller.text.length,
              );
            },
          ),
        ),
      ),
    );

    final field = find.byType(TextField);
    await tester.tap(field);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(field);
    await tester.pump();

    expect(doubleTapCount, 1);
    expect(
      controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 14),
    );

    // A third click starts a new sequence; it must not be treated as another
    // double-click or require a third click for the original selection.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(field);
    await tester.pump();
    expect(doubleTapCount, 1);

    controller.dispose();
  });
}
