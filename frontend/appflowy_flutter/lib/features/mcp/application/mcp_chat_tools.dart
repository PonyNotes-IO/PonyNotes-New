part of 'mcp_tools.dart';

class _McpChatRun {
  _McpChatRun(this.identity, this.chat, this.manager);
  final String identity, chat;
  final ChatStreamManager manager;
  String status = 'running', text = '', error = '';
  Timer? timeout;
  Future<void> finish(String state) async {
    if (status != 'running') return;
    status = state;
    timeout?.cancel();
    await manager.dispose();
  }
}

final _mcpChatRuns = <String, _McpChatRun>{};

extension _McpChatTools on McpTools {
  Future<CallToolResult> _stopChatAction(StopStreamPB request) async {
    final identity = await _grantIdentity();
    await AIEventStopStream(request).send().getOrThrow();
    for (final task in _mcpChatRuns.values.toList()) {
      if (task.identity == identity && task.chat == request.chatId) {
        await task.finish('cancelled');
      }
    }
    return _ok({'chat_id': request.chatId, 'status': 'stop_requested'});
  }

  Future<CallToolResult> _safeChatAction(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id'),
        identity = await _grantIdentity();
    final check = await _validateWorkspace(workspace);
    if (check != null) return check;
    if (args['action'] == 'read_stream') {
      final task = _mcpChatRuns[_requiredString(args, 'task_id')];
      if (task == null || task.identity != identity) {
        return _error('not_found', '生成任务不存在或身份已经改变。');
      }
      await _scopedView(workspace, task.chat);
      if (!_executionIsActive()) {
        return _error('permission_denied', '当前会话授权已结束。');
      }
      return _ok({
        'status': task.status,
        'text': task.text,
        'chat_id': task.chat,
        if (task.error.isNotEmpty) 'error': task.error,
      });
    }
    final chat = _requiredString(args, 'chat_id');
    if (_mcpChatRuns.length >= 20) {
      final old = _mcpChatRuns.entries
          .where((entry) => entry.value.status != 'running')
          .firstOrNull;
      if (old != null) _mcpChatRuns.remove(old.key);
    }
    if (_mcpChatRuns.length >= 20) {
      return _error('too_many_tasks', '当前生成任务数量已达上限。');
    }
    final view = await _scopedView(workspace, chat, write: true);
    if (view.layout != ViewLayoutPB.Chat) {
      throw const FormatException('目标不是聊天页面');
    }
    if (_mcpChatRuns.values.any(
      (run) =>
          run.identity == identity &&
          run.chat == chat &&
          run.status == 'running',
    )) {
      return _error('run_in_progress', '此聊天已有MCP生成任务，请等待完成。');
    }
    if (!await _confirm('ai_chat_action', args)) {
      return _error('permission_denied', '未批准发送AI请求。');
    }
    final manager = ChatStreamManager(chat);
    await manager.prepareStreams();
    final id = const Uuid().v4(), task = _McpChatRun(identity, chat, manager);
    _mcpChatRuns[id] = task;
    manager.answerStream!.listen(
      onData: (text) => task.text = text,
      onEnd: () => unawaited(task.finish('completed')),
      onError: (error) {
        task.error = error;
        unawaited(task.finish('failed'));
      },
    );
    task.timeout = Timer(const Duration(minutes: 5), () async {
      await manager.stopStream();
      await task.finish('timed_out');
    });
    try {
      if (args['action'] == 'send') {
        final message = await manager
            .sendStreamRequest(_requiredString(args, 'text'), null, null)
            .getOrThrow();
        return _ok({'task_id': id, 'message': message.toProto3Json()});
      }
      await manager
          .sendRegenerateRequest(
            Int64.parseInt(_requiredString(args, 'answer_message_id')),
            null,
            null,
          )
          .getOrThrow();
      return _ok({'task_id': id});
    } catch (error) {
      await task.finish('failed');
      rethrow;
    }
  }
}
