import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:markdown_widget/markdown_widget.dart';
import '../application/agent_controller.dart';
import '../application/agent_attachments.dart';
import '../application/agent_permissions.dart';
import 'agent_model_settings.dart';
import 'agent_workspace_controls.dart';
import 'agent_composer.dart';
import 'ai_mode_button.dart';
import 'agent_artifact_panel.dart';
import '../application/agent_reference.dart';
import 'agent_reference_field.dart';
import 'agent_reference_preview.dart';
import 'agent_prompt_card.dart';

class AgentWorkspace extends StatefulWidget {
  const AgentWorkspace({
    super.key,
    required this.controller,
    this.initialMessage = '',
    this.initialImagePaths = const [],
    this.onInitialAccepted,
    this.initialAttachments = const [],
    this.initialReferences = const [],
    this.showModeSelector = true,
  });
  final AgentController controller;
  final String initialMessage;
  final List<String> initialImagePaths;
  final Future<void> Function()? onInitialAccepted;
  final List<PlatformFile> initialAttachments;
  final List<AgentReference> initialReferences;
  final bool showModeSelector;
  @override
  State<AgentWorkspace> createState() => _AgentWorkspaceState();
}

class _AgentWorkspaceState extends State<AgentWorkspace> {
  final input = TextEditingController();
  final scroll = ScrollController();
  final attachments = <PlatformFile>[];
  final selectedReferences = <AgentReference>[];
  AgentController get agent => widget.controller;
  bool initialPending = false;
  bool details = false;
  bool artifactPanel = false;
  bool _artifactWide = false;
  String? selectedArtifact;
  bool submitting = false;
  String behavior = 'steer';
  late int clearanceVersion;
  bool _followOutput = true;
  bool _scrollScheduled = false;

  @override
  void initState() {
    super.initState();
    clearanceVersion = agent.clearanceVersion;
    agent.addListener(_clearRevokedContext);
    agent.addListener(_followConversation);
    initialPending = widget.initialMessage.isNotEmpty;
    input.text = widget.initialMessage;
    attachments.addAll(widget.initialAttachments);
    selectedReferences.addAll(widget.initialReferences);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => unawaited(_openDocument()));
    _scrollToLatest();
  }

  void _followConversation() {
    if (_followOutput) _scrollToLatest();
  }

  void _scrollToLatest() {
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (mounted && _followOutput && scroll.hasClients) {
        scroll.jumpTo(scroll.position.maxScrollExtent);
      }
    });
  }

  void _clearRevokedContext() {
    if (clearanceVersion == agent.clearanceVersion) return;
    clearanceVersion = agent.clearanceVersion;
    input.clear();
    attachments.clear();
    selectedReferences.clear();
    initialPending = false;
    artifactPanel = false;
    selectedArtifact = null;
  }

  @override
  void dispose() {
    agent.removeListener(_clearRevokedContext);
    agent.removeListener(_followConversation);
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> _openDocument() async {
    try {
      for (final path in widget.initialImagePaths) {
        final file = File(path);
        if (await file.length() > 5 * 1024 * 1024) {
          throw StateError('图片不超过 5 MB');
        }
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        setState(
          () => attachments.add(
            PlatformFile(
              name: file.uri.pathSegments.last,
              size: bytes.length,
              bytes: bytes,
            ),
          ),
        );
      }
      await agent.connect();
      if (!mounted || !agent.connected || !initialPending) return;
      if (agent.messages.isEmpty) {
        await _send();
      } else {
        initialPending = false;
        input.clear();
        attachments.clear();
        selectedReferences.clear();
        await widget.onInitialAccepted?.call();
      }
    } catch (e) {
      agent.error = '$e';
      agent.changed();
    }
  }

  Future<void> _send() async {
    final text = input.text.trim();
    if (text.isEmpty || submitting || agent.connecting) return;
    setState(() {
      submitting = true;
      _followOutput = true;
    });
    _scrollToLatest();
    final version = agent.clearanceVersion;
    final files = <Map<String, dynamic>>[];
    try {
      validateAgentAttachments(attachments);
      for (final file in attachments) {
        files.add({
          'file_name': file.name,
          'file_size': file.size,
          'data': base64Encode(file.bytes!),
        });
      }
      final accepted = await agent.send(
        text,
        behavior: agent.running ? behavior : 'prompt',
        attachments: files,
        contextReferences: selectedReferences.toList(),
        initialRequest: initialPending ? agent.chatId : null,
      );
      if (accepted && mounted && version == agent.clearanceVersion) {
        input.clear();
        attachments.clear();
        selectedReferences.clear();
        if (initialPending) {
          initialPending = false;
          await widget.onInitialAccepted?.call();
        }
      }
    } catch (e) {
      agent.error = '$e';
      agent.changed();
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _attach() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: agentAttachmentExtensions,
    );
    if (!mounted || result == null) return;
    try {
      validateAgentAttachments([...attachments, ...result.files]);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(agentDisplayText('$e'))),
      );
      return;
    }
    setState(() => attachments.addAll(result.files));
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return ListenableBuilder(
      listenable: agent,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1080;
          final artifactWide = constraints.maxWidth >= 960;
          _artifactWide = artifactWide;
          return ColoredBox(
            color: theme.surfaceColorScheme.primary,
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 832),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.auto_awesome_outlined,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  '小马 Agent',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    agent.model,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: theme.textColorScheme.secondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                if (constraints.maxWidth >= 600)
                                  TextButton.icon(
                                    onPressed: () =>
                                        _toggleArtifacts(artifactWide),
                                    icon: const Icon(
                                      Icons.folder_open_outlined,
                                      size: 18,
                                    ),
                                    label: Text(
                                      '产物 · ${agent.savedArtifacts.length}',
                                    ),
                                  )
                                else
                                  IconButton(
                                    tooltip: '会话产物',
                                    icon: const Icon(
                                      Icons.folder_open_outlined,
                                      size: 20,
                                    ),
                                    onPressed: () =>
                                        _toggleArtifacts(artifactWide),
                                  ),
                                IconButton(
                                  tooltip: '来源与检索详情',
                                  icon: const Icon(
                                    Icons.view_sidebar_outlined,
                                    size: 20,
                                  ),
                                  onPressed: () => _toggleDetails(wide),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: agent.messages.isEmpty &&
                                    !agent.running &&
                                    !agent.connecting
                                ? _empty()
                                : _timeline(),
                          ),
                          if (agent.interactions.isNotEmpty)
                            _approval(agent.interactions.first),
                          if (agent.prompts.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight: constraints.maxHeight * .5,
                                ),
                                child: SingleChildScrollView(
                                  child: AgentPromptCard(
                                    key:
                                        ValueKey(agent.prompts.values.first.id),
                                    prompt: agent.prompts.values.first,
                                    onStop: agent.stop,
                                    onAnswer: (response) => agent.answerPrompt(
                                      agent.prompts.values.first,
                                      response,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (agent.notice != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 4,
                              ),
                              child: Text(
                                agent.notice!,
                                style: TextStyle(
                                  color: theme.textColorScheme.secondary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          if (agent.error != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                8,
                                20,
                                0,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.error_outline,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: SelectableText(
                                      agentDisplayText(agent.error!),
                                      style: TextStyle(
                                        color:
                                            Theme.of(context).colorScheme.error,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  if (!agent.connected &&
                                      !agent.connecting &&
                                      agent.messages.isNotEmpty)
                                    TextButton(
                                      onPressed: agent.connect,
                                      child: const Text('重新连接'),
                                    ),
                                ],
                              ),
                            ),
                          if (agent.prompts.isEmpty) _composer(),
                        ],
                      ),
                    ),
                  ),
                ),
                if (wide && details) SizedBox(width: 300, child: _details()),
                if (artifactWide && artifactPanel) ...[
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: constraints.maxWidth >= 1280 ? 460 : 400,
                    child: AgentArtifactPanel(
                      artifacts: agent.savedArtifacts,
                      initialKey: selectedArtifact,
                      onClose: () => setState(() => artifactPanel = false),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  void _toggleDetails(bool wide) {
    if (wide) {
      setState(() {
        details = !details;
        artifactPanel = false;
      });
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .7,
        child: _details(),
      ),
    );
  }

  void _toggleArtifacts(bool wide, [String? key]) {
    selectedArtifact = key;
    if (wide) {
      setState(() {
        artifactPanel = key != null || !artifactPanel;
        details = false;
      });
      return;
    }
    final clearance = agent.clearanceVersion;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * .88,
        child: ListenableBuilder(
          listenable: agent,
          builder: (_, __) {
            if (clearance != agent.clearanceVersion) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (sheetContext.mounted) {
                  Navigator.of(sheetContext).pop();
                }
              });
              return const SizedBox.shrink();
            }
            return AgentArtifactPanel(
              artifacts: agent.savedArtifacts,
              initialKey: key,
              onClose: () => Navigator.of(sheetContext).pop(),
            );
          },
        ),
      ),
    );
  }

  Widget _empty() => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome_outlined, size: 28),
              const SizedBox(height: 16),
              const Text(
                '把任务交给小马 Agent',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              const Text(
                '查找资料、比较笔记，或创建和整理页面、编辑数据库。需要修改时会按你的权限设置确认。',
                textAlign: TextAlign.center,
              ),
              if (!agent.connected && agent.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: OutlinedButton(
                    onPressed: agent.connect,
                    child: const Text('重试'),
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _timeline() => Stack(
        children: [
          NotificationListener<ScrollMetricsNotification>(
            onNotification: (_) {
              if (_followOutput) _scrollToLatest();
              return false;
            },
            child: NotificationListener<UserScrollNotification>(
              onNotification: (notification) {
                if (notification.depth != 0) return false;
                final following =
                    notification.direction == ScrollDirection.forward
                        ? false
                        : notification.metrics.extentAfter < 72;
                if (following != _followOutput) {
                  setState(() => _followOutput = following);
                }
                return false;
              },
              child: ListView(
                key: const Key('agent-timeline'),
                controller: scroll,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                children: [
                  for (final message in agent.messages)
                    if (message['role'] == 'user' ||
                        message['role'] == 'assistant')
                      Padding(
                        padding: const EdgeInsets.only(bottom: 22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              message['role'] == 'user' ? '你' : 'AI',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppFlowyTheme.of(context)
                                    .textColorScheme
                                    .secondary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (message['agent_steps'] is List)
                              _historyTools(message['agent_steps'] as List),
                            if (message['local_activities']
                                is List<AgentActivity>)
                              _toolFlow(
                                message['local_activities']
                                    as List<AgentActivity>,
                              ),
                            if (_messageText(message).isNotEmpty)
                              _markdown(_messageText(message)),
                            if (message['role'] == 'user')
                              ..._messageAttachments(message),
                            if (message['role'] == 'user')
                              Wrap(
                                spacing: 6,
                                children: [
                                  for (final item
                                      in (message['mentioned_items'] as List? ??
                                              [])
                                          .whereType<Map>())
                                    Chip(
                                      avatar: const Icon(
                                        Icons.alternate_email,
                                        size: 14,
                                      ),
                                      label: ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 200),
                                        child: Text(
                                          '${item['name'] ?? ''}',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            if (message['role'] == 'assistant')
                              ..._referenceLinks(
                                message['knowledge_references'],
                              ),
                            for (final prompt
                                in (message['prompt_history'] as List? ?? [])
                                    .whereType<Map>())
                              if (prompt['kind'] == 'ask_user' &&
                                  prompt['status'] != 'pending' &&
                                  prompt['status'] != 'suspended')
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  child: Text(
                                    '${(prompt['request'] as Map?)?['question'] ?? '补充信息'}\n${_promptAnswer(prompt)}',
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ),
                            ..._artifactLinks(message),
                          ],
                        ),
                      ),
                  if (agent.activities.isNotEmpty)
                    _toolFlow(agent.activities.values.toList()),
                  if (agent.streamingText.isNotEmpty)
                    _markdown(agent.streamingText),
                  if (agent.running)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              agent.prompts.isNotEmpty
                                  ? agent.prompts.values.first.kind ==
                                          'ask_user'
                                      ? '等待你的回答'
                                      : '等待你的确认'
                                  : agent.interactions.isNotEmpty
                                      ? '等待你的确认'
                                      : submitting && attachments.isNotEmpty
                                          ? '正在上传并准备附件…'
                                          : agent.progressText.isNotEmpty
                                              ? agent.progressText
                                              : '正在处理…',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (!_followOutput)
            Positioned(
              right: 16,
              bottom: 12,
              child: FilledButton.tonalIcon(
                onPressed: () {
                  setState(() => _followOutput = true);
                  _scrollToLatest();
                },
                icon: const Icon(Icons.arrow_downward, size: 16),
                label: const Text('回到最新'),
              ),
            ),
        ],
      );

  List<Widget> _messageAttachments(Map<String, dynamic> message) {
    final files = [
      ...(message['attachments'] as List? ?? []).whereType<Map>(),
      ...(message['images'] as List? ?? []).whereType<Map>().map(
            (image) => {
              'file_name': image['file_name'] ?? '图片',
              'status': 'image',
            },
          ),
    ];
    if (files.isEmpty) return [];
    final theme = AppFlowyTheme.of(context);
    return [
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: files.map((file) {
          final status = switch (file['status']) {
            'uploading' => '正在上传',
            'uploaded' || 'processing' => '解析中',
            'ready' => '解析完成',
            'failed' => '解析失败',
            'expired' => '附件已过期，请重新上传',
            'unconfirmed' => '上传未确认，请重连查看历史',
            'image' => '图片',
            _ => '已上传',
          };
          final failed =
              ['failed', 'expired', 'unconfirmed'].contains(file['status']);
          final size =
              file['file_size'] is num ? (file['file_size'] as num).toInt() : 0;
          final sizeLabel = size == 0
              ? ''
              : size < 1024 * 1024
                  ? ' · ${(size / 1024).ceil()} KB'
                  : ' · ${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
          final name = '${file['file_name'] ?? '附件'}';
          return Tooltip(
            message:
                '$name\n$status${file['error_message'] is String ? '\n${file['error_message']}' : ''}',
            child: Container(
              constraints: const BoxConstraints(maxWidth: 280),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    failed ? Icons.error_outline : Icons.description_outlined,
                    size: 18,
                    color: failed
                        ? theme.textColorScheme.error
                        : theme.textColorScheme.action,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                        Text(
                          '$status$sizeLabel',
                          style: TextStyle(
                            fontSize: 12,
                            color: failed
                                ? theme.textColorScheme.error
                                : theme.textColorScheme.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    ];
  }

  Widget _toolFlow(List<AgentActivity> activities) {
    if (activities.isEmpty) return const SizedBox.shrink();
    final failed = activities.where((a) => a.status == 'failed').length;
    final running = activities
        .where((a) => a.status == 'running' || a.status == 'waiting')
        .toList();
    return ExpansionTile(
      key: ValueKey('tool-flow-${activities.first.id}'),
      tilePadding: EdgeInsets.zero,
      title: Text(
        running.isNotEmpty
            ? '${_toolName(running.last.name)} · ${running.last.status == 'waiting' ? '等待确认' : '进行中'}'
            : '已完成 ${activities.length} 项操作${failed == 0 ? '' : '，$failed 项失败'}',
        style: const TextStyle(fontSize: 13),
      ),
      leading: Icon(
        running.isNotEmpty
            ? Icons.more_horiz
            : failed > 0
                ? Icons.error_outline
                : Icons.check_circle_outline,
        size: 18,
      ),
      children: activities.map(_activity).toList(),
    );
  }

  String _promptAnswer(Map prompt) {
    final response =
        prompt['response'] is Map ? prompt['response'] as Map : const {};
    if (response['declined'] == true) return '已跳过';
    return [
      ...(response['selected'] as List? ?? []).map((v) => '$v'),
      if (response['text'] is String) response['text'] as String,
      if (response['values'] is Map)
        ...(response['values'] as Map)
            .entries
            .map((e) => '${e.key}：${e.value}'),
    ].join(' · ');
  }

  String _toolName(String name) =>
      const {
        'thinking': '分析问题',
        'todo_write': '更新任务计划',
        'search_knowledge': '检索知识库',
        'read_document': '阅读资料',
        'list_documents': '查看资料列表',
        'query_knowledge_graph': '查询知识关系',
        'read_file': '读取文件',
        'attachment_parsing': '解析附件',
        'shell_exec': '执行任务',
        'shell_exec_async': '后台执行任务',
        'ask_user': '确认需求',
        'search_notes': '检索小马笔记',
        'write_sandbox_file': '生成文件',
        'edit_sandbox_file': '编辑文件',
        'web_search': '搜索网页',
        'get_page': '读取笔记',
        'create_page': '创建笔记',
        'append_content': '补充笔记',
        'update_page': '更新笔记',
      }[name] ??
      agentDisplayText(name);

  List<Widget> _artifactLinks(Map<String, dynamic> message) => [
        for (final file
            in (message['artifacts'] as List? ?? []).whereType<Map>())
          Builder(
            builder: (context) {
              final local = agent.artifactFiles[
                  agent.artifactKey('${message['id']}', file['index'] as int)];
              return TextButton.icon(
                onPressed: local == null
                    ? null
                    : () => _toggleArtifacts(
                          _artifactWide,
                          '${agent.chatId}/${message['id']}/${file['index']}',
                        ),
                icon: const Icon(Icons.insert_drive_file_outlined, size: 18),
                label: Text(
                  '${file['file_name']} · ${local == null ? '待保存' : file['cloud_url'] is String ? '已同步云端' : '已保存本地'}',
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          ),
      ];

  Widget _activity(AgentActivity activity) => ExpansionTile(
        tilePadding: EdgeInsets.zero,
        dense: true,
        leading: Icon(
          activity.status == 'completed'
              ? Icons.check
              : activity.status == 'failed'
                  ? Icons.error_outline
                  : Icons.search,
          size: 16,
        ),
        title: Text(
          _toolName(activity.name),
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: Text(
          activity.status == 'completed'
              ? '已完成'
              : activity.status == 'failed'
                  ? '执行失败'
                  : activity.status == 'waiting'
                      ? '等待确认'
                      : '执行中',
          style: const TextStyle(fontSize: 12),
        ),
        children: [
          if (activity.before != null) _snapshot('修改前', activity.before!),
          if (activity.after != null) _snapshot('修改后', activity.after!),
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              agentDisplayText(
                '${const JsonEncoder.withIndent('  ').convert(activity.arguments)}\n\n${activity.result}',
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      );

  Widget _historyTools(List steps) => _toolFlow([
        for (final step in steps.whereType<Map>())
          for (final call
              in (step['tool_calls'] as List? ?? []).whereType<Map>())
            _historyActivity(call),
      ]);

  AgentActivity _historyActivity(Map call) {
    final target = call['target'] is Map ? call['target'] as Map : call;
    final result = call['result'] is Map ? call['result'] as Map : const {};
    final activity = AgentActivity(
      id: '${call['id']}',
      name: '${target['tool_name'] ?? target['name'] ?? call['name']}',
      arguments: target['args'] is Map
          ? Map<String, dynamic>.from(target['args'] as Map)
          : {},
    )
      ..status = result['success'] == false ? 'failed' : 'completed'
      ..result = '${result['output'] ?? result['error'] ?? ''}';
    return activity;
  }

  Widget _snapshot(String title, String value) => ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(title, style: const TextStyle(fontSize: 13)),
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              child: SelectableText(
                agentDisplayText(value),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
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
            Text(
              '需要你确认 · ${request['title']}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (request['before'] is String)
              _snapshot('修改前', request['before'] as String),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 150),
              child: SingleChildScrollView(
                child: SelectableText(
                  agentDisplayText(
                    const JsonEncoder.withIndent('  ')
                        .convert(request['arguments']),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => agent.respond(request, false),
                  child: const Text('拒绝'),
                ),
                FilledButton(
                  onPressed: () => agent.respond(request, true),
                  child: const Text('允许这次'),
                ),
              ],
            ),
          ],
        ),
      );

  Future<void> _toolSettings() async {
    final disabled = agent.permissions.disabledTools.toSet();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('小马 Agent 笔记工具'),
          content: SizedBox(
            width: 540,
            height: MediaQuery.sizeOf(context).height * .55,
            child: ListView(
              children: agent.noteTools.toolSpecs
                  .map(
                    (spec) => CheckboxListTile(
                      value: !disabled.contains(spec.name),
                      title: Text(
                        spec.name,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        spec.description,
                        style: const TextStyle(fontSize: 12),
                      ),
                      onChanged: (value) => setDialogState(
                        () => value == true
                            ? disabled.remove(spec.name)
                            : disabled.add(spec.name),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      try {
        await agent.configurePermissions(disabled: disabled);
      } catch (e) {
        agent.error = agentDisplayText('$e');
        agent.changed();
      }
    }
  }

  List<Widget> _referenceLinks(dynamic value) {
    final ids = <String>{};
    final links = <Widget>[];
    for (final reference
        in (value is List ? value : const []).whereType<Map>()) {
      final id = '${reference['knowledge_id'] ?? ''}';
      if (!ids.add(id)) continue;
      final source = agent.sources[id];
      if (source == null) continue;
      final url = '${source['url'] ?? ''}';
      links.add(
        TextButton.icon(
          onPressed: url.isEmpty ? null : () => _openLink(url),
          icon: const Icon(Icons.description_outlined, size: 16),
          label: Text(
            agentDisplayText('${source['title']}'),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    return links;
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      if (uri.scheme == 'ponynotes' && uri.host == 'knowledge-file') {
        final id = uri.queryParameters['id'];
        if (id == null) return;
        await showDialog<void>(
          context: context,
          builder: (_) => AgentReferencePreview(
            load: (page) => agent.loadReferenceFile(id, page),
          ),
        );
      } else if (uri.scheme == 'ponynotes' && uri.host == 'open') {
        final page = uri.queryParameters['viewId'];
        if (page == null) return;
        final result = await ViewBackendService.getView(page);
        result.fold(
          (view) => getIt<TabsBloc>().openTab(view),
          (error) => throw StateError(error.msg),
        );
      } else if (uri.scheme == 'https' || uri.scheme == 'http') {
        await afLaunchUri(uri);
      }
    } catch (e) {
      agent.error = '$e';
      agent.changed();
    }
  }

  Widget _composer() => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: AgentComposer(
            input: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Focus(
                  onKeyEvent: (_, event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.escape &&
                        agent.running) {
                      unawaited(agent.stop());
                      return KeyEventResult.handled;
                    }
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.enter &&
                        !HardwareKeyboard.instance.isShiftPressed) {
                      unawaited(_send());
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: AgentReferenceField(
                    controller: input,
                    selected: selectedReferences,
                    enabled: !submitting && !agent.running && !agent.connecting,
                    load: agent.loadReferences,
                    onChanged: (items) => setState(
                      () => selectedReferences
                        ..clear()
                        ..addAll(items),
                    ),
                    child: TextField(
                      controller: input,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        hintText: '提问，或描述你想了解的内容',
                        border: InputBorder.none,
                        isDense: true,
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
                              label: Text(file.name),
                              onDeleted: submitting
                                  ? null
                                  : () => setState(
                                        () => attachments.remove(file),
                                      ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                if (agent.queuedInputs.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '待处理 ${agent.queuedInputs.length} 条补充',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
            leading: [
              if (!agent.running)
                IconButton(
                  tooltip: '添加图片或文件',
                  onPressed: submitting ? null : _attach,
                  icon: const Icon(Icons.attach_file, size: 18),
                ),
            ],
            modelSelector: AgentModelSettingsButton(
              currentConfig: agent.providerConfig,
              currentThinking: agent.connected ? agent.thinkingLevel : null,
              internalService: agent.internalService,
              enabled: !agent.running && !agent.connecting && !submitting,
              onChanged: (config, thinking) async {
                await agent.configureModel(config, thinking);
                if (!agent.connected) await agent.connect();
              },
            ),
            actions: [
              if (agent.running)
                IconButton(
                  tooltip: '停止任务',
                  onPressed: agent.stop,
                  icon: const Icon(Icons.stop_circle_outlined),
                ),
              IconButton(
                tooltip: agent.running ? '发送指令' : '发送',
                onPressed: agent.connecting || submitting ? null : _send,
                icon: const Icon(Icons.arrow_upward),
              ),
            ],
            footer: AgentWorkspaceControls(
              agent: agent,
              leading: [
                if (widget.showModeSelector)
                  AiModeButton(
                    agentMode: agent.mode == 'smart-reasoning',
                    enabled: !submitting,
                    onSelected: agent.configureMode,
                  ),
                if (agent.running)
                  DropdownButton<String>(
                    value: behavior,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(
                        value: 'steer',
                        child: Text('补充指令'),
                      ),
                      DropdownMenuItem(
                        value: 'follow_up',
                        child: Text('排队发送'),
                      ),
                    ],
                    onChanged: (value) => setState(() => behavior = value!),
                  ),
                FilterChip(
                  label: const Text('联网'),
                  selected: agent.webSearch,
                  onSelected: agent.running
                      ? null
                      : (value) => setState(() => agent.webSearch = value),
                ),
                IconButton(
                  tooltip: '笔记工具设置',
                  icon: const Icon(Icons.tune, size: 20),
                  onPressed:
                      agent.running || !agent.connected ? null : _toolSettings,
                ),
              ],
            ),
          ),
        ),
      );

  Widget _details() => ListenableBuilder(
        listenable: agent,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('引用来源', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            ..._referenceLinks(agent.references),
            if (agent.references.isEmpty) const Text('回答引用的笔记会显示在这里。'),
            const Divider(),
            const Text('检索与分析', style: TextStyle(fontWeight: FontWeight.w600)),
            for (final activity in agent.activities.values) _activity(activity),
            const Divider(),
            ...contextDetails(agent),
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

  Widget _markdown(String text) {
    final theme = AppFlowyTheme.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final codeBackground = Color.alphaBlend(
      theme.textColorScheme.action.withValues(alpha: dark ? .16 : .08),
      theme.surfaceColorScheme.primary,
    );
    return MarkdownWidget(
      data: agentDisplayText(text),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      config: (dark ? MarkdownConfig.darkConfig : MarkdownConfig.defaultConfig)
          .copy(
        configs: [
          CodeConfig(
            style: TextStyle(
              color: theme.textColorScheme.primary,
              backgroundColor: codeBackground,
            ),
          ),
          PConfig(
            textStyle: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: theme.textColorScheme.primary,
            ),
          ),
          (dark ? PreConfig.darkConfig : const PreConfig()).copy(
            decoration: BoxDecoration(
              color: codeBackground,
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: TextStyle(
              fontSize: 13,
              color: theme.textColorScheme.primary,
            ),
          ),
          LinkConfig(
            onTap: _openLink,
            style: TextStyle(color: theme.textColorScheme.action),
          ),
        ],
      ),
    );
  }
}
