import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/features/agent/application/agent_conversations.dart';
import 'package:appflowy/features/agent/presentation/agent_conversation_sidebar.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'scopes group separately and both create buttons keep their scope',
      (tester) async {
    final created = <AgentConversationVisibility>[];
    String? selected;
    await tester.pumpWidget(
      AppFlowyTheme(
        data: AppFlowyDefaultTheme().light(),
        child: MaterialApp(
          home: AgentConversationSidebar(
            entries: const [
              AgentConversation(id: 'private', title: '自己的讨论'),
              AgentConversation(
                id: 'shared',
                title: '空间共同讨论',
                visibility: AgentConversationVisibility.shared,
                creatorName: '小马',
              ),
            ],
            selectedId: 'shared',
            loading: false,
            enabled: true,
            error: null,
            onOpen: (entry) => selected = entry.id,
            onCreate: created.add,
            onRefresh: () {},
            footer: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    expect(find.text('创建者：小马'), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble_outline), findsNWidgets(2));
    await tester.tap(find.text('私有对话'));
    await tester.pumpAndSettle();
    expect(find.text('自己的讨论'), findsNothing);
    expect(find.text('空间共同讨论'), findsOneWidget);
    await tester.tap(find.text('空间共同讨论'));
    expect(selected, 'shared');
    await tester.tap(find.byTooltip('新建协作对话'));
    await tester.tap(find.byTooltip('新建对话'));
    expect(created, [
      AgentConversationVisibility.shared,
      AgentConversationVisibility.private,
    ]);
  });
  setUpAll(() async {
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (await font.exists()) {
      await (FontLoader('SidebarTestFont')
            ..addFont(font.readAsBytes().then(ByteData.sublistView)))
          .load();
    }
  });

  for (final variant in [
    (name: 'reference-dark', size: const Size(188, 674), dark: true),
    (name: 'desktop-light', size: const Size(208, 674), dark: false),
    (name: 'drawer-light', size: const Size(280, 640), dark: false),
    (name: 'short-dark', size: const Size(208, 240), dark: true),
  ]) {
    testWidgets('sidebar groups and actions work on ${variant.name}',
        (tester) async {
      tester.view.physicalSize = variant.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final capture = GlobalKey();
      const entries = [
        AgentConversation(id: 'first', title: 'OP考研笔记本'),
        AgentConversation(id: 'second', title: 'OP考研笔记本'),
        AgentConversation(id: 'third', title: '每日读书笔记本'),
        AgentConversation(
          id: 'long',
          title: '这是一段很长的对话标题，需要在狭窄的中间栏中省略显示',
        ),
      ];
      var selected = 'first';
      var created = 0;
      var refreshed = 0;
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: AppFlowyTheme(
            data: variant.dark
                ? AppFlowyDefaultTheme().dark()
                : AppFlowyDefaultTheme().light(),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                brightness: variant.dark ? Brightness.dark : Brightness.light,
                fontFamily: 'SidebarTestFont',
              ),
              home: StatefulBuilder(
                builder: (_, setState) => AgentConversationSidebar(
                  entries: entries,
                  selectedId: selected,
                  loading: false,
                  enabled: true,
                  error: null,
                  onOpen: (entry) => setState(() => selected = entry.id),
                  onCreate: (_) => created++,
                  onRefresh: () => refreshed++,
                  footer: const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final output =
          Platform.environment['PONYNOTES_AGENT_SIDEBAR_SCREENSHOTS'];
      if (output != null) {
        await tester.runAsync(() async {
          final image = await (capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File('$output/sidebar-${variant.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.tap(find.text('私有对话'));
      await tester.pumpAndSettle();
      expect(find.text('每日读书笔记本'), findsNothing);
      expect(find.text('暂无协作对话'), findsOneWidget);
      await tester.tap(find.text('协作对话'));
      await tester.pumpAndSettle();
      expect(find.text('暂无协作对话'), findsNothing);
      await tester.tap(find.text('私有对话'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('每日读书笔记本'));
      await tester.pumpAndSettle();
      expect(selected, 'third');
      await tester.tap(find.byTooltip('对话选项').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('复制标题'));
      await tester.pumpAndSettle();
      expect(copied, 'OP考研笔记本');
      expect(selected, 'third');
      await tester.tap(find.text('私有对话'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('新建对话'));
      await tester.pumpAndSettle();
      expect(find.text('每日读书笔记本'), findsOneWidget);
      await tester.tap(find.byTooltip('刷新会话'));
      expect(created, 1);
      expect(refreshed, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty and loading sidebars keep group and footer access',
      (tester) async {
    var loading = false;
    late StateSetter update;
    await tester.pumpWidget(
      AppFlowyTheme(
        data: AppFlowyDefaultTheme().light(),
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return AgentConversationSidebar(
                entries: const [],
                selectedId: null,
                loading: loading,
                enabled: !loading,
                error: null,
                onOpen: (_) {},
                onCreate: (_) {},
                onRefresh: () {},
                footer: const Text('全部产物'),
              );
            },
          ),
        ),
      ),
    );
    expect(find.textContaining('还没有对话'), findsOneWidget);
    expect(find.text('暂无协作对话'), findsOneWidget);
    update(() => loading = true);
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('还没有对话'), findsNothing);
    for (final icon in [Icons.add, Icons.refresh]) {
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, icon).first)
            .onPressed,
        isNull,
      );
    }
    expect(find.text('全部产物'), findsOneWidget);
  });
}
