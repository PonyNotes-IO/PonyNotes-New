import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:appflowy/features/agent/application/agent_controller.dart';
import 'package:appflowy/features/agent/presentation/agent_workspace.dart';
import 'package:appflowy/features/agent/presentation/ai_mode_shell.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../widget_test/widget_test_wrapper.dart';

void main() {
  setUpAll(() async {
    final materialIcons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await materialIcons.load();
    final fontFile = File('C:/Windows/Fonts/msyh.ttc');
    if (await fontFile.exists()) {
      final loader = FontLoader('AgentTestFont')
        ..addFont(
          fontFile.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      await loader.load();
    }
  });
  testWidgets(
      'switching modes preserves the Chat draft and disables switching while Chat runs',
      (tester) async {
    await tester.pumpWidget(
      const WidgetTestWrapper(
        child: AiModeShell(
          chatId: 'test',
          chat: Column(children: [AiModeButton(), TextField()]),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '保留我的草稿');
    await tester.tap(find.byType(AiModeButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agent · 执行任务'));
    await tester.pumpAndSettle();
    expect(find.text('把任务交给 Agent'), findsOneWidget);
    await tester.tap(find.byType(AiModeButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chat · 问答'));
    await tester.pumpAndSettle();
    expect(find.text('保留我的草稿'), findsOneWidget);
    await tester.pumpWidget(
      const WidgetTestWrapper(
        child: AiModeShell(
          chatId: 'test',
          chatBusy: true,
          chat: Column(children: [AiModeButton(), TextField()]),
        ),
      ),
    );
    expect(
      tester
          .widget<PopupMenuButton<bool>>(
            find.byType(PopupMenuButton<bool>).first,
          )
          .enabled,
      isFalse,
    );
  });

  for (final variant in [
    (name: 'desktop-light', size: const Size(1360, 900), dark: false),
    (name: 'phone-dark', size: const Size(390, 844), dark: true),
  ]) {
    testWidgets('approval, context and task controls render on ${variant.name}',
        (tester) async {
      tester.view.physicalSize = variant.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = AgentController(chatId: 'visual-test');
      final denied = Completer<bool>();
      controller.connected = true;
      controller.model = 'DeepSeek';
      controller.running = true;
      controller.contextUsage = {'tokens': 1840};
      controller.messages.addAll([
        {'role': 'user', 'content': '找到项目会议记录，整理成一份行动清单。'},
        {
          'role': 'assistant',
          'content': [
            {'type': 'text', 'text': '已找到 3 份会议记录，正在整理负责人和截止时间。'},
          ],
        },
        {
          'role': 'toolResult',
          'toolName': 'notes_search_notes',
          'toolCallId': 'one',
          'content': [
            {'type': 'text', 'text': '找到 3 份会议记录'},
          ],
        },
      ]);
      controller.steps.addAll([
        {'title': '查找会议记录', 'status': 'completed'},
        {'title': '创建行动清单', 'status': 'running'},
      ]);
      controller.interactions.add({
        'id': 'pending',
        'type': 'note_approval',
        'title': 'create_page',
        'arguments': {'name': '项目行动清单', 'parent_id': '项目空间'},
        'confirmation': denied,
      });
      final boundary = GlobalKey();
      final theme = AppFlowyDefaultTheme();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: variant.dark ? Brightness.dark : Brightness.light,
            fontFamily: 'AgentTestFont',
          ),
          home: Material(
            child: AppFlowyTheme(
              data: variant.dark ? theme.dark() : theme.light(),
              child: RepaintBoundary(
                key: boundary,
                child: AgentWorkspace(controller: controller),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
      expect(find.text('允许这次'), findsOneWidget);
      expect(find.text('拒绝'), findsOneWidget);
      expect(find.byTooltip('停止任务'), findsOneWidget);
      final output = Platform.environment['PONYNOTES_AGENT_SCREENSHOTS'];
      if (output != null) {
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File('$output/${variant.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.text('拒绝'));
      await tester.pump();
      expect(await denied.future, false);
      expect(find.text('允许这次'), findsNothing);
      await tester.enterText(find.byType(TextField), '账号退出后不能留下的任务草稿');
      await controller.disconnect();
      await tester.pump();
      expect(find.text('账号退出后不能留下的任务草稿'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
