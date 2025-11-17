import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/workspace/application/view/ai_chat_view_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy_ui/appflowy_ui.dart';

class SidebarAiButton extends StatelessWidget {
  const SidebarAiButton({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return BlocBuilder<UserWorkspaceBloc, UserWorkspaceState>(
      builder: (context, state) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: AFGhostIconTextButton.primary(
            text: '问AI',
            mainAxisAlignment: MainAxisAlignment.start,
            size: AFButtonSize.l,
            onTap: () => _openAiChatDialog(context, state),
            padding: EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 10,
            ),
            borderRadius: theme.borderRadius.s,
            iconBuilder: (context, isHover, disabled) => FlowySvg(
              FlowySvgs.icon_ai_s,
              size: const Size.square(16.0),
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
        );
      },
    );
  }

  void _openAiChatDialog(
      BuildContext context, UserWorkspaceState workspaceState) async {
    debugPrint('🔄 侧边栏: 点击问AI按钮');
    
    try {
      // 获取当前workspace ID
      final workspaceId = await AIChatViewService.getCurrentWorkspaceId();
      if (workspaceId == null) {
        _showMessage(context, '无法获取工作空间信息');
        return;
      }

      debugPrint('✅ 侧边栏: 获取到workspace ID: $workspaceId');

      // 创建并打开原生AI Chat视图（不带初始消息）
      final view = await AIChatViewService.createAndOpenAIChat(
        parentViewId: workspaceId,
      );

      if (view == null) {
        _showMessage(context, '创建AI对话失败');
      } else {
        debugPrint('✅ 侧边栏: AI Chat视图创建成功');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ 侧边栏: 打开AI Chat失败: $e');
      debugPrint('堆栈跟踪: $stackTrace');
      _showMessage(context, '打开AI聊天时发生错误: $e');
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
