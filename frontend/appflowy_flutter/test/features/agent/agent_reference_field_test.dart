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
    name: '项目会议记录与跨部门方案评审说明及后续行动清单',
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
      var smart = !variant.dark;
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
      expect(find.text('当前模式'), findsNothing);
      expect(find.text('点击切换'), findsNothing);
      expect(find.text('快问快答'), findsNothing);
      expect(find.text('智能推理'), findsNothing);
      expect(
        find.byKey(const ValueKey('agent-reference-categories')),
        findsOneWidget,
      );
      if (variant.size.width >= 504) {
        expect(find.text(references.last.name), findsOneWidget);
      }
      await screenshot('mention-references');
      final panel =
          tester.getRect(find.byKey(const ValueKey('agent-mention-panel')));
      expect(panel.left, greaterThanOrEqualTo(0));
      expect(panel.right, lessThanOrEqualTo(variant.size.width));
      expect(panel.top, greaterThanOrEqualTo(0));
      expect(panel.bottom, lessThanOrEqualTo(variant.size.height));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(smart, !variant.dark);
      expect(controller.text, '请分析 @');
      expect(submitted, 0);
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
      await tester.enterText(input, '请分析 @产品');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selected.map((r) => r.kind), ['file', 'note', 'base']);
      expect(
        find.byTooltip('${references.last.name}\n${references.last.subtitle}'),
        findsOneWidget,
      );
      expect(
        tester.getBottomLeft(find.byType(InputChip).last).dy,
        lessThan(tester.getTopLeft(input).dy),
      );
      await screenshot('selected-references');
      await tester.tap(find.byTooltip('移除引用：产品知识库'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('移除引用：需求说明.pdf'));
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

  for (final variant in [
    (name: 'reference-dark', size: const Size(870, 471), dark: true),
    (name: 'desktop-light', size: const Size(1100, 800), dark: false),
    (name: 'phone-dark', size: const Size(390, 844), dark: true),
    (name: 'compact-light', size: const Size(320, 480), dark: false),
  ]) {
    testWidgets('note groups search and keyboard selection on ${variant.name}',
        (tester) async {
      final shadowsDisabled = debugDisableShadows;
      debugDisableShadows = false;
      addTearDown(() => debugDisableShadows = shadowsDisabled);
      tester.view.physicalSize = variant.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = TextEditingController(text: '帮我总结小马笔记二期需求');
      addTearDown(controller.dispose);
      final notes = [
        for (final visibility in ['private', 'shared'])
          for (var i = 0; i < 3; i++)
            AgentReference.fromJson({
              'kind': 'note',
              'id': '$visibility-$i',
              'name': ['水土保持方案中AI如何自动匹配适用条款', '未命名白板', '小马笔记bug反馈'][i],
              'subtitle': visibility == 'private'
                  ? '工作区 / 默认的工作空间 / 项目'
                  : '工作区 / 小马笔记 / 协作',
              'visibility': visibility,
              'space_name': visibility == 'private' ? '默认的工作空间' : '小马笔记',
              'knowledge_ids': [],
            }),
      ];
      var selected = <AgentReference>[];
      final capture = GlobalKey();
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
              backgroundColor:
                  variant.dark ? const Color(0xFF191919) : Colors.white,
              body: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 814),
                    child: StatefulBuilder(
                      builder: (_, setState) => AgentReferenceField(
                        controller: controller,
                        selected: selected,
                        onChanged: (items) => setState(() => selected = items),
                        load: () async =>
                            [references.first, references[2], ...notes],
                        builder: (field, button) => AgentComposer(
                          compact: true,
                          input: field,
                          leading: [
                            const Text(
                              '快速问答',
                              style: TextStyle(fontSize: 11),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.attach_file, size: 18),
                            button,
                          ],
                          modelSelector: const Text(
                            '选择模型',
                            style: TextStyle(fontSize: 11),
                          ),
                          actions: const [
                            Icon(Icons.arrow_upward, size: 18),
                          ],
                        ),
                        child: TextField(
                          controller: controller,
                          minLines: 3,
                          maxLines: 3,
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
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
      await tester.tap(find.byTooltip('引用知识库、文件或笔记'));
      await tester.pumpAndSettle();
      expect(find.text('当前模式'), findsNothing);
      expect(
        find.byKey(const ValueKey('agent-reference-category-note')),
        findsOneWidget,
      );
      if (variant.size.width >= 504) {
        expect(find.text('私有笔记'), findsOneWidget);
        expect(find.text('协作笔记'), findsOneWidget);
      }
      await tester
          .tap(find.byKey(const ValueKey('agent-reference-category-note')));
      await tester.pumpAndSettle();
      expect(find.text('私有笔记'), findsOneWidget);
      expect(find.text('协作笔记'), findsOneWidget);
      final panel =
          tester.getRect(find.byKey(const ValueKey('agent-mention-panel')));
      expect(panel.left, greaterThanOrEqualTo(12));
      expect(panel.right, lessThanOrEqualTo(variant.size.width - 12));
      expect(panel.top, greaterThanOrEqualTo(0));
      expect(panel.bottom, lessThanOrEqualTo(variant.size.height));
      final output = Platform.environment['PONYNOTES_NOTE_PICKER_SCREENSHOTS'];
      if (output != null) {
        await tester.runAsync(() async {
          final image = await (capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File('$output/notes-${variant.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      // Collapsed notes must also be excluded from keyboard navigation.
      await tester.tap(find.text('私有笔记'));
      await tester.pumpAndSettle();
      expect(find.text('默认的工作空间'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selected.single.id, 'shared-1');
      expect(controller.text, '帮我总结小马笔记二期需求');
      await tester.tap(find.byTooltip('引用知识库、文件或笔记'));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('agent-reference-category-note')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('默认的工作空间'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reference-note:private-2')),
        findsNothing,
      );
      // Search reveals matching notes even inside collapsed spaces.
      await tester.enterText(
        find.byKey(const ValueKey('agent-reference-search')),
        'bug',
      );
      await tester.pumpAndSettle();
      expect(find.text('小马笔记bug反馈'), findsNWidgets(2));
      expect(find.text('未命名白板'), findsOneWidget); // Previously selected chip.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selected.map((r) => r.id), ['shared-1', 'private-2']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDisableShadows = shadowsDisabled;
    });
  }

  test('note catalog metadata does not infer access from a path', () {
    final item = AgentReference.fromJson({
      'kind': 'note',
      'id': 'legacy',
      'name': '笔记',
      'subtitle': '私有名字的空间 / 项目',
    });
    expect(item.noteSection, '笔记');
    expect(item.noteSpace, '私有名字的空间');
    expect(item.toJson(), {'kind': 'note', 'id': 'legacy'});
  });

  testWidgets('reference errors can retry and reopen in the reference browser',
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
    expect(find.text('当前模式'), findsNothing);
    expect(
      find.byKey(const ValueKey('agent-reference-categories')),
      findsOneWidget,
    );
    await tester.tap(find.text('文件'));
    await tester.pumpAndSettle();
    expect(find.text('引用列表加载失败，请重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('需求说明.pdf'), findsOneWidget);
    expect(attempts, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    controller.clear();
    await tester.enterText(find.byType(TextField).first, '草稿 @');
    await tester.pumpAndSettle();
    expect(find.text(references.last.name), findsOneWidget);
    await tester.tap(find.text(references.last.name));
    await tester.pumpAndSettle();
    expect(mode, isNull);
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
