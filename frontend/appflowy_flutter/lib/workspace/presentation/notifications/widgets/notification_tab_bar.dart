import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/home/tab/_round_underline_tab_indicator.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

enum NotificationTabType {
  mention,
  clip,
  reminder,
  system;

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
      padding: const EdgeInsets.only(left: 16),
      child: TabBar(
        controller: tabController,
        tabs: tabs.map((e) => Tab(text: e.tr)).toList(),
        indicatorSize: TabBarIndicatorSize.label,
        // isScrollable: true,
        labelStyle: labelStyle,
        labelColor: baseStyle?.color,
        labelPadding: const EdgeInsets.only(right: 20),
        unselectedLabelStyle: unselectedLabelStyle,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        indicator: RoundUnderlineTabIndicator(
          width: 28.0,
          borderSide: BorderSide(
            color: theme.colorScheme.primary,
            width: 3,
          ),
        ),
      ),
    );
  }
}
