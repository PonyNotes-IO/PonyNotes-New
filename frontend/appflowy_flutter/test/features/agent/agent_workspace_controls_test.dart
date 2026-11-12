import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/features/agent/application/agent_controller.dart';
import 'package:appflowy/features/agent/presentation/agent_workspace_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Controller extends AgentController {
  _Controller() : super(chatId: 'approval-controls');

  @override
  Future<void> configurePermissions({
    String? mode,
    Set<String>? disabled,
  }) async {
    permissions.mode = mode!;
    changed();
  }
}

void main() {
  setUpAll(() async {
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (await font.exists()) {
      await (FontLoader('AgentTestFont')
            ..addFont(font.readAsBytes().then(ByteData.sublistView)))
          .load();
    }
  });

  for (final size in [const Size(1000, 700), const Size(390, 844)]) {
    testWidgets('approval selector chooses all modes at width ${size.width}',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _Controller()..connected = true;
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'AgentTestFont'),
            home: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: ListenableBuilder(
                    listenable: controller,
                    builder: (_, __) =>
                        AgentWorkspaceControls(agent: controller),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('审批模式：请求批准'), findsOneWidget);
      await tester.tap(find.byKey(const Key('agent-approval-mode')));
      await tester.pumpAndSettle();
      expect(find.text('请求批准'), findsOneWidget);
      expect(find.text('自动审批'), findsOneWidget);
      expect(find.text('完全放行'), findsOneWidget);
      expect(find.text('自动批准普通修改，删除等破坏性操作仍需确认'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final output = Platform.environment['PONYNOTES_AGENT_SCREENSHOTS'];
      if (output != null) {
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File('$output/approval-menu-${size.width.toInt()}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<String>, '自动审批'),
      );
      await tester.pumpAndSettle();
      expect(controller.permissions.mode, 'auto');
      expect(find.text('审批模式：自动审批'), findsOneWidget);
      await tester.tap(find.byKey(const Key('agent-approval-mode')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<String>, '完全放行'),
      );
      await tester.pumpAndSettle();
      expect(find.text('开启完全放行？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(controller.permissions.mode, 'auto');
      await tester.tap(find.byKey(const Key('agent-approval-mode')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<String>, '完全放行'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('完全放行'));
      await tester.pumpAndSettle();
      expect(controller.permissions.mode, 'full');
      await tester.tap(find.byKey(const Key('agent-approval-mode')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<String>, '请求批准'),
      );
      await tester.pumpAndSettle();
      expect(controller.permissions.mode, 'ask');
      controller.running = true;
      controller.changed();
      await tester.pump();
      expect(
        tester
            .widget<PopupMenuButton<String>>(
              find.byKey(const Key('agent-approval-mode')),
            )
            .enabled,
        false,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await tester.pump();
    });
  }
}
