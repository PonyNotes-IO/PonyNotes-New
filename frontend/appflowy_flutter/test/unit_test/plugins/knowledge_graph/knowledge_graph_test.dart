import 'dart:async';
import 'dart:convert';

import 'package:appflowy/plugins/knowledge_graph/application/knowledge_graph_cubit.dart';
import 'package:appflowy/plugins/knowledge_graph/application/knowledge_graph_data.dart';
import 'package:appflowy/plugins/knowledge_graph/presentation/knowledge_graph_layout.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter_test/flutter_test.dart';

ViewPB page(
  String id, {
  ViewLayoutPB? layout,
  String parent = 'workspace',
  String extra = '',
}) =>
    ViewPB(
      id: id,
      name: id,
      parentViewId: parent,
      layout: layout ?? ViewLayoutPB.Document,
      extra: extra,
    );

DocumentDataPB document(
  Map<String, (String, dynamic)> blocks, {
  List<dynamic> text = const [],
}) =>
    DocumentDataPB()
      ..blocks.addAll({
        for (final entry in blocks.entries)
          entry.key: BlockPB(
            id: entry.key,
            ty: entry.value.$1,
            data: jsonEncode(entry.value.$2),
          ),
      })
      ..meta = (MetaPB()..textMap['text'] = jsonEncode(text));

void main() {
  test(
      'includes only documents, excluding spaces, handwriting and other layouts',
      () {
    final builder = KnowledgeGraphBuilder(
      [
        page('workspace'),
        page('space', extra: '{"is_space":true}'),
        for (final layout in ViewLayoutPB.values)
          page(layout.name, layout: layout),
        page('handwriting', extra: '{"view_type":"handwriting_saber"}'),
        page('nested', parent: 'Document'),
      ],
      workspaceId: 'workspace',
    );
    final graph = builder.build();
    expect(graph.nodes.map((node) => node.id).toSet(), {'Document', 'nested'});
    expect(
      graph.edges,
      contains(
        const GraphEdge('Document', 'nested', GraphEdgeKind.hierarchy),
      ),
    );
    expect(graph.nodes.map((node) => node.id), isNot(contains('space')));
    expect(graph.nodes.map((node) => node.id), isNot(contains('workspace')));
  });

  test(
      'reads rich-text mentions, subpages and internal links; ignores missing targets and self links',
      () {
    final a = page('a');
    final builder = KnowledgeGraphBuilder(
      [a, page('b'), page('c'), page('d')],
      workspaceId: 'workspace',
    );
    builder.addDocument(
      a,
      document(
        {
          'child': ('sub_page', {'view_id': 'c'}),
        },
        text: [
          {
            'insert': '\$',
            'attributes': {
              'mention': {'type': 'page', 'page_id': 'b'},
            },
          },
          {
            'insert': 'link',
            'attributes': {'href': 'ponynotes://open?viewId=d'},
          },
          {
            'insert': '\$',
            'attributes': {
              'mention': {'page_id': 'b'},
            },
          },
          {
            'insert': '\$',
            'attributes': {
              'mention': {'page_id': 'private-other-user'},
            },
          },
          {
            'insert': '\$',
            'attributes': {
              'mention': {'page_id': 'a'},
            },
          },
          {
            'insert': 'external',
            'attributes': {
              'href': 'https://example.com/?viewId=private-other-user',
            },
          },
        ],
      ),
    );
    expect(builder.build().edges.toSet(), {
      const GraphEdge('a', 'b', GraphEdgeKind.reference),
      const GraphEdge('a', 'c', GraphEdgeKind.reference),
      const GraphEdge('a', 'd', GraphEdgeKind.reference),
    });
    builder.addDocument(
      a,
      DocumentDataPB()..blocks['bad'] = BlockPB(id: 'bad', data: 'bad JSON'),
    );
    expect(builder.build().nodes, hasLength(4));
  });

  test('reciprocal references and parent links produce one document connection',
      () {
    final a = page('a');
    final b = page('b', parent: 'a');
    final builder = KnowledgeGraphBuilder(
      [a, b, page('unrelated')],
      workspaceId: 'workspace',
    );
    builder.addDocument(
      a,
      document({
        'mention-b': (
          'paragraph',
          {
            'delta': [
              {
                'insert': '\$',
                'attributes': {
                  'mention': {'type': 'page', 'page_id': 'b'},
                },
              },
            ],
          }
        ),
      }),
    );
    builder.addDocument(
      b,
      document({
        'link-a': ('link_preview', {'url': 'ponynotes://open?viewId=a'}),
      }),
    );
    final graph = builder.build();
    expect(graph.edges, hasLength(1));
    expect({graph.edges.single.source, graph.edges.single.target}, {'a', 'b'});
    expect(graph.edges.single.kind, GraphEdgeKind.reference);
    expect(graph.filtered(hierarchy: false).edges, hasLength(1));
    expect(
      graph.filtered(orphans: false).nodes.map((node) => node.id).toSet(),
      {'a', 'b'},
    );
  });

  test('embedded images, PDFs and other attachments never become graph nodes',
      () {
    final a = page('a');
    final b = page('b');
    final builder = KnowledgeGraphBuilder([a, b], workspaceId: 'workspace');
    builder.addDocument(
      a,
      document({
        'pdf': (
          'file',
          {'url': 'https://files/report.pdf', 'name': 'Report.pdf'}
        ),
        'video': ('video', {'url': 'https://files/movie.mp4'}),
        'audio': ('audio', {'url': 'https://files/audio.mp3'}),
        'archive': ('file', {'url': 'https://files/archive.zip'}),
        'images': (
          'multi_image',
          {
            'images': jsonEncode({
              'images': [
                {'url': 'https://files/photo.png'},
              ],
            }),
          }
        ),
      }),
    );
    builder.addDocument(
      b,
      document({
        'file': ('file', {'url': 'https://files/report.pdf'}),
      }),
    );
    final graph = builder.build();
    expect(graph.nodes.map((node) => node.id).toSet(), {'a', 'b'});
    expect(graph.edges, isEmpty);
  });

  test('filters preserve only visible document endpoints', () {
    final a = page('a');
    final builder = KnowledgeGraphBuilder(
      [a, page('b', parent: 'a'), page('orphan')],
      workspaceId: 'workspace',
    );
    builder.addDocument(
      a,
      document({
        'pdf': ('file', {'url': '/report.pdf'}),
      }),
    );
    final graph = builder.build();
    expect(graph.nodes, hasLength(3));
    expect(
      graph.filtered(orphans: false).nodes.map((node) => node.id),
      isNot(contains('orphan')),
    );
    expect(
      graph.filtered(hierarchy: false, orphans: false).nodes,
      isEmpty,
    );
    final result = graph.filtered(query: 'ORPHAN');
    expect(result.nodes.single.label, 'orphan');
    expect(result.edges, isEmpty);
  });

  test('repulsion separates neighbors and overlaps with equal opposite forces',
      () {
    final close = knowledgeGraphRepulsion([Offset.zero, const Offset(30, 0)]);
    final distant = knowledgeGraphRepulsion([Offset.zero, const Offset(90, 0)]);
    expect(close.first.dx, lessThan(distant.first.dx));
    expect(distant.first.dx, lessThan(0));
    expect(close.first + close.last, Offset.zero);
    final overlap = knowledgeGraphRepulsion([Offset.zero, Offset.zero]);
    expect(overlap.first.distance.isFinite, isTrue);
    expect(overlap.first.distance, greaterThan(0));
    expect(overlap.first + overlap.last, Offset.zero);
    expect(
      knowledgeGraphRepulsion([Offset.zero, const Offset(180, 0)]),
      [Offset.zero, Offset.zero],
    );
    expect(knowledgeGraphRepulsion([]), isEmpty);
  });

  test(
      'layout is deterministic and finite for a large workspace and an empty graph',
      () {
    expect(layoutKnowledgeGraph(const GraphLayoutInput([], [])), isEmpty);
    final input = GraphLayoutInput(
      List.generate(500, (i) => '$i'),
      List.generate(499, (i) => ('$i', '${i + 1}')),
    );
    final positions = layoutKnowledgeGraph(input);
    expect(positions, hasLength(500));
    expect(
      positions.values.every(
        (p) => p.dx.isFinite && p.dy.isFinite && p.dx >= 0 && p.dy >= 0,
      ),
      isTrue,
    );
    expect(layoutKnowledgeGraph(input), positions);
  });

  test(
      'a failed document keeps all nodes; unsupported layouts are never read as documents',
      () async {
    final reads = <String>[];
    final cubit = KnowledgeGraphCubit(
      workspaceId: 'workspace',
      loadViews: () async => [
        page('a'),
        page('hand', extra: '{"view_type":"handwriting_saber"}'),
        page('board', layout: ViewLayoutPB.Whiteboard),
      ],
      loadDocument: (id) async {
        reads.add(id);
        return null;
      },
    );
    await cubit.refresh();
    expect(cubit.state.data.nodes.map((node) => node.id), ['a']);
    expect(cubit.state.failedDocuments, 1);
    expect(cubit.state.loading, isFalse);
    expect(cubit.state.indexing, isFalse);
    expect(reads, ['a']);
    await cubit.close();
  });

  test('closing during a workspace read discards the stale result', () async {
    final pending = Completer<List<ViewPB>>();
    final cubit = KnowledgeGraphCubit(
      workspaceId: 'workspace',
      loadViews: () => pending.future,
    );
    final refresh = cubit.refresh();
    await cubit.close();
    pending.complete([page('old-workspace')]);
    await refresh;
    expect(cubit.state.data.nodes, isEmpty);
  });

  test('workspace load failure can be retried', () async {
    var fail = true;
    final cubit = KnowledgeGraphCubit(
      workspaceId: 'workspace',
      loadViews: () async {
        if (fail) throw StateError('offline');
        return [];
      },
    );
    await cubit.refresh();
    expect(cubit.state.error, isTrue);
    fail = false;
    await cubit.refresh();
    expect(cubit.state.error, isFalse);
    expect(cubit.state.loading, isFalse);
    await cubit.close();
  });
}
