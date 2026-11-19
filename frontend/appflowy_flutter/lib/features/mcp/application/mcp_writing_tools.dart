part of 'mcp_tools.dart';

class _McpWritingTask {
  _McpWritingTask(
    this.identity,
    this.page,
    this.block,
    this.expected,
    this.instruction,
    this.start,
    this.length,
  );
  final String identity, page, block, expected, instruction;
  final int start, length;
  final service = InternalAiService();
  String status = 'running', text = '', error = '';
}

final _mcpWritingTasks = <String, _McpWritingTask>{};

extension _McpWritingTools on McpTools {
  List<McpToolSpec> get _writingSpecs => [
        _actionTool(
          'editor_ai_action',
          '启动AI文本写作、查询结果，确认后接受到指定文本块或拒绝。生成与正文写入分开执行。',
          {
            'page_id': const JsonString(),
            'block_id': const JsonString(),
            'instruction': const JsonString(),
            'range': const JsonObject(
              properties: {
                'start': JsonInteger(minimum: 0),
                'length': JsonInteger(minimum: 0),
              },
              required: ['start', 'length'],
              additionalProperties: false,
            ),
            'operation': const JsonString(
              enumValues: ['start', 'status', 'accept', 'reject'],
            ),
            'task_id': const JsonString(),
          },
          [],
          _editorAiAction,
          required: const ['workspace_id', 'operation'],
        ),
        _actionTool(
          'transfer_page',
          '跨云工作区复制或移动无子页的文本文档。移动在目标正文校验通过后才将源页移入回收站。附件和嵌入资源需独立迁移。',
          {
            'page_id': const JsonString(),
            'target_workspace_id': const JsonString(),
            'target_parent_id': const JsonString(),
            'operation': const JsonString(enumValues: ['copy', 'move']),
            'request_id': const JsonString(),
          },
          [],
          _transferPage,
          required: const [
            'workspace_id',
            'page_id',
            'target_workspace_id',
            'target_parent_id',
            'operation',
            'request_id',
          ],
        ),
      ];

  Future<CallToolResult> _editorAiAction(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id');
    final check = await _validateWorkspace(workspace);
    if (check != null) return check;
    final identity = await _grantIdentity(), operation = args['operation'];
    if (operation == 'start') {
      _mcpWritingTasks.removeWhere(
        (_, task) =>
            const ['accepted', 'rejected', 'failed'].contains(task.status),
      );
      if (_mcpWritingTasks.length >= 20) {
        return _error('too_many_tasks', '请先处理现有AI写作结果。');
      }
      final page = _requiredString(args, 'page_id'),
          block = _requiredString(args, 'block_id');
      final error = await _requireWritableDocument(workspace, page);
      if (error != null) return error;
      final data = await _readDocument(page, workspace),
          node = data?.buildNode(block);
      final delta = node?.delta;
      if (delta == null) return _error('not_found', '目标文本块不存在。');
      final range = args['range'] as Map?;
      final start = range?['start'] as int? ?? 0;
      final length = range?['length'] as int? ?? delta.length;
      if (start + length > delta.length) {
        throw const FormatException('文本范围越界');
      }
      final instruction = _requiredString(args, 'instruction');
      if (!await _confirm('editor_ai_action', args)) {
        return _error('permission_denied', '未批准调用AI写作。');
      }
      final id = const Uuid().v4(),
          task = _McpWritingTask(
            identity,
            page,
            block,
            delta.toPlainText(),
            instruction,
            start,
            length,
          );
      _mcpWritingTasks[id] = task;
      unawaited(() async {
        try {
          final config =
              await AgentInternalService().preferred(workspaceId: workspace);
          task.text = await task.service.complete(
            systemPrompt: task.instruction,
            text: delta.slice(start, start + length).toPlainText(),
            configOverride: config,
          );
          if (task.status == 'running') task.status = 'ready';
        } catch (error) {
          if (task.status == 'running') {
            task.status = 'failed';
            task.error = '$error';
          }
        }
      }());
      return _ok({'task_id': id, 'status': task.status});
    }
    final id = _requiredString(args, 'task_id'), task = _mcpWritingTasks[id];
    if (task == null || task.identity != identity) {
      return _error('not_found', '写作任务不存在或身份已变化。');
    }
    if (operation == 'reject') {
      task.service.cancel();
      task.status = 'rejected';
      task.text = '';
      return _ok({'status': task.status});
    }
    await _scopedView(workspace, task.page, write: operation == 'accept');
    if (operation == 'accept') {
      if (task.status != 'ready') return _error('not_ready', '生成尚未完成或已处理。');
      if (!await _confirm('editor_ai_action', {
        'page_id': task.page,
        'block_id': task.block,
        'operation': 'accept',
      })) {
        return _error('permission_denied', '未批准接受生成结果。');
      }
      final result = await _documentText({
        'workspace_id': workspace,
        'page_id': task.page,
        'block_id': task.block,
        'action': 'edit_text',
        'expected_text': task.expected,
        'range': {'start': task.start, 'length': task.length},
        'replacement_delta': [
          {'insert': task.text},
        ],
      });
      if (!result.isError) task.status = 'accepted';
      return result;
    }
    return _ok({
      'task_id': id,
      'status': task.status,
      'text': task.text,
      if (task.error.isNotEmpty) 'error': task.error,
    });
  }

  Future<CallToolResult> _transferPage(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id'),
        page = _requiredString(args, 'page_id');
    final target = _requiredString(args, 'target_workspace_id'),
        parent = _requiredString(args, 'target_parent_id');
    final moving = args['operation'] == 'move';
    final source = await _scopedView(workspace, page, write: moving);
    if (source.layout != ViewLayoutPB.Document ||
        source.isSpace ||
        source.childViews.isNotEmpty) {
      return _error('unsupported_layout', '跨工作区工具仅迁移无子页的普通文档；复杂资源请先导出迁移。');
    }
    final profile = (await _currentProfile())!;
    if (profile.workspaceType == WorkspaceTypePB.LocalW) {
      return _error('unsupported_backend', '本地/跨后端迁移通过导入导出流程完成。');
    }
    final targetWorkspace = await _workspaceById(profile, target);
    if (targetWorkspace == null) {
      return _error('permission_denied', '无权访问目标工作区。');
    }
    Future<Document?> snapshotSource() async {
      final live = DocumentBloc.findOpen(page)?.state.editorState?.document;
      if (live != null) return Document.fromJson(live.toJson());
      return (await _readDocument(page, workspace))?.toDocument();
    }

    final content = await snapshotSource();
    if (content == null) return _error('document_unavailable', '源文档无法读取。');
    final nodes = _flattenDocument(content.root);
    if (nodes.any(
      (block) => const [
        'image',
        'multi_image',
        'video',
        'audio',
        'pdf_embed',
        'whiteboard',
        'file',
        'gallery',
        'grid',
        'board',
        'calendar',
        'sub_page',
      ].contains(block.node.type),
    )) {
      return _error('requires_asset_transfer', '文档包含附件/子资源，需先迁移这些资源，源页未修改。');
    }
    if (moving &&
        (await _noteReadLinks(workspace, page, repair: true))
            .incoming
            .isNotEmpty) {
      return _error('referenced_page', '此页仍有笔记引用。可先复制到目标工作区，保留原链接。');
    }
    if (!await _confirm('transfer_page', args)) {
      return _error('permission_denied', '未批准跨工作区迁移。');
    }
    final id = const Uuid().v5(
      Namespace.url.value,
      '$workspace|$page|$target|${_requiredString(args, 'request_id')}',
    );
    final endpoint = '/api/workspace/${Uri.encodeComponent(target)}/page-view';
    final details = {'target_workspace_id': target, 'target_page_id': id};
    final targetEndpoint = '$endpoint/$id';
    Map<String, dynamic>? targetView;
    Future<void> readTargetView() async {
      try {
        final result = await _cloudRequest('GET', targetEndpoint);
        targetView = _object(_object(result, 'data'), 'view');
      } catch (_) {
        targetView = null;
      }
    }

    await readTargetView();
    if (targetView == null && _executionIsActive()) {
      try {
        await _cloudRequest(
          'POST',
          endpoint,
          body: {
            'parent_view_id': parent,
            'layout': 0,
            'name': source.name,
            'page_data': content.toJson()['document'],
            'view_id': id,
            'collab_id': id,
          },
        );
      } catch (_) {
        // A timeout can occur after the destination was saved. Read it back.
      }
      await readTargetView();
    }
    if (targetView?['view_id'] != id ||
        targetView?['parent_view_id'] != parent ||
        targetView?['name'] != source.name) {
      return _error('transfer_unconfirmed', '目标页位置或名称尚未确认，源页保留。',
          details: details);
    }
    final targetDocument = (await _documentService.getCloudDocument(
      documentId: id,
      workspaceId: target,
    ))
        .fold((data) => data.toDocument(), (_) => null);
    if (targetDocument == null ||
        !mcpTransferContentMatches(content, targetDocument)) {
      return _error('transfer_unconfirmed', '目标正文尚未通过回读校验，源页保留。',
          details: details);
    }
    if (moving) {
      final latestView = await _scopedView(workspace, page, write: true);
      final latest = await snapshotSource();
      if (latestView.name != source.name ||
          latestView.childViews.isNotEmpty ||
          latest == null ||
          !mcpTransferContentMatches(content, latest)) {
        return _error('content_changed', '源页在迁移期间变化，源页保留。', details: details);
      }
      if (!_executionIsActive() ||
          await _validateWorkspace(workspace) != null) {
        return _error('permission_denied', '源工作区或工具授权已变化，源页保留。',
            details: details);
      }
      final removed =
          await _deletePage({'workspace_id': workspace, 'page_id': page});
      if (removed.isError) {
        return _error('transfer_unconfirmed', '目标副本已校验。请查询回收站确认源页状态。',
            details: details);
      }
    }
    return _ok({
      ...details,
      'operation': args['operation'],
      'status': moving ? 'moved' : 'copied',
      'source_trashed': moving,
    });
  }
}

/// The cloud creates its own block IDs. Compare ordered content and style.
bool mcpTransferContentMatches(Document source, Document target) {
  bool equal(Node a, Node b) {
    if (a.type != b.type ||
        !const DeepCollectionEquality().equals(a.attributes, b.attributes) ||
        a.children.length != b.children.length) {
      return false;
    }
    for (var index = 0; index < a.children.length; index++) {
      if (!equal(a.children[index], b.children[index])) return false;
    }
    return true;
  }

  return equal(source.root, target.root);
}
