import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/setting/widgets/mobile_setting_group_widget.dart';
import 'package:appflowy/mobile/presentation/setting/widgets/mobile_setting_item_widget.dart';
import 'package:appflowy/workspace/application/settings/notifications/notification_settings_cubit.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class NotificationsSettingGroup extends StatelessWidget {
  const NotificationsSettingGroup({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<NotificationSettingsCubit>(
      create: (_) => NotificationSettingsCubit(),
      child: BlocBuilder<NotificationSettingsCubit, NotificationSettingsState>(
        builder: (context, state) {
          return MobileSettingGroup(
            groupTitle: '通知设置',
            settingItemList: [
              _NotificationToggleItem(
                name: '@我',
                hint: '当他人 @我 或在文档中提及时通知我',
                value: state.isAtMeEnabled,
                onChanged: (_) => context
                    .read<NotificationSettingsCubit>()
                    .toggleAtMeEnabled(),
              ),
              _NotificationToggleItem(
                name: '待处理',
                hint: '需要我审批的申请',
                value: state.isPendingEnabled,
                onChanged: (_) => context
                    .read<NotificationSettingsCubit>()
                    .togglePendingEnabled(),
              ),
              _NotificationToggleItem(
                name: '权限变更',
                hint: '当权限调整时通知我',
                value: state.isPermissionChangeEnabled,
                onChanged: (_) => context
                    .read<NotificationSettingsCubit>()
                    .togglePermissionChangeEnabled(),
              ),
              _NotificationToggleItem(
                name: '加入团队',
                hint: '当加入团队或成员加入协作时通知我',
                value: state.isJoinTeamEnabled,
                onChanged: (_) => context
                    .read<NotificationSettingsCubit>()
                    .toggleJoinTeamEnabled(),
              ),
              _NotificationToggleItem(
                name: '剪藏通知',
                hint: '当剪藏图片、网页等成功或失败时通知我',
                value: state.isClipEnabled,
                onChanged: (_) => context
                    .read<NotificationSettingsCubit>()
                    .toggleClipEnabled(),
                showBottomDivider: false,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NotificationToggleItem extends StatelessWidget {
  const _NotificationToggleItem({
    required this.name,
    required this.hint,
    required this.value,
    required this.onChanged,
    this.showBottomDivider = true,
  });

  final String name;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool showBottomDivider;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            name,
            style: theme.textStyle.heading4.standard(
              color: theme.textColorScheme.primary,
            ),
          ),
          trailing: Switch.adaptive(
            activeColor: Theme.of(context).colorScheme.primary,
            value: value,
            onChanged: onChanged,
          ),
          onTap: () => onChanged(!value),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            hint,
            style: theme.textStyle.body.standard(
              color: theme.textColorScheme.secondary,
            ),
          ),
        ),
        if (showBottomDivider)
          Divider(
            color: theme.borderColorScheme.primary.withValues(alpha: 0.5),
            height: 0.5,
          ),
      ],
    );
  }
}
