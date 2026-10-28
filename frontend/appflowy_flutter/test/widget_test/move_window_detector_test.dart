import 'dart:io';

import 'package:appflowy/core/frameless_window.dart';
import 'package:appflowy/startup/tasks/device_info_task.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  final calls = <MethodCall>[];
  int? previousMacOSVersion;

  setUp(() {
    previousMacOSVersion = ApplicationInfo.macOSMajorVersion;
    ApplicationInfo.macOSMajorVersion = 15;
    calls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    ApplicationInfo.macOSMajorVersion = previousMacOSVersion;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets(
    '标题空白区域仍能启动原生窗口拖动',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MoveWindowDetector(child: SizedBox.expand()),
        ),
      );

      await tester.drag(find.byType(MoveWindowDetector), const Offset(80, 20));
      await tester.pumpAndSettle();

      expect(calls.map((call) => call.method), ['startDragging']);
    },
    skip: !Platform.isMacOS,
  );

  testWidgets(
    '滑块拖动只修改数值',
    (tester) async {
      var value = 5.0;
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: MoveWindowDetector(
              child: Center(
                child: SizedBox(
                  width: 200,
                  child: StatefulBuilder(
                    builder: (context, setState) => Slider(
                      value: value,
                      min: 1,
                      max: 20,
                      onChanged: (next) => setState(() => value = next),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.dragFrom(
        tester.getTopLeft(find.byType(Slider)) + const Offset(56, 24),
        const Offset(80, 0),
      );
      await tester.pumpAndSettle();

      expect(value, greaterThan(5));
      expect(calls, isEmpty);
    },
    skip: !Platform.isMacOS,
  );

  testWidgets(
    '文档拖动手势优先于窗口拖动',
    (tester) async {
      var documentDragStarted = false;
      await tester.pumpWidget(
        MaterialApp(
          home: MoveWindowDetector(
            child: Center(
              child: Draggable<String>(
                data: 'document',
                feedback: const Text('文档'),
                onDragStarted: () => documentDragStarted = true,
                child: const SizedBox(
                  width: 200,
                  height: 40,
                  child: Text('顶部文档'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.drag(find.byType(Draggable<String>), const Offset(0, 80));
      await tester.pumpAndSettle();

      expect(documentDragStarted, isTrue);
      expect(calls, isEmpty);
    },
    skip: !Platform.isMacOS,
  );
}
