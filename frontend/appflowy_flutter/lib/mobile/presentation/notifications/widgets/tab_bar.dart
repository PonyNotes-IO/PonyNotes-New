import 'package:appflowy/mobile/presentation/home/tab/_round_underline_tab_indicator.dart';
import 'package:appflowy/workspace/presentation/notifications/widgets/notification_tab_bar.dart';
import 'package:flutter/material.dart';

class MobileNotificationTabBar extends StatelessWidget {
  const MobileNotificationTabBar({
    super.key,
    this.height = 38.0,
    required this.tabController,
    required this.tabs,
  });

  final double height;
  final List<NotificationTabType> tabs;
  final TabController tabController;

  @override
  Widget build(BuildContext context) {
    final baseStyle = Theme.of(context).textTheme.bodyMedium;
    final labelStyle = baseStyle?.copyWith(
      fontWeight: FontWeight.w500,
      fontSize: 14.0,
      height: 22.0 / 14.0,
    );
    final unselectedLabelStyle = baseStyle?.copyWith(
      fontWeight: FontWeight.w400,
      fontSize: 13.0,
      height: 22.0 / 13.0,
    );

    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: TabBar(
        controller: tabController,
        tabs: tabs.map((e) => Tab(text: e.tr)).toList(),
        indicatorSize: TabBarIndicatorSize.label,
        isScrollable: false,
        labelStyle: labelStyle,
        labelColor: const Color(0xFFFF3800),
        labelPadding: EdgeInsets.zero,
        unselectedLabelStyle: unselectedLabelStyle,
        unselectedLabelColor: baseStyle?.color,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        indicator: const RoundUnderlineTabIndicator(
          width: 28.0,
          borderSide: BorderSide(
            color: Color(0xFFFF3800),
            width: 3,
          ),
        ),
      ),
    );
  }
}
