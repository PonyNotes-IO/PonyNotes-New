part of 'mcp_tools.dart';

extension _McpAgentTools on McpTools {
  List<McpToolSpec> get _agentSpecs => [
        _actionTool(
          'agent_runs',
          '控制当前窗口已打开的Agent会话：发送消息、引导、停止、查询附件或运行事件。',
          {
            'conversation_id': const JsonString(),
            'text': const JsonString(),
            'request_id': const JsonString(),
            'references': const JsonArray(items: JsonObject()),
            'source_handles': const JsonArray(items: JsonString(), maxItems: 4),
            'operation': const JsonString(enumValues: ['status', 'retry']),
          },
          [
            'send_agent_message',
            'agent_attachments',
            'stop_agent_run',
            'steer_agent_run',
            'read_agent_run',
          ],
          _agentRuns,
          required: const ['workspace_id', 'action', 'conversation_id'],
        ),
        _actionTool(
          'respond_agent_prompt',
          '由用户确认后提交Agent提问的回答。',
          {
            'conversation_id': const JsonString(),
            'prompt_id': const JsonString(),
            'response': const JsonObject(),
          },
          [],
          _respondAgentPrompt,
          required: const [
            'workspace_id',
            'conversation_id',
            'prompt_id',
            'response',
          ],
        ),
        _actionTool(
          'resolve_agent_approval',
          '弹出客户端真人确认后处理待审批工具请求；不会信任Agent自填批准标记。',
          {
            'conversation_id': const JsonString(),
            'request_id': const JsonString(),
            'decision': const JsonString(enumValues: ['allow', 'deny']),
          },
          [],
          _resolveAgentApproval,
          required: const [
            'workspace_id',
            'conversation_id',
            'request_id',
            'decision',
          ],
        ),
        _actionTool(
          'set_agent_permissions',
          '经客户端真人确认调整会话工具和审批模式。',
          {
            'conversation_id': const JsonString(),
            'disabled_tools': const JsonArray(items: JsonString()),
            'approval_mode':
                const JsonString(enumValues: ['ask', 'auto', 'full']),
          },
          [],
          _setAgentPermissions,
          required: const ['workspace_id', 'conversation_id'],
        ),
        _actionTool(
          'agent_artifacts',
          '列出Agent产物，下载到用户授权目录或提交已授权的云端产物记录。',
          {
            'conversation_id': const JsonString(),
            'message_id': const JsonString(),
            'artifact_index': const JsonInteger(minimum: 0),
            'destination_handle': const JsonString(),
            'name': const JsonString(),
            'record': const JsonObject(),
            'operation': const JsonString(),
          },
          [
            'list_agent_artifacts',
            'save_agent_artifact',
            'download_agent_artifact',
            'manage_agent_resource',
          ],
          _agentArtifacts,
          required: const ['workspace_id', 'action', 'conversation_id'],
        ),
      ];

  Future<AgentController> _liveAgent(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id');
    final error = await _validateWorkspace(workspace);
    if (error != null) throw StateError('工作区已切换');
    final controller = AgentController.forWorkspaceConversation(
      workspace,
      _requiredString(args, 'conversation_id'),
    );
    if (controller == null) throw StateError('请先在客户端打开此Agent会话，再控制运行');
    return controller;
  }

  Future<CallToolResult> _agentRuns(Map<String, dynamic> args) async {
    final controller = await _liveAgent(args);
    switch (args['action']) {
      case 'read_agent_run':
        return _ok({
          'running': controller.running,
          'progress': controller.progressText,
          'active_message_id': controller.activeMessageId,
          'activities': controller.activities.values
              .map(
                (a) => {
                  'id': a.id,
                  'name': a.name,
                  'status': a.status,
                  'result': a.result,
                },
              )
              .toList(),
          'prompts': controller.prompts.values
              .map(
                (p) => {
                  'id': p.id,
                  'message_id': p.messageId,
                  'kind': p.kind,
                  'request': p.request,
                },
              )
              .toList(),
        });
      case 'stop_agent_run':
        await controller.stop();
        return _ok({'stopped': !controller.running});
      case 'agent_attachments':
        if (args['operation'] == 'retry') {
          if (!await _confirm('agent_runs', args)) {
            return _error('permission_denied', '未批准重试附件上传');
          }
          return _ok({'retried': await controller.retryUpload()});
        }
        return _ok(
          await controller.service.request(
            'GET',
            _requiredString(args, 'workspace_id'),
            controller.chatId,
            '/attachments',
          ),
        );
      case 'send_agent_message':
        if (!await _confirm('agent_runs', args)) {
          return _error('permission_denied', '用户未批准发送消息。');
        }
        final catalog = await controller.loadReferences();
        final references =
            (args['references'] as List? ?? []).cast<Map>().map((requested) {
          return catalog
                  .where(
                    (item) =>
                        item.id == requested['id'] &&
                        item.kind == requested['kind'],
                  )
                  .firstOrNull ??
              (throw const FormatException('引用不在当前会话可访问目录中'));
        }).toList();
        final files = <PlatformFile>[];
        for (final handle
            in (args['source_handles'] as List? ?? []).cast<String>()) {
          final file = File(await _resolveGrant(handle, 'file'));
          final length = await file.length();
          if (length > 5 * 1024 * 1024) {
            throw const FormatException('附件不得超过5 MB');
          }
          files.add(
            PlatformFile(
              name: paths.basename(file.path),
              size: length,
              bytes: await file.readAsBytes(),
            ),
          );
        }
        validateAgentAttachments(files);
        final sent = await controller.send(
          _requiredString(args, 'text'),
          contextReferences: references,
          attachments: files
              .map(
                (file) => {
                  'file_name': file.name,
                  'file_size': file.size,
                  'data': base64Encode(file.bytes!),
                },
              )
              .toList(),
        );
        return sent
            ? _ok({'started': true, 'conversation_id': controller.chatId})
            : _error('send_failed', controller.error ?? '消息发送失败');
      case 'steer_agent_run':
        final sent = await controller.send(
          _requiredString(args, 'text'),
          behavior: 'steer',
        );
        return sent
            ? _ok({'submitted': true})
            : _error('send_failed', controller.error ?? '引导提交失败');
      default:
        throw const FormatException('未知运行操作');
    }
  }

  Future<CallToolResult> _respondAgentPrompt(Map<String, dynamic> args) async {
    final controller = await _liveAgent(args);
    final prompt = controller.prompts[_requiredString(args, 'prompt_id')];
    if (prompt == null) return _error('not_found', '待回答提问不存在。');
    if (!await _confirm('respond_agent_prompt', args)) {
      return _error('permission_denied', '用户未批准提交回答。');
    }
    await controller.answerPrompt(prompt, _object(args, 'response'));
    return prompt.error == null
        ? _ok({'status': prompt.status})
        : _error('submit_failed', prompt.error!);
  }

  Future<CallToolResult> _resolveAgentApproval(
    Map<String, dynamic> args,
  ) async {
    final controller = await _liveAgent(args);
    final request = controller.interactions
        .where((item) => item['id'] == args['request_id'])
        .firstOrNull;
    if (request == null) return _error('not_found', '待审批请求不存在。');
    if (!await _confirm(
      'resolve_agent_approval',
      {...args, 'target_request': request['name']},
    )) {
      return _error('permission_denied', '用户未批准处理此请求。');
    }
    controller.respond(request, args['decision'] == 'allow');
    return _ok({'resolved': args['request_id'], 'decision': args['decision']});
  }

  Future<CallToolResult> _setAgentPermissions(Map<String, dynamic> args) async {
    final controller = await _liveAgent(args);
    final disabled = (args['disabled_tools'] as List?)?.cast<String>().toSet();
    if (disabled != null &&
        disabled.any((name) => !toolSpecs.any((spec) => spec.name == name))) {
      throw const FormatException('工具名不存在');
    }
    if (!await _confirm('set_agent_permissions', args)) {
      return _error('permission_denied', '用户未批准修改Agent权限。');
    }
    await controller.configurePermissions(
      mode: args['approval_mode'] as String?,
      disabled: disabled,
    );
    return _ok({
      'approval_mode': controller.permissions.mode,
      'disabled_tools': controller.permissions.disabledTools.toList(),
    });
  }

  Future<CallToolResult> _agentArtifacts(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id'),
        conversation = _requiredString(args, 'conversation_id');
    final check = await _validateWorkspace(workspace);
    if (check != null) return check;
    final service = AgentService();
    if (args['action'] == 'manage_agent_resource') {
      return _error(
        'unsupported_capability',
        '当前产品未提供产物删除、消息删除或智能体分享的客户端管理接口。',
      );
    }
    if (args['action'] == 'list_agent_artifacts') {
      final data = await service.request('GET', workspace, conversation, '');
      return _ok({'history': data});
    }
    if (args['action'] == 'save_agent_artifact' && args['record'] != null) {
      if (!await _confirm('agent_artifacts', args)) {
        return _error('permission_denied', '用户未批准保存产物。');
      }
      return _ok(
        await service.request(
          'POST',
          workspace,
          conversation,
          '/artifacts',
          _object(args, 'record'),
        ),
      );
    }
    final directory = await _resolveGrant(
      _requiredString(args, 'destination_handle'),
      'directory',
    );
    final name = _requiredString(args, 'name');
    if (paths.basename(name) != name) throw const FormatException('文件名包含路径');
    final target = File(paths.join(directory, name));
    if (await target.exists()) return _error('conflict', '输出文件已存在');
    await service.downloadArtifact(
      await service.identity(workspace),
      workspace,
      conversation,
      _requiredString(args, 'message_id'),
      args['artifact_index'] as int,
      target,
    );
    return _ok({'saved': name});
  }
}
