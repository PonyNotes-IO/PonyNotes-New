import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/features/ai_internal/application/internal_ai_service.dart';
import 'package:appflowy/plugins/knowledge_graph/application/knowledge_graph_cubit.dart';
import 'package:appflowy/plugins/knowledge_graph/application/knowledge_graph_data.dart';
import 'package:appflowy/plugins/knowledge_graph/application/knowledge_graph_extraction.dart';
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

const evidence = 'Alice founded PonyNotes.';

Map<String, dynamic> extraction() => {
      'node': <dynamic>[
        {
          'name': 'Alice',
          'type': 'Person',
          'attributes': ['Founder'],
        },
        {
          'name': 'PonyNotes',
          'type': 'Product',
          'attributes': ['Note app'],
        },
      ],
      'relation': <dynamic>[
        {
          'node1': 'Alice',
          'node2': 'PonyNotes',
          'type': 'founded',
          'evidence': evidence,
        },
      ],
    };

DocumentDataPB note(String text) => document({
      'paragraph': (
        'paragraph',
        {
          'delta': [
            {'insert': text},
          ],
        }
      ),
    });

void main() {
  test('validates graph evidence and never accepts model-supplied source IDs',
      () {
    final raw = extraction();
    (raw['node'] as List).add({'name': 'invented', 'type': 'Person'});
    (raw['relation'] as List).addAll([
      {
        'node1': 'Alice',
        'node2': 'missing',
        'type': 'owns',
        'evidence': evidence,
      },
      {
        'node1': 'Alice',
        'node2': 'Alice',
        'type': 'owns',
        'evidence': evidence,
      },
      {
        'node1': 'Alice',
        'node2': 'PonyNotes',
        'type': 'owns',
        'evidence': 'fabricated',
      },
      {
        'node1': 'Alice',
        'node2': 'PonyNotes',
        'type': 'owns',
        'evidence': 'Alice',
      },
    ]);
    final graph =
        parseGraphExtraction('```json\n${jsonEncode(raw)}\n```', evidence);
    expect(graph['node'], hasLength(2));
    expect(graph['relation'], hasLength(1));
    expect(
      () => parseGraphExtraction('not json', evidence),
      throwsFormatException,
    );
    expect(
      () => parseGraphExtraction('{"node":[]}', evidence),
      throwsFormatException,
    );
    expect(
      () => parseGraphExtraction(
        jsonEncode({
          'node': List.filled(101, {}),
          'relation': [],
        }),
        evidence,
      ),
      throwsFormatException,
    );
  });

  test(
      'chunks follow block order and ignore deleted rich text and attachment data',
      () {
    final doc = DocumentDataPB(pageId: 'root')
      ..blocks.addAll({
        'root': BlockPB(id: 'root', childrenId: 'children', data: '{}'),
        'second': BlockPB(
          id: 'second',
          externalType: 'text',
          externalId: 't2',
          data: '{}',
        ),
        'first': BlockPB(
          id: 'first',
          externalType: 'text',
          externalId: 't1',
          data: '{}',
        ),
        'image': BlockPB(
          id: 'image',
          ty: 'image',
          data: '{"url":"https://private"}',
        ),
      })
      ..meta = MetaPB(
        childrenMap: {
          'children':
              ChildrenPB(children: ['first', 'second', 'image', 'root']),
        },
        textMap: {
          't1': jsonEncode([
            {'insert': 'Alice founded'},
          ]),
          't2': jsonEncode([
            {'insert': 'PonyNotes.'},
          ]),
          'deleted': jsonEncode([
            {'insert': 'deleted content'},
          ]),
        },
      );
    final chunks = graphDocumentChunks('page', doc);
    expect(chunks.single.text, 'Alice founded\nPonyNotes.');
    expect(chunks.single.blockId, 'first');
    expect(chunks.single.viewId, 'page');
    expect(chunks.single.blockFor('PonyNotes.'), 'second');
    expect(chunks.single.blockFor('Alice founded'), 'first');
    final longText = '${'a' * 3999}😀${'b' * 4100}';
    final longChunks = graphDocumentChunks('page', note(longText));
    expect(longChunks.every((c) => c.text.length <= 4000), isTrue);
    expect(longChunks.map((c) => c.text).join(), longText);
    expect(
      graphDocumentFingerprint(chunks),
      isNot(graphDocumentFingerprint(longChunks)),
    );
  });

  test(
      'merges entities and provenance while preserving directed relation types',
      () {
    final builder = KnowledgeGraphBuilder(
      [page('a'), page('b'), page('c')],
      workspaceId: 'workspace',
    );
    for (final id in ['a', 'b']) {
      builder.addExtraction(
        page(id),
        GraphSource(viewId: id, blockId: 'block', text: evidence),
        extraction(),
      );
    }
    final reverse = extraction();
    reverse['relation'] = [
      {
        'node1': 'PonyNotes',
        'node2': 'Alice',
        'type': 'created by',
        'evidence': evidence,
      },
      {
        'node1': 'Alice',
        'node2': 'PonyNotes',
        'type': 'works on',
        'evidence': evidence,
      },
    ];
    builder.addExtraction(
      page('a'),
      const GraphSource(viewId: 'a', blockId: 'second', text: evidence),
      reverse,
    );
    final data = builder.build();
    expect(data.nodes.where((n) => n.entityType != null), hasLength(2));
    final relations =
        data.edges.where((e) => e.kind == GraphEdgeKind.relation).toList();
    expect(relations, hasLength(3));
    expect(relations.first.sources, hasLength(2));
    expect(
      data.filtered(query: 'Alice', entitiesOnly: true).nodes,
      hasLength(2),
    );
    expect(data.filtered(entityType: 'Person').nodes.single.label, 'Alice');
    expect(
      data.filtered(focus: 'entity:alice').nodes.map((n) => n.id),
      isNot(contains('c')),
    );
  });

  test(
      'extraction caches unchanged pages and removes edited, deleted and unreadable sources',
      () async {
    final directory = await Directory.systemTemp.createTemp('pony-graph-test-');
    addTearDown(() => directory.delete(recursive: true));
    final cache = GraphExtractionCache(
      userId: 'user',
      workspaceId: 'workspace',
      directory: () async => directory,
    );
    var views = [page('a'), page('b')];
    var text = evidence;
    var reads = 0;
    var unavailable = false;
    KnowledgeGraphCubit create({GraphExtractionCache? store}) =>
        KnowledgeGraphCubit(
          workspaceId: 'workspace',
          cache: store ?? cache,
          loadViews: () async => views,
          loadDocument: (_) async => unavailable ? null : note(text),
          extractChunk: (_) async {
            reads++;
            return extraction();
          },
        );
    final first = create();
    await first.refresh();
    expect(reads, 0); // Refresh never sends text to a model.
    await first.extract();
    expect(reads, 2);
    expect(
      first.state.data.nodes.where((n) => n.entityType != null),
      hasLength(2),
    );
    await first.close();
    final second = create();
    await second.refresh();
    expect(
      second.state.data.edges
          .where((e) => e.kind == GraphEdgeKind.relation)
          .single
          .sources,
      hasLength(2),
    );
    await second.extract();
    expect(reads, 2);
    views = [page('a')];
    await second.refresh();
    expect(
      second.state.data.edges
          .where((e) => e.kind == GraphEdgeKind.relation)
          .single
          .sources
          .single
          .viewId,
      'a',
    );
    text = 'Changed text without the old facts.';
    await second.refresh();
    expect(second.state.data.nodes.where((n) => n.entityType != null), isEmpty);
    text = evidence;
    await second.refresh();
    await second.extract();
    unavailable = true;
    await second.refresh();
    expect(second.state.failedDocuments, 1);
    expect(second.state.data.nodes.where((n) => n.entityType != null), isEmpty);
    await second.close();
    unavailable = false;
    final other = create(
      store: GraphExtractionCache(
        userId: 'another-user',
        workspaceId: 'workspace',
        directory: () async => directory,
      ),
    );
    await other.refresh();
    expect(other.state.data.nodes.where((n) => n.entityType != null), isEmpty);
    await other.close();
    final otherWorkspace = GraphExtractionCache(
      userId: 'user',
      workspaceId: 'another-workspace',
      directory: () async => directory,
    );
    expect(await otherWorkspace.load(), isEmpty);
  });

  test(
      'partial extraction retries failures, and cancel or close discards in-flight output',
      () async {
    var fail = true;
    var calls = 0;
    final cubit = KnowledgeGraphCubit(
      workspaceId: 'workspace',
      loadViews: () async => [page('a'), page('b')],
      loadDocument: (_) async => note(evidence),
      extractChunk: (source) async {
        calls++;
        if (source.viewId == 'b' && fail) {
          throw const FormatException('bad model response');
        }
        return extraction();
      },
    );
    await cubit.refresh();
    await cubit.extract();
    expect(cubit.state.failedExtractions, 1);
    expect(cubit.state.extractionError, 'invalidResponse');
    fail = false;
    await cubit.extract();
    expect(calls, 3); // Already successful page a is not billed again.
    expect(cubit.state.failedExtractions, 0);
    await cubit.close();
    for (final close in [false, true]) {
      final pending = Completer<Map<String, dynamic>>();
      final waiting = KnowledgeGraphCubit(
        workspaceId: 'workspace',
        loadViews: () async => [page('a')],
        loadDocument: (_) async => note(evidence),
        extractChunk: (_) => pending.future,
      );
      await waiting.refresh();
      final run = waiting.extract();
      if (close) {
        await waiting.close();
      } else {
        waiting.cancelExtraction();
      }
      // Stop must settle before a provider finishes responding.
      await run.timeout(const Duration(seconds: 1));
      pending.complete(extraction());
      expect(
        waiting.state.data.nodes.where((n) => n.entityType != null),
        isEmpty,
      );
      if (!close) {
        expect(waiting.state.extracting, isFalse);
        await waiting.close();
      }
    }
  });

  test(
      'model quota failures stop the batch without silently reporting empty results',
      () async {
    var calls = 0;
    final cubit = KnowledgeGraphCubit(
      workspaceId: 'workspace',
      loadViews: () async => [page('a'), page('b')],
      loadDocument: (_) async => note(evidence),
      extractChunk: (_) async {
        calls++;
        throw InternalAiException(InternalAiErrorKind.quotaExhausted, 'quota');
      },
    );
    await cubit.refresh();
    await cubit.extract();
    expect(calls, 1);
    expect(cubit.state.extractionError, 'quotaExhausted');
    expect(cubit.state.extracting, isFalse);
    await cubit.close();
  });

  test('an edit during extraction cancels stale output and reloads the notes',
      () async {
    final pending = Completer<Map<String, dynamic>>();
    final secondRead = Completer<void>();
    var reads = 0;
    final cubit = KnowledgeGraphCubit(
      workspaceId: 'workspace',
      loadViews: () async => [page('a')],
      loadDocument: (_) async {
        reads++;
        if (reads == 2) secondRead.complete();
        return note(reads == 1 ? evidence : 'Changed content.');
      },
      extractChunk: (_) => pending.future,
    );
    await cubit.refresh();
    final run = cubit.extract();
    await cubit.refresh();
    await run.timeout(const Duration(seconds: 1));
    await secondRead.future;
    await Future<void>.delayed(Duration.zero);
    pending.complete(extraction());
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.data.nodes.where((n) => n.entityType != null), isEmpty);
    expect(cubit.state.extracting, isFalse);
    await cubit.close();
  });

  test(
      'cache write failure keeps the extracted graph and reports persistence failure',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('pony-graph-write-test-');
    addTearDown(() => directory.delete(recursive: true));
    final blocker = File('${directory.path}/blocked');
    await blocker.writeAsString('not a directory');
    final cubit = KnowledgeGraphCubit(
      workspaceId: 'workspace',
      cache: GraphExtractionCache(
        userId: 'user',
        workspaceId: 'workspace',
        directory: () async => Directory(blocker.path),
      ),
      loadViews: () async => [page('a')],
      loadDocument: (_) async => note(evidence),
      extractChunk: (_) async => extraction(),
    );
    await cubit.refresh();
    await cubit.extract();
    expect(cubit.state.cacheError, isTrue);
    expect(
      cubit.state.data.nodes.where((n) => n.entityType != null),
      hasLength(2),
    );
    await cubit.close();
  });

  test('handwriting graph includes backlinks without reading ink as a document',
      () async {
    final reads = <String>[];
    final hand = page(
      'hand',
      parent: 'parent',
      extra: '{"view_type":"handwriting_saber"}',
    );
    final cubit = KnowledgeGraphCubit(
      workspaceId: 'workspace',
      focusViewId: hand.id,
      loadViews: () async => [
        hand,
        page('parent'),
        page('child', parent: 'hand'),
        page('child-hand', parent: 'hand', extra: hand.extra),
        page('backlink'),
        page('unrelated'),
        page('other-hand', extra: hand.extra),
      ],
      loadDocument: (id) async {
        reads.add(id);
        return document({
          if (id == 'backlink') 'link': ('sub_page', {'view_id': 'hand'}),
        });
      },
    );
    addTearDown(cubit.close);
    await cubit.refresh();
    expect(reads, isNot(contains('hand')));
    expect(reads, isNot(contains('other-hand')));
    expect(cubit.state.failedDocuments, 0);
    expect(
      cubit.state.data
          .filtered(focus: hand.id)
          .nodes
          .map((node) => node.id)
          .toSet(),
      {'hand', 'parent', 'child', 'child-hand', 'backlink'},
    );
    expect(
      KnowledgeGraphBuilder(
        [page('public')],
        workspaceId: 'workspace',
        focusViewId: 'inaccessible',
      ).build().nodes.map((node) => node.id),
      isNot(contains('inaccessible')),
    );
  });

  test('note graph extracts only its source and keeps workspace cache separate',
      () async {
    final extracted = <String>[];
    final cubit = KnowledgeGraphCubit(
      workspaceId: 'workspace',
      focusViewId: 'note',
      loadViews: () async => [page('note'), page('other')],
      loadDocument: (_) async => document({
        'text': (
          'paragraph',
          {
            'delta': [
              {'insert': evidence},
            ],
          },
        ),
      }),
      extractChunk: (chunk) async {
        extracted.add(chunk.viewId);
        return extraction();
      },
    );
    addTearDown(cubit.close);
    await cubit.refresh();
    await cubit.extract();
    expect(extracted, ['note']);
    final directory = await Directory.systemTemp.createTemp('note-graph-cache');
    addTearDown(() => directory.delete(recursive: true));
    final workspaceCache = GraphExtractionCache(
      userId: 'user',
      workspaceId: 'workspace',
      directory: () async => directory,
    );
    final noteCache = GraphExtractionCache(
      userId: 'user',
      workspaceId: 'workspace',
      viewId: 'note',
      directory: () async => directory,
    );
    await workspaceCache.save({'workspace-result': true});
    await noteCache.save({'note-result': true});
    expect(await workspaceCache.load(), {'workspace-result': true});
    expect(await noteCache.load(), {'note-result': true});
  });

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
