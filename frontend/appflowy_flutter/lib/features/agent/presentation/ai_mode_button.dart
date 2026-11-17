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
import 'agent_mode_details.dart';
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
  });
  final bool agentMode;
  final ValueChanged<bool>? onSelected;
  final VoidCallback? onSettings;
  final bool enabled;

  @override
  State<AiModeButton> createState() => _AiModeButtonState();
}

class _AiModeButtonState extends State<AiModeButton> {
  final _menu = MenuController();
  final _quickFocus = FocusNode();
  final _smartFocus = FocusNode();
  late bool _preview = widget.agentMode;

  @override
  void initState() {
    super.initState();
    AgentController.accountClearance.addListener(_close);
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
    AgentController.accountClearance.removeListener(_close);
    _quickFocus.dispose();
    _smartFocus.dispose();
    super.dispose();
  }

  void _close() => _menu.close();

  void _previewMode(bool smart) {
    if (_preview != smart) setState(() => _preview = smart);
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

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.maybeOf(context);
    final foreground = theme?.textColorScheme.primary ??
        Theme.of(context).colorScheme.onSurface;
    final background = theme?.surfaceColorScheme.layer01 ??
        Theme.of(context).colorScheme.surface;
    final textStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontSize: 12,
          color: foreground,
        );
    final media = MediaQuery.of(context);
    final width = math.min(420.0, media.size.width - 24);
    final height = math.min(
      248.0,
      math.max(0.0, media.size.height - media.viewInsets.bottom - 48),
    );

    Widget surface(Widget child) => Material(
          color: background,
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: .2),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: foreground.withValues(alpha: .12)),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        );

    Widget modeItem(bool smart) => MouseRegion(
          onEnter: (_) => _previewMode(smart),
          child: Semantics(
            selected: smart == widget.agentMode,
            child: MenuItemButton(
              key: ValueKey('agent-mode-${smart ? 'smart' : 'quick'}'),
              focusNode: smart ? _smartFocus : _quickFocus,
              onFocusChange: (focused) {
                if (focused) _previewMode(smart);
              },
              onPressed: () => _select(smart),
              style: MenuItemButton.styleFrom(
                foregroundColor: foreground,
                backgroundColor: _preview == smart
                    ? foreground.withValues(alpha: .08)
                    : null,
                textStyle: textStyle,
                padding: const EdgeInsets.symmetric(horizontal: 7),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              leadingIcon: Icon(
                AgentModeDetails.icon(smart),
                size: 16,
                color: Colors.indigo.shade400,
              ),
              trailingIcon: smart == widget.agentMode
                  ? Icon(Icons.check, size: 13, color: foreground)
                  : const SizedBox(width: 13),
              child: Text(AgentModeDetails.label(smart)),
            ),
          ),
        );

    return MenuAnchor(
      controller: _menu,
      crossAxisUnconstrained: false,
      consumeOutsideTap: true,
      onOpen: () {
        setState(() => _preview = widget.agentMode);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _menu.isOpen) {
            (widget.agentMode ? _smartFocus : _quickFocus).requestFocus();
          }
        });
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: width < 380 ? 128 : 166,
                child: surface(
                  SingleChildScrollView(
                    primary: false,
                    padding: const EdgeInsets.all(5),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(7, 5, 7, 6),
                          child: Text(
                            '内置智能体',
                            style: textStyle?.copyWith(
                              fontSize: 10,
                              color: foreground.withValues(alpha: .5),
                            ),
                          ),
                        ),
                        modeItem(false),
                        modeItem(true),
                        if (widget.onSettings != null) ...[
                          Divider(
                            height: 13,
                            color: foreground.withValues(alpha: .06),
                          ),
                          MenuItemButton(
                            onPressed: () {
                              _close();
                              widget.onSettings?.call();
                            },
                            style: MenuItemButton.styleFrom(
                              foregroundColor: foreground,
                              textStyle: textStyle,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 7),
                              minimumSize: const Size(0, 30),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            leadingIcon: const Icon(Icons.tune, size: 15),
                            child: const Text('对话设置'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: surface(
                  SizedBox(
                    height: height,
                    child: AgentModeDetails(
                      smart: _preview,
                      current: _preview == widget.agentMode,
                      startsNewConversation: widget.onSelected == null,
                      onSelected: () => _select(_preview),
                    ),
                  ),
                ),
              ),
            ],
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
              Text(AgentModeDetails.label(widget.agentMode)),
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
