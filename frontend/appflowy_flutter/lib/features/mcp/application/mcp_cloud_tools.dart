part of 'mcp_tools.dart';

extension _McpCloudTools on McpTools {
  List<McpToolSpec> get _cloudSpecs => [
        _actionTool(
          'knowledge_bases',
          '列出、创建、收藏及修改知识库可见性。',
          {
            'base_id': const JsonString(),
            'request_id':
                const JsonString(description: '创建知识库的幂等请求UUID，重试使用同一值'),
            'name': const JsonString(),
            'visibility': const JsonString(enumValues: ['private', 'shared']),
            'favorite': const JsonBoolean(),
          },
          [
            'list_knowledge_bases',
            'create_knowledge_base',
            'set_knowledge_base_visibility',
            'set_knowledge_base_favorite',
            'manage_knowledge_resource',
          ],
          _knowledgeBases,
        ),
        _actionTool(
          'knowledge_documents',
          '读取知识文档、来源、Wiki、网页导入选项或导入网页。',
          {
            'base_id': const JsonString(),
            'document_id': const JsonString(),
            'wiki_page_id': const JsonString(),
            'page': const JsonInteger(minimum: 1),
            'page_size': const JsonInteger(minimum: 1, maximum: 100),
            'url': const JsonString(),
            'options': const JsonObject(),
          },
          [
            'list_knowledge_documents',
            'get_knowledge_document',
            'list_knowledge_sources',
            'read_knowledge_wiki',
            'get_web_import_options',
            'import_knowledge_url',
          ],
          _knowledgeDocuments,
        ),
        _actionTool(
          'search_knowledge',
          '按工作区和知识库执行语义检索，不包含未授权知识库。',
          {
            'base_id': const JsonString(),
            'query': const JsonString(minLength: 1, maxLength: 2000),
            'limit': const JsonInteger(minimum: 1, maximum: 100),
          },
          [],
          (args) => _knowledge('search', args),
          required: const ['workspace_id', 'base_id', 'query'],
          readOnly: true,
        ),
      ];

  Future<Map<String, dynamic>> _cloudRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (!path.startsWith('/api/') || path.contains('://')) {
      throw const FormatException('无效的业务路径');
    }
    final account = await cloudAccount();
    final request = http.Request(method, Uri.parse('${account.baseUrl}$path'))
      ..followRedirects = false
      ..headers['Authorization'] = 'Bearer ${account.accessToken}';
    if (path == '/api/import/create') {
      request.headers['X-Host'] = account.baseUrl;
    }
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final client = http.Client();
    try {
      final response =
          await http.Response.fromStream(await client.send(request))
              .timeout(const Duration(seconds: 55));
      final current = await cloudAccount();
      if (current.userId != account.userId ||
          current.baseUrl != account.baseUrl) {
        throw StateError('账号或后端已切换');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('业务请求失败（HTTP ${response.statusCode}）');
      }
      if (response.bodyBytes.isEmpty) return {};
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map) throw const FormatException('业务服务返回无效数据');
      if (data['success'] == false ||
          (data['code'] != null && data['code'] != 0)) {
        throw StateError('业务服务拒绝操作');
      }
      return Map<String, dynamic>.from(data);
    } finally {
      client.close();
    }
  }

  Future<CallToolResult> _knowledge(
    String action,
    Map<String, dynamic> args,
  ) async {
    final workspace = _requiredString(args, 'workspace_id');
    final check = await _validateWorkspace(workspace);
    if (check != null) return check;
    final payload = Map<String, dynamic>.from(args)..remove('action');
    final response =
        await _cloudRequest('POST', '/api/knowledge/$action', body: payload);
    final after = await _validateWorkspace(workspace);
    if (after != null) return after;
    return _ok(response);
  }

  Future<CallToolResult> _knowledgeBases(Map<String, dynamic> args) async {
    final action = _requiredString(args, 'action');
    final payload = Map<String, dynamic>.from(args);
    switch (action) {
      case 'manage_knowledge_resource':
        return _error(
          'unsupported_capability',
          '当前知识库业务API仅提供创建、可见性、收藏、读取、导入和同步；重命名/删除/重解析未接入此产品服务。',
        );
      case 'list_knowledge_bases':
        return _knowledge('bases', payload);
      case 'create_knowledge_base':
        _requiredString(args, 'name');
        _requiredString(args, 'visibility');
        _requiredString(args, 'request_id');
        return _knowledge('create', payload);
      case 'set_knowledge_base_favorite':
        _requiredString(args, 'base_id');
        if (args['favorite'] is! bool) {
          throw const FormatException('需要favorite');
        }
        payload['is_favorite'] = payload.remove('favorite');
        return _knowledge('favorite', payload);
      case 'set_knowledge_base_visibility':
        _requiredString(args, 'base_id');
        _requiredString(args, 'visibility');
        if (!await _confirm('knowledge_bases', args)) {
          return _error('permission_denied', '未批准知识库可见性变更。');
        }
        return _knowledge('visibility', payload);
      default:
        throw const FormatException('未知知识库操作');
    }
  }

  Future<CallToolResult> _knowledgeDocuments(Map<String, dynamic> args) async {
    _requiredString(args, 'base_id');
    final payload = Map<String, dynamic>.from(args);
    final action = switch (args['action']) {
      'list_knowledge_documents' => 'documents',
      'get_knowledge_document' => 'document',
      'list_knowledge_sources' => 'sources',
      'read_knowledge_wiki' =>
        args['wiki_page_id'] == null ? 'wiki' : 'wiki_page',
      'get_web_import_options' => 'web_import_options',
      'import_knowledge_url' => 'import_url',
      _ => throw const FormatException('未知知识文档操作'),
    };
    if (args['wiki_page_id'] != null) {
      payload['slug'] = payload.remove('wiki_page_id');
    }
    if (action == 'import_url') {
      _requiredString(args, 'url');
      if (args['options'] != null) payload.addAll(_object(args, 'options'));
      payload['workspace_id'] = args['workspace_id'];
      payload['base_id'] = args['base_id'];
    }
    payload.remove('options');
    return _knowledge(action, payload);
  }

  Future<CallToolResult> _joinWorkspaceByCode(
    Map<String, dynamic> args,
  ) async =>
      _ok(
        await _cloudRequest(
          'POST',
          '/api/workspace/join-by-invite-code',
          body: {'code': _requiredString(args, 'invite_code')},
        ),
      );
}
