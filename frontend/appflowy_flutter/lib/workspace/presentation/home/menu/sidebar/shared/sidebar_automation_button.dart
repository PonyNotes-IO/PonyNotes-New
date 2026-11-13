import 'package:appflowy/plugins/database/calendar/application/calendar_unsaved_guard.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_entry_style.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SidebarAutomationButton extends StatelessWidget {
  const SidebarAutomationButton({super.key});
  @override
  Widget build(BuildContext context) => AFGhostIconTextButton.primary(
        text: '自动化任务',
        mainAxisAlignment: MainAxisAlignment.start,
        padding: sidebarEntryPadding,
        borderRadius: AppFlowyTheme.of(context).borderRadius.s,
        textStyle: sidebarEntryTextStyle(context),
        iconTextGap: sidebarEntryIconTextGap,
        iconBuilder: (_, __, ___) => Icon(
          Icons.schedule_outlined,
          size: 18,
          color: sidebarEntryTextStyle(context).color,
        ),
        onTap: () =>
            CalendarUnsavedGuard.instance.maybeConfirmLeave(context, () {
          context.read<TabsBloc>().add(
                TabsEvent.openPlugin(
                  plugin: makePlugin(pluginType: PluginType.agentAutomations),
                ),
              );
        }),
      );
}
