import 'dart:convert';
import 'dart:math' as math;
import 'package:appflowy/workspace/application/view/ai_chat_view_service.dart';
import 'package:flutter/material.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:appflowy/mobile/presentation/chat/mobile_chat_screen.dart';
import 'package:flowy_infra/platform_extension.dart';
import 'package:go_router/go_router.dart';
import 'package:universal_platform/universal_platform.dart';
import '../application/agent_conversations.dart';
import 'agent_conversations_page.dart';
import '../application/agent_definition.dart';
import 'agent_picker_panel.dart';
import '../application/agent_controller.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';

void openIndependentAiConversation(BuildContext context, [String? id]) {
  AgentConversations.requestOpen(id);
  if (PlatformInfo.isDesktopOrTablet) {
    getIt<TabsBloc>().add(
      TabsEvent.openPlugin(
        plugin: makePlugin(pluginType: PluginType.aiWelcome),
      ),
    );
  } else {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const AgentConversationsPage(),
      ),
    );
  }
}

void openCreatedAiDocument(BuildContext context, String id, String title) {
  if (context.mounted && UniversalPlatform.isMobile && !PlatformInfo.isTablet) {
    context.push(
      '${MobileChatScreen.routeName}?${MobileChatScreen.viewId}=$id&${MobileChatScreen.viewTitle}=${Uri.encodeComponent(title)}',
    );
  }
}

bool isAgentDocument(String extra) {
  if (extra.isEmpty) return false;
  try {
    final value = jsonDecode(extra);
    return value is Map &&
        (value['ai_mode'] == 'agent' || value['ai_engine'] == 'weknora');
  } on FormatException {
    return false;
  }
}

/// Select a mode in place, or start another conversation from legacy chat.
class AiModeButton extends StatefulWidget {
  const AiModeButton({
    super.key,
    required this.agentMode,
    this.onSelected,
    this.onSettings,
    this.enabled = true,
    this.selectedAgent,
    this.loadAgents,
    this.onAgentSelected,
  });
  final bool agentMode;
  final ValueChanged<bool>? onSelected;
  final VoidCallback? onSettings;
  final bool enabled;
  final AgentDefinition? selectedAgent;
  final Future<List<AgentDefinition>> Function()? loadAgents;
  final ValueChanged<AgentDefinition>? onAgentSelected;

  @override
  State<AiModeButton> createState() => _AiModeButtonState();
}

class _AiModeButtonState extends State<AiModeButton> {
  final _menu = MenuController();
  List<AgentDefinition> _agents = const [
    AgentDefinition.quick,
    AgentDefinition.smartReasoning,
  ];
  bool _loading = false;
  String? _loadError;
  int _loadVersion = 0;

  Future<void> _load() async {
    final load = widget.loadAgents;
    if (load == null) return;
    final version = ++_loadVersion;
    setState(() {
      _loading = true;
      _loadError = null;
      _agents = const [AgentDefinition.quick, AgentDefinition.smartReasoning];
    });
    try {
      final agents = await load();
      if (mounted && version == _loadVersion) setState(() => _agents = agents);
    } catch (error) {
      if (mounted && version == _loadVersion) {
        setState(() {
          _loadError = error is StateError
              ? error.message.toString()
              : '智能体加载失败，请检查网络后重试';
        });
      }
    } finally {
      if (mounted && version == _loadVersion) setState(() => _loading = false);
    }
  }

  void _selectAgent(AgentDefinition agent) {
    _close();
    if (!widget.enabled) return;
    if (widget.onAgentSelected != null) {
      widget.onAgentSelected!(agent);
    } else {
      _select(agent.smart);
    }
  }

  @override
  void initState() {
    super.initState();
    AgentController.accountClearance.addListener(_clear);
  }

  @override
  void didUpdateWidget(covariant AiModeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _menu.isOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !widget.enabled) _close();
      });
    }
  }

  @override
  void dispose() {
    AgentController.accountClearance.removeListener(_clear);
    _loadVersion++;
    super.dispose();
  }

  void _close() => _menu.close();

  void _clear() {
    _loadVersion++;
    _agents = [];
    _close();
  }

  Future<void> _select(bool smart) async {
    _close();
    if (!widget.enabled) return;
    if (widget.onSelected != null) {
      widget.onSelected!(smart);
      return;
    }
    try {
      if (smart) {
        openIndependentAiConversation(context);
        return;
      }
      final workspace = await AIChatViewService.getCurrentWorkspaceId();
      if (workspace == null) throw StateError('请先打开工作区');
      final document = await AIChatViewService.createAndOpenAIChat(
        parentViewId: workspace,
        agentMode: smart,
      );
      if (document == null) throw StateError('创建对话失败，请重试');
      if (mounted) {
        openCreatedAiDocument(context, document.id, document.name);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  void _configure() {
    _close();
    if (widget.onSettings != null) {
      widget.onSettings!.call();
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('配置智能体'),
        content: const Text('智能体配置即将开放'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.maybeOf(context);
    final foreground = theme?.textColorScheme.primary ??
        Theme.of(context).colorScheme.onSurface;
    final textStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontSize: 13,
          color: foreground,
        );
    final media = MediaQuery.of(context);
    final width = math.min(494.0, media.size.width - 24);
    final height = math.min(
      310.0,
      math.max(0.0, media.size.height - media.viewInsets.bottom - 48),
    );

    return MenuAnchor(
      controller: _menu,
      crossAxisUnconstrained: false,
      consumeOutsideTap: true,
      onOpen: () {
        setState(() {});
        _load();
      },
      onClose: () => setState(() {}),
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        minimumSize: WidgetStatePropertyAll(Size(width, 0)),
        maximumSize: WidgetStatePropertyAll(Size(width, height)),
        alignment: AlignmentDirectional.bottomStart,
      ),
      alignmentOffset: const Offset(0, 8),
      menuChildren: [
        SizedBox(
          key: const ValueKey('agent-mode-panel'),
          width: width,
          height: height,
          child: AgentPickerPanel(
            smartMode: widget.agentMode,
            autofocus: true,
            onModeSelected: _select,
            onConfigure: _configure,
            agents: _agents,
            selectedAgent: widget.selectedAgent,
            onAgentSelected: _selectAgent,
            loading: _loading,
            error: _loadError,
            onRetry: _load,
          ),
        ),
      ],
      builder: (context, controller, child) => TextButton(
        onPressed: widget.enabled
            ? () => controller.isOpen ? controller.close() : controller.open()
            : null,
        style: TextButton.styleFrom(
          foregroundColor: foreground,
          textStyle: textStyle?.copyWith(fontSize: 13),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          minimumSize: const Size(0, 30),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: const StadiumBorder(),
        ),
        child: Tooltip(
          message: widget.onSelected == null ? '新建其他模式的对话' : '选择智能体',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  widget.selectedAgent?.name ??
                      (widget.agentMode ? '智能推理' : '快速问答'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 3),
              Icon(
                controller.isOpen ? Icons.expand_less : Icons.expand_more,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
