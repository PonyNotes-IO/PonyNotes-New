import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:appflowy_backend/log.dart';

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
            onTap: () => _openAiWelcomePage(context),
            padding: EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 10,
            ),
            borderRadius: theme.borderRadius.s,
            iconBuilder: (context, isHover, disabled) =>
                Image.asset(
                  'assets/images/home_icon_ai.png',
                  width: 18,
                  height: 18,
                )
            //     FlowySvg(
            //   FlowySvgs.icon_ai_s,
            //   size: const Size.square(16.0),
            //   color: Theme.of(context).textTheme.bodyMedium?.color,
            // ),
          ),
        );
      },
    );
  }

  void _openAiWelcomePage(BuildContext context) {
    Log.info('🔄 侧边栏: 点击问AI按钮，打开AI欢迎页');
    
    try {
      // 创建AI欢迎页插件
      final plugin = makePlugin(pluginType: PluginType.aiWelcome, data: null);
      
      // 使用TabsBloc打开插件
      context.read<TabsBloc>().add(
        TabsEvent.openPlugin(
          plugin: plugin,
        ),
      );
      
      Log.info('✅ 侧边栏: AI欢迎页已打开');
    } catch (e, stackTrace) {
      Log.error('❌ 侧边栏: 打开AI欢迎页失败: $e', e, stackTrace);
      _showMessage(context, '打开AI欢迎页时发生错误: $e');
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
