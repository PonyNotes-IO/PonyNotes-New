import 'dart:async';
import 'package:appflowy/features/ai_internal/application/ai_provider_config.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../application/agent_conversations.dart';
import '../application/agent_attachments.dart';
import '../application/agent_controller.dart';
import '../application/agent_model_preferences.dart';
import 'agent_workspace.dart';
import 'agent_model_settings.dart';
import 'agent_artifact_library.dart';
import 'ai_mode_button.dart';
import '../application/agent_reference.dart';
import 'agent_reference_field.dart';
import 'agent_composer.dart';

class AgentConversationsPage extends StatefulWidget {
  const AgentConversationsPage({
    super.key,
    this.conversations,
    this.onLegacy,
    this.controllerFactory,
    this.initialMessage = '',
    this.initialAttachments = const [],
  });
  final AgentConversations? conversations;
  final VoidCallback? onLegacy;
  final AgentController Function(AgentConversation, String)? controllerFactory;
  final String initialMessage;
  final List<PlatformFile> initialAttachments;
  @override
  State<AgentConversationsPage> createState() => _AgentConversationsPageState();
}

class _AgentConversationsPageState extends State<AgentConversationsPage> {
  late final sessions = widget.conversations ?? AgentConversations();
  late final input = TextEditingController(text: widget.initialMessage);
  late final files = widget.initialAttachments.toList();
  final scaffold = GlobalKey<ScaffoldState>();
  AgentController? active;
  String initialMessage = '';
  List<PlatformFile> initialFiles = [];
  final selectedReferences = <AgentReference>[];
  List<AgentReference> initialReferences = [];
  AiProviderConfig? model;
  String thinking = AgentModelPreferences.defaultLevel;
  bool smart = true;
  String? uploadError;
  bool wasRunning = false;
  bool revoked = false;

  @override
  void initState() {
    super.initState();
    AgentController.accountClearance.addListener(_revoke);
    AgentConversations.requestedConversation.addListener(_requested);
    AgentConversations.requestedPrompt.addListener(_prompt);
    unawaited(_load());
  }

  Future<void> _load() async {
    await sessions.load();
    if (!mounted) return;
    final thinking = await AgentModelPreferences.loadThinking();
    if (!mounted) return;
    setState(() => this.thinking = thinking);
    final id = AgentConversations.requestedConversation.value;
    if (id != null) _selectRequested(id);
    _prompt();
  }

  void _prompt() {
    final request = AgentConversations.requestedPrompt.value;
    if (request == null || revoked || sessions.loading) return;
    input.text = request.$1;
    selectedReferences.clear();
    files
      ..clear()
      ..addAll(request.$2);
    AgentConversations.requestedPrompt.value = null;
    unawaited(_create(send: true));
  }

  void _requested() {
    final id = AgentConversations.requestedConversation.value;
    if (id == null || revoked) return;
    final row = sessions.entries.where((entry) => entry.id == id).firstOrNull;
    if (row == null) {
      if (!sessions.loading) {
        unawaited(_load());
      }
      return;
    }
    AgentConversations.requestedConversation.value = null;
    _open(row);
  }

  void _selectRequested(String id) {
    final row = sessions.entries.where((entry) => entry.id == id).firstOrNull;
    if (row != null && !revoked) {
      AgentConversations.requestedConversation.value = null;
      _open(row);
    }
  }

  void _revoke() {
    active?.removeListener(_activity);
    active?.dispose();
    active = null;
    sessions.clear();
    input.clear();
    files.clear();
    selectedReferences.clear();
    initialReferences = [];
    if (mounted) setState(() => revoked = true);
  }

  void _activity() {
    if (wasRunning && active?.running == false) unawaited(_load());
    wasRunning = active?.running ?? false;
  }

  void _open(
    AgentConversation row, {
    String message = '',
    List<PlatformFile> attachments = const [],
    List<AgentReference> references = const [],
    bool? smartMode,
  }) {
    if (active?.chatId == row.id) return;
    active?.removeListener(_activity);
    active?.dispose();
    active = widget.controllerFactory?.call(row, sessions.workspaceId!) ??
        AgentController(
          chatId: row.id,
          documentName: row.title,
          independent: true,
          initialThinking: thinking,
          service: sessions.service,
          workspaceId: () async => sessions.workspaceId,
        );
    if (model != null) active!.providerConfig = model;
    if (smartMode != null) active!.configureMode(smartMode);
    active!.addListener(_activity);
    wasRunning = false;
    setState(() {
      initialMessage = message;
      initialFiles = attachments;
      initialReferences = references;
    });
    scaffold.currentState?.closeDrawer();
  }

  Future<void> _create({bool send = false}) async {
    final message = send ? input.text.trim() : '';
    if (send && message.isEmpty) return;
    final row = await sessions.create(message);
    if (!mounted || revoked || row == null) return;
    _open(
      row,
      message: message,
      attachments: send ? files.toList() : [],
      references: send ? selectedReferences.toList() : [],
      smartMode: smart,
    );
    if (send) {
      input.clear();
      files.clear();
      selectedReferences.clear();
    }
  }

  Future<void> _attach() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
        type: FileType.custom,
        allowedExtensions: agentAttachmentExtensions,
      );
      if (!mounted || picked == null) return;
      validateAgentAttachments([...files, ...picked.files]);
      setState(() {
        files.addAll(picked.files);
        uploadError = null;
      });
    } catch (e) {
      if (mounted) setState(() => uploadError = '$e');
    }
  }

  Future<List<AgentReference>> _loadReferences() async {
    final workspace = sessions.workspaceId;
    final identity = sessions.identity;
    if (workspace == null || revoked) throw StateError('请先加载工作区');
    final items = await sessions.service.references(workspace);
    if (revoked ||
        workspace != sessions.workspaceId ||
        identity != sessions.identity ||
        identity != await sessions.service.identity(workspace)) {
      throw StateError('账号或工作区已切换');
    }
    return items;
  }

  @override
  void dispose() {
    AgentController.accountClearance.removeListener(_revoke);
    AgentConversations.requestedConversation.removeListener(_requested);
    AgentConversations.requestedPrompt.removeListener(_prompt);
    active?.removeListener(_activity);
    active?.dispose();
    if (widget.conversations == null) sessions.dispose();
    input.dispose();
    super.dispose();
  }

  Widget _history() => Material(
        color: AppFlowyTheme.maybeOf(context)?.surfaceColorScheme.primary ??
            Theme.of(context).colorScheme.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: OutlinedButton.icon(
                onPressed: sessions.creating || revoked || sessions.loading
                    ? null
                    : _create,
                icon: const Icon(Icons.add_box_outlined),
                label: const Text('新建对话'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('历史会话', style: TextStyle(fontSize: 12)),
                  ),
                  IconButton(
                    tooltip: '刷新会话',
                    onPressed: sessions.loading || sessions.creating || revoked
                        ? null
                        : _load,
                    icon: const Icon(Icons.refresh, size: 18),
                  ),
                ],
              ),
            ),
            if (sessions.loading) const LinearProgressIndicator(),
            if (sessions.error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '会话加载失败：${sessions.error}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: sessions.entries.isEmpty && !sessions.loading
                  ? const Center(child: Text('开始你的第一个对话'))
                  : ListView.builder(
                      itemCount: sessions.entries.length,
                      itemBuilder: (_, i) {
                        final entry = sessions.entries[i];
                        return ListTile(
                          dense: true,
                          selected: active?.chatId == entry.id,
                          leading:
                              const Icon(Icons.chat_bubble_outline, size: 18),
                          title: Text(
                            entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _open(entry),
                        );
                      },
                    ),
            ),
            if (widget.onLegacy != null)
              TextButton(
                onPressed: widget.onLegacy,
                child: const Text('旧对话（保留）'),
              ),
          ],
        ),
      );

  Widget _welcome() => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_awesome_outlined, size: 36),
                const SizedBox(height: 20),
                const Text(
                  '我是小马笔记 AI，很高兴见到你！',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                const Text('查找资料、整理笔记，或把任务交给我', textAlign: TextAlign.center),
                const SizedBox(height: 32),
                AgentComposer(
                  input: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AgentReferenceField(
                        controller: input,
                        selected: selectedReferences,
                        enabled:
                            !sessions.creating && !sessions.loading && !revoked,
                        load: _loadReferences,
                        onChanged: (items) => setState(
                          () => selectedReferences
                            ..clear()
                            ..addAll(items),
                        ),
                        child: TextField(
                          controller: input,
                          minLines: 3,
                          maxLines: 6,
                          enabled: !sessions.creating,
                          decoration: const InputDecoration(
                            hintText: '有什么想问的，或需要我完成的任务？',
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          onSubmitted: (_) => _create(send: true),
                        ),
                      ),
                      if (files.isNotEmpty)
                        Wrap(
                          spacing: 8,
                          children: files
                              .map(
                                (f) => InputChip(
                                  label: Text(f.name),
                                  onDeleted: () =>
                                      setState(() => files.remove(f)),
                                ),
                              )
                              .toList(),
                        ),
                      if (uploadError != null)
                        Text(
                          uploadError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                  leading: [
                    IconButton(
                      tooltip: '上传文件',
                      onPressed: sessions.creating ? null : _attach,
                      icon: const Icon(Icons.attach_file),
                    ),
                  ],
                  modelSelector: AgentModelSettingsButton(
                    currentConfig: model,
                    currentThinking: thinking,
                    onChanged: (config, level) async {
                      setState(() {
                        model = config;
                        thinking = level;
                      });
                    },
                  ),
                  actions: [
                    IconButton(
                      tooltip: '发送消息',
                      onPressed:
                          sessions.creating || sessions.loading || revoked
                              ? null
                              : () => _create(send: true),
                      icon: const Icon(Icons.arrow_upward),
                    ),
                  ],
                  footer: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      AiModeButton(
                        agentMode: smart,
                        enabled: !sessions.creating && !revoked,
                        onSelected: (value) => setState(() => smart = value),
                      ),
                      const AllAgentArtifactsButton(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: sessions,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final content = revoked
                ? const Center(child: Text('账号或工作区已切换，请重新打开问 AI'))
                : active == null
                    ? _welcome()
                    : AgentWorkspace(
                        key: ValueKey(active),
                        controller: active!,
                        initialMessage: initialMessage,
                        initialAttachments: initialFiles,
                        initialReferences: initialReferences,
                        onInitialAccepted: () async {
                          initialMessage = '';
                          initialFiles = [];
                          await _load();
                        },
                      );
            return Scaffold(
              key: scaffold,
              drawer: wide ? null : Drawer(child: SafeArea(child: _history())),
              appBar: wide
                  ? null
                  : AppBar(
                      title: const Text('问 AI'),
                      leading: IconButton(
                        tooltip: 'AI 历史会话',
                        icon: const Icon(Icons.menu),
                        onPressed: () => scaffold.currentState?.openDrawer(),
                      ),
                    ),
              body: Row(
                children: [
                  if (wide) ...[
                    SizedBox(width: 256, child: _history()),
                    const VerticalDivider(width: 1),
                  ],
                  Expanded(child: content),
                ],
              ),
            );
          },
        ),
      );
}
