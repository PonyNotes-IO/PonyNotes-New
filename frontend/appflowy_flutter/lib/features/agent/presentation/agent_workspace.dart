import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:appflowy/features/ai_internal/presentation/ai_provider_settings_view.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown_widget/markdown_widget.dart';
import '../application/agent_controller.dart';
import 'agent_settings_dialog.dart';

class AgentWorkspace extends StatefulWidget {
  const AgentWorkspace({
    super.key,
    required this.controller,
    this.onChat,
    this.modeControl,
    this.chatContext,
  });
  final AgentController controller;
  final VoidCallback? onChat;
  final Widget? modeControl;
  final String Function()? chatContext;
  @override
  State<AgentWorkspace> createState() => _AgentWorkspaceState();
}

class _AgentWorkspaceState extends State<AgentWorkspace> {
  final input = TextEditingController();
  final scroll = ScrollController();
  String behavior = 'steer';
  bool details = false;
  String? handover;
  final attachments = <PlatformFile>[];
  AgentController get agent => widget.controller;
  int clearanceVersion = 0;
  @override
  void initState() {
    super.initState();
    clearanceVersion = agent.clearanceVersion;
    agent.addListener(_clearRevokedContext);
  }

  void _clearRevokedContext() {
    if (clearanceVersion == agent.clearanceVersion) return;
    clearanceVersion = agent.clearanceVersion;
    input.clear();
    attachments.clear();
    handover = null;
  }

  @override
  void dispose() {
    agent.removeListener(_clearRevokedContext);
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final sentVersion = agent.clearanceVersion;
    final text = input.text.trim();
    if (text.isEmpty || agent.connecting) return;
    input.clear();
    final images = <Map<String, dynamic>>[];
    final textFiles = StringBuffer();
    if (handover != null) textFiles.write('\n\n用户确认引入的 Chat 上下文：\n$handover');
    for (final file in attachments) {
      final bytes = file.bytes!;
      final ext = (file.extension ?? '').toLowerCase();
      if (['png', 'jpg', 'jpeg', 'webp', 'gif'].contains(ext)) {
        images.add({
          'type': 'image',
          'data': base64Encode(bytes),
          'mimeType': ext == 'jpg' ? 'image/jpeg' : 'image/$ext',
        });
      } else {
        textFiles.write(
          '\n\n用户提供的附件 ${file.name}：\n${utf8.decode(bytes, allowMalformed: true)}',
        );
      }
    }
    try {
      await agent.send(
        '$text$textFiles',
        behavior: agent.running ? behavior : 'prompt',
        images: images,
      );
    } catch (e) {
      agent.error = '$e';
      agent.changed();
    }
    if (agent.connected && mounted) setState(attachments.clear);
    if (!agent.connected && mounted && sentVersion == agent.clearanceVersion) {
      input.text = text;
    }
  }

  Future<void> _attach() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: [
        'txt',
        'md',
        'json',
        'csv',
        'dart',
        'rs',
        'js',
        'ts',
        'py',
        'png',
        'jpg',
        'jpeg',
        'webp',
        'gif',
      ],
    );
    if (!mounted || result == null) return;
    if (result.files
            .any((file) => file.size > 5 * 1024 * 1024 || file.bytes == null) ||
        attachments.length + result.files.length > 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('最多添加 4 个附件，每个文件不超过 5 MB')),
      );
      return;
    }
    setState(() => attachments.addAll(result.files));
  }

  Future<void> _settings() async {
    if (await showAgentSettings(context)) {
      await agent.disconnect();
    }
  }

  Future<void> _handover() async {
    final text = widget.chatContext?.call() ?? '';
    if (text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('当前 Chat 还没有可引入的内容')));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('引入 Chat 上下文'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(child: SelectableText(text)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('加入下一条任务'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) setState(() => handover = text);
  }

  Future<void> _model() async {
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: SizedBox(
          width: 640,
          height: MediaQuery.sizeOf(context).height * .8,
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: '关闭模型设置',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
              const Expanded(child: AiProviderSettingsView()),
            ],
          ),
        ),
      ),
    );
    await agent.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return ListenableBuilder(
      listenable: agent,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1080;
          return ColoredBox(
            color: theme.surfaceColorScheme.primary,
            child: Row(
              children: [
                if (wide && agent.connected)
                  SizedBox(width: 205, child: _history()),
                Expanded(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.auto_awesome_outlined, size: 18),
                            const SizedBox(width: 8),
                            const Text(
                              'Agent',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                agent.connecting
                                    ? '正在连接…'
                                    : '${agent.location}${agent.model.isEmpty ? '' : ' · ${agent.model}'}',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: theme.textColorScheme.secondary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            if (!wide && agent.connected)
                              IconButton(
                                tooltip: '会话历史',
                                icon: const Icon(Icons.history, size: 20),
                                onPressed: () => showModalBottomSheet<void>(
                                  context: context,
                                  builder: (_) => _history(),
                                ),
                              ),
                            IconButton(
                              tooltip: '上下文与操作详情',
                              icon: const Icon(
                                Icons.view_sidebar_outlined,
                                size: 20,
                              ),
                              onPressed: () {
                                if (wide) {
                                  setState(() => details = !details);
                                } else {
                                  showModalBottomSheet<void>(
                                    context: context,
                                    isScrollControlled: true,
                                    builder: (_) => SizedBox(
                                      height:
                                          MediaQuery.sizeOf(context).height *
                                              .7,
                                      child: _details(),
                                    ),
                                  );
                                }
                              },
                            ),
                            IconButton(
                              tooltip: '模型设置',
                              icon: const Icon(Icons.memory_outlined, size: 20),
                              onPressed: agent.running ? null : _model,
                            ),
                            IconButton(
                              tooltip: 'Agent 设置',
                              icon: const Icon(Icons.tune, size: 20),
                              onPressed: agent.running ? null : _settings,
                            ),
                          ],
                        ),
                      ),
                      if (agent.steps.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: Text(
                              '任务步骤 · ${agent.steps.where((s) => s['status'] == 'completed').length}/${agent.steps.length}',
                              style: const TextStyle(fontSize: 13),
                            ),
                            children: agent.steps
                                .map(
                                  (step) => ListTile(
                                    dense: true,
                                    leading: Icon(
                                      step['status'] == 'completed'
                                          ? Icons.check_circle_outline
                                          : step['status'] == 'failed'
                                              ? Icons.error_outline
                                              : Icons.radio_button_unchecked,
                                      size: 16,
                                    ),
                                    title: Text('${step['title']}'),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      Expanded(
                        child: agent.messages.isEmpty && !agent.running
                            ? _empty()
                            : _timeline(),
                      ),
                      if (agent.interactions.isNotEmpty)
                        _approval(agent.interactions.first),
                      if (agent.authorizationUrl != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: TextButton.icon(
                            onPressed: () => afLaunchUri(
                              Uri.parse(agent.authorizationUrl!),
                            ),
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('打开 MCP 登录授权页面'),
                          ),
                        ),
                      if (agent.error != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: SelectableText(
                                  agent.error!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      _composer(),
                    ],
                  ),
                ),
                if (wide && details) SizedBox(width: 300, child: _details()),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _empty() => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_awesome_outlined, size: 28),
                const SizedBox(height: 16),
                const Text(
                  '把任务交给 Agent',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                const Text(
                  '查找资料、整理笔记，或完成多步骤任务。写入前会请求确认。',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: agent.connecting ? null : agent.connect,
                  child: Text(agent.connecting ? '正在连接…' : '连接执行器'),
                ),
                TextButton(
                  onPressed: _settings,
                  child: const Text('配置执行环境与 MCP'),
                ),
              ],
            ),
          ),
        ),
      );
  Widget _timeline() => ListView(
        controller: scroll,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        children: [
          for (final message in agent.messages)
            if ((message['role'] == 'user' || message['role'] == 'assistant') &&
                _messageText(message).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message['role'] == 'user' ? '你' : 'Agent',
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            AppFlowyTheme.of(context).textColorScheme.secondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _markdown(_messageText(message)),
                  ],
                ),
              )
            else if (message['role'] == 'toolResult')
              _historyActivity(message),
          if (agent.streamingText.isNotEmpty) _markdown(agent.streamingText),
          for (final activity in agent.activities.values
              .where((activity) => activity.status == 'running'))
            _activity(activity),
          if (agent.running)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    agent.interactions.isNotEmpty
                        ? '等待你的确认'
                        : agent.compacting
                            ? '正在压缩上下文…'
                            : '正在执行…',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
        ],
      );
  Widget _historyActivity(Map<String, dynamic> message) {
    final activity = AgentActivity(
      id: '${message['toolCallId']}',
      name: '${message['toolName']}',
      arguments: const {},
    );
    activity.status = message['isError'] == true ? 'failed' : 'completed';
    activity.result = _messageText(message);
    final details = message['details'] as Map?;
    activity.before = details?['before'] as String?;
    activity.after = details?['after'] as String?;
    return _activity(activity);
  }

  Widget _activity(AgentActivity activity) => ExpansionTile(
        tilePadding: EdgeInsets.zero,
        dense: true,
        leading: Icon(
          activity.status == 'completed'
              ? Icons.check
              : activity.status == 'failed'
                  ? Icons.error_outline
                  : Icons.build_outlined,
          size: 16,
        ),
        title: Text(activity.name, style: const TextStyle(fontSize: 13)),
        subtitle: Text(
          activity.status == 'completed'
              ? '已完成'
              : activity.status == 'failed'
                  ? '执行失败'
                  : '执行中',
          style: const TextStyle(fontSize: 12),
        ),
        children: [
          if (activity.before != null) _snapshot('修改前', activity.before!),
          if (activity.after != null) _snapshot('修改后', activity.after!),
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              '${const JsonEncoder.withIndent('  ').convert(activity.arguments)}\n\n${activity.result}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      );
  Widget _snapshot(String title, String text) => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: SelectableText(
                    text,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  Widget _approval(Map<String, dynamic> request) => Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (request['before'] is String)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('查看修改前内容', style: TextStyle(fontSize: 13)),
                children: [_snapshot('当前页面', request['before'] as String)],
              ),
            Text(
              '需要你确认 · ${request['title']}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 150),
              child: SingleChildScrollView(
                child: SelectableText(
                  request['arguments'] == null
                      ? '${request['message'] ?? ''}'
                      : const JsonEncoder.withIndent('  ')
                          .convert(request['arguments']),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                if (request['type'] == 'select')
                  ...((request['options'] as List? ?? []).map(
                    (option) => OutlinedButton(
                      onPressed: () => agent.respond(request, option),
                      child: Text('$option'),
                    ),
                  ))
                else if (request['type'] == 'input')
                  TextButton(
                    onPressed: () async {
                      final controller = TextEditingController();
                      final value = await showDialog<String>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text('${request['title']}'),
                          content: TextField(controller: controller),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(
                                context,
                                controller.text,
                              ),
                              child: const Text('提交'),
                            ),
                          ],
                        ),
                      );
                      controller.dispose();
                      agent.respond(request, value);
                    },
                    child: const Text('填写'),
                  )
                else
                  FilledButton(
                    onPressed: () => agent.respond(request, true),
                    child: const Text('允许这次'),
                  ),
                TextButton(
                  onPressed: () => agent.respond(request, false),
                  child: const Text('拒绝'),
                ),
              ],
            ),
          ],
        ),
      );
  Widget _composer() => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Shortcuts(
                  shortcuts: {
                    const SingleActivator(LogicalKeyboardKey.escape):
                        const _StopAgentIntent(),
                    const SingleActivator(LogicalKeyboardKey.enter):
                        const _SendAgentIntent(),
                  },
                  child: Actions(
                    actions: {
                      _StopAgentIntent: CallbackAction<_StopAgentIntent>(
                        onInvoke: (_) {
                          agent.stop();
                          return null;
                        },
                      ),
                      _SendAgentIntent: CallbackAction<_SendAgentIntent>(
                        onInvoke: (_) {
                          _send();
                          return null;
                        },
                      ),
                    },
                    child: TextField(
                      controller: input,
                      minLines: 1,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        hintText: '描述任务，或补充一条指令',
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (agent.queuedInputs.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Tooltip(
                      message: agent.queuedInputs.join('\n'),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '待执行 ${agent.queuedInputs.length} 条指令',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                if (attachments.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 6,
                      children: attachments
                          .map(
                            (file) => InputChip(
                              label: Text(
                                file.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onDeleted: () =>
                                  setState(() => attachments.remove(file)),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                Row(
                  children: [
                    if (widget.chatContext != null && !agent.running)
                      IconButton(
                        tooltip: '引入 Chat 上下文',
                        onPressed: _handover,
                        icon: const Icon(Icons.add_comment_outlined, size: 18),
                      ),
                    if (!agent.running)
                      IconButton(
                        tooltip: '添加图片或文本附件',
                        onPressed: agent.running ? null : _attach,
                        icon: const Icon(Icons.attach_file, size: 18),
                      ),
                    widget.modeControl ??
                        TextButton(
                          onPressed: agent.running ? null : widget.onChat,
                          child: const Text('Agent ▾'),
                        ),
                    if (agent.running)
                      DropdownButton<String>(
                        value: behavior,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(value: 'steer', child: Text('补充指令')),
                          DropdownMenuItem(
                            value: 'follow_up',
                            child: Text('排队发送'),
                          ),
                        ],
                        onChanged: (value) => setState(() => behavior = value!),
                      ),
                    const Spacer(),
                    if (agent.running)
                      IconButton(
                        tooltip: '停止任务',
                        onPressed: agent.stop,
                        icon: const Icon(Icons.stop_circle_outlined),
                      ),
                    IconButton(
                      tooltip: agent.running ? '发送指令' : '发送任务',
                      onPressed: agent.connecting ? null : _send,
                      icon: const Icon(Icons.arrow_upward),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
  Widget _history() => ListenableBuilder(
        listenable: agent,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            TextButton.icon(
              onPressed: agent.running
                  ? null
                  : () => _guard(() => agent.selectSession(null)),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新任务'),
            ),
            for (final session in agent.sessions)
              ListTile(
                dense: true,
                leading: const Icon(Icons.chat_bubble_outline, size: 16),
                title: Text(
                  '${session['name'] ?? session['firstMessage'] ?? 'Agent 会话'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: agent.running
                    ? null
                    : () => _guard(
                          () => agent.selectSession('${session['id']}'),
                        ),
              ),
          ],
        ),
      );
  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      agent.error = '$e';
      agent.changed();
    }
  }

  Widget _details() => ListenableBuilder(
        listenable: agent,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('上下文', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Text('${agent.model}\n${agent.location}'),
            const SizedBox(height: 8),
            Text(
              agent.contextUsage == null
                  ? '开始对话后显示上下文用量'
                  : '上下文用量：${agent.contextUsage!['tokens'] ?? '—'} tokens',
            ),
            TextButton.icon(
              onPressed: !agent.connected || agent.running || agent.compacting
                  ? null
                  : agent.compact,
              icon: const Icon(Icons.compress, size: 16),
              label: Text(agent.compacting ? '正在压缩…' : '压缩上下文'),
            ),
            const Divider(),
            if (handover != null)
              InputChip(
                label: const Text('已引入 Chat 上下文'),
                onDeleted: () => setState(() => handover = null),
              ),
            const Text('操作与产物', style: TextStyle(fontWeight: FontWeight.w600)),
            ..._artifacts(),
            for (final activity in agent.activities.values) _activity(activity),
            if (agent.connected)
              TextButton(
                onPressed: agent.running ? null : agent.disconnect,
                child: const Text('断开执行器'),
              ),
          ],
        ),
      );
  String _messageText(Map<String, dynamic> message) {
    final content = message['content'];
    if (content is String) return content;
    return (content as List? ?? [])
        .whereType<Map>()
        .where((part) => part['type'] == 'text')
        .map((part) => part['text'] ?? '')
        .join('\n');
  }

  List<Widget> _artifacts() {
    final pages = <String, String>{};
    void collect(dynamic value, int depth) {
      if (depth > 5) return;
      if (value is Map) {
        if (value['page_id'] is String) {
          pages[value['page_id'] as String] =
              '${value['name'] ?? value['title'] ?? value['page_id']}';
        }
        for (final nested in value.values) {
          collect(nested, depth + 1);
        }
      } else if (value is List) {
        for (final nested in value) {
          collect(nested, depth + 1);
        }
      }
    }

    for (final message in agent.messages.where(
      (message) =>
          message['role'] == 'toolResult' && message['isError'] != true,
    )) {
      try {
        collect(jsonDecode(_messageText(message)), 0);
      } on FormatException {/* Tool results can also be plain text. */}
    }
    return pages.entries
        .map(
          (entry) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined, size: 18),
            title:
                Text(entry.value, maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.open_in_new, size: 16),
            onTap: () => _guard(() async {
              final result = await ViewBackendService.getView(entry.key);
              result.fold(
                (view) => getIt<TabsBloc>().openTab(view),
                (error) => throw StateError(error.msg),
              );
            }),
          ),
        )
        .toList();
  }

  Widget _markdown(String text) {
    final theme = AppFlowyTheme.of(context);
    return MarkdownWidget(
      data: text,
      shrinkWrap: true,
      config: MarkdownConfig(
        configs: [
          PConfig(
            textStyle: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: theme.textColorScheme.primary,
            ),
          ),
          PreConfig(
            decoration: BoxDecoration(
              color: theme.fillColorScheme.contentHover,
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle:
                TextStyle(fontSize: 13, color: theme.textColorScheme.primary),
          ),
        ],
      ),
    );
  }
}

class _StopAgentIntent extends Intent {
  const _StopAgentIntent();
}

class _SendAgentIntent extends Intent {
  const _SendAgentIntent();
}
