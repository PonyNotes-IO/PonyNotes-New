import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/features/agent/application/agent_controller.dart';
import 'package:appflowy/features/agent/presentation/agent_mode_details.dart';
import 'package:appflowy/features/agent/presentation/ai_mode_button.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (await font.exists()) {
      await (FontLoader('AgentPickerTestFont')
            ..addFont(font.readAsBytes().then(ByteData.sublistView)))
          .load();
    }
  });

  for (final variant in [
    (name: 'reference-dark', size: const Size(944, 644), dark: true),
    (name: 'desktop-light', size: const Size(1360, 900), dark: false),
    (name: 'phone-dark', size: const Size(390, 844), dark: true),
    (name: 'compact-light', size: const Size(320, 480), dark: false),
  ]) {
    testWidgets('preview and select an agent on ${variant.name}',
        (tester) async {
      tester.view.physicalSize = variant.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final capture = GlobalKey();
      var smart = true;
      var changes = 0;
      var settings = 0;
      final shadowsDisabled = debugDisableShadows;
      debugDisableShadows = false;
      addTearDown(() => debugDisableShadows = shadowsDisabled);
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: variant.dark ? Brightness.dark : Brightness.light,
              fontFamily: 'AgentPickerTestFont',
            ),
            builder: (_, child) => AppFlowyTheme(
              data: variant.dark
                  ? AppFlowyDefaultTheme().dark()
                  : AppFlowyDefaultTheme().light(),
              child: child!,
            ),
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 44, 32),
                  child: Container(
                    width: 524,
                    height: 120,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.deepOrange),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.bottomLeft,
                    child: StatefulBuilder(
                      builder: (_, setState) => AiModeButton(
                        agentMode: smart,
                        onSelected: (value) => setState(() {
                          smart = value;
                          changes++;
                        }),
                        onSettings: () => settings++,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(AiModeButton));
      await tester.pumpAndSettle();
      expect(find.text('内置智能体'), findsOneWidget);
      expect(find.text('当前模式'), findsOneWidget);
      expect(
        tester.widget<AgentModeDetails>(find.byType(AgentModeDetails)).smart,
        isTrue,
      );
      final panel =
          tester.getRect(find.byKey(const ValueKey('agent-mode-panel')));
      expect(panel.left, greaterThanOrEqualTo(0));
      expect(panel.right, lessThanOrEqualTo(variant.size.width));
      expect(panel.top, greaterThanOrEqualTo(0));
      expect(panel.bottom, lessThanOrEqualTo(variant.size.height));

      final output = Platform.environment['PONYNOTES_AGENT_PICKER_SCREENSHOTS'];
      if (output != null) {
        await tester.runAsync(() async {
          final image = await (capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File('$output/agent-picker-${variant.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      final quick = find.byKey(const ValueKey('agent-mode-quick'));
      await mouse.moveTo(tester.getCenter(quick));
      await tester.pumpAndSettle();
      expect(
        tester.widget<AgentModeDetails>(find.byType(AgentModeDetails)).smart,
        isFalse,
      );
      expect(smart, isTrue);
      expect(changes, 0);
      await tester.tap(quick);
      await tester.pumpAndSettle();
      expect(smart, isFalse);
      expect(changes, 1);
      expect(find.byKey(const ValueKey('agent-mode-panel')), findsNothing);

      await mouse.moveTo(Offset.zero);
      await tester.tap(find.byType(AiModeButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('对话设置'));
      await tester.pumpAndSettle();
      expect(settings, 1);
      expect(find.byKey(const ValueKey('agent-mode-panel')), findsNothing);
      expect(tester.takeException(), isNull);
      debugDisableShadows = shadowsDisabled;
    });
  }

  testWidgets('keyboard selection, dismiss and account clearance',
      (tester) async {
    var smart = true;
    var enabled = true;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return AiModeButton(
                agentMode: smart,
                enabled: enabled,
                onSelected: (value) => setState(() => smart = value),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byType(AiModeButton));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(smart, isFalse);
    expect(find.byKey(const ValueKey('agent-mode-panel')), findsNothing);
    await tester.tap(find.byType(AiModeButton));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('agent-mode-panel')), findsNothing);
    await tester.tap(find.byType(AiModeButton));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(700, 500));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('agent-mode-panel')), findsNothing);
    await tester.tap(find.byType(AiModeButton));
    await tester.pumpAndSettle();
    AgentController.accountClearance.value++;
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('agent-mode-panel')), findsNothing);
    await tester.tap(find.byType(AiModeButton));
    await tester.pumpAndSettle();
    update(() => enabled = false);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('agent-mode-panel')), findsNothing);
    await tester.tap(find.byType(AiModeButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('agent-mode-panel')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
