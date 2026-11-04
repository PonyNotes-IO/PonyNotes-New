import 'dart:async';
import 'dart:convert';

import 'package:appflowy/features/mcp/application/mcp_tools.dart';
import 'package:appflowy/features/mcp/application/mcp_permissions.dart';
import 'package:appflowy/features/mcp/application/mcp_audit_log.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/application/note_link_data.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/mention/mention_block.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> body(CallToolResult result) =>
    jsonDecode((result.content.single as TextContent).text)
        as Map<String, dynamic>;
CallToolResult failure(String code) => CallToolResult(
      isError: true,
      content: [
        TextContent(
          text: jsonEncode({
            'error': {'code': code, 'message': code},
          }),
        ),
      ],
    );

class _Documents extends DocumentService {
  final saved = <String, DocumentDataPB>{};
  final reads = <String>[];
  final closed = <String>[];
  @override
  Future<FlowyResult<DocumentDataPB, FlowyError>> openDocument({
    required String documentId,
    String? workspaceId,
  }) =>
      getDocument(documentId: documentId, workspaceId: workspaceId);
  @override
  Future<FlowyResult<DocumentDataPB, FlowyError>> getDocument({
    required String documentId,
    String? workspaceId,
  }) async {
    reads.add(documentId);
    final document = saved[documentId];
    return document == null
        ? FlowyResult.failure(FlowyError(msg: 'not found'))
        : FlowyResult.success(
            DocumentDataPB.fromBuffer(document.writeToBuffer()),
          );
  }

  @override
  Future<FlowyResult<void, FlowyError>> closeDocument({
    required String viewId,
  }) async {
    closed.add(viewId);
    return FlowyResult.success(null);
  }
}

/// In-memory persistence adapter; exercises the full tool handler and verification predicate.
class _ReferenceTools extends McpTools {
  _ReferenceTools(this.fixture, {bool agent = false})
      : super(
          endpoint: 'test',
          version: 'test',
          documentService: fixture.documents,
          noteLinks: fixture.dependencies,
          isAgentChannel: agent,
        );
  final _Fixture fixture;
  @override
  Future<CallToolResult?> persistDocument({
    required String pageId,
    required String workspaceId,
    required EditorState state,
    required Transaction transaction,
    required bool Function(DocumentDataPB) verify,
  }) async {
    if (fixture.rejectWrites) return failure('write_failed');
    fixture.writes.add(pageId);
    await state.apply(transaction);
    final saved = DocumentDataPBFromTo.fromDocument(state.document)!;
    if (!fixture.staleSave) fixture.documents.saved[pageId] = saved;
    if (!verify(fixture.documents.saved[pageId]!)) {
      return failure('write_unconfirmed');
    }
    return null;
  }
}

class _Fixture {
  _Fixture() {
    for (final id in ['a', 'b', 'isolated']) {
      views[id] = ViewPB(
        id: id,
        name: 'Note $id',
        workspaceId: 'ws',
        layout: ViewLayoutPB.Document,
      );
      final node = paragraphNode(
        delta: Delta()..insert(id == 'a' ? 'before 😀 after' : 'passage $id'),
      )..id = '$id-block';
      documents.saved[id] = DocumentDataPBFromTo.fromDocument(
        Document(root: pageNode(children: [node])),
      )!;
    }
  }
  final documents = _Documents();
  final views = <String, ViewPB>{};
  final writes = <String>[];
  final repairCalls = <String>[];
  final openedGraphs = <String?>[];
  final openedReferences = <(String, String?)>[];
  final extraEdges = <NoteLinkPB>[];
  final writeChecks = <String>[];
  bool rejectWrites = false;
  bool staleSave = false;
  bool failRepair = false;
  bool locked = false;
  bool guest = false;
  bool expirePermission = false;
  bool editBeforeCommit = false;
  int viewReads = 0;

  McpNoteLinkDependencies get dependencies => McpNoteLinkDependencies(
        validateWorkspace: (workspace) async =>
            workspace == 'ws' ? null : failure('workspace_mismatch'),
        loadViews: () async {
          viewReads++;
          if (editBeforeCommit && viewReads > 1) {
            final node = paragraphNode(text: 'collaborator changed this')
              ..id = 'a-block';
            documents.saved['a'] = DocumentDataPBFromTo.fromDocument(
              Document(root: pageNode(children: [node])),
            )!;
          }
          if (expirePermission && viewReads > 1) {
            return views.values.where((view) => view.id != 'b').toList();
          }
          return views.values.toList();
        },
        requireWritable: (_, page) async {
          writeChecks.add(page);
          return guest
              ? failure('permission_denied')
              : locked
                  ? failure('page_locked')
                  : null;
        },
        readLinks: (_, page, repair) async {
          if (repair) {
            repairCalls.add(page);
            if (failRepair) throw StateError('index unavailable');
          }
          final edges = <NoteLinkPB>[...extraEdges];
          for (final entry in documents.saved.entries) {
            final editor = EditorState(document: entry.value.toDocument()!);
            edges.addAll(editorOutgoingLinks(entry.key, editor));
            editor.dispose();
          }
          return DocumentLinksPB(
            indexedPages: views.length,
            incoming: page.isEmpty
                ? []
                : edges.where(
                    (edge) => edge.dstPageId == page && edge.srcPageId != page,
                  ),
            outgoing: page.isEmpty
                ? edges
                : edges.where((edge) => edge.srcPageId == page),
          );
        },
        openGraph: (view) async => openedGraphs.add(view?.id),
        openReference: (view, block) async =>
            openedReferences.add((view.id, block)),
      );

  Future<CallToolResult> call(
    String tool, [
    Map<String, dynamic> args = const {},
  ]) =>
      _ReferenceTools(this).executeTool(tool, {'workspace_id': 'ws', ...args});
  String text(String page, String block) =>
      documents.saved[page]!.buildNode(block)!.delta!.toPlainText();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    Log.shared.disableLog = true;
  });

  test(
      'MCP registry exposes six new tools with accurate read and write annotations',
      () {
    final specs = McpTools(endpoint: 'test', version: 'test').toolSpecs;
    expect(specs.map((spec) => spec.name).toSet(), hasLength(36));
    for (final name in [
      'insert_note_reference',
      'remove_note_reference',
      'get_reference_context',
      'get_note_graph',
      'open_note_reference',
      'open_note_graph',
    ]) {
      final spec = specs.singleWhere((spec) => spec.name == name);
      expect(spec.inputSchema.toJson()['additionalProperties'], isFalse);
      expect(
        spec.readOnly,
        name == 'get_reference_context' || name == 'get_note_graph',
      );
    }
    expect(
      specs
          .singleWhere((spec) => spec.name == 'remove_note_reference')
          .destructive,
      isTrue,
    );
  });

  test(
      'paragraph insertion round trips through source text, backlinks, contexts and graph',
      () async {
    final fixture = _Fixture();
    final targetBefore = fixture.documents.saved['b']!.writeToBuffer();
    final offset = 'before 😀 '.runes.length;
    final result = await fixture.call('insert_note_reference', {
      'page_id': 'a',
      'block_id': 'a-block',
      'offset': offset,
      'target_page_id': 'b',
      'target_block_id': 'b-block',
      'expected_source_text': 'before 😀 after',
    });
    expect(result.isError, isFalse, reason: body(result).toString());
    expect(body(result)['kind'], 'block_ref');
    expect(body(result)['index_updated'], isTrue);
    expect(fixture.text('a', 'a-block'), r'before 😀 $after');
    expect(fixture.writes, ['a']);
    expect(fixture.documents.saved['b']!.writeToBuffer(), targetBefore);
    expect(fixture.documents.closed, contains('a'));
    final backlinks = body(
      await fixture.call(
        'get_backlinks',
        {'page_id': 'b', 'block_id': 'b-block', 'include_context': true},
      ),
    );
    expect(backlinks['incoming_note_count'], 1);
    expect(backlinks['backlinks'].single['char_offset'], offset);
    expect(backlinks['backlinks'].single['to_block_id'], 'b-block');
    expect(backlinks['backlinks'].single['source_excerpt'], contains('Note b'));
    final context = body(
      await fixture.call('get_reference_context', {
        'page_id': 'a',
        'block_id': 'a-block',
        'offset': offset,
        'target_page_id': 'b',
        'target_block_id': 'b-block',
      }),
    );
    expect(context['reference_exists'], isTrue);
    expect(context['target_excerpt'], 'passage b');
    final graph = body(await fixture.call('get_note_graph'));
    expect(graph['nodes'], hasLength(3));
    expect(
      graph['nodes'].singleWhere(
        (dynamic node) => node['page_id'] == 'isolated',
      )['is_isolated'],
      isTrue,
    );
    expect(graph['edges'].single['block_reference_count'], 1);
  });

  test(
      'new-paragraph whole-note references do not create a target or folder relation',
      () async {
    final fixture = _Fixture();
    final result = await fixture
        .call('insert_note_reference', {'page_id': 'a', 'target_page_id': 'b'});
    expect(result.isError, isFalse, reason: body(result).toString());
    expect(body(result)['kind'], 'reference');
    final block = body(result)['block_id'] as String;
    expect(block, isNot('a-block'));
    expect(fixture.text('a', block), r'$');
    expect(fixture.views.keys, unorderedEquals(['a', 'b', 'isolated']));
    expect(
      body(
        await fixture.call('get_note_graph', {'blocks_only': true}),
      )['edges'],
      isEmpty,
    );
  });

  test(
      'replacement counts Unicode characters and preserves adjacent formatting',
      () async {
    final fixture = _Fixture();
    final result = await fixture.call('insert_note_reference', {
      'page_id': 'a',
      'block_id': 'a-block',
      'target_page_id': 'b',
      'offset': 7,
      'replace_length': 1,
    });
    expect(result.isError, isFalse, reason: body(result).toString());
    expect(fixture.text('a', 'a-block'), r'before $ after');
    expect(body(result)['char_offset'], 7);
  });

  test(
      'removing a paragraph reference only deletes its placeholder and updates backlinks',
      () async {
    final fixture = _Fixture();
    await fixture.call('insert_note_reference', {
      'page_id': 'a',
      'block_id': 'a-block',
      'offset': 7,
      'target_page_id': 'b',
      'target_block_id': 'b-block',
    });
    final targetBefore = fixture.documents.saved['b']!.writeToBuffer();
    final result = await fixture.call('remove_note_reference', {
      'page_id': 'a',
      'block_id': 'a-block',
      'offset': 7,
      'target_page_id': 'b',
      'target_block_id': 'b-block',
    });
    expect(result.isError, isFalse, reason: body(result).toString());
    expect(body(result)['removed'], isTrue);
    expect(fixture.text('a', 'a-block'), 'before 😀 after');
    expect(fixture.documents.saved['b']!.writeToBuffer(), targetBefore);
    expect(
      body(
        await fixture.call('get_backlinks', {'page_id': 'b'}),
      )['backlinks'],
      isEmpty,
    );
  });

  test('adjacent references to the same target remain separately indexed',
      () async {
    final fixture = _Fixture();
    for (var i = 0; i < 2; i++) {
      final result = await fixture.call('insert_note_reference', {
        'page_id': 'a',
        'block_id': 'a-block',
        'offset': 0,
        'target_page_id': 'b',
      });
      expect(result.isError, isFalse, reason: body(result).toString());
    }
    final backlinks =
        body(await fixture.call('get_backlinks', {'page_id': 'b'}));
    expect(backlinks['incoming_occurrences'], 2);
    expect(backlinks['incoming_note_count'], 1);
    expect(backlinks['backlinks'].single['occurrence'], 2);
  });

  test(
      'wrong target, stale source text, invalid positions and missing target blocks never write',
      () async {
    final fixture = _Fixture();
    for (final args in [
      {'target_block_id': 'missing'},
      {'offset': 100},
      {'offset': 0, 'replace_length': 100},
      {'expected_source_text': 'stale'},
    ]) {
      final result = await fixture.call('insert_note_reference', {
        'page_id': 'a',
        'block_id': 'a-block',
        'target_page_id': 'b',
        ...args,
      });
      expect(result.isError, isTrue);
    }
    final remove = await fixture.call('remove_note_reference', {
      'page_id': 'a',
      'block_id': 'a-block',
      'offset': 0,
      'target_page_id': 'b',
    });
    expect(body(remove)['error']['code'], 'reference_changed');
    expect(fixture.writes, isEmpty);
    expect(fixture.text('a', 'a-block'), 'before 😀 after');
  });

  test(
      'read-only source is denied, but a locked target can still be referenced',
      () async {
    final fixture = _Fixture()..guest = true;
    var result = await fixture
        .call('insert_note_reference', {'page_id': 'a', 'target_page_id': 'b'});
    expect(body(result)['error']['code'], 'permission_denied');
    fixture
      ..guest = false
      ..locked = true;
    result = await fixture
        .call('insert_note_reference', {'page_id': 'a', 'target_page_id': 'b'});
    expect(body(result)['error']['code'], 'page_locked');
    fixture.locked = false;
    fixture.views['b']!.isLocked = true;
    result = await fixture
        .call('insert_note_reference', {'page_id': 'a', 'target_page_id': 'b'});
    expect(result.isError, isFalse);
    expect(fixture.writeChecks.every((id) => id == 'a'), isTrue);
  });

  test(
      'workspace mismatch and access revoked before commit never persist a reference',
      () async {
    final fixture = _Fixture();
    final mismatch = await fixture.call(
      'insert_note_reference',
      {'workspace_id': 'other', 'page_id': 'a', 'target_page_id': 'b'},
    );
    expect(body(mismatch)['error']['code'], 'workspace_mismatch');
    fixture.expirePermission = true;
    final revoked = await fixture
        .call('insert_note_reference', {'page_id': 'a', 'target_page_id': 'b'});
    expect(body(revoked)['error']['code'], 'not_found');
    expect(fixture.writes, isEmpty);
    expect(fixture.documents.closed, contains('a'));
  });

  test(
      'a dangling reference may be removed without reading its unavailable target',
      () async {
    final fixture = _Fixture();
    await fixture.call('insert_note_reference', {
      'page_id': 'a',
      'block_id': 'a-block',
      'offset': 0,
      'target_page_id': 'b',
    });
    fixture.views.remove('b');
    fixture.documents.reads.clear();
    final result = await fixture.call('remove_note_reference', {
      'page_id': 'a',
      'block_id': 'a-block',
      'offset': 0,
      'target_page_id': 'b',
    });
    expect(result.isError, isFalse);
    expect(fixture.documents.reads, isNot(contains('b')));
  });

  test('saved content remains successful when derived index repair fails',
      () async {
    final fixture = _Fixture()..failRepair = true;
    final result = await fixture
        .call('insert_note_reference', {'page_id': 'a', 'target_page_id': 'b'});
    expect(result.isError, isFalse);
    expect(body(result)['inserted'], isTrue);
    expect(body(result)['index_updated'], isFalse);
    expect(fixture.writes, ['a']);
  });

  test('failed and unconfirmed saves never report inserted=true', () async {
    final fixture = _Fixture()..rejectWrites = true;
    var result = await fixture
        .call('insert_note_reference', {'page_id': 'a', 'target_page_id': 'b'});
    expect(body(result)['error']['code'], 'write_failed');
    fixture
      ..rejectWrites = false
      ..staleSave = true;
    result = await fixture
        .call('insert_note_reference', {'page_id': 'a', 'target_page_id': 'b'});
    expect(body(result)['error']['code'], 'write_unconfirmed');
    expect(fixture.repairCalls, isEmpty);
  });

  test(
      'graph and legacy queries filter unreadable endpoints, hierarchy, and cross-workspace views',
      () async {
    final fixture = _Fixture();
    fixture.views['b']!.parentViewId = 'a';
    fixture.views['foreign'] =
        ViewPB(id: 'foreign', name: 'secret', workspaceId: 'other');
    fixture.extraEdges.addAll([
      NoteLinkPB(
        srcPageId: 'private',
        dstPageId: 'b',
        kind: 'reference',
        label: 'private label',
      ),
      NoteLinkPB(srcPageId: 'a', dstPageId: 'foreign', kind: 'reference'),
      NoteLinkPB(srcPageId: 'a', dstPageId: 'b', kind: 'embed'),
      NoteLinkPB(srcPageId: 'a', dstPageId: 'b', kind: 'reference'),
    ]);
    for (final tool in ['get_workspace_links_graph', 'get_note_graph']) {
      final graph = body(await fixture.call(tool));
      expect(graph['nodes'], hasLength(3));
      expect(graph['edges'], hasLength(1));
      expect(jsonEncode(graph), isNot(contains('private')));
      expect(jsonEncode(graph), isNot(contains('foreign')));
    }
    final backlinks =
        body(await fixture.call('get_backlinks', {'page_id': 'b'}));
    expect(backlinks['backlinks'], hasLength(1));
    expect(backlinks['incoming_note_count'], 1);
  });

  test(
      'graph filters share the independent graph semantics and never read body text',
      () async {
    final fixture = _Fixture();
    fixture.extraEdges.addAll([
      NoteLinkPB(
        srcPageId: 'a',
        dstPageId: 'b',
        srcBlockId: 'a-block',
        dstBlockId: 'b-block',
        kind: 'block_ref',
        occurrence: 2,
      ),
      NoteLinkPB(srcPageId: 'b', dstPageId: 'a', kind: 'reference'),
    ]);
    final graph = body(
      await fixture.call(
        'get_note_graph',
        {'focus_page_id': 'b', 'direction': 'incoming', 'blocks_only': true},
      ),
    );
    expect(graph['nodes'], hasLength(2));
    expect(graph['edges'].single['from_page_id'], 'a');
    expect(graph['edges'].single['occurrence_count'], 2);
    expect(fixture.documents.reads, isEmpty);
    expect(
      body(await fixture.call('get_note_graph', {'limit': 1}))['omitted_notes'],
      2,
    );
  });

  test(
      'backlink pagination separates note counts, occurrences and returned records',
      () async {
    final fixture = _Fixture();
    fixture.extraEdges.addAll([
      for (var i = 0; i < 3; i++)
        NoteLinkPB(
          srcPageId: 'a',
          srcBlockId: 'a$i',
          dstPageId: 'b',
          kind: 'reference',
          occurrence: 2,
        ),
    ]);
    final links = body(
      await fixture
          .call('get_backlinks', {'page_id': 'b', 'limit': 1, 'offset': 1}),
    );
    expect(links['incoming_note_count'], 1);
    expect(links['incoming_occurrences'], 6);
    expect(links['incoming_records'], 3);
    expect(links['backlinks'].single['from_block_id'], 'a1');
    expect(links['has_more_incoming'], isTrue);
  });

  test('source edits arriving before commit are not overwritten', () async {
    final fixture = _Fixture()..editBeforeCommit = true;
    final result = await fixture.call('insert_note_reference', {
      'page_id': 'a',
      'block_id': 'a-block',
      'offset': 0,
      'target_page_id': 'b',
    });
    expect(body(result)['error']['code'], 'reference_changed');
    expect(fixture.text('a', 'a-block'), 'collaborator changed this');
    expect(fixture.writes, isEmpty);
  });

  test('replacement cannot silently delete another structured reference',
      () async {
    final fixture = _Fixture();
    await fixture.call('insert_note_reference', {
      'page_id': 'a',
      'block_id': 'a-block',
      'offset': 0,
      'target_page_id': 'b',
    });
    final before = fixture.text('a', 'a-block');
    final result = await fixture.call('insert_note_reference', {
      'page_id': 'a',
      'block_id': 'a-block',
      'offset': 0,
      'replace_length': 1,
      'target_page_id': 'isolated',
    });
    expect(body(result)['error']['code'], 'invalid_params');
    expect(fixture.text('a', 'a-block'), before);
    expect(fixture.writes, ['a']);
  });

  test(
      'same-note block references appear at the target while graph self loops stay hidden',
      () async {
    final fixture = _Fixture();
    final result = await fixture.call('insert_note_reference', {
      'page_id': 'a',
      'block_id': 'a-block',
      'offset': 0,
      'target_page_id': 'a',
      'target_block_id': 'a-block',
    });
    expect(result.isError, isFalse, reason: body(result).toString());
    final backlinks = body(
      await fixture
          .call('get_backlinks', {'page_id': 'a', 'block_id': 'a-block'}),
    );
    expect(backlinks['backlinks'], hasLength(1));
    expect(backlinks['incoming_note_count'], 1);
    expect(body(await fixture.call('get_note_graph'))['edges'], isEmpty);
  });

  test(
      'explicit index repair keeps content unchanged and returns the compatible snapshot',
      () async {
    final fixture = _Fixture();
    final before = fixture.documents.saved['a']!.writeToBuffer();
    final result = await fixture.call('reindex_page_links', {'page_id': 'a'});
    expect(result.isError, isFalse);
    expect(fixture.repairCalls, ['a']);
    expect(fixture.documents.saved['a']!.writeToBuffer(), before);
    expect(
      body(result).keys,
      containsAll(['backlinks', 'outgoing', 'unresolved', 'indexed_pages']),
    );
  });

  test(
      'open reference validates source then navigates either exact endpoint without modifying content',
      () async {
    final fixture = _Fixture();
    await fixture.call('insert_note_reference', {
      'page_id': 'a',
      'block_id': 'a-block',
      'offset': 0,
      'target_page_id': 'b',
      'target_block_id': 'b-block',
    });
    fixture.writes.clear();
    for (final side in ['target', 'source']) {
      final result = await fixture.call('open_note_reference', {
        'page_id': 'a',
        'block_id': 'a-block',
        'offset': 0,
        'target_page_id': 'b',
        'target_block_id': 'b-block',
        'side': side,
      });
      expect(result.isError, isFalse, reason: body(result).toString());
      expect(body(result)['navigation_requested'], isTrue);
    }
    expect(fixture.openedReferences, [('b', 'b-block'), ('a', 'a-block')]);
    final stale = await fixture.call('open_note_reference', {
      'page_id': 'a',
      'block_id': 'a-block',
      'offset': 1,
      'target_page_id': 'b',
      'target_block_id': 'b-block',
    });
    expect(body(stale)['error']['code'], 'reference_changed');
    expect(fixture.openedReferences, hasLength(2));
    expect(fixture.writes, isEmpty);
  });

  test(
      'open graph routes to independent global or local plugin and denies inaccessible focus',
      () async {
    final fixture = _Fixture();
    final global = body(await fixture.call('open_note_graph'));
    final local =
        body(await fixture.call('open_note_graph', {'focus_page_id': 'b'}));
    expect(global['plugin_id'], 'note_graph:global');
    expect(local['plugin_id'], 'note_graph:b');
    expect(fixture.openedGraphs, [null, 'b']);
    expect(
      (await fixture.call('open_note_graph', {'focus_page_id': 'private'}))
          .isError,
      isTrue,
    );
    expect(fixture.openedGraphs, hasLength(2));
  });

  test(
      'invalid schemas are rejected before any business access for both MCP and internal calls',
      () async {
    final fixture = _Fixture();
    for (final request in [
      ('get_note_graph', {'depth': 0}),
      ('get_note_graph', {'direction': 'sideways'}),
      ('get_note_graph', {'show_isolated': 'yes'}),
      ('get_note_graph', {'limit': 10000}),
      (
        'insert_note_reference',
        {'page_id': 'a', 'target_page_id': 'b', 'offset': -1}
      ),
      (
        'remove_note_reference',
        {'page_id': 'a', 'block_id': 'a-block', 'target_page_id': 'b'}
      ),
      ('get_backlinks', {'page_id': 'b', 'limit': 0}),
      ('open_note_graph', {'unexpected': true}),
    ]) {
      final result = await fixture.call(request.$1, request.$2);
      expect(
        body(result)['error']['code'],
        'invalid_params',
        reason: request.toString(),
      );
    }
    expect(fixture.viewReads, 0);
    expect(fixture.writes, isEmpty);
  });

  test('disabled new tools reject existing sessions and audit only IDs',
      () async {
    SharedPreferences.setMockInitialValues({});
    await McpPermissions.instance.allowAll();
    await McpAuditLog.instance.clear();
    final fixture = _Fixture();
    final tools = _ReferenceTools(fixture, agent: true);
    await McpPermissions.instance.setAllowed('insert_note_reference', false);
    final result = await tools.executeTool('insert_note_reference', {
      'workspace_id': 'ws',
      'page_id': 'a',
      'target_page_id': 'b',
      'expected_source_text': 'private body',
    });
    expect(body(result)['error']['code'], 'permission_denied');
    expect(fixture.writes, isEmpty);
    expect(
      McpAuditLog.instance.entries.first.target,
      contains('target_page_id=b'),
    );
    expect(
      McpAuditLog.instance.entries.first.target,
      isNot(contains('private body')),
    );
    await McpPermissions.instance.allowAll();
    await McpAuditLog.instance.clear();
  });

  test(
      'new tools are discoverable and callable over an actual MCP stream transport',
      () async {
    final fixture = _Fixture();
    final tools = _ReferenceTools(fixture);
    final toServer = StreamController<List<int>>();
    final toClient = StreamController<List<int>>();
    final server =
        McpServer(const Implementation(name: 'test-server', version: 'test'));
    tools.registerAll(server);
    final client =
        McpClient(const Implementation(name: 'test-client', version: 'test'));
    try {
      await server.connect(
        IOStreamTransport(stream: toServer.stream, sink: toClient.sink),
      );
      await client.connect(
        IOStreamTransport(stream: toClient.stream, sink: toServer.sink),
      );
      final listed = await client.listTools();
      expect(
        listed.tools.map((tool) => tool.name),
        containsAll([
          'insert_note_reference',
          'remove_note_reference',
          'get_reference_context',
          'get_note_graph',
          'open_note_graph',
          'open_note_reference',
        ]),
      );
      final result = await client.callTool(
        const CallToolRequest(
          name: 'get_note_graph',
          arguments: {'workspace_id': 'ws'},
        ),
      );
      expect(body(result)['nodes'], hasLength(3));
      final inserted = await client.callTool(
        const CallToolRequest(
          name: 'insert_note_reference',
          arguments: {
            'workspace_id': 'ws',
            'page_id': 'a',
            'target_page_id': 'b',
            'target_block_id': 'b-block',
          },
        ),
      );
      expect(inserted.isError, isFalse, reason: body(inserted).toString());
      final location = body(inserted);
      final queried = await client.callTool(
        const CallToolRequest(
          name: 'get_backlinks',
          arguments: {
            'workspace_id': 'ws',
            'page_id': 'b',
            'block_id': 'b-block',
          },
        ),
      );
      expect(body(queried)['incoming_note_count'], 1);
      final removed = await client.callTool(
        CallToolRequest(
          name: 'remove_note_reference',
          arguments: {
            'workspace_id': 'ws',
            'page_id': 'a',
            'block_id': location['block_id'],
            'offset': location['char_offset'],
            'target_page_id': 'b',
            'target_block_id': 'b-block',
          },
        ),
      );
      expect(removed.isError, isFalse, reason: body(removed).toString());
    } finally {
      await client.close();
      await server.close();
      await toServer.close();
      await toClient.close();
    }
  });
}
