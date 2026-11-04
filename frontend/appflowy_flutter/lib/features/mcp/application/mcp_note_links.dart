part of 'mcp_tools.dart';

/// Injectable business boundaries; production defaults use the same services as the editor.
class McpNoteLinkDependencies {
  const McpNoteLinkDependencies({
    required this.validateWorkspace,
    required this.loadViews,
    required this.requireWritable,
    required this.readLinks,
    this.openGraph,
    this.openReference,
  });
  final Future<CallToolResult?> Function(String workspaceId) validateWorkspace;
  final Future<List<ViewPB>> Function() loadViews;
  final Future<CallToolResult?> Function(String workspaceId, String pageId)
      requireWritable;
  final Future<DocumentLinksPB> Function(
    String workspaceId,
    String pageId,
    bool repair,
  ) readLinks;
  final Future<void> Function(ViewPB? focus)? openGraph;
  final Future<void> Function(ViewPB view, String? blockId)? openReference;
}

const _noteRelationsSchema = JsonObject(
  properties: {
    'workspace_id': JsonString(description: '当前工作区 ID'),
    'page_id': JsonString(description: '笔记 ID'),
    'block_id': JsonString(description: '可选：限定被引用目标段落，出链限定来源段落'),
    'include_context': JsonBoolean(description: '读取当前引用片段，默认 false；可能涉及多个正文读取'),
    'limit':
        JsonInteger(minimum: 1, maximum: 100, description: '每个方向的返回记录上限，默认 50'),
    'offset': JsonInteger(minimum: 0, description: '每个方向跳过的记录数量，默认 0'),
  },
  required: [
    'workspace_id',
    'page_id',
  ],
  additionalProperties: false,
);

const _noteGraphSchema = JsonObject(
  properties: {
    'workspace_id': JsonString(description: '当前工作区 ID'),
    'focus_page_id': JsonString(description: '可选：以该笔记为中心的局部图谱'),
    'depth': JsonInteger(minimum: 1, maximum: 3, description: '局部图谱深度，默认 1'),
    'direction': JsonString(
      enumValues: ['both', 'incoming', 'outgoing'],
      description: '局部图谱的引用方向，默认 both',
    ),
    'query': JsonString(description: '按标题筛选；局部图谱保留中心笔记'),
    'show_isolated': JsonBoolean(description: '全局图谱是否显示未关联笔记，默认 true'),
    'blocks_only': JsonBoolean(description: '仅保留段落引用，默认 false'),
    'limit':
        JsonInteger(minimum: 1, maximum: 500, description: '笔记数量上限，默认 400'),
  },
  required: [
    'workspace_id',
  ],
  additionalProperties: false,
);

const _noteInsertSchema = JsonObject(
  properties: {
    'workspace_id': JsonString(description: '当前工作区 ID'),
    'page_id': JsonString(description: '写入引用的来源笔记 ID'),
    'block_id': JsonString(description: '来源文本段落；省略则在笔记末尾新增段落'),
    'target_page_id': JsonString(description: '被引用笔记 ID'),
    'target_block_id': JsonString(description: '被引用段落 ID；省略表示整篇笔记引用'),
    'offset': JsonInteger(
      minimum: 0,
      description:
          '来源段落的 Unicode 字符偏移，与 char_offset 同口径，emoji 算一个字符；省略则追加到段落末尾',
    ),
    'replace_length': JsonInteger(
      minimum: 0,
      description: '替换多少个 Unicode 字符，默认 0；需要 block_id 和 offset',
    ),
    'expected_source_text':
        JsonString(description: '可选乐观校验：必须等于来源块当前原始文本（mention 是 \$），不一致则拒绝写入'),
  },
  required: [
    'workspace_id',
    'page_id',
    'target_page_id',
  ],
  additionalProperties: false,
);

const _noteReferenceLocationSchema = JsonObject(
  properties: {
    'workspace_id': JsonString(description: '当前工作区 ID'),
    'page_id': JsonString(description: '引用来源笔记 ID'),
    'block_id': JsonString(description: '引用来源段落 ID'),
    'offset': JsonInteger(
      minimum: 0,
      description: '引用的 Unicode 字符位置，与 get_backlinks.char_offset 同口径',
    ),
    'target_page_id': JsonString(description: '预期引用目标笔记 ID，防止来源内容变化后操作错位'),
    'target_block_id': JsonString(description: '预期目标段落 ID；省略时要求该位置为整篇笔记引用'),
    'expected_source_text': JsonString(description: '可选：来源块原始文本必须仍与该值一致'),
  },
  required: [
    'workspace_id',
    'page_id',
    'block_id',
    'offset',
    'target_page_id',
  ],
  additionalProperties: false,
);

final _noteNavigateSchema = JsonObject(
  properties: {
    ...?_noteReferenceLocationSchema.properties,
    'side': const JsonString(
      enumValues: ['source', 'target'],
      description: '定位引用来源或目标，默认 target',
    ),
  },
  required: _noteReferenceLocationSchema.required,
  additionalProperties: false,
);

const _noteOpenGraphSchema = JsonObject(
  properties: {
    'workspace_id': JsonString(description: '当前工作区 ID'),
    'focus_page_id': JsonString(description: '可选：打开该笔记的局部双链图谱；省略打开全局图谱'),
  },
  required: [
    'workspace_id',
  ],
  additionalProperties: false,
);

class _NoteToolFailure implements Exception {
  const _NoteToolFailure(this.result);
  final CallToolResult result;
}

extension _McpNoteLinks on McpTools {
  List<McpToolSpec> get _noteLinkSpecs => [
        McpToolSpec(
          name: 'insert_note_reference',
          description: '在正文插入结构化页面或段落引用，保存目标页面与段落 ID，自动派生反链。'
              '不复制正文、不向目标笔记再写一次链接。支持指定来源位置或追加新段落。',
          inputSchema: _noteInsertSchema,
          handler: (args) => _noteCall(args, _insertNoteReference),
        ),
        McpToolSpec(
          name: 'remove_note_reference',
          destructive: true,
          description: '移除来源段落指定位置的结构化引用，保留两端正文。目标 ID 与位置必须匹配，避免误删其他内容；反链自动更新。',
          inputSchema: _noteReferenceLocationSchema,
          handler: (args) => _noteCall(args, _removeNoteReference),
        ),
        McpToolSpec(
          name: 'get_reference_context',
          description: '校验正文指定位置仍是预期引用，返回来源与目标段落当前片段和可定位 ID。'
              'offset 使用 Unicode 字符计数，取自 get_backlinks 的 char_offset。',
          inputSchema: _noteReferenceLocationSchema,
          readOnly: true,
          handler: (args) => _noteCall(args, _getReferenceContext),
        ),
        McpToolSpec(
          name: 'open_note_reference',
          description: '验证来源位置的引用后，在客户端定位并高亮其来源或目标段落。'
              'side=target 默认打开被引用位置，side=source 返回来源。仅改变界面，不修改正文。',
          inputSchema: _noteNavigateSchema,
          handler: (args) => _noteCall(args, _openNoteReference),
        ),
        McpToolSpec(
          name: 'get_note_graph',
          description: '查询独立双链图谱：只含真实笔记引用，不含目录或 AI 关系。默认包含无连线的孤立笔记；'
              '支持中心笔记、1～3 跳、入链/出链、标题和段落引用筛选。不读取全部笔记正文，不调用 AI。',
          inputSchema: _noteGraphSchema,
          readOnly: true,
          handler: (args) => _noteCall(args, _getNoteGraph),
        ),
        McpToolSpec(
          name: 'open_note_graph',
          description: '在客户端打开独立的双链图谱（全局或指定笔记局部图谱），改变界面上下文，不替换原知识图谱的功能。',
          inputSchema: _noteOpenGraphSchema,
          handler: (args) => _noteCall(args, _openNoteGraph),
        ),
      ];

  Never _noteFail(
    String code,
    String message, {
    Map<String, dynamic>? details,
  }) =>
      throw _NoteToolFailure(_error(code, message, details: details));

  Future<CallToolResult> _noteCall(
    Map<String, dynamic> args,
    Future<CallToolResult> Function(Map<String, dynamic>) run,
  ) async {
    try {
      return await run(args);
    } on _NoteToolFailure catch (error) {
      return error.result;
    } on JsonSchemaValidationException catch (error) {
      return _error('invalid_params', error.message);
    }
  }

  String _noteId(
    Map<String, dynamic> args,
    String key, {
    bool required = false,
  }) {
    final value = args[key];
    if (value == null && !required) return '';
    if (value is! String || value.trim().isEmpty) {
      _noteFail('invalid_params', '$key 必须为非空字符串。');
    }
    return (value as String).trim();
  }

  /// 读取可省略的非负整数参数。
  int _noteInt(
    Map<String, dynamic> args,
    String key,
    int fallback, {
    int max = 0x7fffffff,
  }) {
    final value = args[key] ?? fallback;
    if (value is! int || value < 0 || value > max) {
      _noteFail('invalid_params', '$key 超出允许范围或不是整数。');
    }
    return value as int;
  }

  /// 读取必填的非负整数。
  ///
  /// 早先对必填参数也用 `_noteInt(args, 'offset', -1)`：`-1` 撞上下界校验，
  /// 真正省略时会抛 `invalid_params` 而不是"参数缺失"。只因为 schema 恰好把
  /// 它标成 required 才没暴露。必填就该显式走这条路径，不再借哨兵值。
  int _noteRequiredInt(
    Map<String, dynamic> args,
    String key, {
    int max = 0x7fffffff,
  }) {
    if (args[key] == null) {
      _noteFail('invalid_params', '$key 为必填的非负整数。');
    }
    return _noteInt(args, key, 0, max: max);
  }

  bool _noteBool(Map<String, dynamic> args, String key, bool fallback) {
    final value = args[key] ?? fallback;
    if (value is! bool) _noteFail('invalid_params', '$key 必须是布尔值。');
    return value as bool;
  }

  Future<(String, Map<String, ViewPB>)> _noteScope(
    Map<String, dynamic> args,
  ) async {
    final workspace = _noteId(args, 'workspace_id', required: true);
    final invalid = await (noteLinks?.validateWorkspace(workspace) ??
        _validateWorkspace(workspace));
    if (invalid != null) throw _NoteToolFailure(invalid);
    final List<ViewPB> views;
    if (noteLinks != null) {
      views = await noteLinks!.loadViews();
    } else {
      final result = await ViewBackendService.getAllViews();
      views = result.fold(
        (value) => value.items,
        (error) => _noteFail('document_unavailable', '无法读取当前可访问的笔记列表。'),
      );
    }
    return (
      workspace,
      {
        for (final view in views)
          if ((view.workspaceId.isEmpty || view.workspaceId == workspace) &&
              !view.isSpace &&
              view.layout == ViewLayoutPB.Document &&
              // 工作区根文档只是工作区外壳，不算可选笔记；排除后
              // accessible_notes 与图谱节点数保持同一口径。
              !NoteGraphData.isWorkspaceRoot(view, workspace))
            view.id: view,
      }
    );
  }

  ViewPB _noteView(Map<String, ViewPB> views, String id) =>
      views[id] ?? _noteFail('not_found', '笔记不存在、不属于当前工作区或无权访问。');

  /// 索引覆盖情况三态判定。
  ///
  /// `indexed_pages` 是 `note_link_state` 的行数，含已删除/移出工作区页面的
  /// 历史残留，因此它和"可访问笔记数"不是同一口径。残留只会让它偏大，
  /// 所以 `indexedPages >= accessibleNotes` 并不能证明"全部笔记都建过索引"。
  ///
  /// 早先直接输出 `indexedPages < accessibleNotes` 的二值结论，在残留足够多
  /// 时会假阴性：明明有新页未索引，却报告完整。这里拆成三态，只在计数确实
  /// 存在缺口时声称 `partial`，其余情况如实标记 `unverified`，让调用方自己
  /// 决定要不要先跑一次 `reindex_page_links`。
  String _noteIndexCoverage(DocumentLinksPB snapshot, int accessibleNotes) {
    if (accessibleNotes == 0) return 'no_notes';
    if (snapshot.indexedPages == 0) return 'empty';
    if (snapshot.indexedPages < accessibleNotes) return 'partial';
    return 'unverified';
  }

  Future<DocumentLinksPB> _noteReadLinks(
    String workspace,
    String page, {
    bool repair = false,
  }) =>
      noteLinks?.readLinks(workspace, page, repair) ??
      NoteLinkService.read(
        workspaceId: workspace,
        pageId: page,
        repair: repair,
      );

  Future<void> _noteWriteAccess(String workspace, String page) async {
    final failure = await (noteLinks?.requireWritable(workspace, page) ??
        _requireWritableDocument(workspace, page));
    if (failure != null) throw _NoteToolFailure(failure);
  }

  Future<Node?> _noteReadBlock(
    String workspace,
    String page,
    String block,
  ) async {
    if (block.isEmpty) return null;
    final live = DocumentBloc.findOpen(page)?.state.editorState;
    if (live != null) return _findNode(live.document, block);
    final document = await _readDocument(page, workspace);
    return document?.buildNode(block);
  }

  String _noteRawText(Node node) => (node.delta?.toJson() ?? [])
      .map((op) => op['insert'] is String ? op['insert'] as String : '\uFFFC')
      .join();

  Map? _noteMentionAt(Node node, int offset) {
    var position = 0;
    for (final op in node.delta?.toJson() ?? <Map<String, dynamic>>[]) {
      final insert = op['insert'];
      final attrs = op['attributes'];
      final mention = attrs is Map ? attrs['mention'] : null;
      if (insert is String &&
          offset >= position &&
          offset < position + insert.runes.length &&
          insert.runes.elementAt(offset - position) == 36 &&
          mention is Map &&
          mention['type'] == 'page') {
        return mention;
      }
      position += insert is String ? insert.runes.length : 1;
    }
    return null;
  }

  void _noteCheckLocation(
    Map<String, dynamic> args,
    Node node,
    String target,
    String targetBlock,
  ) {
    if (args.containsKey('expected_source_text')) {
      if (args['expected_source_text'] is! String) {
        _noteFail('invalid_params', 'expected_source_text 必须是字符串。');
      }
      if (args['expected_source_text'] != _noteRawText(node)) {
        _noteFail('reference_changed', '来源段落已变化，请重新读取后确认位置。');
      }
    }
    final offset = _noteRequiredInt(args, 'offset');
    final mention = _noteMentionAt(node, offset);
    if (mention == null ||
        mention['page_id'] != target ||
        (mention['block_id'] ?? '') != targetBlock) {
      _noteFail('reference_changed', '该位置不再是预期引用，请重新读取来源段落。');
    }
  }

  Future<void> _noteConfirmSource(
    String workspace,
    String page,
    Node source,
  ) async {
    final fresh = await _readDocument(page, workspace);
    final current = fresh?.buildNode(source.id);
    if (current?.delta == null ||
        !const DeepCollectionEquality()
            .equals(current!.delta!.toJson(), source.delta!.toJson())) {
      _noteFail('reference_changed', '来源段落在提交前发生变化，未修改正文；请重新读取位置。');
    }
  }

  void _noteCheckReplacement(Node node, int start, int length) {
    var position = 0;
    for (final op in node.delta!.toJson()) {
      final insert = op['insert'];
      final count = insert is String ? insert.runes.length : 1;
      final attrs = op['attributes'];
      if (position < start + length &&
          position + count > start &&
          (insert is! String ||
              (attrs is Map &&
                  (attrs['mention'] != null || attrs['formula'] != null)))) {
        _noteFail('invalid_params', '替换范围包含结构化引用、提醒或公式；仅允许替换普通文本。');
      }
      position += count;
    }
  }

  Map<String, dynamic> _noteEdge(NoteLinkPB link, Map<String, ViewPB> views) =>
      {
        'from_page_id': link.srcPageId,
        'from_title': views[link.srcPageId]?.name ?? '',
        'from_block_id': link.srcBlockId,
        'to_page_id': link.dstPageId,
        'to_title': views[link.dstPageId]?.name ?? '',
        'to_block_id': link.dstBlockId,
        'kind': link.kind,
        'label': link.label,
        'char_offset': link.charOffset,
        'occurrence': link.occurrence > 0 ? link.occurrence : 1,
      };

  List<NoteLinkPB> _noteVisibleEdges(
    Iterable<NoteLinkPB> links,
    Map<String, ViewPB> views, {
    bool selfBlocks = false,
  }) =>
      links.where((link) {
        if (!const {'reference', 'block_ref', 'embed'}.contains(link.kind)) {
          return false;
        }
        if (!views.containsKey(link.srcPageId) ||
            !views.containsKey(link.dstPageId)) {
          return false;
        }
        if (link.kind == 'embed' &&
            views[link.dstPageId]!.parentViewId == link.srcPageId) {
          return false;
        }
        return link.srcPageId != link.dstPageId ||
            (selfBlocks && link.dstBlockId.isNotEmpty);
      }).toList();

  Future<CallToolResult> _getBacklinks(Map<String, dynamic> args) =>
      _noteCall(args, (args) async {
        _noteRelationsSchema.validate(args);
        final (workspace, views) = await _noteScope(args);
        final page = _noteId(args, 'page_id', required: true);
        _noteView(views, page);
        final block = _noteId(args, 'block_id');
        if (block.isNotEmpty &&
            await _noteReadBlock(workspace, page, block) == null) {
          _noteFail('not_found', '段落不存在或尚未同步。');
        }
        final limit = _noteInt(args, 'limit', 50, max: 100);
        if (limit == 0) _noteFail('invalid_params', 'limit 必须大于 0。');
        final offset = _noteInt(args, 'offset', 0);
        final contexts = _noteBool(args, 'include_context', false);
        final snapshot = await _noteReadLinks(workspace, page);
        final incoming = _noteVisibleEdges(
          [
            ...snapshot.incoming,
            ...snapshot.outgoing.where(
              (link) =>
                  link.srcPageId == page &&
                  link.dstPageId == page &&
                  link.dstBlockId.isNotEmpty,
            ),
          ],
          views,
          selfBlocks: true,
        ).where((link) => block.isEmpty || link.dstBlockId == block).toList();
        final outgoing =
            _noteVisibleEdges(snapshot.outgoing, views, selfBlocks: true)
                .where((link) => block.isEmpty || link.srcBlockId == block)
                .toList();
        final documents = <String, Future<DocumentDataPB?>>{};
        Future<Map<String, dynamic>> entry(NoteLinkPB link) async {
          final result = _noteEdge(link, views);
          if (contexts) {
            final id = link.srcPageId;
            final data = await documents.putIfAbsent(
              id,
              () => _readDocument(id, workspace)
                  .timeout(const Duration(seconds: 3))
                  .catchError((_) => null),
            );
            final node = data?.buildNode(link.srcBlockId);
            result['source_excerpt'] = node == null
                ? null
                : noteLinkContext(
                    noteBlockText(
                      node,
                      titles: {
                        for (final view in views.values) view.id: view.name,
                      },
                    ),
                    link.charOffset,
                  );
          }
          return result;
        }

        return _ok({
          'workspace_id': workspace,
          'page_id': page,
          'title': views[page]!.name,
          if (block.isNotEmpty) 'block_id': block,
          'indexed_pages': snapshot.indexedPages,
          'accessible_notes': views.length,
          'index_coverage': _noteIndexCoverage(snapshot, views.length),
          'truncated': snapshot.truncated,
          'coverage': 'local_synced_accessible_notes',
          'incomplete': snapshot.indexedPages < views.length,
          'incoming_note_count':
              incoming.map((link) => link.srcPageId).toSet().length,
          'outgoing_note_count':
              outgoing.map((link) => link.dstPageId).toSet().length,
          'incoming_occurrences': noteLinkOccurrences(incoming),
          'outgoing_occurrences': noteLinkOccurrences(outgoing),
          'incoming_records': incoming.length,
          'outgoing_records': outgoing.length,
          'offset': offset,
          'limit': limit,
          'has_more_incoming':
              offset + limit < incoming.length || snapshot.truncated,
          'has_more_outgoing': offset + limit < outgoing.length,
          'backlinks':
              await Future.wait(incoming.skip(offset).take(limit).map(entry)),
          'outgoing':
              await Future.wait(outgoing.skip(offset).take(limit).map(entry)),
          'unresolved': [
            for (final link in snapshot.unresolved
                .where((link) => block.isEmpty || link.srcBlockId == block)
                .skip(offset)
                .take(limit))
              {
                'src_block_id': link.srcBlockId,
                'raw_title': link.rawTitle,
                'char_offset': link.charOffset,
              },
          ],
        });
      });

  Future<CallToolResult> _getWorkspaceLinksGraph(Map<String, dynamic> args) =>
      _noteCall(args, (args) async {
        McpTools._linksGraphSchema.validate(args);
        final (workspace, views) = await _noteScope(args);
        final snapshot = await _noteReadLinks(workspace, '');
        return _ok({
          'workspace_id': workspace,
          'graph_type': 'note_links',
          'indexed_pages': snapshot.indexedPages,
          'accessible_notes': views.length,
          'index_coverage': _noteIndexCoverage(snapshot, views.length),
          'truncated': snapshot.truncated,
          'incomplete': snapshot.indexedPages < views.length,
          'coverage': 'local_synced_accessible_notes',
          'nodes': [
            for (final view in views.values)
              if (!NoteGraphData.isWorkspaceRoot(view, workspace))
                {'page_id': view.id, 'title': view.name},
          ],
          'edges': _noteVisibleEdges(snapshot.outgoing, views)
              .map((link) => _noteEdge(link, views))
              .toList(),
        });
      });

  Future<CallToolResult> _reindexPageLinks(Map<String, dynamic> args) =>
      _noteCall(args, (args) async {
        McpTools._pageIdSchema.validate(args);
        final (workspace, views) = await _noteScope(args);
        final page = _noteId(args, 'page_id', required: true);
        _noteView(views, page);
        await _noteReadLinks(workspace, page, repair: true);
        return _getBacklinks(args);
      });

  Future<CallToolResult> _getNoteGraph(Map<String, dynamic> args) async {
    _noteGraphSchema.validate(args);
    final focus = _noteId(args, 'focus_page_id');
    final depth = _noteInt(args, 'depth', 1, max: 3);
    final limit = _noteInt(args, 'limit', 400, max: 500);
    if (depth == 0 || limit == 0) {
      _noteFail('invalid_params', 'depth 与 limit 必须大于 0。');
    }
    final direction = args['direction'] ?? 'both';
    if (direction is! String ||
        !['both', 'incoming', 'outgoing'].contains(direction)) {
      _noteFail('invalid_params', '不支持的 direction。');
    }
    if (args.containsKey('query') && args['query'] is! String) {
      _noteFail('invalid_params', 'query 必须是字符串。');
    }
    final isolated = _noteBool(args, 'show_isolated', true);
    final blocksOnly = _noteBool(args, 'blocks_only', false);
    final (workspace, views) = await _noteScope(args);
    if (focus.isNotEmpty) _noteView(views, focus);
    final snapshot = await _noteReadLinks(workspace, '');
    final all = NoteGraphData.fromIndex(views.values, snapshot, workspaceId: workspace);
    final graph = all.filtered(
      focus: focus.isEmpty ? null : focus,
      depth: depth,
      direction: NoteGraphDirection.values.byName(direction as String),
      query: args['query'] as String? ?? '',
      showIsolated: isolated,
      blocksOnly: blocksOnly,
      limit: limit,
    );
    return _ok({
      'workspace_id': workspace,
      'graph_type': 'note_links',
      'focus_page_id': focus.isEmpty ? null : focus,
      'depth': depth,
      'direction': direction,
      'indexed_pages': snapshot.indexedPages,
      'accessible_notes': all.notes.length,
      'index_coverage': _noteIndexCoverage(snapshot, all.notes.length),
      'truncated': snapshot.truncated,
      'incomplete': snapshot.indexedPages < all.notes.length,
      'coverage': 'local_synced_accessible_notes',
      'omitted_notes': graph.omittedNotes,
      'nodes': [
        for (final view in graph.notes.values)
          {
            'page_id': view.id,
            'title': view.name,
            'incoming_note_count': all.incomingTo(view.id).length,
            'outgoing_note_count': all.outgoingFrom(view.id).length,
            'is_isolated': all.degree(view.id) == 0,
          },
      ],
      'edges': [
        for (final edge in graph.edges)
          {
            'from_page_id': edge.source,
            'to_page_id': edge.target,
            'reference_count': edge.references.length,
            'occurrence_count': edge.occurrences,
            'block_reference_count': edge.blockReferences,
          },
      ],
    });
  }

  Future<CallToolResult> _openNoteGraph(Map<String, dynamic> args) async {
    _noteOpenGraphSchema.validate(args);
    final (workspace, views) = await _noteScope(args);
    final id = _noteId(args, 'focus_page_id');
    final focus = id.isEmpty ? null : _noteView(views, id);
    final plugin = NoteGraphPlugin(focusView: focus);
    if (noteLinks?.openGraph != null) {
      await noteLinks!.openGraph!(focus);
    } else {
      if (!getIt.isRegistered<TabsBloc>() || getIt<TabsBloc>().isClosed) {
        _noteFail('ui_unavailable', '客户端当前没有可用的标签页界面。');
      }
      final tabs = getIt<TabsBloc>();
      if (tabs.state.currentPageManager.plugin.id == plugin.id) {
        return _ok({
          'workspace_id': workspace,
          'graph_type': 'note_links',
          'plugin_id': plugin.id,
          'focus_page_id': id.isEmpty ? null : id,
          'opened': true,
        });
      }
      final confirmed = tabs.stream
          .firstWhere(
            (state) => state.currentPageManager.plugin.id == plugin.id,
          )
          .timeout(const Duration(seconds: 5));
      // No view argument: SpaceHub must not redirect this graph into the source document.
      tabs.add(TabsEvent.openPlugin(plugin: plugin));
      try {
        await confirmed;
      } on TimeoutException {
        if (tabs.state.currentPageManager.plugin.id != plugin.id) {
          _noteFail('open_unconfirmed', '图谱打开请求已提交，尚未确认界面切换。');
        }
      }
    }
    return _ok({
      'workspace_id': workspace,
      'graph_type': 'note_links',
      'plugin_id': plugin.id,
      'focus_page_id': id.isEmpty ? null : id,
      'opened': true,
    });
  }

  Future<CallToolResult> _openNoteReference(Map<String, dynamic> args) async {
    _noteNavigateSchema.validate(args);
    // Validate the actual source mention, rather than trusting a stale index edge.
    //
    // 校验失败有两条路径：抛 `_NoteToolFailure`，或直接返回错误结果。这里必须
    // 显式检查返回值——只靠异常的话，一旦该校验将来改成"返回错误而不抛"，
    // 就会退化成"校验失败仍然导航到错误位置"。
    final location = Map<String, dynamic>.of(args)..remove('side');
    final validated = await _getReferenceContext(location);
    if (validated.isError) return validated;
    final (workspace, views) = await _noteScope(args);
    final source = args['side'] == 'source';
    final page =
        _noteId(args, source ? 'page_id' : 'target_page_id', required: true);
    final block = _noteId(args, source ? 'block_id' : 'target_block_id');
    final view = _noteView(views, page);
    if (block.isNotEmpty &&
        await _noteReadBlock(workspace, page, block) == null) {
      _noteFail('not_found', '引用段落已删除或尚未同步，未执行跳转。');
    }
    if (noteLinks?.openReference != null) {
      await noteLinks!.openReference!(view, block.isEmpty ? null : block);
    } else {
      if (!getIt.isRegistered<TabsBloc>() || getIt<TabsBloc>().isClosed) {
        _noteFail('ui_unavailable', '客户端当前没有可用的标签页界面。');
      }
      if (block.isNotEmpty) NoteBlockNavigation.request(page, block);
      getIt<TabsBloc>().openPlugin(
        view,
        arguments: {
          if (block.isNotEmpty) PluginArgumentKeys.blockId: block,
        },
      );
    }
    return _ok({
      'workspace_id': workspace,
      'page_id': page,
      'block_id': block.isEmpty ? null : block,
      'side': source ? 'source' : 'target',
      'navigation_requested': true,
    });
  }

  Future<CallToolResult> _getReferenceContext(Map<String, dynamic> args) async {
    _noteReferenceLocationSchema.validate(args);
    final (workspace, views) = await _noteScope(args);
    final page = _noteId(args, 'page_id', required: true);
    final block = _noteId(args, 'block_id', required: true);
    final target = _noteId(args, 'target_page_id', required: true);
    final targetBlock = _noteId(args, 'target_block_id');
    _noteView(views, page);
    _noteView(views, target);
    final node = await _noteReadBlock(workspace, page, block);
    if (node == null) _noteFail('not_found', '来源段落不存在或尚未同步。');
    _noteCheckLocation(args, node, target, targetBlock);
    final targetNode = targetBlock.isEmpty
        ? null
        : await _noteReadBlock(workspace, target, targetBlock);
    return _ok({
      'workspace_id': workspace,
      'page_id': page,
      'block_id': block,
      'char_offset': args['offset'],
      'target_page_id': target,
      'target_block_id': targetBlock,
      'source_excerpt': noteLinkContext(
        noteBlockText(
          node,
          titles: {for (final view in views.values) view.id: view.name},
        ),
        args['offset'] as int,
      ),
      'target_excerpt': targetNode == null
          ? null
          : noteLinkContext(noteBlockText(targetNode), 0),
      'target_status': targetBlock.isEmpty
          ? 'whole_note'
          : targetNode == null
              ? 'block_unavailable'
              : 'available',
      'reference_exists': true,
    });
  }

  Future<CallToolResult> _insertNoteReference(Map<String, dynamic> args) async {
    _noteInsertSchema.validate(args);
    final source = _noteId(args, 'page_id', required: true);
    final sourceBlock = _noteId(args, 'block_id');
    final target = _noteId(args, 'target_page_id', required: true);
    final targetBlock = _noteId(args, 'target_block_id');
    if (sourceBlock.isEmpty &&
        ['offset', 'replace_length', 'expected_source_text']
            .any(args.containsKey)) {
      _noteFail('invalid_params', '位置、替换长度和文本校验需要 block_id。');
    }
    final replace = _noteInt(args, 'replace_length', 0);
    if (replace > 0 && !args.containsKey('offset')) {
      _noteFail('invalid_params', '替换文本需要 offset。');
    }
    if (args.containsKey('offset')) _noteInt(args, 'offset', 0);
    final (workspace, views) = await _noteScope(args);
    _noteView(views, source);
    _noteView(views, target);
    await _noteWriteAccess(workspace, source);
    if (targetBlock.isNotEmpty) {
      final targetNode = await _noteReadBlock(workspace, target, targetBlock);
      if (targetNode?.delta == null) _noteFail('not_found', '目标必须为已同步的正文文本段落。');
    }
    final state = await _loadEditorState(source, workspace);
    if (state == null) _noteFail('document_unavailable', '来源笔记尚不可读取。');
    try {
      final Node node;
      final transaction = state.transaction;
      var offset = 0;
      final attrs = MentionBlockKeys.buildMentionPageAttributes(
        mentionType: MentionType.page,
        pageId: target,
        blockId: targetBlock.isEmpty ? null : targetBlock,
      );
      (attrs[MentionBlockKeys.mention]
          as Map<String, dynamic>)['reference_id'] = nanoid(12);
      if (sourceBlock.isEmpty) {
        node = paragraphNode(
          delta: Delta()
            ..insert(MentionBlockKeys.mentionChar, attributes: attrs),
        );
        transaction.insertNode([state.document.root.children.length], node);
      } else {
        final existing = _findNode(state.document, sourceBlock);
        if (existing == null ||
            existing.delta == null ||
            existing.id == state.document.root.id) {
          _noteFail('not_found', '来源必须为存在的正文文本段落。');
        }
        node = existing;
        final raw = _noteRawText(node);
        if (args.containsKey('expected_source_text')) {
          if (args['expected_source_text'] is! String) {
            _noteFail('invalid_params', 'expected_source_text 必须是字符串。');
          }
          if (args['expected_source_text'] != raw) {
            _noteFail('reference_changed', '来源段落已变化，未写入引用。');
          }
        }
        offset = _noteInt(args, 'offset', raw.runes.length);
        if (offset + replace > raw.runes.length) {
          _noteFail('invalid_params', '插入位置或替换范围超出段落长度。');
        }
        if (replace > 0) _noteCheckReplacement(node, offset, replace);
        final start = String.fromCharCodes(raw.runes.take(offset)).length;
        final length =
            String.fromCharCodes(raw.runes.skip(offset).take(replace)).length;
        transaction.replaceText(
          node,
          start,
          length,
          MentionBlockKeys.mentionChar,
          attributes: attrs,
        );
      }
      final blockId = sourceBlock.isEmpty
          ? transaction.operations
              .whereType<InsertOperation>()
              .first
              .nodes
              .first
              .id
          : node.id;
      final (_, latestViews) = await _noteScope(args);
      _noteView(latestViews, source);
      _noteView(latestViews, target);
      await _noteWriteAccess(workspace, source);
      if (sourceBlock.isNotEmpty) {
        await _noteConfirmSource(workspace, source, node);
      }
      if (targetBlock.isNotEmpty) {
        final currentTarget =
            await _noteReadBlock(workspace, target, targetBlock);
        if (currentTarget?.delta == null) {
          _noteFail('not_found', '目标段落已变化或不再可用。');
        }
      }
      final result = await persistDocument(
        pageId: source,
        workspaceId: workspace,
        state: state,
        transaction: transaction,
        verify: (data) {
          final saved = data.buildNode(blockId);
          final mention = saved == null ? null : _noteMentionAt(saved, offset);
          return mention?['page_id'] == target &&
              (mention?['block_id'] ?? '') == targetBlock;
        },
      );
      if (result != null) return result;
      final indexed = await _noteRefreshAfterWrite(workspace, source);
      return _ok({
        'workspace_id': workspace,
        'page_id': source,
        'block_id': blockId,
        'char_offset': offset,
        'target_page_id': target,
        'target_block_id': targetBlock,
        'kind': targetBlock.isEmpty ? 'reference' : 'block_ref',
        'inserted': true,
        'index_updated': indexed,
      });
    } finally {
      await _closeEditorState(source, state);
    }
  }

  Future<CallToolResult> _removeNoteReference(Map<String, dynamic> args) async {
    _noteReferenceLocationSchema.validate(args);
    final source = _noteId(args, 'page_id', required: true);
    final block = _noteId(args, 'block_id', required: true);
    final target = _noteId(args, 'target_page_id', required: true);
    final targetBlock = _noteId(args, 'target_block_id');
    final offset = _noteRequiredInt(args, 'offset');
    final (workspace, views) = await _noteScope(args);
    _noteView(views, source);
    // A dangling reference can still be removed without access to the old target.
    await _noteWriteAccess(workspace, source);
    final state = await _loadEditorState(source, workspace);
    if (state == null) _noteFail('document_unavailable', '来源笔记尚不可读取。');
    try {
      final node = _findNode(state.document, block);
      if (node == null || node.delta == null) {
        _noteFail('not_found', '来源段落不存在。');
      }
      _noteCheckLocation(args, node, target, targetBlock);
      final start =
          String.fromCharCodes(_noteRawText(node).runes.take(offset)).length;
      final expected = node.delta!.compose(
        Delta()
          ..retain(start)
          ..delete(1),
      );
      final transaction = state.transaction..deleteText(node, start, 1);
      await _noteWriteAccess(workspace, source);
      await _noteConfirmSource(workspace, source, node);
      final result = await persistDocument(
        pageId: source,
        workspaceId: workspace,
        state: state,
        transaction: transaction,
        verify: (data) =>
            jsonEncode(data.buildNode(block)?.delta?.toJson()) ==
            jsonEncode(expected.toJson()),
      );
      if (result != null) return result;
      final indexed = await _noteRefreshAfterWrite(workspace, source);
      return _ok({
        'workspace_id': workspace,
        'page_id': source,
        'block_id': block,
        'char_offset': offset,
        'target_page_id': target,
        'target_block_id': targetBlock,
        'removed': true,
        'index_updated': indexed,
      });
    } finally {
      await _closeEditorState(source, state);
    }
  }

  Future<bool> _noteRefreshAfterWrite(String workspace, String page) async {
    try {
      await _noteReadLinks(workspace, page, repair: true)
          .timeout(const Duration(seconds: 3));
      return true;
    } catch (_) {
      return false;
    } // Content is saved; indexing failure must not invite duplicate writes.
  }
}
