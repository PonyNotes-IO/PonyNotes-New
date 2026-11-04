import 'package:appflowy/plugins/database/calendar/application/calendar_unsaved_guard.dart';
import 'package:appflowy/plugins/note_graph/note_graph_plugin.dart';
import 'package:appflowy/plugins/note_graph/presentation/note_graph_page.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_entry_style.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SidebarNoteGraphButton extends StatelessWidget {
  const SidebarNoteGraphButton({super.key});
  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return AFGhostIconTextButton.primary(
      text: noteGraphText(context, '双链图谱', 'Note link graph'),
      mainAxisAlignment: MainAxisAlignment.start,
      padding: sidebarEntryPadding,
      borderRadius: theme.borderRadius.s,
      textStyle: sidebarEntryTextStyle(context),
      iconTextGap: sidebarEntryIconTextGap,
      iconBuilder: (context, isHover, disabled) => Icon(
        Icons.account_tree_outlined,
        size: 18,
        color: sidebarEntryTextStyle(context).color,
      ),
      onTap: () => CalendarUnsavedGuard.instance.maybeConfirmLeave(context, () {
        context
            .read<TabsBloc>()
            .add(TabsEvent.openPlugin(plugin: NoteGraphPlugin()));
      }),
    );
  }
}
