import 'package:appflowy/plugins/document/application/note_relations_controller.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/backlinks/backlink_panel.dart';
import 'package:appflowy/plugins/note_graph/note_graph_plugin.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/plugins/note_graph/application/note_graph_cubit.dart';
import 'package:appflowy/plugins/note_graph/application/note_graph_data.dart';
import 'package:appflowy/plugins/note_graph/presentation/note_graph_canvas.dart';
import 'package:appflowy/plugins/note_graph/presentation/note_graph_page.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class _CapturingTabs extends MockBloc<TabsEvent, TabsState>
    implements TabsBloc {
  final events = <TabsEvent>[];
  @override
  void add(TabsEvent event) => events.add(event);
}

List<ViewPB> _notes() => [
      ViewPB(id: 'a', name: 'Research methods'),
      ViewPB(id: 'b', name: 'Reading notes'),
      ViewPB(id: 'c', name: 'Project planning'),
      ViewPB(id: 'd', name: 'Personal journal'),
      ViewPB(id: 'e', name: 'Unconnected note'),
    ];
NoteLinkPB _link(String source, String target, {bool block = false}) =>
    NoteLinkPB(
      srcPageId: source,
      srcBlockId: '$source-paragraph',
      dstPageId: target,
      dstBlockId: block ? '$target-paragraph' : '',
      kind: block ? 'block_ref' : 'reference',
      occurrence: 1,
    );
NoteGraphCubit _cubit() => NoteGraphCubit(
      workspaceId: 'workspace',
      loadViews: () async => _notes(),
      loadLinks: () async => DocumentLinksPB(
        indexedPages: 5,
        outgoing: [
          _link('a', 'b', block: true),
          _link('b', 'a'),
          _link('c', 'b', block: true),
          _link('d', 'c'),
        ],
      ),
      loadExcerpt: (page, block) async => 'Live passage from $page at $block',
    );

Future<void> _waitLayout(WidgetTester tester) async {
  for (var attempt = 0; attempt < 80; attempt++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 16));
    final paints = tester.widgetList<CustomPaint>(
      find.descendant(
        of: find.byType(NoteGraphCanvas),
        matching: find.byType(CustomPaint),
      ),
    );
    if (paints.any(
      (paint) =>
          paint.painter?.semanticsBuilder
              ?.call(const Size(800, 500))
              .isNotEmpty ==
          true,
    )) {
      // Fit updates the transform after layout; finish painting it before hit testing.
      await tester.pumpAndSettle();
      return;
    }
  }
  throw StateError('Note graph layout did not complete');
}

CustomPainterSemantics _semantic(WidgetTester tester, String key) {
  final paints = tester.widgetList<CustomPaint>(
    find.descendant(
      of: find.byType(NoteGraphCanvas),
      matching: find.byType(CustomPaint),
    ),
  );
  return paints
      .expand(
        (paint) =>
            paint.painter?.semanticsBuilder?.call(const Size(800, 500)) ??
            <CustomPainterSemantics>[],
      )
      .firstWhere((entry) => entry.key == ValueKey(key));
}

Future<void> _mount(
  WidgetTester tester,
  NoteGraphCubit cubit, {
  String? focus,
  void Function(ViewPB, String?)? onOpen,
  GlobalKey? preview,
}) async {
  await cubit.refresh();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        fontFamily: preview == null ? null : 'NoteGraphPreview',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF386C65)),
      ),
      home: Scaffold(
        body: RepaintBoundary(
          key: preview,
          child: BlocProvider.value(
            value: cubit,
            child: NoteGraphView(
              focusId: focus,
              onOpen: onOpen ?? (_, __) {},
            ),
          ),
        ),
      ),
    ),
  );
  await _waitLayout(tester);
}

void main() {
  testWidgets(
      'independent graph exposes directed note relationships without AI controls',
      (tester) async {
    final cubit = _cubit();
    await _mount(tester, cubit);
    expect(find.text('Note link graph'), findsOneWidget);
    expect(find.text('5 notes · 4 directed relationships'), findsOneWidget);
    expect(find.textContaining('Extract'), findsNothing);
    expect(find.textContaining('Model'), findsNothing);
    expect(
      _semantic(tester, 'note-graph-edge-a-b').properties.label,
      'Research methods → Reading notes',
    );
    expect(
      _semantic(tester, 'note-graph-edge-b-a').properties.label,
      'Reading notes → Research methods',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await cubit.close();
  });

  testWidgets(
      'selecting a connection shows both live passages and navigates to exact block IDs',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final opened = <(String, String?)>[];
    final cubit = _cubit();
    await _mount(
      tester,
      cubit,
      onOpen: (view, block) => opened.add((view.id, block)),
    );
    _semantic(tester, 'note-graph-edge-a-b').properties.onTap!();
    await tester.pumpAndSettle();
    expect(find.text('Source passage'), findsOneWidget);
    expect(find.text('Target passage'), findsOneWidget);
    expect(find.text('Live passage from a at a-paragraph'), findsOneWidget);
    expect(find.text('Live passage from b at b-paragraph'), findsOneWidget);
    await tester.tap(find.text('Open source passage'));
    await tester.tap(find.text('Open target passage'));
    expect(opened, [('a', 'a-paragraph'), ('b', 'b-paragraph')]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await cubit.close();
  });

  testWidgets(
      'node inspector shows backlink and outgoing counts and can focus locally',
      (tester) async {
    final cubit = _cubit();
    await _mount(tester, cubit);
    _semantic(tester, 'note-graph-node-b').properties.onTap!();
    await tester.pumpAndSettle();
    expect(find.text('2 incoming notes'), findsOneWidget);
    expect(find.text('1 outgoing notes'), findsOneWidget);
    await tester.ensureVisible(find.text('Focus on this note'));
    await tester.tap(find.text('Focus on this note'));
    await _waitLayout(tester);
    expect(find.text('Around: Reading notes'), findsOneWidget);
    expect(find.text('3 notes · 3 directed relationships'), findsOneWidget);
    await tester.tap(find.text('All notes'));
    await _waitLayout(tester);
    expect(find.text('5 notes · 4 directed relationships'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await cubit.close();
  });

  testWidgets(
      'filters expose paragraph links and unconnected notes and keep the local scope',
      (tester) async {
    final cubit = _cubit();
    await _mount(tester, cubit, focus: 'b');
    expect(find.text('3 notes · 3 directed relationships'), findsOneWidget);
    await tester.tap(find.text('Paragraph references'));
    await _waitLayout(tester);
    expect(find.text('3 notes · 2 directed relationships'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('note-graph-search')),
      'does not exist',
    );
    await _waitLayout(tester); // the focal note stays visible
    expect(find.text('1 notes · 0 directed relationships'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await _waitLayout(tester);
    await tester.tap(find.text('All notes'));
    await _waitLayout(tester);
    expect(find.text('5 notes · 2 directed relationships'), findsOneWidget);
    await tester.tap(find.text('Unconnected notes'));
    await _waitLayout(tester);
    expect(find.text('3 notes · 2 directed relationships'), findsOneWidget);
    await tester.tap(find.text('Unconnected notes'));
    await _waitLayout(tester);
    expect(find.text('5 notes · 2 directed relationships'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await cubit.close();
  });

  testWidgets(
      'index failure offers retry and does not display a false empty graph',
      (tester) async {
    var failed = true;
    final cubit = NoteGraphCubit(
      workspaceId: 'workspace',
      loadViews: () async => _notes(),
      loadLinks: () async {
        if (failed) throw StateError('offline');
        return DocumentLinksPB(indexedPages: 5, outgoing: [_link('a', 'b')]);
      },
    );
    await cubit.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider.value(
            value: cubit,
            child: NoteGraphView(onOpen: (_, __) {}),
          ),
        ),
      ),
    );
    expect(find.text('Could not load note relationships'), findsOneWidget);
    failed = false;
    await tester.tap(find.text('Retry'));
    await _waitLayout(tester);
    expect(find.text('5 notes · 1 directed relationships'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await cubit.close();
  });

  testWidgets(
      'narrow graph remains usable when a relationship inspector is open',
      (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final cubit = _cubit();
    await _mount(tester, cubit);
    _semantic(tester, 'note-graph-edge-a-b').properties.onTap!();
    await tester.pumpAndSettle();
    expect(find.text('Reference details'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await cubit.close();
  });

  testWidgets('canvas pointer selection and double click open the chosen note',
      (tester) async {
    final opened = <String>[];
    final cubit = _cubit();
    await _mount(tester, cubit, onOpen: (view, _) => opened.add(view.id));
    Offset pointFor(String id) {
      final node = _semantic(tester, 'note-graph-node-$id');
      final finder = find.descendant(
        of: find.byType(NoteGraphCanvas),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && widget.painter?.semanticsBuilder != null,
        ),
      );
      return tester
          .renderObject<RenderBox>(finder)
          .localToGlobal(node.rect.center);
    }

    await tester.tapAt(pointFor('a'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('Research methods'), findsOneWidget);
    final point = pointFor('b');
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(point);
    await tester.pumpAndSettle();
    expect(opened, ['b']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await cubit.close();
  });

  testWidgets(
      'document graph entry opens an independent plugin without a SpaceHub view redirect',
      (tester) async {
    final editor = EditorState(
      document: Document(root: pageNode(children: [paragraphNode()])),
    );
    final relations = NoteRelationsController(
      pageId: 'a',
      workspaceId: 'ws',
      identity: 'user/ws',
      editorState: editor,
    )
      ..views = {'a': _notes().first}
      ..links = DocumentLinksPB()
      ..loading = false;
    final tabs = _CapturingTabs();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<TabsBloc>.value(
            value: tabs,
            child: ChangeNotifierProvider<NoteRelationsController?>.value(
              value: relations,
              child: BacklinkPanel(
                pageId: 'a',
                editorState: editor,
                editable: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Open note link graph'));
    expect(tabs.events, hasLength(1));
    var openedGraph = false;
    tabs.events.single.whenOrNull(
      openPlugin: (plugin, view, _) {
        expect(plugin, isA<NoteGraphPlugin>());
        expect(plugin.id, 'note_graph:a');
        expect(view, isNull, reason: 'SpaceHub intercepts ordinary view opens');
        openedGraph = true;
      },
    );
    expect(openedGraph, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tabs.close();
    relations.dispose();
    editor.dispose();
  });

  testWidgets('notes without any links render as independent dots by default',
      (tester) async {
    final cubit = NoteGraphCubit(
      workspaceId: 'workspace',
      loadViews: () async => _notes(),
      loadLinks: () async => DocumentLinksPB(indexedPages: 5),
    );
    await _mount(tester, cubit);
    expect(find.text('5 notes · 0 directed relationships'), findsOneWidget);
    expect(
      _semantic(tester, 'note-graph-node-e').properties.label,
      'Unconnected note',
    );
    final paints = tester.widgetList<CustomPaint>(
      find.descendant(
        of: find.byType(NoteGraphCanvas),
        matching: find.byType(CustomPaint),
      ),
    );
    final semantics = paints
        .expand(
          (paint) =>
              paint.painter?.semanticsBuilder?.call(const Size(800, 500)) ??
              <CustomPainterSemantics>[],
        )
        .toList();
    expect(semantics, hasLength(5));
    expect(
      semantics.every(
        (entry) => entry.key.toString().contains('note-graph-node-'),
      ),
      isTrue,
    );
    expect(find.text('No matching notes'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await cubit.close();
  });

  testWidgets(
      'dragging a node stretches links and settles without panning or opening notes',
      (tester) async {
    final cubit = _cubit();
    final opened = <String>[];
    await _mount(tester, cubit, onOpen: (view, _) => opened.add(view.id));
    Finder paint() => find.descendant(
          of: find.byType(NoteGraphCanvas),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is CustomPaint &&
                widget.painter?.semanticsBuilder != null,
          ),
        );
    Offset scene(String id) =>
        _semantic(tester, 'note-graph-node-$id').rect.center;
    Offset screen(String id) =>
        tester.renderObject<RenderBox>(paint()).localToGlobal(scene(id));
    Matrix4 transform() => Matrix4.copy(
          tester
              .widget<InteractiveViewer>(
                find.descendant(
                  of: find.byType(NoteGraphCanvas),
                  matching: find.byType(InteractiveViewer),
                ),
              )
              .transformationController!
              .value,
        );
    final before = scene('a');
    final neighbor = scene('b');
    final matrix = transform();
    final pointer = await tester.startGesture(
      screen('a'),
      kind: ui.PointerDeviceKind.mouse,
    );
    await tester.pump();
    await pointer.moveBy(const Offset(75, -15));
    await tester.pump(const Duration(milliseconds: 160));
    expect((scene('a') - before).distance, greaterThan(20));
    expect((scene('b') - neighbor).distance, greaterThan(.1));
    expect(transform(), matrix);
    await pointer.up();
    final dropped = scene('a');
    await tester.pumpAndSettle();
    final settled = scene('a');
    expect((settled - dropped).distance, lessThan(60));
    await tester.pump(const Duration(seconds: 2));
    expect((scene('a') - settled).distance, lessThan(.01));
    expect(opened, isEmpty);
    expect(find.text('Reference details'), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await cubit.close();
  });

  testWidgets(
      'reduced motion renders dots directly without a running spring ticker',
      (tester) async {
    final data = NoteGraphData.fromIndex(
      _notes(),
      DocumentLinksPB(outgoing: [_link('a', 'b')]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: SizedBox(
            width: 800,
            height: 500,
            child: NoteGraphCanvas(
              data: data,
              onSelectNote: (_) {},
              onSelectEdge: (_) {},
              onOpenNote: (_) {},
            ),
          ),
        ),
      ),
    );
    await _waitLayout(tester);
    final position = _semantic(tester, 'note-graph-node-a').rect.center;
    await tester.pump(const Duration(milliseconds: 100));
    expect(_semantic(tester, 'note-graph-node-a').rect.center, position);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('note graph preview', (tester) async {
    final path = Platform.environment['NOTE_GRAPH_PREVIEW_PATH'];
    if (path == null) return;
    await tester.runAsync(() async {
      await (FontLoader('NoteGraphPreview')
            ..addFont(
              File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')
                  .readAsBytes()
                  .then(ByteData.sublistView),
            ))
          .load();
      await (FontLoader('MaterialIcons')
            ..addFont(
              File('/home/michi/fvm/versions/3.35.0/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
                  .readAsBytes()
                  .then(ByteData.sublistView),
            ))
          .load();
    });
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    final cubit = _cubit();
    await _mount(tester, cubit, preview: key);
    _semantic(tester, 'note-graph-edge-a-b').properties.onTap!();
    await tester.pumpAndSettle();
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(path).writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox.shrink());
    await cubit.close();
  });
}
