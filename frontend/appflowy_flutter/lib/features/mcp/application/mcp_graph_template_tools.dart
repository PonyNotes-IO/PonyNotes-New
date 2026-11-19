part of 'mcp_tools.dart';

final _mcpGraphs = <String, KnowledgeGraphCubit>{};

extension _McpGraphTemplateTools on McpTools {
  List<McpToolSpec> get _graphTemplateSpecs => [
        _actionTool(
          'templates',
          '浏览/搜索/预览模板，应用模板，管理收藏及同步。',
          {
            'template_id': const JsonString(),
            'parent_id': const JsonString(),
            'query': const JsonString(),
            'category': const JsonString(),
            'scope': const JsonString(enumValues: ['all', 'personal', 'team']),
            'saved': const JsonBoolean(),
            'operation': const JsonString(enumValues: ['start', 'status']),
          },
          [
            'list_templates',
            'get_template',
            'apply_template',
            'set_template_favorite',
            'sync_templates',
            'save_template',
          ],
          _templates,
        ),
        _actionTool(
          'knowledge_graph',
          '读取混合知识图谱并启动/取消语义抽取，返回节点、边、进度与失败数量。',
          {
            'focus_view_id': const JsonString(),
            'task_id': const JsonString(),
            'operation': const JsonString(enumValues: ['status', 'cancel']),
            'offset': const JsonInteger(minimum: 0),
            'limit': const JsonInteger(minimum: 1, maximum: 500),
            'settings': const JsonObject(),
          },
          [
            'get_knowledge_graph',
            'extract_knowledge_graph',
            'knowledge_graph_task',
            'set_graph_view',
          ],
          _knowledgeGraph,
        ),
      ];

  Future<CallToolResult> _templates(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id');
    final check = await _validateWorkspace(workspace);
    if (check != null) return check;
    final action = args['action'];
    if (action == 'save_template') {
      return _error(
        'unsupported_capability',
        '当前模板产品入口支持浏览、收藏和应用，未提供创建/编辑/发布模板内容的协议。',
      );
    }
    if (action == 'sync_templates') {
      if (args['operation'] == 'status') {
        return _ok({'status': await TemplateService.getSyncStatus()});
      }
      await TemplateService.bidirectionalSync();
      return _ok({'completed': true});
    }
    final items = args['scope'] == 'personal'
        ? await TemplateService.getMyTemplates()
        : args['scope'] == 'team'
            ? await TemplateService.getTeamTemplates()
            : await TemplateService.getAllTemplates();
    if (action == 'list_templates') {
      final query = args['query'] as String? ?? '',
          category = args['category'] as String?;
      return _ok({
        'templates': items
            .where(
              (t) =>
                  (category == null || t.category == category) &&
                  (t.title.contains(query) || t.description.contains(query)),
            )
            .map((t) => t.toJson())
            .toList(),
      });
    }
    final template =
        items.where((t) => t.id == args['template_id']).firstOrNull;
    if (template == null) return _error('not_found', '模板不存在。');
    if (action == 'get_template') return _ok(template.toJson());
    if (action == 'set_template_favorite') {
      if (args['saved'] is! bool) throw const FormatException('需要saved');
      final success = args['saved'] == true
          ? await TemplateService.addTemplateToMyTemplates(template)
          : await TemplateService.removeTemplateFromMyTemplates(template.id);
      return success
          ? _ok({'saved': args['saved']})
          : _error('write_failed', '模板收藏保存失败。');
    }
    final write = await _requireWriteAccess(workspace);
    if (write != null) return write;
    final parent = _requiredString(args, 'parent_id');
    if (parent != workspace) await _scopedView(workspace, parent, write: true);
    final markdown = AppFlowyTemplateIntegration.contentForTemplate(template);
    return _createPage({
      'workspace_id': workspace,
      'parent_id': parent,
      'title': template.title,
      'markdown': markdown,
    });
  }

  Future<CallToolResult> _knowledgeGraph(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id');
    final check = await _validateWorkspace(workspace);
    if (check != null) return check;
    final identity = await _grantIdentity(), action = args['action'];
    if (action == 'set_graph_view') {
      final profile = (await _currentProfile())!;
      final key =
          'note-graph-layout-v1/${profile.id}/$workspace/${args['focus_view_id'] ?? 'global'}';
      return _ok(
        await KnowledgeGraphToolBridge.update(
          key,
          _object(args, 'settings'),
        ),
      );
    }
    if (args['focus_view_id'] != null) {
      await _scopedView(workspace, args['focus_view_id'] as String);
    }
    KnowledgeGraphCubit? graph;
    String? task = args['task_id'] as String?;
    if (task != null) {
      graph = _mcpGraphs['$identity|$task'];
      if (graph == null) return _error('not_found', '图谱任务不存在或身份已变更。');
    } else {
      if (_mcpGraphs.length >= 20) {
        final completed = _mcpGraphs.entries
            .where((entry) => !entry.value.state.extracting)
            .firstOrNull;
        if (completed == null) return _error('too_many_tasks', '图谱任务数量已达上限。');
        _mcpGraphs.remove(completed.key);
        await completed.value.close();
      }
      task = const Uuid().v4();
      graph = KnowledgeGraphCubit(
        workspaceId: workspace,
        focusViewId: args['focus_view_id'] as String?,
        loadLinks: () => NoteLinkService.read(workspaceId: workspace),
        cache: GraphExtractionCache(
          userId: (await _currentProfile())!.id.toString(),
          workspaceId: workspace,
          viewId: args['focus_view_id'] as String?,
        ),
      );
      await graph.refresh();
      _mcpGraphs['$identity|$task'] = graph;
    }
    if (action == 'extract_knowledge_graph') {
      if (!await _confirm('knowledge_graph', args)) {
        return _error('permission_denied', '未批准调用AI抽取知识图谱。');
      }
      unawaited(graph.extract());
    } else if (action == 'knowledge_graph_task' &&
        args['operation'] == 'cancel') {
      graph.cancelExtraction();
    }
    final state = graph.state;
    final offset = _intArg(args, 'offset', 0, 0, 0x7fffffff),
        limit = _intArg(args, 'limit', 400, 1, 500);
    return _ok({
      'task_id': task,
      'extracting': state.extracting,
      'completed_chunks': state.completedChunks,
      'total_chunks': state.totalChunks,
      'failed_extractions': state.failedExtractions,
      'indexed_pages': state.indexedPages,
      'truncated': state.truncated,
      'nodes': state.data.nodes
          .skip(offset)
          .take(limit)
          .map(
            (n) => {
              'id': n.id,
              'label': n.label,
              'page_id': n.view.id,
              'entity_type': n.entityType,
              'description': n.description,
            },
          )
          .toList(),
      'edges': state.data.edges
          .skip(offset)
          .take(limit)
          .map(
            (e) => {
              'source': e.source,
              'target': e.target,
              'kind': e.kind.name,
              'label': e.label,
            },
          )
          .toList(),
      'error': state.extractionError,
    });
  }
}
