import 'dart:async';

import 'package:appflowy/plugins/note_graph/application/note_graph_cubit.dart';
import 'package:appflowy/plugins/note_graph/application/note_graph_data.dart';
import 'package:appflowy/plugins/note_graph/note_graph_plugin.dart';
import 'package:appflowy/plugins/note_graph/presentation/note_graph_layout.dart';
import 'package:appflowy/plugins/knowledge_graph/knowledge_graph_plugin.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-document/notification.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-notification/protobuf.dart';
import 'package:appflowy_backend/rust_stream.dart';
import 'package:flutter_test/flutter_test.dart';

ViewPB note(String id, {String? parent}) => ViewPB(
      id: id,
      name: 'Note $id',
      parentViewId: parent ?? 'workspace',
      layout: ViewLayoutPB.Document,
    );
NoteLinkPB link(
  String source,
  String target, {
  String? sourceBlock,
  String? block,
  String kind = 'reference',
  int occurrences = 1,
}) =>
    NoteLinkPB(
      srcPageId: source,
      srcBlockId: sourceBlock ?? '$source-block',
      dstPageId: target,
      dstBlockId: block,
      kind: kind,
      occurrence: occurrences,
    );

void main() {
  test(
      'note graph is a separate plugin type and identity from the existing knowledge graph',
      () {
    final old = KnowledgeGraphPlugin(focusView: note('a'));
    final global = NoteGraphPlugin();
    final local = NoteGraphPlugin(focusView: note('a'));
    expect(old.pluginType, PluginType.knowledgeGraph);
    expect(global.pluginType, PluginType.noteGraph);
    expect({old.id, global.id, local.id}, hasLength(3));
    expect(NoteGraphPluginConfig().creatable, isFalse);
    expect(NoteGraphPluginBuilder().build(note('a')).id, local.id);
  });

  test(
      'graph contains only explicit readable document references, with no folder or semantic edges',
      () {
    final views = [
      note('a'),
      note('b', parent: 'a'),
      note('isolated'),
      ViewPB(id: 'grid', layout: ViewLayoutPB.Grid),
      ViewPB(
        id: 'space',
        layout: ViewLayoutPB.Document,
        extra: '{"is_space":true}',
      ),
    ];
    final graph = NoteGraphData.fromIndex(
      views,
      DocumentLinksPB(
        outgoing: [
          link(
            'a',
            'b',
            kind: 'embed',
          ), // an owned child page is a hierarchy edge
          link('b', 'a', block: 'a-paragraph', kind: 'block_ref'),
          link('a', 'a'), link('a', 'private'), link('private', 'b'),
          link('a', 'grid'), link('a', 'space'),
          link('a', 'b', kind: 'relation'),
        ],
      ),
    );
    expect(graph.notes.keys, unorderedEquals(['a', 'b', 'isolated']));
    expect(graph.edges.single.key, ('b', 'a'));
    expect(graph.edges.single.references.single.dstBlockId, 'a-paragraph');
    expect(
      graph.filtered().notes.keys,
      unorderedEquals(['a', 'b', 'isolated']),
    );
    expect(
      graph.filtered(showIsolated: false).notes.keys,
      unorderedEquals(['a', 'b']),
    );
    expect(graph.filtered().notes, hasLength(3));
  });

  test(
      'reciprocal citations retain their directions, source blocks, and occurrence counts',
      () {
    final record = link(
      'a',
      'b',
      sourceBlock: 'a1',
      block: 'b1',
      occurrences: 2,
      kind: 'block_ref',
    );
    final graph = NoteGraphData.fromIndex(
      [note('a'), note('b')],
      DocumentLinksPB(
        outgoing: [
          record,
          record,
          link('a', 'b', sourceBlock: 'a2'),
          link('b', 'a'),
        ],
      ),
    );
    expect(graph.edges, hasLength(2));
    final forward = graph.edges.firstWhere((edge) => edge.source == 'a');
    expect(forward.references, hasLength(2));
    expect(forward.occurrences, 3);
    expect(forward.blockReferences, 1);
    record.dstBlockId = 'changed';
    expect(forward.references.first.dstBlockId, 'b1');
    expect(graph.incomingTo('a'), {'b'});
    expect(graph.outgoingFrom('a'), {'b'});
    expect(
      graph
          .filtered(focus: 'a', direction: NoteGraphDirection.incoming)
          .edges
          .single
          .key,
      ('b', 'a'),
    );
    expect(
      graph
          .filtered(focus: 'a', direction: NoteGraphDirection.outgoing)
          .edges
          .single
          .key,
      ('a', 'b'),
    );
    final blocks = graph.filtered(blocksOnly: true);
    expect(blocks.edges.single.references.single.dstBlockId, 'b1');
    expect(blocks.edges.single.occurrences, 2);
  });

  test(
      'local scope follows incoming or outgoing citations for one to three hops',
      () {
    final graph = NoteGraphData.fromIndex(
      [
        for (final id in ['a', 'b', 'c', 'd', 'e', 'isolated']) note(id),
      ],
      DocumentLinksPB(
        outgoing: [
          link('a', 'b'),
          link('b', 'c'),
          link('c', 'd'),
          link('e', 'b'),
        ],
      ),
    );
    expect(
      graph
          .filtered(focus: 'b', direction: NoteGraphDirection.incoming)
          .notes
          .keys,
      unorderedEquals(['b', 'a', 'e']),
    );
    expect(
      graph
          .filtered(focus: 'b', direction: NoteGraphDirection.outgoing)
          .notes
          .keys,
      unorderedEquals(['b', 'c']),
    );
    expect(
      graph
          .filtered(
            focus: 'a',
            depth: 3,
            direction: NoteGraphDirection.outgoing,
          )
          .notes
          .keys,
      unorderedEquals(['a', 'b', 'c', 'd']),
    );
    expect(graph.filtered(focus: 'isolated').notes.keys, ['isolated']);
    expect(graph.filtered(focus: 'unreadable').notes, isEmpty);
    expect(graph.filtered(query: 'Note c').notes.keys, ['c']);
    final limited = graph.filtered(limit: 2);
    expect(limited.notes, hasLength(2));
    expect(limited.omittedNotes, 4);
    expect(
      limited.edges.every(
        (edge) =>
            limited.notes.containsKey(edge.source) &&
            limited.notes.containsKey(edge.target),
      ),
      isTrue,
    );
  });

  test(
      'force layout is stable, finite, handles reverse edges, and is independent of semantic layout',
      () {
    const input = NoteGraphLayoutInput(
      ['a', 'b', 'c'],
      [('a', 'b'), ('b', 'a'), ('b', 'c')],
    );
    expect(layoutNoteGraph(input), layoutNoteGraph(input));
    final layout = layoutNoteGraph(input);
    expect(
      layout.values.every((point) => point.dx.isFinite && point.dy.isFinite),
      isTrue,
    );
    expect(layout.values.toSet(), hasLength(3));
    expect(layoutNoteGraph(const NoteGraphLayoutInput([], [])), isEmpty);
  });

  test(
      'index graph does not read any document content until an edge is inspected',
      () async {
    var bodyReads = 0;
    final cubit = NoteGraphCubit(
      workspaceId: 'ws',
      loadViews: () async => [note('a'), note('b')],
      loadLinks: () async =>
          DocumentLinksPB(indexedPages: 2, outgoing: [link('a', 'b')]),
      loadExcerpt: (_, __) async {
        bodyReads++;
        return 'live passage';
      },
    );
    await cubit.refresh();
    expect(cubit.state.data.edges, hasLength(1));
    expect(cubit.state.incomplete, isFalse);
    expect(bodyReads, 0);
    expect(await cubit.excerpt('a', 'a-block'), 'live passage');
    expect(await cubit.excerpt('a', 'a-block'), 'live passage');
    expect(await cubit.excerpt('private', 'secret-block'), isEmpty);
    expect(bodyReads, 1);
    await cubit.close();
  });

  test('permission refresh drops unreadable notes and late snippets', () async {
    var allowed = true;
    final pending = Completer<String>();
    final cubit = NoteGraphCubit(
      workspaceId: 'ws',
      loadViews: () async => [note('b'), if (allowed) note('a')],
      loadLinks: () async =>
          DocumentLinksPB(indexedPages: 2, outgoing: [link('a', 'b')]),
      loadExcerpt: (_, __) => pending.future,
    );
    await cubit.refresh();
    final excerpt = cubit.excerpt('a', 'a-block');
    allowed = false;
    await cubit.refresh();
    pending.complete('private text');
    expect(await excerpt, isEmpty);
    expect(cubit.state.data.edges, isEmpty);
    expect(cubit.state.data.notes.containsKey('a'), isFalse);
    await cubit.close();
  });

  test('index failure is retryable and incomplete coverage is explicit',
      () async {
    var fail = true;
    final cubit = NoteGraphCubit(
      workspaceId: 'ws',
      loadViews: () async => [note('a'), note('b')],
      loadLinks: () async {
        if (fail) throw StateError('unavailable');
        return DocumentLinksPB(
          indexedPages: 1,
          truncated: true,
          outgoing: [link('a', 'b')],
        );
      },
    );
    await cubit.refresh();
    expect(cubit.state.error, isTrue);
    fail = false;
    await cubit.refresh();
    expect(cubit.state.error, isFalse);
    expect(cubit.state.incomplete, isTrue);
    expect(cubit.state.truncated, isTrue);
    await cubit.close();
  });

  test('only this workspace link updates refresh the independent graph',
      () async {
    var reads = 0;
    final cubit = NoteGraphCubit(
      workspaceId: 'ws',
      loadViews: () async => [note('a')],
      loadLinks: () async {
        reads++;
        return DocumentLinksPB(indexedPages: 1);
      },
    );
    cubit.start();
    await Future<void>.delayed(Duration.zero);
    final initial = reads;
    RustStreamReceiver.shared.observable.add(
      SubscribeObject(
        source: 'Document',
        id: 'other',
        ty: DocumentNotification.DidUpdateLinks.value,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(reads, initial);
    RustStreamReceiver.shared.observable.add(
      SubscribeObject(
        source: 'Document',
        id: 'ws',
        ty: DocumentNotification.DidUpdateLinks.value,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(reads, initial + 1);
    await cubit.close();
  });

  test('closing while the index is loading discards its result', () async {
    final pending = Completer<DocumentLinksPB>();
    final cubit = NoteGraphCubit(
      workspaceId: 'ws',
      loadViews: () async => [note('a')],
      loadLinks: () => pending.future,
    );
    final refresh = cubit.refresh();
    await Future<void>.delayed(Duration.zero);
    await cubit.close();
    pending.complete(DocumentLinksPB());
    await refresh;
    expect(cubit.isClosed, isTrue);
  });
}
