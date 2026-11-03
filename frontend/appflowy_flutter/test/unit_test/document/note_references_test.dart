import 'package:appflowy_backend/rust_stream.dart';
import 'package:appflowy_backend/protobuf/flowy-notification/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-document/notification.pbenum.dart';
import 'package:appflowy/plugins/document/application/note_link_data.dart';
import 'package:appflowy/plugins/document/application/note_relations_controller.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/backlinks/backlink_panel.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/backlinks/note_reference_picker.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/backlinks/referenced_block.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

EditorState editorWith(Node node) => EditorState(
      document: Document(root: pageNode(children: [node])),
    );

void main() {
  test('paragraph reference stores stable document and block identities',
      () async {
    final node = paragraphNode(delta: Delta()..insert('前文 😀 后文'));
    final editor = editorWith(node);
    editor.selection =
        Selection.collapsed(Position(path: [0], offset: '前文 😀 '.length));
    final anchor = NoteReferenceAnchor.capture(editor)!;
    expect(
      await anchor.insert(
        editor,
        const NoteReferenceTarget('target-note', 'target-block'),
      ),
      isTrue,
    );
    final link = editorOutgoingLinks('source-note', editor).single;
    expect(link.dstPageId, 'target-note');
    expect(link.dstBlockId, 'target-block');
    expect(link.kind, 'block_ref');
    expect(node.delta!.toPlainText(), r'前文 😀 $后文');
    editor.dispose();
  });

  test('reference insertion replaces the chosen source range', () async {
    final node = paragraphNode(delta: Delta()..insert('before selected after'));
    final editor = editorWith(node);
    editor.selection = Selection(
      start: Position(path: [0], offset: 7),
      end: Position(path: [0], offset: 15),
    );
    expect(
      await NoteReferenceAnchor.capture(editor)!.insert(
        editor,
        const NoteReferenceTarget('target', 'paragraph'),
      ),
      isTrue,
    );
    expect(node.delta!.toPlainText(), r'before $ after');
    editor.dispose();
  });

  test('an async picker cannot overwrite an intervening source edit', () async {
    final node = paragraphNode(delta: Delta()..insert('original'));
    final editor = editorWith(node);
    editor.selection = Selection.collapsed(Position(path: [0], offset: 8));
    final anchor = NoteReferenceAnchor.capture(editor)!;
    await editor.apply(editor.transaction..insertText(node, 8, ' edited'));
    expect(
      await anchor.insert(
        editor,
        const NoteReferenceTarget('target', 'block'),
      ),
      isFalse,
    );
    expect(node.delta!.toPlainText(), 'original edited');
    expect(editorOutgoingLinks('source', editor), isEmpty);
    editor.dispose();
  });

  test('read-only editors cannot insert references after a picker was opened',
      () async {
    final node = paragraphNode(delta: Delta()..insert('original'));
    final editor = editorWith(node);
    editor.selection = Selection.collapsed(Position(path: [0], offset: 8));
    final anchor = NoteReferenceAnchor.capture(editor)!;
    editor.editableNotifier.value = false;
    expect(
      await anchor.insert(
        editor,
        const NoteReferenceTarget('target', 'block'),
      ),
      isFalse,
    );
    expect(node.delta!.toPlainText(), 'original');
    editor.dispose();
  });

  final references = [
    NoteLinkPB(
      srcPageId: 'a',
      srcBlockId: 'a1',
      dstPageId: 'b',
      dstBlockId: 'b1',
      occurrence: 2,
    ),
    NoteLinkPB(
      srcPageId: 'a',
      srcBlockId: 'a2',
      dstPageId: 'b',
      dstBlockId: 'b1',
      occurrence: 1,
    ),
    NoteLinkPB(
      srcPageId: 'c',
      srcBlockId: 'c1',
      dstPageId: 'b',
      dstBlockId: 'b2',
      occurrence: 1,
    ),
  ];

  test('note counts differ from reference occurrences and target block counts',
      () {
    expect(groupNoteLinks(references, incoming: true).length, 2);
    expect(groupNoteLinks(references, incoming: false).length, 1);
    expect(noteLinkOccurrences(references), 4);
    final editor = editorWith(paragraphNode());
    final controller = NoteRelationsController(
      pageId: 'b',
      workspaceId: 'ws',
      identity: 'user/ws',
      editorState: editor,
    )
      ..views = {
        for (final id in ['a', 'b', 'c']) id: ViewPB(id: id),
      }
      ..links = DocumentLinksPB(incoming: references);
    expect(controller.incomingTo('b1'), hasLength(2));
    expect(controller.incomingTo('b2'), hasLength(1));
    expect(controller.incomingTo('other'), isEmpty);
    controller.dispose();
    editor.dispose();
  });

  test('inaccessible sources disappear from backlinks and excerpt reads',
      () async {
    final editor = editorWith(paragraphNode());
    var allowed = true;
    var excerptReads = 0;
    final controller = NoteRelationsController(
      pageId: 'b',
      workspaceId: 'ws',
      identity: 'user/ws',
      editorState: editor,
      loadViews: () async => [ViewPB(id: 'b'), if (allowed) ViewPB(id: 'a')],
      loadLinks: () async =>
          DocumentLinksPB(incoming: references, indexedPages: 3),
      loadExcerpt: (_, __, ___) async {
        excerptReads++;
        return 'private excerpt';
      },
    );
    await controller.refresh();
    expect(controller.incoming, hasLength(2));
    expect(await controller.excerpt('a', 'a1'), 'private excerpt');
    allowed = false;
    await controller.refresh();
    expect(controller.incoming, isEmpty);
    expect(await controller.excerpt('a', 'a1'), isEmpty);
    expect(excerptReads, 1);
    controller.dispose();
    editor.dispose();
  });

  test('target receives a backlink notification without a second insertion',
      () async {
    final editor = editorWith(paragraphNode());
    var snapshot = DocumentLinksPB(indexedPages: 2);
    final controller = NoteRelationsController(
      pageId: 'b',
      workspaceId: 'ws',
      identity: 'user/ws',
      editorState: editor,
      loadViews: () async => [ViewPB(id: 'a'), ViewPB(id: 'b')],
      loadLinks: () async => snapshot,
    );
    controller.start();
    await controller.refresh();
    expect(controller.incoming, isEmpty);
    snapshot = DocumentLinksPB(indexedPages: 2, incoming: [references.first]);
    RustStreamReceiver.shared.observable.add(
      SubscribeObject(
        source: 'Document',
        id: 'ws',
        ty: DocumentNotification.DidUpdateLinks.value,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 260));
    expect(controller.incomingTo('b1'), hasLength(1));
    expect(editorOutgoingLinks('b', editor), isEmpty);
    controller.dispose();
    editor.dispose();
  });

  test(
      'live internal block references invalidate caches on insertion and removal',
      () async {
    final node = paragraphNode(delta: Delta()..insert('source '));
    final editor = editorWith(node);
    final controller = NoteRelationsController(
      pageId: 'b',
      workspaceId: 'ws',
      identity: 'user/ws',
      editorState: editor,
      loadViews: () async => [ViewPB(id: 'b')],
      loadLinks: () async => DocumentLinksPB(indexedPages: 1),
    );
    controller.start();
    await controller.refresh();
    expect(controller.incomingTo('target-block'), isEmpty);
    editor.selection = Selection.collapsed(Position(path: [0], offset: 7));
    await NoteReferenceAnchor.capture(editor)!
        .insert(editor, const NoteReferenceTarget('b', 'target-block'));
    expect(controller.incomingTo('target-block'), hasLength(1));
    await editor.apply(editor.transaction..deleteText(node, 7, 1));
    expect(controller.incomingTo('target-block'), isEmpty);
    controller.dispose();
    editor.dispose();
  });

  testWidgets(
      'a target paragraph exposes automatically derived sources and transient highlight',
      (tester) async {
    final node = paragraphNode()..id = 'b1';
    final editor = editorWith(node);
    final controller = NoteRelationsController(
      pageId: 'b',
      workspaceId: 'ws',
      identity: 'user/ws',
      editorState: editor,
      loadExcerpt: (_, block, __) async => 'source passage $block',
    )
      ..views = {
        'a': ViewPB(id: 'a', name: 'Source A'),
        'b': ViewPB(id: 'b', name: 'Target'),
      }
      ..links = DocumentLinksPB(incoming: references)
      ..loading = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<NoteRelationsController?>.value(
            value: controller,
            child: ReferencedBlock(
              node: node,
              configuration: const BlockComponentConfiguration(),
              child: const Text('Target passage'),
            ),
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('block-reference-sources-b1')),
      findsOneWidget,
    );
    expect(find.text('1'), findsOneWidget);
    controller.highlight('b1');
    await tester.pumpAndSettle();
    final animated = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('referenced-block-b1')),
    );
    expect(
      (animated.decoration! as BoxDecoration).color,
      isNot(Colors.transparent),
    );
    await tester.tap(find.byKey(const ValueKey('block-reference-sources-b1')));
    await tester.pumpAndSettle();
    expect(find.text('References to this passage · 1 notes'), findsOneWidget);
    expect(find.text('Source A'), findsOneWidget);
    expect(find.text('3 references'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(controller.highlightedBlockId, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    editor.dispose();
  });

  testWidgets('footer groups source notes and removes index maintenance UI',
      (tester) async {
    final editor = editorWith(paragraphNode());
    final controller = NoteRelationsController(
      pageId: 'b',
      workspaceId: 'ws',
      identity: 'user/ws',
      editorState: editor,
      loadExcerpt: (_, block, __) async => 'source passage $block',
    )
      ..views = {
        for (final id in ['a', 'b', 'c']) id: ViewPB(id: id, name: 'Note $id'),
      }
      ..links = DocumentLinksPB(incoming: references)
      ..loading = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ChangeNotifierProvider<NoteRelationsController?>.value(
              value: controller,
              child: BacklinkPanel(
                pageId: 'b',
                editorState: editor,
                editable: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Backlinks · 2 notes'), findsOneWidget);
    expect(find.text('Note a'), findsOneWidget);
    expect(find.text('Note c'), findsOneWidget);
    expect(find.textContaining('Rebuild'), findsNothing);
    expect(find.textContaining('indexed on this device'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    editor.dispose();
  });
  testWidgets('picker searches passages and returns the chosen block identity',
      (tester) async {
    final first = paragraphNode(delta: Delta()..insert('Unrelated paragraph'));
    final target =
        paragraphNode(delta: Delta()..insert('The passage about 双链笔记'));
    NoteReferenceTarget? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('Choose passage'),
              onPressed: () async {
                selected = await showDialog<NoteReferenceTarget>(
                  context: context,
                  builder: (_) => NoteReferencePicker(
                    loadViews: () async =>
                        [ViewPB(id: 'target-note', name: 'Target note')],
                    loadBlocks: (_) async => [first, target],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Choose passage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Target note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '双链');
    await tester.pumpAndSettle();
    expect(find.text('Unrelated paragraph'), findsNothing);
    await tester.tap(find.text('The passage about 双链笔记'));
    await tester.pumpAndSettle();
    expect(selected!.pageId, 'target-note');
    expect(selected!.blockId, target.id);
  });

  testWidgets(
      'picker keeps a whole-note alternative and recovers from a read failure',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: NoteReferencePicker(
          initialView: ViewPB(id: 'target', name: 'Target note'),
          loadBlocks: (_) async {
            if (attempts++ == 0) throw StateError('offline');
            return [paragraphNode(delta: Delta()..insert('Recovered passage'))];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Link to the whole note'), findsOneWidget);
    await tester.tap(find.text('Could not load content. Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Recovered passage'), findsOneWidget);
    expect(attempts, 2);
  });

  testWidgets(
      'nested editor blocks retain their selectable keys and reference markers',
      (tester) async {
    final child =
        paragraphNode(delta: Delta()..insert('Nested target passage'));
    final parent =
        paragraphNode(delta: Delta()..insert('Parent'), children: [child]);
    final editor = editorWith(parent);
    final controller = NoteRelationsController(
      pageId: 'target',
      workspaceId: 'ws',
      identity: 'user/ws',
      editorState: editor,
    )
      ..views = {'source': ViewPB(id: 'source'), 'target': ViewPB(id: 'target')}
      ..links = DocumentLinksPB(
        incoming: [
          NoteLinkPB(
            srcPageId: 'source',
            srcBlockId: 'source-block',
            dstPageId: 'target',
            dstBlockId: child.id,
            occurrence: 1,
          ),
        ],
      );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<NoteRelationsController?>.value(
            value: controller,
            child: AppFlowyEditor(
              editorState: editor,
              shrinkWrap: true,
              blockComponentBuilders: {
                ...standardBlockComponentBuilderMap,
                ParagraphBlockKeys.type:
                    ReferencedBlockBuilder(ParagraphBlockComponentBuilder()),
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(child.selectable, isNotNull);
    expect(parent.selectable, isNotNull);
    expect(
      find.byKey(ValueKey('block-reference-sources-${child.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('block-reference-sources-${parent.id}')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    editor.dispose();
  });
}
