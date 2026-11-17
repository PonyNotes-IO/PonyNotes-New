import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:appflowy/features/agent/application/agent_controller.dart';
import 'package:appflowy/features/agent/application/agent_reference.dart';
import 'package:appflowy/features/agent/presentation/agent_reference_field.dart';
import 'package:appflowy/features/agent/presentation/agent_reference_preview.dart';
import 'package:appflowy/features/agent/presentation/agent_composer.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const references = [
  AgentReference(kind: 'base', id: 'kb', name: '产品知识库', subtitle: '私有知识库'),
  AgentReference(kind: 'base', id: 'shared', name: '团队资料', subtitle: '共享知识库'),
  AgentReference(kind: 'file', id: 'file', name: '需求说明.pdf', subtitle: '团队资料'),
  AgentReference(
    kind: 'note',
    id: 'note',
    name: '项目会议记录',
    subtitle: '协作空间 / 项目',
  ),
];

void main() {
  setUpAll(() async {
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (await font.exists()) {
      await (FontLoader('ReferenceTestFont')
            ..addFont(font.readAsBytes().then(ByteData.sublistView)))
          .load();
    }
  });

  for (final variant in [
    (name: 'desktop', size: const Size(1100, 800), dark: false),
    (name: 'reference-dark', size: const Size(925, 630), dark: true),
    (name: 'phone-dark', size: const Size(390, 844), dark: true),
    (name: 'compact', size: const Size(320, 640), dark: false),
  ]) {
    testWidgets(
        'typed references select, deduplicate and delete on ${variant.name}',
        (tester) async {
      tester.view.physicalSize = variant.size;
      tester.view.devicePixelRatio = 1;
      final shadowsDisabled = debugDisableShadows;
      debugDisableShadows = false;
      addTearDown(() => debugDisableShadows = shadowsDisabled);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var selected = <AgentReference>[];
      var submitted = 0;
      var smart = true;
      final capture = GlobalKey();
      Future<void> screenshot(String state) async {
        final output = Platform.environment['PONYNOTES_REFERENCE_SCREENSHOTS'];
        if (output == null) return;
        await tester.pump();
        await tester.runAsync(() async {
          final image = await (capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File('$output/$state-${variant.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: variant.dark ? Brightness.dark : Brightness.light,
              fontFamily: 'ReferenceTestFont',
            ),
            builder: (_, child) => AppFlowyTheme(
              data: variant.dark
                  ? AppFlowyDefaultTheme().dark()
                  : AppFlowyDefaultTheme().light(),
              child: child!,
            ),
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: StatefulBuilder(
                    builder: (_, setState) => ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 740),
                      child: AgentReferenceField(
                        controller: controller,
                        selected: selected,
                        smartMode: smart,
                        onModeChanged: (value) => setState(() => smart = value),
                        load: () async => references,
                        onChanged: (items) => setState(() => selected = items),
                        builder: (field, button) => AgentComposer(
                          compact: true,
                          input: field,
                          leading: [button],
                          modelSelector: const SizedBox.shrink(),
                          actions: const [],
                        ),
                        child: TextField(
                          controller: controller,
                          onSubmitted: (_) => submitted++,
                          decoration: const InputDecoration(
                            hintText: '提问或输入 @ 引用资料',
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final input = find.byType(TextField).first;
      await tester.enterText(input, '请分析 @');
      await tester.pumpAndSettle();
      expect(find.text('当前模式'), findsOneWidget);
      await screenshot('mention-modes');
      final panel =
          tester.getRect(find.byKey(const ValueKey('agent-mention-panel')));
      expect(panel.left, greaterThanOrEqualTo(0));
      expect(panel.right, lessThanOrEqualTo(variant.size.width));
      expect(panel.top, greaterThanOrEqualTo(0));
      expect(panel.bottom, lessThanOrEqualTo(variant.size.height));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(find.text('点击切换'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(smart, false);
      expect(controller.text, '请分析 ');
      expect(submitted, 0);
      await tester.enterText(input, '请分析 @');
      await tester.pumpAndSettle();
      expect(find.text('知识库'), findsOneWidget);
      expect(find.text('文件'), findsOneWidget);
      expect(find.text('笔记'), findsOneWidget);
      await tester.tap(find.text('文件'));
      await tester.pumpAndSettle();
      expect(find.text('需求说明.pdf'), findsOneWidget);
      await screenshot('reference-picker');
      await tester.tap(find.text('需求说明.pdf'));
      await tester.pumpAndSettle();
      expect(selected.single.id, 'file');
      expect(controller.text, '请分析 ');
      await tester.tap(find.byTooltip('引用知识库、文件或笔记'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '需求');
      await tester.pumpAndSettle();
      expect(find.text('没有找到匹配的资料'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('没有找到匹配的资料'), findsNothing);
      await tester.enterText(input, '请分析@会议');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selected.map((r) => r.kind), ['file', 'note']);
      expect(submitted, 0);
      final chip = tester.widget<InputChip>(find.byType(InputChip).first);
      chip.onDeleted!();
      await tester.pumpAndSettle();
      expect(selected.single.kind, 'note');
      await tester.enterText(input, 'name@example.com');
      await tester.pumpAndSettle();
      expect(find.byTooltip('关闭引用选择'), findsNothing);
      await tester.enterText(input, '@');
      await tester.pumpAndSettle();
      controller.selection =
          TextSelection(baseOffset: 0, extentOffset: controller.text.length);
      await tester.pumpAndSettle();
      expect(find.byTooltip('关闭引用选择'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDisableShadows = shadowsDisabled;
    });
  }

  testWidgets('reference errors can retry without blocking mode selection',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var attempts = 0;
    bool? mode;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AgentReferenceField(
              controller: controller,
              selected: const [],
              onChanged: (_) {},
              onModeChanged: (value) => mode = value,
              load: () async {
                if (++attempts == 1) throw StateError('offline');
                return references;
              },
              child: TextField(controller: controller),
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, '草稿 @');
    await tester.pumpAndSettle();
    expect(find.text('当前模式'), findsOneWidget);
    await tester.tap(find.text('文件'));
    await tester.pumpAndSettle();
    expect(find.text('引用列表加载失败，请重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('需求说明.pdf'), findsOneWidget);
    expect(attempts, 2);
    await tester.tap(find.text('快问快答'));
    await tester.pumpAndSettle();
    expect(mode, false);
    expect(controller.text, '草稿 ');
    expect(find.byKey(const ValueKey('agent-mention-panel')), findsNothing);
  });

  testWidgets('revocation closes the picker and discards a late response',
      (tester) async {
    final pending = Completer<List<AgentReference>>();
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AgentReferenceField(
              controller: controller,
              selected: const [],
              onChanged: (_) {},
              load: () => pending.future,
              child: TextField(controller: controller),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('引用知识库、文件或笔记'));
    await tester.pump();
    AgentController.accountClearance.value++;
    pending.complete(references);
    await tester.pumpAndSettle();
    expect(find.text('需求说明.pdf'), findsNothing);
    expect(find.byTooltip('关闭引用选择'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reference preview pages parsed content and clears on revocation',
      (tester) async {
    final pages = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentReferencePreview(
            load: (page) async {
              pages.add(page);
              return {
                'title': '需求说明.pdf',
                'chunks': [
                  {'content': '第 $page 页资料正文'},
                ],
                'total': 26,
              };
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('第 1 页资料正文'), findsOneWidget);
    await tester.tap(find.text('下一页'));
    await tester.pumpAndSettle();
    expect(pages, [1, 2]);
    expect(find.textContaining('第 2 页资料正文'), findsOneWidget);
    AgentController.accountClearance.value++;
    await tester.pumpAndSettle();
    expect(find.textContaining('第 2 页资料正文'), findsNothing);
    expect(find.text('账号或工作区已切换，请关闭后重新打开'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
