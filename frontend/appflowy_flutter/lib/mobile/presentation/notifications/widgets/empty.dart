import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/presentation/notifications/widgets/notification_tab_bar.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

class EmptyNotification extends StatelessWidget {
  const EmptyNotification({
    super.key,
    required this.type,
  });

  final NotificationTabType type;

  @override
  Widget build(BuildContext context) {
    final title = switch (type) {
      NotificationTabType.mention =>
        LocaleKeys.notificationHub_empty_mention_title.tr(),
      NotificationTabType.clip =>
        LocaleKeys.notificationHub_empty_clip_title.tr(),
      NotificationTabType.reminder =>
        LocaleKeys.notificationHub_empty_reminder_title.tr(),
      NotificationTabType.system =>
        LocaleKeys.notificationHub_empty_system_title.tr(),
      NotificationTabType.archived =>
        LocaleKeys.notificationHub_empty_archived_title.tr(),
    };
    final desc = switch (type) {
      NotificationTabType.mention =>
        LocaleKeys.notificationHub_empty_mention_body.tr(),
      NotificationTabType.clip =>
        LocaleKeys.notificationHub_empty_clip_body.tr(),
      NotificationTabType.reminder =>
        LocaleKeys.notificationHub_empty_reminder_body.tr(),
      NotificationTabType.system =>
        LocaleKeys.notificationHub_empty_system_body.tr(),
      NotificationTabType.archived =>
        LocaleKeys.notificationHub_empty_archived_body.tr(),
    };
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const FlowySvg(FlowySvgs.m_empty_notification_xl),
        const VSpace(12.0),
        FlowyText(
          title,
          fontSize: 16.0,
          figmaLineHeight: 24.0,
          fontWeight: FontWeight.w500,
        ),
        const VSpace(4.0),
        Opacity(
          opacity: 0.45,
          child: FlowyText(
            desc,
            fontSize: 15.0,
            figmaLineHeight: 22.0,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}
