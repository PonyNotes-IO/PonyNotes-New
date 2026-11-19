part of 'mcp_tools.dart';

extension _McpCloudProductTools on McpTools {
  List<McpToolSpec> get _cloudProductSpecs => [
        _actionTool(
          'data_sources',
          '数据源类型/列表/日志、连接测试、创建配置、同步控制与删除。凭据通过system_action返回的credential_ref传入。',
          {
            'base_id': const JsonString(),
            'source_id': const JsonString(),
            'operation': const JsonString(
              enumValues: [
                'types',
                'list',
                'logs',
                'resources',
                'sync',
                'pause',
                'resume',
              ],
            ),
            'type': const JsonString(),
            'name': const JsonString(),
            'config': const JsonObject(),
            'credential_ref': const JsonString(),
            'settings': const JsonObject(),
          },
          [
            'read_data_sources',
            'test_data_source',
            'create_data_source',
            'update_data_source',
            'data_source_resources',
            'control_data_source',
            'delete_data_source',
          ],
          _dataSources,
        ),
        _actionTool(
          'set_data_source_credentials',
          '由用户输入数据源凭据并更新。credential_ref内容是该数据源所需字段的JSON对象。',
          {
            'base_id': const JsonString(),
            'source_id': const JsonString(),
            'type': const JsonString(),
            'credential_ref': const JsonString(),
          },
          [],
          (args) => _dataSources(
            {...args, 'action': 'set_data_source_credentials'},
          ),
          required: const [
            'workspace_id',
            'base_id',
            'source_id',
            'type',
            'credential_ref',
          ],
        ),
        _actionTool(
          'ai_models',
          '查询内置/自定义模型，配置自定义模型，选择模型及知识库绑定。',
          {
            'base_id': const JsonString(),
            'model_id': const JsonString(),
            'source': const JsonString(
              enumValues: ['builtin', 'custom', 'knowledge'],
            ),
            'config': const JsonObject(),
            'credential_ref': const JsonString(),
          },
          [
            'list_ai_models',
            'save_ai_model',
            'delete_ai_model',
            'select_ai_model',
            'get_knowledge_model_settings',
            'bind_knowledge_models',
            'set_ai_prompt_database',
          ],
          _aiModels,
        ),
        _actionTool(
          'get_ai_usage',
          '读取当前工作区AI调用次数、积分及使用上限。',
          {},
          [],
          (args) async {
            final workspace = _requiredString(args, 'workspace_id');
            final check = await _validateWorkspace(workspace);
            if (check != null) return check;
            return _ok(
              await _cloudRequest(
                'GET',
                '/api/ai/agent/usage?workspace_id=${Uri.encodeComponent(workspace)}',
              ),
            );
          },
          required: const ['workspace_id'],
          readOnly: true,
        ),
        _actionTool(
          'agent_automations',
          '读取、创建、编辑、暂停/恢复/立即运行自动化，查看或取消运行。',
          {
            'automation_id': const JsonString(),
            'run_id': const JsonString(),
            'operation':
                const JsonString(enumValues: ['pause', 'resume', 'run']),
            'config': const JsonObject(),
            'trigger': const JsonObject(),
            'page': const JsonInteger(minimum: 1),
            'page_size': const JsonInteger(minimum: 1, maximum: 100),
          },
          [
            'list_agent_automations',
            'get_agent_automation',
            'validate_agent_trigger',
            'create_agent_automation',
            'update_agent_automation',
            'control_agent_automation',
            'delete_agent_automation',
            'list_agent_automation_runs',
            'cancel_agent_automation_run',
          ],
          _agentAutomations,
        ),
        _actionTool(
          'agent_conversations',
          '列出、创建、读取Agent会话，查询智能体与引用目录。',
          {
            'conversation_id': const JsonString(),
            'title': const JsonString(),
            'visibility': const JsonString(enumValues: ['private', 'shared']),
            'kind': const JsonString(enumValues: ['agents', 'references']),
            'offset': const JsonInteger(minimum: 0),
            'model_id': const JsonString(),
            'mode': const JsonString(
              enumValues: ['quick-answer', 'smart-reasoning'],
            ),
            'thinking': const JsonString(),
            'agent_id': const JsonString(),
            'cloud_sync': const JsonBoolean(),
          },
          [
            'list_agent_conversations',
            'create_agent_conversation',
            'get_agent_conversation',
            'list_agent_resources',
            'configure_agent_conversation',
            'update_agent_conversation',
          ],
          _agentConversations,
        ),
      ];

  Future<CallToolResult> _dataSources(Map<String, dynamic> args) async {
    final action = _requiredString(args, 'action');
    _requiredString(args, 'base_id');
    final payload = Map<String, dynamic>.from(args)..remove('action');
    final operation = switch (action) {
      'read_data_sources' => args['operation'] ?? 'list',
      'test_data_source' => 'test',
      'create_data_source' => 'create',
      'update_data_source' => 'save',
      'data_source_resources' => 'resources',
      'control_data_source' => _requiredString(args, 'operation'),
      'delete_data_source' => 'delete',
      'set_data_source_credentials' => 'credentials',
      _ => throw const FormatException('未知数据源操作'),
    };
    if (!const [
      'types',
      'list',
      'logs',
      'resources',
      'test',
      'create',
      'save',
      'credentials',
      'sync',
      'pause',
      'resume',
      'delete',
    ].contains(operation)) {
      throw const FormatException('未知数据源子操作');
    }
    if (!const ['types', 'list', 'test', 'create'].contains(operation)) {
      _requiredString(args, 'source_id');
    }
    if (args['config'] != null) payload.addAll(_object(args, 'config'));
    if (args['credential_ref'] != null) {
      final credentials = jsonDecode(
        await _resolveGrant(args['credential_ref'] as String, 'secret'),
      );
      if (credentials is! Map) throw const FormatException('凭据须为字段名到值的JSON对象');
      payload['credentials'] = credentials;
    }
    payload.remove('config');
    payload.remove('credential_ref');
    payload['workspace_id'] = args['workspace_id'];
    payload['base_id'] = args['base_id'];
    payload['source_id'] = args['source_id'];
    payload['operation'] = operation;
    if (!const ['types', 'list', 'logs', 'resources'].contains(operation) &&
        !await _confirm('data_sources', args)) {
      return _error('permission_denied', '用户未批准数据源操作。');
    }
    return _knowledge('data_source', payload);
  }

  Future<CallToolResult> _aiModels(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id'),
        action = _requiredString(args, 'action');
    final check = await _validateWorkspace(workspace);
    if (check != null) return check;
    final service = AgentInternalService();
    if (action == 'list_ai_models') {
      if (args['source'] == 'knowledge') return _knowledge('models', args);
      final builtin = await service.models();
      final custom = args['source'] == 'builtin'
          ? <Map<String, dynamic>>[]
          : await service.customModels(workspace);
      return _ok({
        'builtin': builtin
            .map(
              (m) => {
                'id': m.modelName,
                'name': m.label,
                'supports_reasoning': m.supportsReasoning,
                'supports_vision': m.supportsVision,
              },
            )
            .toList(),
        'custom': custom,
      });
    }
    if (action == 'get_knowledge_model_settings') {
      return _knowledge('model_settings', args);
    }
    if (action == 'bind_knowledge_models') {
      if (!await _confirm('ai_models', args)) {
        return _error('permission_denied', '未批准模型绑定。');
      }
      return _knowledge('model_bind', {
        ..._object(args, 'config'),
        'workspace_id': workspace,
        'base_id': _requiredString(args, 'base_id'),
      });
    }
    if (action == 'set_ai_prompt_database') {
      final payload = CustomPromptDatabaseConfigurationPB()
        ..mergeFromProto3Json(_object(args, 'config'));
      await AIEventSetCustomPromptDatabaseConfiguration(payload)
          .send()
          .getOrThrow();
      return _ok({'completed': true});
    }
    if (action == 'select_ai_model') {
      final id = _requiredString(args, 'model_id');
      AiProviderConfig? model;
      if (id.startsWith('custom:')) {
        final catalog = await service.customModels(workspace);
        final value = catalog.where((m) => m['id'] == id).firstOrNull;
        if (value != null) model = AgentInternalService.customConfig(value);
      } else {
        model = (await service.models())
            .where((m) => m.modelName == id)
            .firstOrNull;
      }
      if (model == null) return _error('not_found', '模型不存在或无权使用。');
      await service.select(model);
      return _ok({'selected': id});
    }
    if (!await _confirm('ai_models', args)) {
      return _error('permission_denied', '未批准修改模型。');
    }
    if (action == 'delete_ai_model') {
      if (args['source'] == 'knowledge') {
        return _knowledge('model_delete', {
          'workspace_id': workspace,
          'id': _requiredString(args, 'model_id'),
        });
      }
      await service.deleteCustomModel(
        workspace,
        _requiredString(args, 'model_id'),
      );
      return _ok({'deleted': true});
    }
    final config = _object(args, 'config');
    if (args['credential_ref'] != null) {
      final parameters =
          Map<String, dynamic>.from(config['parameters'] as Map? ?? {});
      parameters['api_key'] =
          await _resolveGrant(args['credential_ref'] as String, 'secret');
      config['parameters'] = parameters;
    }
    if (args['source'] == 'knowledge') {
      return _knowledge('model_save', {
        'workspace_id': workspace,
        if (args['model_id'] != null) 'id': args['model_id'],
        'model': config,
      });
    }
    return _ok({
      'model_id': await service.saveCustomModel(
        workspace,
        config,
        id: args['model_id'] as String?,
      ),
    });
  }

  Future<CallToolResult> _agentAutomations(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id'),
        action = _requiredString(args, 'action');
    final check = await _validateWorkspace(workspace);
    if (check != null) return check;
    final base = '/api/ai/agent/automations/${Uri.encodeComponent(workspace)}';
    if (action == 'list_agent_automations') {
      return _ok(await _cloudRequest('GET', base));
    }
    if (action == 'validate_agent_trigger') {
      return _ok(
        await _cloudRequest(
          'POST',
          '$base/validate-trigger',
          body: {'trigger': _object(args, 'trigger')},
        ),
      );
    }
    if (action == 'cancel_agent_automation_run') {
      return _ok(
        await _cloudRequest(
          'POST',
          '$base/runs/${Uri.encodeComponent(_requiredString(args, 'run_id'))}/cancel',
        ),
      );
    }
    if (action == 'create_agent_automation') {
      if (!await _confirm('agent_automations', args)) {
        return _error('permission_denied', '未批准创建自动化。');
      }
      return _ok(
        await _cloudRequest('POST', base, body: _object(args, 'config')),
      );
    }
    final id = Uri.encodeComponent(_requiredString(args, 'automation_id'));
    if (action == 'get_agent_automation') {
      return _ok(await _cloudRequest('GET', '$base/$id'));
    }
    if (action == 'list_agent_automation_runs') {
      return _ok(
        await _cloudRequest(
          'GET',
          '$base/$id/runs?page=${args['page'] ?? 1}&page_size=${args['page_size'] ?? 20}',
        ),
      );
    }
    if (!await _confirm('agent_automations', args)) {
      return _error('permission_denied', '未批准修改或执行自动化。');
    }
    if (action == 'update_agent_automation') {
      return _ok(
        await _cloudRequest(
          'PUT',
          '$base/$id',
          body: _object(args, 'config'),
        ),
      );
    }
    if (action == 'delete_agent_automation') {
      return _ok(await _cloudRequest('DELETE', '$base/$id'));
    }
    final operation = _requiredString(args, 'operation');
    if (!const ['pause', 'resume', 'run'].contains(operation)) {
      throw const FormatException('未知自动化控制操作');
    }
    return _ok(await _cloudRequest('POST', '$base/$id/$operation'));
  }

  Future<CallToolResult> _agentConversations(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id');
    final check = await _validateWorkspace(workspace);
    if (check != null) return check;
    final service = AgentService();
    if (args['action'] == 'update_agent_conversation') {
      return _error('unsupported_capability', '当前会话列表仅支持复制标题，未提供重命名、删除或收藏接口。');
    }
    if (args['action'] == 'configure_agent_conversation') {
      final controller = await _liveAgent(args);
      if (args['mode'] != null) {
        controller.configureMode(args['mode'] == 'smart-reasoning');
      }
      if (args['cloud_sync'] is bool) {
        await controller.configureCloudSync(args['cloud_sync'] as bool);
      }
      if (args['agent_id'] != null) {
        final agents = await controller.loadAgents();
        final agent =
            agents.where((agent) => agent.id == args['agent_id']).firstOrNull;
        if (agent == null) return _error('not_found', '智能体不存在或不可访问。');
        controller.configureAgent(agent);
      }
      if (args['model_id'] != null) {
        final internal = controller.internalService,
            id = args['model_id'] as String;
        AiProviderConfig? model;
        if (id.startsWith('custom:')) {
          final custom = (await internal.customModels(workspace))
              .where((m) => m['id'] == id)
              .firstOrNull;
          if (custom != null) model = AgentInternalService.customConfig(custom);
        } else {
          model = (await internal.models())
              .where((m) => m.modelName == id)
              .firstOrNull;
        }
        if (model == null) return _error('not_found', '模型不存在。');
        await controller.configureModel(
          model,
          args['thinking'] as String? ?? 'default',
        );
      }
      return _ok({
        'configured': true,
        'mode': controller.mode,
        'cloud_sync': controller.cloudSync,
      });
    }
    switch (args['action']) {
      case 'list_agent_conversations':
        return _ok(
          await service.request(
            'GET',
            workspace,
            '',
            '?offset=${args['offset'] ?? 0}',
          ),
        );
      case 'create_agent_conversation':
        return _ok(
          await service.request('POST', workspace, '', '', {
            'id': const Uuid().v4(),
            'title': args['title'] ?? '新对话',
            'visibility': args['visibility'] ?? 'private',
          }),
        );
      case 'get_agent_conversation':
        return _ok(
          await service.request(
            'GET',
            workspace,
            _requiredString(args, 'conversation_id'),
            '',
          ),
        );
      case 'list_agent_resources':
        return _ok(
          await service.request(
            'GET',
            workspace,
            '',
            args['kind'] == 'agents' ? '/agents' : '/references',
          ),
        );
      default:
        throw const FormatException('未知会话操作');
    }
  }
}
