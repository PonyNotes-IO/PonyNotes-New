import 'package:appflowy/plugins/database/calendar/application/calendar_unsaved_guard.dart';
import 'package:appflowy/plugins/knowledge_graph/knowledge_graph_strings.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_entry_style.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SidebarKnowledgeGraphButton extends StatelessWidget {
  const SidebarKnowledgeGraphButton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return AFGhostIconTextButton.primary(
      text: graphText(context, 'title'),
      mainAxisAlignment: MainAxisAlignment.start,
      padding: sidebarEntryPadding,
      borderRadius: theme.borderRadius.s,
      textStyle: sidebarEntryTextStyle(context),
      iconTextGap: sidebarEntryIconTextGap,
      iconBuilder: (context, isHover, disabled) => Icon(
        Icons.hub_outlined,
        size: 18,
        color: sidebarEntryTextStyle(context).color,
      ),
      onTap: () => CalendarUnsavedGuard.instance.maybeConfirmLeave(context, () {
        context.read<TabsBloc>().add(
              TabsEvent.openPlugin(
                plugin: makePlugin(pluginType: PluginType.knowledgeGraph),
              ),
            );
      }),
    );
  }
}
