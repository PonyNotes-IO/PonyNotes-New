import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:appflowy_ui/appflowy_ui.dart';

class SidebarTemplateNewButton extends StatelessWidget {
  const SidebarTemplateNewButton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: AFGhostIconTextButton.primary(
        text: '模版',
        mainAxisAlignment: MainAxisAlignment.start,
        size: AFButtonSize.l,
        onTap: () {
          // 打开模板插件
          context.read<TabsBloc>().add(
            TabsEvent.openPlugin(
              plugin: makePlugin(pluginType: PluginType.template),
            ),
          );
        },
        padding: EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 10,
        ),
        borderRadius: theme.borderRadius.s,
        iconBuilder: (context, isHover, disabled) => FlowySvg(
          FlowySvgs.icon_template_s,
          size: const Size.square(16.0),
          color: Theme.of(context).textTheme.bodyMedium?.color,
        ),
      ),
    );
  }
}


