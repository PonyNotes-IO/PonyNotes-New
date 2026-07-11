import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/notifications/mobile_notifications_screen.dart';
import 'package:appflowy/mobile/presentation/presentation.dart';
import 'package:appflowy/user/application/reminder/reminder_bloc.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class MobileNotificationPageHeader extends StatefulWidget {
  const MobileNotificationPageHeader({super.key});

  @override
  State<MobileNotificationPageHeader> createState() =>
      _MobileNotificationPageHeaderState();
}

class _MobileNotificationPageHeaderState
    extends State<MobileNotificationPageHeader> {
  final PopoverController moreActionController = PopoverController();

  @override
  void dispose() {
    moreActionController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final afTheme = AppFlowyTheme.of(context);
    final theme = Theme.of(context);

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(BottomNavigationBarItemType.home.routeName!);
              }
            },
            icon: FlowySvg(
              FlowySvgs.mobile_return_s,
              size: const Size(7, 12),
              color: afTheme.iconColorScheme.primary,
            ),
          ),
          const SizedBox(width: 4),
          const Expanded(
            child: Text(
              '消息通知',
              textAlign: TextAlign.center,
            ),
          ),
          _buildMoreActionButton(context),
        ],
      ),
    );
  }

  Widget _buildMoreActionButton(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return AppFlowyPopover(
      constraints: const BoxConstraints.tightFor(width: 220),
      offset: const Offset(0, 8),
      margin: EdgeInsets.zero,
      controller: moreActionController,
      onOpen: () => keepEditorFocusNotifier.increase(),
      onClose: () => keepEditorFocusNotifier.decrease(),
      popupBuilder: (_) => _buildMoreActions(context),
      child: FlowyIconButton(
        width: 24,
        icon: FlowySvg(
          FlowySvgs.three_dots_m,
          color: theme.iconColorScheme.primary,
        ),
        onPressed: () {
          keepEditorFocusNotifier.increase();
          moreActionController.show();
        },
      ),
    );
  }

  Widget _buildMoreActions(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        boxShadow: const [
          BoxShadow(
            offset: Offset(0, 4),
            blurRadius: 24,
            color: Color(0x1F000000),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 30,
            child: FlowyButton(
              text: FlowyText.regular(
                LocaleKeys.settings_notifications_settings_markAllAsRead.tr(),
              ),
              leftIcon: FlowySvg(FlowySvgs.m_notification_mark_as_read_s),
              onTap: () {
                showToastNotification(
                  message: LocaleKeys
                      .notificationHub_markAllAsReadSucceedToast
                      .tr(),
                );
                context
                    .read<ReminderBloc>()
                    .add(const ReminderEvent.markAllRead());
                moreActionController.close();
              },
            ),
          ),
          const VSpace(2),
          SizedBox(
            height: 30,
            child: FlowyButton(
              text: FlowyText.regular(
                LocaleKeys.settings_notifications_settings_archiveAll.tr(),
              ),
              leftIcon: FlowySvg(FlowySvgs.m_notification_archived_s),
              onTap: () {
                showToastNotification(
                  message: LocaleKeys
                      .notificationHub_markAllAsArchivedSucceedToast
                      .tr(),
                );
                context
                    .read<ReminderBloc>()
                    .add(const ReminderEvent.archiveAll());
                moreActionController.close();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class MobileNotificationMultiSelectPageHeader extends StatelessWidget {
  const MobileNotificationMultiSelectPageHeader({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildCancelButton(
            isOpaque: false,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            onTap: () => bottomNavigationBarType.value =
                BottomNavigationBarActionType.home,
          ),
          ValueListenableBuilder(
            valueListenable: mSelectedNotificationIds,
            builder: (_, value, __) {
              return FlowyText(
                // todo: i18n
                '${value.length} Selected',
                fontSize: 17.0,
                figmaLineHeight: 24.0,
                fontWeight: FontWeight.w500,
              );
            },
          ),
          // this button is used to align the text to the center
          _buildCancelButton(
            isOpaque: true,
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
        ],
      ),
    );
  }

  //
  Widget _buildCancelButton({
    required bool isOpaque,
    required EdgeInsets padding,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: padding,
        child: FlowyText(
          LocaleKeys.button_cancel.tr(),
          fontSize: 17.0,
          figmaLineHeight: 24.0,
          fontWeight: FontWeight.w400,
          color: isOpaque ? Colors.transparent : null,
        ),
      ),
    );
  }
}
