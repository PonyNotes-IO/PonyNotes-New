import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/plugins/database/calendar/application/calendar_unsaved_guard.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_ui/appflowy_ui.dart';

class SidebarHomeButton extends StatelessWidget {
  const SidebarHomeButton({
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
            text: '主页',
            mainAxisAlignment: MainAxisAlignment.start,
            size: AFButtonSize.l,
            onTap: () => _openHomePage(context, state),
            padding: EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 11,
            ),
            borderRadius: theme.borderRadius.s,
            iconBuilder: (context, isHover, disabled) => FlowySvg(
              FlowySvgs.icon_home_s,
              size: const Size.square(18.0),
            ),
          ),
        );
      },
    );
  }

  void _openHomePage(
      BuildContext context, UserWorkspaceState workspaceState) async {
    try {
      // 若当前在日历且存在未保存的新建/编辑，先弹窗确认再离开
      CalendarUnsavedGuard.instance.maybeConfirmLeave(context, () {
        // 创建主页插件
        final homePlugin = makePlugin(
          pluginType: PluginType.homepage,
          data: null,
        );

        // 在新标签页中打开主页
        getIt<TabsBloc>().add(
          TabsEvent.openPlugin(
            plugin: homePlugin,
          ),
        );
      });
    } catch (e) {
      _showMessage('打开主页时发生错误: $e');
    }
  }

  void _showMessage(String message) {
    showToastNotification(message: message);
  }
}
