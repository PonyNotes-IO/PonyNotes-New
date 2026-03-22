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
        
        // 当添加新选项卡时，滚动到最新的选项卡位置
        if (state.pages > _previousPageCount) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          });
        }
        
        _previousPageCount = state.pages;
      },
      builder: (context, state) {
        if (state.pages == 1) {
          return const SizedBox.shrink();
        }

        final isAllPinned = state.isAllPinned;

        return Container(
          alignment: Alignment.bottomLeft,
          height: HomeSizes.tabBarHeight,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: MoveWindowDetector(
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: state.pageManagers.map((pm) {
                  return ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: HomeSizes.tabBarWidth,
                    ),
                    child: FlowyTab(
                      key: ValueKey('tab-${pm.plugin.id}'),
                      pageManager: pm,
                      isCurrent: state.currentPageManager == pm,
                      isAllPinned: isAllPinned,
                      onTap: () {
                        if (state.currentPageManager != pm) {
                          final index = state.pageManagers.indexOf(pm);
                          widget.onIndexChanged(index);
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }
}
