import 'package:appflowy/core/frameless_window.dart';
import 'package:flutter/material.dart';

import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/tabs/flowy_tab.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class TabsManager extends StatefulWidget {
  const TabsManager({super.key, required this.onIndexChanged});

  final void Function(int) onIndexChanged;

  @override
  State<TabsManager> createState() => _TabsManagerState();
}

class _TabsManagerState extends State<TabsManager> {
  static const double _pinnedTabWidth = 54;
  static const double _minUnpinnedTabWidth = 72;
  static const Color _lightModeTabStripColor = Color(0xFFF9F9F9);
  static const Color _darkModeTabStripColor = Color(0xFF2C2C2C);

  final ScrollController _scrollController = ScrollController();
  int _previousPageCount = 0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TabsBloc, TabsState>(
      listenWhen: (prev, curr) =>
          prev.currentIndex != curr.currentIndex || prev.pages != curr.pages,
      listener: (context, state) {
        widget.onIndexChanged(state.currentIndex);

        // Scroll to the newest tab when tab count increases.
        if (state.pages > _previousPageCount) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          });
        }

        _previousPageCount = state.pages;
      },
      builder: (context, state) {
        final isAllPinned = state.isAllPinned;
        final theme = Theme.of(context);
        final tabStripColor = theme.brightness == Brightness.dark
            ? _darkModeTabStripColor
            : _lightModeTabStripColor;
        final visiblePageManagers =
            state.pageManagers.where((pm) => pm.shouldShowInTabBar).toList();

        return Container(
          alignment: Alignment.bottomLeft,
          height: HomeSizes.tabBarHeight,
          decoration: BoxDecoration(
            color: tabStripColor,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final unpinnedTabWidth = _resolveUnpinnedTabWidth(
                maxWidth: constraints.maxWidth,
                state: state,
              );

              return MoveWindowDetector(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: visiblePageManagers.map((pm) {
                      return FlowyTab(
                        key: ValueKey('tab-${pm.plugin.id}'),
                        pageManager: pm,
                        width: pm.isPinned ? _pinnedTabWidth : unpinnedTabWidth,
                        isCurrent: state.currentPageManager == pm,
                        isAllPinned: isAllPinned,
                        onTap: () {
                          if (state.currentPageManager != pm) {
                            final index = state.pageManagers.indexOf(pm);
                            widget.onIndexChanged(index);
                          }
                        },
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  double _resolveUnpinnedTabWidth({
    required double maxWidth,
    required TabsState state,
  }) {
    final pageManagers =
        state.pageManagers.where((pm) => pm.shouldShowInTabBar).toList();
    final pinnedCount = pageManagers.where((pm) => pm.isPinned).length;
    final unpinnedCount = pageManagers.length - pinnedCount;
    if (unpinnedCount <= 0) {
      return HomeSizes.tabBarWidth;
    }

    final availableForUnpinned = maxWidth - pinnedCount * _pinnedTabWidth;
    final rawWidth = availableForUnpinned / unpinnedCount;
    return rawWidth
        .clamp(
          _minUnpinnedTabWidth,
          HomeSizes.tabBarWidth,
        )
        .toDouble();
  }
}
