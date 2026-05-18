import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_entry_style.dart';
import 'package:appflowy_ui/appflowy_ui.dart';

class SidebarCalendarButton extends StatelessWidget {
  const SidebarCalendarButton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return BlocBuilder<UserWorkspaceBloc, UserWorkspaceState>(
      builder: (context, state) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: AFGhostIconTextButton.primary(
            text: '日历',
            mainAxisAlignment: MainAxisAlignment.start,
            size: AFButtonSize.l,
            onTap: () => _openCalendar(context, state),
            padding: sidebarEntryPadding,
            borderRadius: theme.borderRadius.s,
            textStyle: sidebarEntryTextStyle(context),
            iconTextGap: sidebarEntryIconTextGap,
            iconBuilder: (context, isHover, disabled) => FlowySvg(
              FlowySvgs.icon_calendar_s,
              size: const Size.square(18.0),
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
        );
      },
    );
  }

  void _openCalendar(
    BuildContext context,
    UserWorkspaceState workspaceState,
  ) async {
    try {
      // 创建日历插件
      final calendarPlugin = makePlugin(
        pluginType: PluginType.calendar,
      );

      // 在新标签页中打开日历
      context.read<TabsBloc>().add(
            TabsEvent.openPlugin(plugin: calendarPlugin),
          );
    } catch (e) {
      // 静默处理错误，不显示用户
    }
  }
}
