import 'dart:convert';
import 'package:appflowy/workspace/application/view/ai_chat_view_service.dart';
import 'package:flutter/material.dart';
import 'package:appflowy/mobile/presentation/chat/mobile_chat_screen.dart';
import 'package:flowy_infra/platform_extension.dart';
import 'package:go_router/go_router.dart';
import 'package:universal_platform/universal_platform.dart';
import '../application/agent_conversations.dart';
import 'agent_conversations_page.dart';
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

/// Mode is chosen for a document; changing engines starts a new document.
class AiModeButton extends StatelessWidget {
  const AiModeButton({
    super.key,
    required this.agentMode,
    this.onSelected,
    this.enabled = true,
  });
  final bool agentMode;
  final ValueChanged<bool>? onSelected;
  final bool enabled;
  @override
  Widget build(BuildContext context) => PopupMenuButton<bool>(
        enabled: enabled,
        tooltip: onSelected == null ? '新建其他模式的对话' : '选择对话模式',
        initialValue: agentMode,
        onSelected: (value) async {
          if (onSelected != null) {
            onSelected!(value);
            return;
          }
          try {
            if (value) {
              openIndependentAiConversation(context);
              return;
            }
            final workspace = await AIChatViewService.getCurrentWorkspaceId();
            if (workspace == null) throw StateError('请先打开工作区');
            final document = await AIChatViewService.createAndOpenAIChat(
              parentViewId: workspace,
              agentMode: value,
            );
            if (document == null) throw StateError('创建对话失败，请重试');
            if (context.mounted) {
              openCreatedAiDocument(context, document.id, document.name);
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('$e')));
            }
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: false,
            child: Text(onSelected == null ? '旧对话（保留）' : '快问快答'),
          ),
          PopupMenuItem(
            value: true,
            child: Text(onSelected == null ? 'Agent 原型' : '智能推理'),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                agentMode ? '智能推理' : '快问快答',
                style: const TextStyle(fontSize: 13),
              ),
              const Icon(Icons.expand_more, size: 16),
            ],
          ),
        ),
      );
}
