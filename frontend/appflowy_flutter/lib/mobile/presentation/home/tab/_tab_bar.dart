import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/mobile/presentation/home/tab/_round_underline_tab_indicator.dart';
import 'package:appflowy/mobile/presentation/home/tab/space_order_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:reorderable_tabbar/reorderable_tabbar.dart';

class MobileSpaceTabBar extends StatefulWidget {
  const MobileSpaceTabBar({
    super.key,
    this.height = 38.0,
    required this.tabController,
    required this.tabs,
    required this.onReorder,
  });

  final double height;
  final List<MobileSpaceTabType> tabs;
  final TabController tabController;
  final OnReorder onReorder;

  @override
  State<MobileSpaceTabBar> createState() => _MobileSpaceTabBarState();
}

class _MobileSpaceTabBarState extends State<MobileSpaceTabBar> {
  @override
  void initState() {
    super.initState();
    widget.tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    widget.tabController.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = Theme.of(context).textTheme.bodyMedium;
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

    return SizedBox(
      height: widget.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: widget.height,
            padding: const EdgeInsets.only(left: 8.0, top: 0.0),
            child: ReorderableTabBar(
              controller: widget.tabController,
              tabs: widget.tabs.map((e) => Tab(text: e.tr)).toList(),
              indicatorSize: TabBarIndicatorSize.label,
              isScrollable: true,
              labelStyle: labelStyle,
              labelColor: const Color(0xFFFF3800),
              unselectedLabelColor: baseStyle?.color,
              labelPadding: const EdgeInsets.symmetric(horizontal: 12.0),
              unselectedLabelStyle: unselectedLabelStyle,
              overlayColor: WidgetStateProperty.all(Colors.transparent),
              indicator: const RoundUnderlineTabIndicator(
                width: 56.0,
                borderSide: BorderSide(
                  color: Colors.transparent,
                  width: 6,
                ),
              ),
              onReorder: widget.onReorder,
            ),
          ),
          AnimatedBuilder(
            animation: widget.tabController,
            builder: (context, child) {
              final length = widget.tabController.length;
              if (length == 0) {
                return const SizedBox.shrink();
              }
              return _buildIndicator(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildIndicator(BuildContext context) {
    final tabController = widget.tabController;
    final length = tabController.length;
    if (length == 0) {
      return const SizedBox.shrink();
    }

    final currentIndex = tabController.index;
    final animationOffset = tabController.offset;

    const labelPadding = 12.0;
    const containerPadding = 8.0;

    final tabWidths = <double>[];
    for (int i = 0; i < length; i++) {
      final tabWidth = _getTabTextWidth(i) + labelPadding * 2;
      tabWidths.add(tabWidth);
    }

    final indicatorWidth = tabWidths[currentIndex];
    final finalIndicatorWidth = indicatorWidth.clamp(40.0, 100.0);

    double currentTabStart = containerPadding;
    for (int i = 0; i < currentIndex; i++) {
      currentTabStart += tabWidths[i];
    }
    final currentTabCenter = currentTabStart + tabWidths[currentIndex] / 2;

    double nextTabCenter = currentTabCenter;
    if (animationOffset != 0.0 && currentIndex < length - 1) {
      double nextTabStart = currentTabStart + tabWidths[currentIndex];
      nextTabCenter = nextTabStart + tabWidths[currentIndex + 1] / 2;
    }

    final indicatorPosition =
        currentTabCenter + (nextTabCenter - currentTabCenter) * animationOffset;

    final left = indicatorPosition - finalIndicatorWidth / 2;

    return Positioned(
      left: left,
      bottom: 0,
      child: FlowySvg(
        FlowySvgs.mf_select_s,
        size: Size(finalIndicatorWidth, 8),
        blendMode: null,
      ),
    );
  }

  double _getTabTextWidth(int index) {
    if (index < 0 || index >= widget.tabs.length) {
      return 0;
    }
    final tabLabel = widget.tabs[index].tr;
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
          fontSize: 16.0,
        );

    final textPainter = TextPainter(
      text: TextSpan(text: tabLabel, style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    return textPainter.width;
  }
}
