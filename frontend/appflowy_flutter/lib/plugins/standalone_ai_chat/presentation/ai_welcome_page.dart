import 'package:appflowy/core/network/ai_model_service.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/plugins/ai_chat/presentation/chat_page/ai_chat_usage_indicator.dart';
import 'package:appflowy/workspace/application/workspace/workspace_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/chat_image.dart';
import 'ai_welcome_theme.dart';
import 'widgets/ai_input_area.dart';
import 'widgets/ai_welcome_header.dart';

/// AI 欢迎页，对应空聊天态的完整布局。
/// AI welcome page for the empty-chat state.
class AIWelcomePage extends StatelessWidget {
  const AIWelcomePage({
    super.key,
    required this.onMessageSent,
    this.onChatHistoryTap,
  });

  final Function(
    String message,
    AIModel? model,
    List<ChatImage>? images,
    bool enableDeepThinking,
    bool enableWebSearch,
  ) onMessageSent;

  /// 点击聊天记录按钮的回调。
  /// Callback for the chat history button.
  final VoidCallback? onChatHistoryTap;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AIWelcomeTheme.backgroundColor(context),
      body: ColoredBox(
        color: AIWelcomeTheme.backgroundColor(context),
        child: SizedBox.expand(
          child: Column(
            children: [
              // 顶部头像和欢迎文字区域 / Header section.
              AIWelcomeHeader(
                onChatHistoryTap: onChatHistoryTap,
              ),
              // 输入交互区域和使用提示 / Input area and usage hint.
              AIInputArea(
                onMessageSent: onMessageSent,
                onChatHistoryTap: onChatHistoryTap,
              ),
              const Spacer(),
              // 底部提示文字 / Footer disclaimer.
              Container(
                margin: const EdgeInsets.only(bottom: 64),
                child: Text(
                  '内容由 AI 生成，请仔细甄别',
                  style: AIWelcomeTheme.tooltipStyle(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「问 AI」主页底部的使用情况 / 未订阅提示。
/// Usage and subscription hint shown at the bottom of the AI home page.
class _AIWelcomeUsageIndicator extends StatelessWidget {
  const _AIWelcomeUsageIndicator();

  Future<FlowyResult<WorkspaceUsagePB?, FlowyError>> _loadUsage(
    BuildContext context,
  ) async {
    final workspaceBloc = context.read<UserWorkspaceBloc>();
    final workspaceId = workspaceBloc.state.currentWorkspace?.workspaceId;
    if (workspaceId == null || workspaceId.isEmpty) {
      Log.warn('[AIWelcomeUsage] 当前 workspaceId 为空，跳过使用情况查询');
      return FlowyResult.success(null);
    }

    final service = WorkspaceService(
      workspaceId: workspaceId,
      // getWorkspaceUsage 目前只使用 workspaceId，这里传 0 即可。
      // getWorkspaceUsage currently only uses workspaceId, so zero is enough.
      userId: fixnum.Int64.ZERO,
    );

    Log.info('[AIWelcomeUsage] 调用 getWorkspaceUsage, workspaceId=$workspaceId');
    return service.getWorkspaceUsage();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FlowyResult<WorkspaceUsagePB?, FlowyError>>(
      future: _loadUsage(context),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final result = snapshot.data!;
        return result.fold(
          (usage) => AIChatUsageIndicator(usage: usage),
          (error) {
            Log.error('[AIWelcomeUsage] 获取使用情况失败: $error');
            return const SizedBox.shrink();
          },
        );
      },
    );
  }
}
