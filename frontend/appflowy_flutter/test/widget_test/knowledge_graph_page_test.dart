import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:appflowy/plugins/knowledge_graph/application/knowledge_graph_cubit.dart';
import 'package:appflowy/plugins/knowledge_graph/application/knowledge_graph_data.dart';
import 'package:appflowy/plugins/knowledge_graph/presentation/knowledge_graph_canvas.dart';
import 'package:appflowy/plugins/knowledge_graph/presentation/knowledge_graph_page.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SourceTranslations extends AssetLoader {
  const _SourceTranslations();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(
        File('../resources/translations/${locale.languageCode}-${locale.countryCode}.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
}

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
    }
  });

  Future<void> mount(
    WidgetTester tester,
    KnowledgeGraphCubit cubit, {
    ValueChanged<GraphNode>? onOpen,
  }) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
        startLocale: previewPath == null
            ? const Locale('en', 'US')
            : const Locale('zh', 'CN'),
        fallbackLocale: const Locale('en', 'US'),
        path: 'assets/translations',
        assetLoader: const _SourceTranslations(),
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
                  child: KnowledgeGraphView(onOpen: onOpen ?? (_) {}),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<List<CustomPainterSemantics>> waitForNodes(WidgetTester tester) async {
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
        if (nodes != null && nodes.isNotEmpty) return nodes;
      }
    }
    throw StateError('Graph layout did not complete');
  }

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
    await mount(tester, cubit, onOpen: (node) => opened = node);
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
    await mount(tester, cubit, onOpen: (node) => opened = node);
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
    await tester.tap(
      find.byTooltip(previewPath == null ? 'Filters and display' : '筛选与显示'),
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
}
