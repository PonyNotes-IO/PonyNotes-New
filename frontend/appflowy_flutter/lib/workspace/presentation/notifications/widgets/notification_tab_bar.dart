import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/home/tab/_round_underline_tab_indicator.dart';
import 'package:appflowy/user/application/reminder/reminder_bloc.dart';
import 'package:appflowy/user/application/reminder/reminder_extension.dart';
import 'package:appflowy_backend/protobuf/flowy-user/reminder.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum NotificationTabType {
  mention,
  clip,
  reminder,
  system,
  archived;

  String get tr {
    switch (this) {
      case NotificationTabType.mention:
        return LocaleKeys.notificationHub_tabs_mention.tr();
      case NotificationTabType.clip:
        return LocaleKeys.notificationHub_tabs_clip.tr();
      case NotificationTabType.reminder:
        return LocaleKeys.notificationHub_tabs_reminder.tr();
      case NotificationTabType.system:
        return LocaleKeys.notificationHub_tabs_system.tr();
      case NotificationTabType.archived:
        return LocaleKeys.notificationHub_tabs_archived.tr();
    }
  }

  /// Get the string value for meta storage
  String get value {
    switch (this) {
      case NotificationTabType.mention:
        return 'mention';
      case NotificationTabType.clip:
        return 'clip';
      case NotificationTabType.reminder:
        return 'reminder';
      case NotificationTabType.system:
        return 'system';
      case NotificationTabType.archived:
        return 'archived';
    }
  }
}

class NotificationTabBar extends StatelessWidget {
  const NotificationTabBar({
    super.key,
    required this.tabController,
    this.height = 32,
    required this.tabs,
  });

  final double height;
  final List<NotificationTabType> tabs;
  final TabController tabController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodyMedium;
    final labelStyle = baseStyle?.copyWith(
      fontWeight: FontWeight.w500,
      fontSize: 16.0,
      height: 22.0 / 16.0,
    );
    final unselectedLabelStyle = baseStyle?.copyWith(
      fontWeight: FontWeight.w400,
      fontSize: 15.0,
      height: 22.0 / 15.0,
    );

    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: BlocBuilder<ReminderBloc, ReminderState>(
        builder: (context, state) {
          return TabBar(
            controller: tabController,
            tabs: tabs.map((tabType) {
              final unreadCount = _getUnreadCountForTab(state.reminders, tabType);
              return SizedBox(
                width: 72,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Tab(text: tabType.tr),
                    if (unreadCount > 0)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: _buildUnreadBadge(context, unreadCount),
                      ),
                  ],
                ),
              );
            }).toList(),
            indicatorSize: TabBarIndicatorSize.label,
            isScrollable: false,
            labelPadding: EdgeInsets.zero,
            labelStyle: labelStyle,
            labelColor: baseStyle?.color,
            unselectedLabelStyle: unselectedLabelStyle,
            overlayColor: WidgetStateProperty.all(Colors.transparent),
            indicator: RoundUnderlineTabIndicator(
              width: 28.0,
              borderSide: BorderSide(
                color: theme.colorScheme.primary,
                width: 3,
              ),
            ),
          );
        },
      ),
    );
  }

  int _getUnreadCountForTab(List<ReminderPB> reminders, NotificationTabType tabType) {
    if (tabType == NotificationTabType.archived) return 0;
    return reminders.where((reminder) {
      if (reminder.isRead || reminder.isArchived) return false;
      final notificationType = reminder.notificationType;
      return notificationType == tabType.value;
    }).length;
  }

  Widget _buildUnreadBadge(BuildContext context, int count) {
    final theme = AppFlowyTheme.of(context);
    final overNumber = count > 99;
    Size size = Size.square(14);
    if (count >= 10 && count <= 99) {
      size = Size(17, 14);
    } else if (count > 99) {
      size = Size(24, 14);
    }
    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        color: theme.borderColorScheme.errorThick,
        borderRadius: BorderRadius.all(Radius.circular(size.height / 2)),
      ),
      child: Center(
        child: Text(
          overNumber ? '99+' : '$count',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: Colors.white,
            fontSize: 10,
            height: 1,
          ),
        ),
      ),
    );
  }
}
