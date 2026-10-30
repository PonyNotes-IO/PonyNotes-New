import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:appflowy/plugins/knowledge_graph/application/knowledge_graph_cubit.dart';
import 'package:appflowy/plugins/knowledge_graph/application/knowledge_graph_data.dart';
import 'package:appflowy/plugins/knowledge_graph/presentation/knowledge_graph_canvas.dart';
import 'package:appflowy/plugins/knowledge_graph/presentation/knowledge_graph_page.dart';
import 'package:appflowy/workspace/presentation/home/full_window_controller.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previewPath = Platform.environment['GRAPH_PREVIEW_PATH'];
  final previewKey = GlobalKey();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    if (previewPath != null) {
      final loader = FontLoader('GraphPreview')
        ..addFont(
          File('C:/Windows/Fonts/msyh.ttc')
              .readAsBytes()
              .then(ByteData.sublistView),
        );
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          File('E:/fly/FlyEnv-Data/env/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
              .readAsBytes()
              .then(ByteData.sublistView),
        );
      await icons.load();
    }
  });

  Future<void> mount(
    WidgetTester tester,
    KnowledgeGraphCubit cubit, {
    ValueChanged<GraphNode>? onOpen,
    void Function(ViewPB, String)? onOpenSource,
    VoidCallback? onConfigureModel,
    ViewPB? focusView,
    bool documentLinks = false,
  }) async {
    await tester.runAsync(() async {
      for (final locale in ['en-US', 'zh-CN']) {
        await rootBundle.loadString('assets/translations/$locale.json');
      }
    });
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
        startLocale: previewPath == null
            ? const Locale('en', 'US')
            : const Locale('zh', 'CN'),
        fallbackLocale: const Locale('en', 'US'),
        path: 'assets/translations',
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            theme: ThemeData(
              fontFamily: previewPath == null ? null : 'GraphPreview',
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF6554A4),
              ),
              scaffoldBackgroundColor: Colors.white,
            ),
            home: Scaffold(
              body: RepaintBoundary(
                key: previewKey,
                child: BlocProvider.value(
                  value: cubit,
                  child: KnowledgeGraphView(
                    onOpen: onOpen ?? (_) {},
                    onOpenSource: onOpenSource,
                    onConfigureModel: onConfigureModel,
                    focusView: focusView,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The production loader decodes large asset files outside the fake clock.
    for (var attempt = 0;
        attempt < 50 && find.byType(KnowledgeGraphView).evaluate().isEmpty;
        attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pumpAndSettle();
    }
    if (documentLinks) {
      await tester
          .tap(find.text(previewPath == null ? 'Document links' : '文档关系'));
      await tester.pumpAndSettle();
    }
  }

  Future<List<CustomPainterSemantics>> waitForNodes(
    WidgetTester tester, {
    int? count,
  }) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      final paints = tester.widgetList<CustomPaint>(
        find.descendant(
          of: find.byType(KnowledgeGraphCanvas),
          matching: find.byType(CustomPaint),
        ),
      );
      for (final paint in paints) {
        final nodes =
            paint.painter?.semanticsBuilder?.call(const Size(800, 600));
        if (nodes != null &&
            nodes.isNotEmpty &&
            (count == null || nodes.length == count)) {
          return nodes;
        }
      }
    }
    throw StateError('Graph layout did not complete');
  }

  Future<void> openAction(WidgetTester tester, String label) async {
    await tester.tap(find.byType(PopupMenuButton<VoidCallback>));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<VoidCallback>, label));
    await tester.pumpAndSettle();
  }

  testWidgets('note graph stays scoped after searching and resetting filters',
      (tester) async {
    final note = ViewPB(id: 'note', name: 'Current note');
    final cubit = KnowledgeGraphCubit(
      workspaceId: 'workspace',
      loadViews: () async => [
        note,
        ViewPB(id: 'linked', name: 'Direct neighbor', parentViewId: 'note'),
        ViewPB(id: 'distant', name: 'Two hops away', parentViewId: 'linked'),
        ViewPB(id: 'unrelated', name: 'Unrelated'),
      ],
      loadDocument: (_) async => DocumentDataPB(),
    );
    addTearDown(cubit.close);
    await cubit.refresh();
    await mount(tester, cubit, focusView: note);
    final nodes = await waitForNodes(tester, count: 2);
    expect(nodes.map((node) => node.properties.label).toSet(), {
      'Current note',
      'Direct neighbor',
    });
    await openAction(
      tester,
      previewPath == null ? 'Filters and display' : '筛选与显示',
    );
    await tester.enterText(find.byType(TextField), 'no matching note');
    await tester.pumpAndSettle();
    expect(find.byType(KnowledgeGraphCanvas), findsNothing);
    await tester.tap(
      find
          .widgetWithText(
            TextButton,
            previewPath == null ? 'Reset filters' : '重置筛选',
          )
          .first,
    );
    final resetNodes = await waitForNodes(tester, count: 2);
    expect(resetNodes.map((node) => node.properties.label).toSet(), {
      'Current note',
      'Direct neighbor',
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('handwriting graph shows note links and disables text extraction',
      (tester) async {
    final note = ViewPB(
      id: 'hand',
      name: 'Handwriting',
      extra: '{"view_type":"handwriting_saber"}',
    );
    final cubit = KnowledgeGraphCubit(
      workspaceId: 'workspace',
      focusViewId: note.id,
      loadViews: () async => [note],
    );
    addTearDown(cubit.close);
    await cubit.refresh();
    await mount(tester, cubit, focusView: note);
    await waitForNodes(tester, count: 1);
    await tester.binding.setSurfaceSize(const Size(160, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpAndSettle();
    expect(
      find.text(previewPath == null ? 'Entity graph' : '实体图谱'),
      findsNothing,
    );
    await tester.tap(find.byType(PopupMenuButton<VoidCallback>));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PopupMenuItem<VoidCallback>>(
            find.widgetWithText(
              PopupMenuItem<VoidCallback>,
              previewPath == null
                  ? 'Extract entities and relationships'
                  : '抽取实体与关系',
            ),
          )
          .enabled,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('graph toolbar has four actions and preserves graph commands',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1007, 681));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(FullWindowController.exit);
    var loads = 0;
    final cubit = KnowledgeGraphCubit(
      workspaceId: 'workspace',
      loadViews: () async {
        loads++;
        return [
          ViewPB(id: 'notes', name: 'Project notes'),
          ViewPB(id: 'research', name: 'Research notes'),
          ViewPB(id: 'meeting', name: 'Meeting notes'),
        ];
      },
      loadDocument: (_) async => DocumentDataPB(),
    );
    addTearDown(cubit.close);
    await cubit.refresh();
    await mount(tester, cubit, documentLinks: true);
    await waitForNodes(tester, count: 3);
    for (final icon in [Icons.send_outlined, Icons.star_border]) {
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, icon))
            .onPressed,
        isNull,
      );
    }
    expect(find.byIcon(Icons.fullscreen), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome), findsNothing);
    expect(find.byIcon(Icons.refresh), findsNothing);
    expect(find.byIcon(Icons.tune), findsNothing);
    await tester.tap(find.byIcon(Icons.fullscreen));
    await tester.pumpAndSettle();
    expect(FullWindowController.isFullWindow.value, isTrue);
    await tester.tap(find.byIcon(Icons.fullscreen_exit));
    await tester.pumpAndSettle();
    expect(FullWindowController.isFullWindow.value, isFalse);
    if (previewPath != null) {
      await tester.runAsync(() async {
        final boundary = previewKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(previewPath).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await openAction(tester, previewPath == null ? 'Refresh graph' : '刷新图谱');
    await waitForNodes(tester, count: 3);
    expect(loads, 2);
    await openAction(
      tester,
      previewPath == null ? 'Filters and display' : '筛选与显示',
    );
    expect(find.byType(TextField), findsOneWidget);
    await tester.binding.setSurfaceSize(const Size(360, 640));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty workspaces show a useful empty state', (tester) async {
    final cubit = KnowledgeGraphCubit(
      workspaceId: 'workspace',
      loadViews: () async => [],
    );
    await cubit.refresh();
    addTearDown(cubit.close);
    await mount(tester, cubit);
    expect(
      find.text(
        previewPath == null ? 'No documents in this workspace' : '工作区内还没有文档',
      ),
      findsOneWidget,
    );
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets('bundled graph translations match source translations',
      (tester) async {
    await tester.runAsync(() async {
      for (final locale in ['en-US', 'zh-CN']) {
        final bundled = jsonDecode(
          await rootBundle.loadString('assets/translations/$locale.json'),
        ) as Map;
        final source = jsonDecode(
          File('../resources/translations/$locale.json').readAsStringSync(),
        ) as Map;
        expect(
          bundled['knowledgeGraph'],
          source['knowledgeGraph'],
          reason: 'Sync source translations before bundling the app',
        );
      }
    });
  });

  testWidgets(
      'defaults to entity setup, separates document links and translates missing model errors',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final cubit = KnowledgeGraphCubit(
      workspaceId: 'workspace',
      loadViews: () async => [ViewPB(id: 'notes', name: 'Project notes')],
      loadDocument: (_) async => DocumentDataPB()
        ..blocks['block'] = BlockPB(
          id: 'block',
          data: jsonEncode({
            'delta': [
              {'insert': 'Alice founded PonyNotes.'},
            ],
          }),
        ),
    );
    addTearDown(cubit.close);
    await cubit.refresh();
    var configured = false;
    await mount(tester, cubit, onConfigureModel: () => configured = true);
    expect(
      find.text(
        previewPath == null ? 'Build your knowledge graph' : '尚未生成知识图谱',
      ),
      findsOneWidget,
    );
    expect(find.byType(KnowledgeGraphCanvas), findsNothing);
    await tester
        .tap(find.text(previewPath == null ? 'Document links' : '文档关系'));
    await waitForNodes(tester, count: 1);
    await tester.tap(find.text(previewPath == null ? 'Entity graph' : '实体图谱'));
    await tester.pumpAndSettle();
    expect(find.byType(KnowledgeGraphCanvas), findsNothing);
    await tester.tap(
      find.text(
        previewPath == null ? 'Extract entities and relationships' : '抽取实体与关系',
      ),
    );
    await tester.pumpAndSettle();
    expect(cubit.state.extractionError, 'notConfigured');
    expect(
      find.text(
        previewPath == null
            ? 'Configure an AI model to build the graph'
            : '先配置 AI 模型，再生成知识图谱',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('knowledgeGraph.'), findsNothing);
    await tester.tap(
      find.text(previewPath == null ? 'Configure AI model' : '配置 AI 模型').first,
    );
    expect(configured, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'node dragging attracts links, repels unlinked neighbors, and settles without panning or opening',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cubit = KnowledgeGraphCubit(
      workspaceId: 'workspace',
      loadViews: () async => [
        for (final id in ['a', 'b', 'isolated'])
          ViewPB(id: id, name: id, layout: ViewLayoutPB.Document),
      ],
      loadDocument: (id) async => DocumentDataPB()
        ..meta = (MetaPB()
          ..textMap['text'] = jsonEncode(
            id == 'a'
                ? [
                    {
                      'insert': '\$',
                      'attributes': {
                        'mention': {'type': 'page', 'page_id': 'b'},
                      },
                    },
                  ]
                : [],
          )),
    );
    addTearDown(cubit.close);
    await cubit.refresh();
    GraphNode? opened;
    await mount(
      tester,
      cubit,
      onOpen: (node) => opened = node,
      documentLinks: true,
    );
    await waitForNodes(tester);
    await tester.pump();
    await tester.tap(find.byTooltip(previewPath == null ? 'Zoom in' : '放大'));
    await tester.pump();
    final paintFinder = find
        .descendant(
          of: find.byType(KnowledgeGraphCanvas),
          matching: find.byType(CustomPaint),
        )
        .first;
    Map<String, Offset> positions() => {
          for (final node in tester
              .widget<CustomPaint>(paintFinder)
              .painter!
              .semanticsBuilder!(Size.zero))
            node.properties.label!: node.rect.center,
        };
    Offset global(Offset point) =>
        tester.renderObject<RenderBox>(paintFinder).localToGlobal(point);
    final initial = positions();
    final controller = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    final viewport = controller.value.clone();
    final gesture = await tester.startGesture(
      global(initial['a']!),
      kind: ui.PointerDeviceKind.mouse,
    );
    // A fast first move must not get mistaken for a canvas pan before rebuilding.
    await gesture.moveBy(const Offset(120, 80));
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final held = positions();
    expect((held['a']! - initial['a']!).distance, greaterThan(10));
    expect((held['b']! - initial['b']!).distance, greaterThan(0.1));
    expect(controller.value, viewport);
    expect(opened, isNull);
    await gesture.up();
    final frames = await tester.pumpAndSettle(const Duration(milliseconds: 16));
    expect(frames, lessThan(600));
    final settled = positions();
    expect((settled['a']! - held['a']!).distance, greaterThan(0.1));
    await tester.pump(const Duration(seconds: 1));
    expect(positions(), settled);
    expect(controller.value, viewport);
    expect(opened, isNull);
    await tester.tapAt(global(settled['a']!));
    await tester.pump();
    expect(opened?.id, 'a');
    // Cancelled drags restore canvas panning and never open the document.
    opened = null;
    final cancelled = await tester.startGesture(
      global(settled['a']!),
      kind: ui.PointerDeviceKind.mouse,
    );
    await tester.pump();
    await cancelled.moveBy(const Offset(30, 20));
    await tester.pump(const Duration(milliseconds: 16));
    await cancelled.cancel();
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    expect(
      tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .panEnabled,
      isTrue,
    );
    expect(opened, isNull);
    final isolatedStart = positions()['isolated']!;
    final neighborStart = positions()['b']!;
    final isolatedTarget = neighborStart + const Offset(12, 0);
    final isolatedDrag = await tester.startGesture(
      global(isolatedStart),
      kind: ui.PointerDeviceKind.mouse,
    );
    await tester.pump();
    await isolatedDrag.moveTo(global(isolatedTarget));
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect((positions()['isolated']! - isolatedStart).distance, greaterThan(1));
    expect(positions()['b']!.dx, lessThan(neighborStart.dx - 1));
    expect(
      (positions()['isolated']! - isolatedTarget).distance,
      greaterThan(1),
    );
    await isolatedDrag.up();
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    final separated = positions();
    expect(
      (separated['isolated']! - separated['b']!).distance,
      greaterThan(20),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(positions(), separated);
    expect(controller.value, viewport);
    expect(opened, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'graph opens nodes, zooms, searches, and resets filters without overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final views = [
      ViewPB(id: 'notes', name: 'Project notes', layout: ViewLayoutPB.Document),
      ViewPB(
        id: 'research',
        name: 'Research notes',
        layout: ViewLayoutPB.Document,
      ),
      ViewPB(
        id: 'sketch',
        name: 'Design canvas',
        parentViewId: 'notes',
        layout: ViewLayoutPB.Whiteboard,
      ),
      ViewPB(id: 'calendar', name: 'Calendar', layout: ViewLayoutPB.Calendar),
      ViewPB(
        id: 'handwriting',
        name: 'Handwriting',
        extra: '{"view_type":"handwriting_saber"}',
      ),
      ViewPB(
        id: 'chat',
        name: 'Research chat',
        parentViewId: 'notes',
        layout: ViewLayoutPB.Chat,
      ),
    ];
    final cubit = KnowledgeGraphCubit(
      workspaceId: 'workspace',
      loadViews: () async => views,
      loadDocument: (id) async => DocumentDataPB()
        ..blocks['link'] = BlockPB(
          id: 'link',
          ty: 'paragraph',
          data: jsonEncode({
            'delta': [
              {
                'insert': '\$',
                'attributes': {
                  'mention': {
                    'type': 'page',
                    'page_id': id == 'notes' ? 'research' : 'notes',
                  },
                },
              },
            ],
          }),
        ),
    );
    await cubit.refresh();
    addTearDown(cubit.close);
    GraphNode? opened;
    await mount(
      tester,
      cubit,
      onOpen: (node) => opened = node,
      documentLinks: true,
    );
    final nodes = await waitForNodes(tester);
    await tester.pump();
    expect(nodes, hasLength(2));
    expect(
      nodes.map((node) => node.properties.label).toSet(),
      {'Project notes', 'Research notes'},
    );
    expect(
      cubit.state.data.edges
          .where((edge) => edge.kind == GraphEdgeKind.reference),
      hasLength(1),
    );
    // Use the actual painted node position transformed into viewport coordinates.
    final viewer =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    final transform = viewer.transformationController!;
    final nodePosition = nodes.first.rect.center;
    final paintFinder = find
        .descendant(
          of: find.byType(KnowledgeGraphCanvas),
          matching: find.byType(CustomPaint),
        )
        .first;
    final global =
        tester.renderObject<RenderBox>(paintFinder).localToGlobal(nodePosition);
    await tester.tapAt(global);
    await tester.pump();
    expect(opened?.id, isNotNull);
    final previousScale = transform.value.getMaxScaleOnAxis();
    await tester.tap(find.byTooltip(previewPath == null ? 'Zoom in' : '放大'));
    await tester.pump();
    expect(transform.value.getMaxScaleOnAxis(), greaterThan(previousScale));
    final beforePan = transform.value.clone();
    await tester.dragFrom(
      tester.getTopLeft(find.byType(InteractiveViewer)) + const Offset(40, 100),
      const Offset(50, 30),
    );
    await tester.pumpAndSettle();
    expect(transform.value, isNot(beforePan));
    await openAction(
      tester,
      previewPath == null ? 'Filters and display' : '筛选与显示',
    );
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(
      find.text(previewPath == null ? 'Show attachments' : '显示附件'),
      findsNothing,
    );
    await tester.enterText(find.byType(TextField), 'no matching file');
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
    await tester.tap(
      find
          .widgetWithText(
            TextButton,
            previewPath == null ? 'Reset filters' : '重置筛选',
          )
          .first,
    );
    await tester.pump();
    await waitForNodes(tester);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    if (previewPath != null) {
      await tester.runAsync(() async {
        final boundary = previewKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(previewPath).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    // Verify the settings overlay on a smaller desktop window as well.
    await tester.binding.setSurfaceSize(const Size(560, 640));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'extracts entities, inspects directed relationships and opens source blocks',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const text = 'Alice founded PonyNotes.';
    final cubit = KnowledgeGraphCubit(
      workspaceId: 'workspace',
      loadViews: () async => [ViewPB(id: 'notes', name: 'Project notes')],
      loadDocument: (_) async => DocumentDataPB()
        ..blocks['evidence-block'] = BlockPB(
          id: 'evidence-block',
          data: jsonEncode({
            'delta': [
              {'insert': text},
            ],
          }),
        ),
      extractChunk: (_) async => {
        'node': [
          {
            'name': 'Alice',
            'type': 'Person',
            'attributes': ['Founder of PonyNotes'],
          },
          {'name': 'PonyNotes', 'type': 'Product', 'attributes': []},
        ],
        'relation': [
          {
            'node1': 'Alice',
            'node2': 'PonyNotes',
            'type': 'founded',
            'evidence': text,
          },
        ],
      },
    );
    addTearDown(cubit.close);
    await cubit.refresh();
    (String, String)? opened;
    await mount(
      tester,
      cubit,
      onOpenSource: (view, block) => opened = (view.id, block),
    );
    expect(find.byType(KnowledgeGraphCanvas), findsNothing);
    await openAction(
      tester,
      previewPath == null ? 'Extract entities and relationships' : '抽取实体与关系',
    );
    final nodes = await waitForNodes(tester, count: 2);
    final alice = nodes.singleWhere((n) => n.properties.label == 'Alice');
    final paintFinder = find
        .descendant(
          of: find.byType(KnowledgeGraphCanvas),
          matching: find.byType(CustomPaint),
        )
        .first;
    final position = tester
        .renderObject<RenderBox>(paintFinder)
        .localToGlobal(alice.rect.center);
    await tester.tapAt(position);
    await tester.pumpAndSettle();
    expect(find.text('Alice → PonyNotes'), findsOneWidget);
    expect(find.text('Founder of PonyNotes'), findsOneWidget);
    await tester.tap(find.text('Alice → PonyNotes'));
    await tester.pumpAndSettle();
    expect(find.text(text), findsOneWidget);
    await tester.tap(find.text('Project notes'));
    expect(opened, ('notes', 'evidence-block'));
    await tester
        .tap(find.text(previewPath == null ? 'Show neighbors' : '查看一跳邻居'));
    await tester.pumpAndSettle();
    await waitForNodes(tester, count: 2);
    if (previewPath != null) {
      await tester.runAsync(() async {
        final boundary = previewKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(previewPath).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.binding.setSurfaceSize(const Size(360, 640));
    await tester.pumpAndSettle();
    expect(find.text(text), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(
      find.byTooltip(
        MaterialLocalizations.of(
          tester.element(find.byType(KnowledgeGraphView)),
        ).closeButtonTooltip,
      ),
    );
    await tester.pumpAndSettle();
    await openAction(
      tester,
      previewPath == null ? 'Filters and display' : '筛选与显示',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(previewPath == null ? 'Person' : '人物').last);
    await tester.pumpAndSettle();
    await waitForNodes(tester, count: 1);
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(const Size(1100, 720));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(
        TextButton,
        previewPath == null ? 'Reset filters' : '重置筛选',
      ),
    );
    await tester.pumpAndSettle();
    await waitForNodes(tester, count: 2);
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .initialValue,
      '',
    );
  });
}
