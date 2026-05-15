import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/calendar/application/calendar_unsaved_guard.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:appflowy_ui/appflowy_ui.dart';

class SidebarTrashItem extends StatelessWidget {
  const SidebarTrashItem({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: AFGhostIconTextButton.primary(
        text: LocaleKeys.trash_text.tr(),
        mainAxisAlignment: MainAxisAlignment.start,
        size: AFButtonSize.l,
        onTap: () => _openTrash(context),
        padding: EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 11,
        ),
        borderRadius: theme.borderRadius.s,
        iconBuilder: (context, isHover, disabled) => FlowySvg(
          FlowySvgs.icon_trash_s,
          size: const Size.square(18.0),
          color: Theme.of(context).textTheme.bodyMedium?.color,
        ),
      ),
    );
  }

  void _openTrash(BuildContext context) async {
    try {
      // 若当前在日历且存在未保存的新建/编辑，先弹窗确认再离开
      CalendarUnsavedGuard.instance.maybeConfirmLeave(context, () {
        // 创建回收站插件
        final trashPlugin = makePlugin(
          pluginType: PluginType.trash,
          data: null,
        );

        // 在新标签页中打开回收站
        context.read<TabsBloc>().add(
          TabsEvent.openPlugin(plugin: trashPlugin),
        );
      });
    } catch (e) {
      // 静默处理错误，不显示用户
    }
  }
}
