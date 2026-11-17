import 'dart:async';
import 'package:appflowy/features/ai_internal/application/ai_provider_config.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../application/agent_conversations.dart';
import '../application/agent_attachments.dart';
import '../application/agent_controller.dart';
import '../application/agent_definition.dart';
import '../application/agent_model_preferences.dart';
import 'agent_workspace.dart';
import 'agent_model_settings.dart';
import 'agent_artifact_library.dart';
import 'ai_mode_button.dart';
import '../application/agent_reference.dart';
import 'agent_reference_field.dart';
import 'agent_composer.dart';
import 'agent_conversation_sidebar.dart';

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
  final inputFocus = FocusNode();
  late final files = widget.initialAttachments.toList();
  final scaffold = GlobalKey<ScaffoldState>();
  AgentController? active;
  AgentDefinition? selectedAgent;
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
  int suggestionSet = 0;

  static const suggestions = [
    [
      '帮我总结最近的笔记，提炼重点',
      '从知识库中查找相关资料',
      '把会议记录整理成待办清单',
      '对比两份资料的异同',
      '帮我拟一份本周工作计划',
      '把这个想法扩展成一篇文章',
    ],
    [
      '梳理笔记中的关键观点和结论',
      '为这个主题整理一份学习提纲',
      '从资料中提取重要数据',
      '把零散笔记整理成结构化文档',
      '帮我润色这段文字',
      '根据项目记录生成一份周报',
    ],
  ];

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
    selectedAgent = null;
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
          collaborative: row.shared,
          initialThinking: thinking,
          service: sessions.service,
          workspaceId: () async => sessions.workspaceId,
        );
    if (model != null) active!.providerConfig = model;
    if (smartMode != null) active!.configureMode(smartMode);
    if (smartMode != null && selectedAgent != null) {
      active!.configureAgent(selectedAgent!);
    }
    active!.addListener(_activity);
    wasRunning = false;
    setState(() {
      initialMessage = message;
      initialFiles = attachments;
      initialReferences = references;
    });
    scaffold.currentState?.closeDrawer();
  }

  Future<void> _create({
    bool send = false,
    AgentConversationVisibility visibility =
        AgentConversationVisibility.private,
  }) async {
    final message = send ? input.text.trim() : '';
    if (send && message.isEmpty) return;
    final row = await sessions.create(message, visibility: visibility);
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
    inputFocus.dispose();
    super.dispose();
  }

  Widget _history() {
    final theme = AppFlowyTheme.of(context);
    final muted = theme.textColorScheme.primary.withValues(alpha: .6);
    return AgentConversationSidebar(
      entries: sessions.entries,
      selectedId: active?.chatId,
      loading: sessions.loading,
      enabled: !sessions.creating && !revoked && !sessions.loading,
      error: sessions.error,
      onOpen: _open,
      onCreate: (visibility) => _create(visibility: visibility),
      onRefresh: _load,
      footer: Padding(
        padding: const EdgeInsets.all(8),
        child: TextButtonTheme(
          data: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: muted,
              textStyle:
                  Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12),
              alignment: Alignment.centerLeft,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AllAgentArtifactsButton(),
              if (widget.onLegacy != null)
                TextButton.icon(
                  onPressed: widget.onLegacy,
                  icon: const Icon(Icons.history, size: 17),
                  label: const Text('旧对话（保留）'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _useSuggestion(String prompt) {
    input.value = TextEditingValue(
      text: prompt,
      selection: TextSelection.collapsed(offset: prompt.length),
    );
    inputFocus.requestFocus();
  }

  KeyEventResult _submitKey(FocusNode _, KeyEvent event) {
    if (event is KeyDownEvent &&
        inputFocus.hasFocus &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed &&
        input.value.composing.isCollapsed) {
      if (!sessions.creating && !sessions.loading && !revoked) {
        unawaited(_create(send: true));
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _welcome() {
    final theme = AppFlowyTheme.of(context);
    final secondary = theme.textColorScheme.primary.withValues(alpha: .65);
    final tertiary = theme.textColorScheme.primary.withValues(alpha: .42);
    final enabled = !sessions.creating && !sessions.loading && !revoked;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  24,
                  (constraints.maxHeight * .16).clamp(40, 128),
                  24,
                  24,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    children: [
                      Text(
                        '小马笔记AI，让你的知识触手可及',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: compact ? 22 : 26,
                          fontWeight: FontWeight.w600,
                          height: 1.5,
                          color: theme.textColorScheme.primary,
                        ),
                      ),
                      SizedBox(height: compact ? 48 : 98),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '你可以这样问我',
                            style: TextStyle(
                              fontSize: 12,
                              color: tertiary,
                            ),
                          ),
                          IconButton(
                            tooltip: '换一组问题',
                            constraints: const BoxConstraints.tightFor(
                              width: 28,
                              height: 28,
                            ),
                            padding: EdgeInsets.zero,
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => setState(
                              () => suggestionSet =
                                  (suggestionSet + 1) % suggestions.length,
                            ),
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              Icons.refresh,
                              size: 14,
                              color: tertiary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 780),
                        child: Column(
                          children: [
                            for (var row = 0; row < 3; row++) ...[
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final prompt
                                      in suggestions[suggestionSet]
                                          .skip(row * 2)
                                          .take(2))
                                    OutlinedButton(
                                      onPressed: enabled
                                          ? () => _useSuggestion(prompt)
                                          : null,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: secondary,
                                        side: BorderSide(
                                          color: theme.textColorScheme.primary
                                              .withValues(alpha: .08),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 9,
                                        ),
                                        minimumSize: const Size(0, 36),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        textStyle: TextStyle(
                                          fontFamily: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.fontFamily,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w400,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                      child: Text(
                                        prompt,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                ],
                              ),
                              if (row < 2) const SizedBox(height: 8),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AgentComposerFrame(
              child: Focus(
                onKeyEvent: _submitKey,
                child: AgentReferenceField(
                  controller: input,
                  selected: selectedReferences,
                  enabled: enabled,
                  smartMode: smart,
                  onModeChanged: (value) => setState(() {
                    smart = value;
                    selectedAgent = value
                        ? AgentDefinition.smartReasoning
                        : AgentDefinition.quick;
                  }),
                  load: _loadReferences,
                  onChanged: (items) => setState(
                    () => selectedReferences
                      ..clear()
                      ..addAll(items),
                  ),
                  builder: (field, referenceButton) => AgentComposer(
                    compact: true,
                    input: field,
                    leading: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.textColorScheme.primary
                              .withValues(alpha: .04),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: AiModeButton(
                          agentMode: smart,
                          selectedAgent: selectedAgent,
                          loadAgents: () async {
                            final workspace = sessions.workspaceId ??
                                await sessions.workspace();
                            if (workspace == null) throw StateError('请先打开工作区');
                            final agents =
                                await sessions.service.agents(workspace);
                            if (workspace != await sessions.workspace()) {
                              throw StateError('工作区已切换，请重新选择智能体');
                            }
                            return agents;
                          },
                          onAgentSelected: (agent) => setState(() {
                            selectedAgent = agent;
                            smart = agent.smart;
                          }),
                          enabled: enabled,
                        ),
                      ),
                      IconButton(
                        tooltip: '上传文件',
                        style: IconButton.styleFrom(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          minimumSize: const Size(30, 30),
                        ),
                        onPressed: enabled ? _attach : null,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.attach_file, size: 18),
                      ),
                      referenceButton,
                    ],
                    modelSelector: selectedAgent?.sourceTenantId != null
                        ? const Text('共享方模型', style: TextStyle(fontSize: 12))
                        : AgentModelSettingsButton(
                            enabled: enabled,
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
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: input,
                        builder: (context, value, _) => IconButton.filled(
                          tooltip: '发送消息',
                          onPressed: enabled && value.text.trim().isNotEmpty
                              ? () => _create(send: true)
                              : null,
                          style: IconButton.styleFrom(
                            backgroundColor: theme.textColorScheme.primary,
                            foregroundColor: theme.surfaceColorScheme.primary,
                            disabledBackgroundColor: theme
                                .textColorScheme.primary
                                .withValues(alpha: .12),
                            disabledForegroundColor:
                                theme.surfaceColorScheme.primary,
                            minimumSize: const Size(30, 30),
                            maximumSize: const Size(30, 30),
                            padding: EdgeInsets.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: sessions.creating
                              ? const SizedBox.square(
                                  dimension: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.arrow_upward,
                                  size: 18,
                                ),
                        ),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: input,
                        focusNode: inputFocus,
                        minLines: 1,
                        maxLines: 5,
                        enabled: enabled,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: theme.textColorScheme.primary,
                        ),
                        decoration: InputDecoration(
                          hintText: '我可以帮你写代码、写作各种创意内容，请把你的任务交给我吧～',
                          hintMaxLines: 1,
                          hintStyle: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: tertiary,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.only(top: 2, bottom: 8),
                          isDense: true,
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
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: sessions,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 820;
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
              backgroundColor:
                  AppFlowyTheme.of(context).surfaceColorScheme.primary,
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
                    SizedBox(width: 208, child: _history()),
                    VerticalDivider(
                      width: 1,
                      color: AppFlowyTheme.of(context)
                          .borderColorScheme
                          .primary
                          .withValues(alpha: .35),
                    ),
                  ],
                  Expanded(child: content),
                ],
              ),
            );
          },
        ),
      );
}
