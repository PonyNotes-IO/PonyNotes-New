import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/settings/notifications/notification_settings_cubit.dart';
import 'package:appflowy/workspace/presentation/settings/shared/setting_list_tile.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_body.dart';
import 'package:appflowy/workspace/presentation/widgets/toggle/toggle.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SettingsNotificationsView extends StatelessWidget {
  const SettingsNotificationsView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NotificationSettingsCubit, NotificationSettingsState>(
      builder: (context, state) {
        return SettingsBody(
          title: '通知设置',
          children: [
            // Master switch
            SettingListTile(
              label: LocaleKeys.settings_notifications_enableNotifications_label
                  .tr(),
              hint: LocaleKeys.settings_notifications_enableNotifications_hint
                  .tr(),
              trailing: [
                Toggle(
                  value: state.isNotificationsEnabled,
                  onChanged: (_) => context
                      .read<NotificationSettingsCubit>()
                      .toggleNotificationsEnabled(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Per-type settings
            SettingListTile(
              label: '@我',
              hint: '当他人 @我 或在文档中提及时通知我',
              trailing: [
                Toggle(
                  value: state.isAtMeEnabled,
                  onChanged: (_) => context
                      .read<NotificationSettingsCubit>()
                      .toggleAtMeEnabled(),
                ),
              ],
            ),
            SettingListTile(
              label: '待处理',
              hint: '需要我审批的申请',
              trailing: [
                Toggle(
                  value: state.isPendingEnabled,
                  onChanged: (_) => context
                      .read<NotificationSettingsCubit>()
                      .togglePendingEnabled(),
                ),
              ],
            ),
            SettingListTile(
              label: '权限变更',
              hint: '当权限调整时，通知我',
              trailing: [
                Toggle(
                  value: state.isPermissionChangeEnabled,
                  onChanged: (_) => context
                      .read<NotificationSettingsCubit>()
                      .togglePermissionChangeEnabled(),
                ),
              ],
            ),
            SettingListTile(
              label: '加入团队或加入协作时',
              hint: '当加入团队或成员加入协作时通知我',
              trailing: [
                Toggle(
                  value: state.isJoinTeamEnabled,
                  onChanged: (_) => context
                      .read<NotificationSettingsCubit>()
                      .toggleJoinTeamEnabled(),
                ),
              ],
            ),
            SettingListTile(
              label: '剪藏通知',
              hint: '当剪藏图片、网页等成功或失败时通知我',
              trailing: [
                Toggle(
                  value: state.isClipEnabled,
                  onChanged: (_) => context
                      .read<NotificationSettingsCubit>()
                      .toggleClipEnabled(),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
