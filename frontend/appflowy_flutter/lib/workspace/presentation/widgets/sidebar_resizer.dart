import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SidebarResizer extends StatefulWidget {
  const SidebarResizer({
    super.key,
    this.enabled = true,
  });

  /// 是否启用拖拽功能。当为 false 时，分隔线不可拖拽，也不会响应 hover 事件。
  /// 用于在白板视图时禁用分隔线，避免触发 setState 导致 WKWebView 布局偏移。
  final bool enabled;

  @override
  State<SidebarResizer> createState() => _SidebarResizerState();
}

class _SidebarResizerState extends State<SidebarResizer> {
  final ValueNotifier<bool> isHovered = ValueNotifier(false);
  final ValueNotifier<bool> isDragging = ValueNotifier(false);
  double? _dragStartGlobalX;

  @override
  void dispose() {
    isHovered.dispose();
    isDragging.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 当禁用时，使用简单的静态分隔线，不响应任何交互事件
    // 这样可以避免 MouseRegion 的 onEnter/onExit 触发 setState
    // 从而避免 WKWebView 布局偏移
    if (!widget.enabled) {
      return Container(
        width: 2,
        margin: const EdgeInsets.only(right: 2.0),
        height: MediaQuery.of(context).size.height,
        color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => isHovered.value = true,
      onExit: (_) => isHovered.value = false,
      child: GestureDetector(
        dragStartBehavior: DragStartBehavior.down,
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (details) {
          isDragging.value = true;
          _dragStartGlobalX = details.globalPosition.dx;

          context
              .read<HomeSettingBloc>()
              .add(const HomeSettingEvent.editPanelResizeStart());
        },
        onHorizontalDragUpdate: (details) {
          isDragging.value = true;
          final dragStartGlobalX =
              _dragStartGlobalX ?? details.globalPosition.dx;

          context.read<HomeSettingBloc>().add(
                HomeSettingEvent.editPanelResized(
                  details.globalPosition.dx - dragStartGlobalX,
                ),
              );
        },
        onHorizontalDragEnd: (details) {
          isDragging.value = false;
          _dragStartGlobalX = null;

          context
              .read<HomeSettingBloc>()
              .add(const HomeSettingEvent.editPanelResizeEnd());
        },
        onHorizontalDragCancel: () {
          isDragging.value = false;
          _dragStartGlobalX = null;

          context
              .read<HomeSettingBloc>()
              .add(const HomeSettingEvent.editPanelResizeEnd());
        },
        child: ValueListenableBuilder(
          valueListenable: isHovered,
          builder: (context, isHovered, _) {
            return ValueListenableBuilder(
              valueListenable: isDragging,
              builder: (context, isDragging, _) {
                return Container(
                  width: 2,
                  // increase the width of the resizer to make it easier to drag
                  margin: const EdgeInsets.only(right: 2.0),
                  height: MediaQuery.of(context).size.height,
                  color: isHovered || isDragging
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                );
              },
            );
          },
        ),
      ),
    );
  }
}
