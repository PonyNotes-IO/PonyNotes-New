import 'package:appflowy/plugins/database/calendar/application/calendar_unsaved_guard.dart';
import 'package:appflowy/plugins/knowledge_base/knowledge_base_service.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_entry_style.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SidebarKnowledgeBaseButton extends StatefulWidget {
  const SidebarKnowledgeBaseButton({super.key});

  @override
  State<SidebarKnowledgeBaseButton> createState() =>
      _SidebarKnowledgeBaseButtonState();
}

class _SidebarKnowledgeBaseButtonState
    extends State<SidebarKnowledgeBaseButton> {
  bool _expanded = false;

  void _open(KnowledgeBaseCategory? category) =>
      CalendarUnsavedGuard.instance.maybeConfirmLeave(context, () {
        if (!mounted) return;
        context.read<TabsBloc>().add(
              TabsEvent.openPlugin(
                plugin: makePlugin(
                  pluginType: PluginType.knowledgeBase,
                  data: category,
                ),
              ),
            );
      });

  @override
  Widget build(BuildContext context) {
    final style = sidebarEntryTextStyle(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AFGhostIconTextButton.primary(
          text: kbText(context, '知识库', 'Knowledge bases'),
          showExpandArrow: true,
          isExpanded: _expanded,
          mainAxisAlignment: MainAxisAlignment.start,
          padding: sidebarEntryPadding,
          textStyle: style,
          borderRadius: AppFlowyTheme.of(context).borderRadius.s,
          iconTextGap: sidebarEntryIconTextGap,
          iconBuilder: (_, __, ___) =>
              Icon(Icons.menu_book_outlined, size: 18, color: style.color),
          onTap: () {
            setState(() => _expanded = !_expanded);
            _open(null);
          },
        ),
        if (_expanded)
          for (final category in KnowledgeBaseCategory.values)
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: AFGhostIconTextButton.primary(
                text: category.label(context),
                mainAxisAlignment: MainAxisAlignment.start,
                padding: sidebarEntryPadding,
                textStyle: style.copyWith(fontSize: 13),
                borderRadius: AppFlowyTheme.of(context).borderRadius.s,
                iconTextGap: sidebarEntryIconTextGap,
                iconBuilder: (_, __, ___) =>
                    Icon(category.icon, size: 16, color: style.color),
                onTap: () => _open(category),
              ),
            ),
      ],
    );
  }
}
