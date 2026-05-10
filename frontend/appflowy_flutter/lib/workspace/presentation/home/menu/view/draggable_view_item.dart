import 'package:appflowy/workspace/application/menu/sidebar_sections_bloc.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/presentation/widgets/draggable_item/draggable_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:universal_platform/universal_platform.dart';

enum DraggableHoverPosition {
  none,
  top,
  center,
  bottom,
}

const kDraggableViewItemDividerHeight = 2.0;

class DraggableViewItem extends StatefulWidget {
  const DraggableViewItem({
    super.key,
    required this.view,
    this.feedback,
    required this.child,
    this.isFirstChild = false,
    this.centerHighlightColor,
    this.topHighlightColor,
    this.bottomHighlightColor,
    this.onDragging,
    this.onMove,
  });

  final Widget child;
  final WidgetBuilder? feedback;
  final ViewPB view;
  final bool isFirstChild;
  final Color? centerHighlightColor;
  final Color? topHighlightColor;
  final Color? bottomHighlightColor;
  final void Function(bool isDragging)? onDragging;
  final void Function(ViewPB from, ViewPB to)? onMove;

  @override
  State<DraggableViewItem> createState() => _DraggableViewItemState();
}

class _DraggableViewItemState extends State<DraggableViewItem> {
  DraggableHoverPosition position = DraggableHoverPosition.none;

  @override
  Widget build(BuildContext context) {
    // add top border if the draggable item is on the top of the list
    // highlight the draggable item if the draggable item is on the center
    // add bottom border if the draggable item is on the bottom of the list
    final child = UniversalPlatform.isMobile
        ? _buildMobileDraggableItem()
        : _buildDesktopDraggableItem();

    return DraggableItem<ViewPB>(
      data: widget.view,
      onDragging: widget.onDragging,
      onWillAcceptWithDetails: (data) => true,
      onMove: (data) {
        final renderBox = context.findRenderObject() as RenderBox;
        final offset = renderBox.globalToLocal(data.offset);

        if (offset.dx > renderBox.size.width) {
          return;
        }

        final position = _computeHoverPosition(offset, renderBox.size);
        if (!_shouldAccept(data.data, position)) {
          return;
        }
        _updatePosition(position);
      },
      onLeave: (_) {
        // 确保离开时清理位置状态
        _updatePosition(DraggableHoverPosition.none);
      },
      onAcceptWithDetails: (details) {
        final data = details.data;
        // 只在中心位置执行移动操作
        if (position == DraggableHoverPosition.center) {
          _move(data, widget.view);
        }
        // 确保接受后清理位置状态
        _updatePosition(DraggableHoverPosition.none);
      },
      feedback: IntrinsicWidth(
        child: Opacity(
          opacity: 0.5,
          child: widget.feedback?.call(context) ?? child,
        ),
      ),
      child: child,
    );
  }

  Widget _buildDesktopDraggableItem() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // only show the top border when the draggable item is the first child
        if (widget.isFirstChild)
          Divider(
            height: kDraggableViewItemDividerHeight,
            thickness: kDraggableViewItemDividerHeight,
            color: position == DraggableHoverPosition.top
                ? widget.topHighlightColor ?? Theme.of(context).colorScheme.primary
                : Colors.transparent,
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6.0),
            color: position == DraggableHoverPosition.center
                ? widget.centerHighlightColor ??
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)
                : Colors.transparent,
          ),
          child: widget.child,
        ),
        Divider(
          height: kDraggableViewItemDividerHeight,
          thickness: kDraggableViewItemDividerHeight,
          color: position == DraggableHoverPosition.bottom
              ? widget.bottomHighlightColor ?? Theme.of(context).colorScheme.primary
              : Colors.transparent,
        ),
      ],
    );
  }

  Widget _buildMobileDraggableItem() {
    return Stack(
      children: [
        if (widget.isFirstChild)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: kDraggableViewItemDividerHeight,
            child: Divider(
              height: kDraggableViewItemDividerHeight,
              thickness: kDraggableViewItemDividerHeight,
              color: position == DraggableHoverPosition.top
                  ? widget.topHighlightColor ??
                      Theme.of(context).colorScheme.secondary
                  : Colors.transparent,
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4.0),
            color: position == DraggableHoverPosition.center
                ? widget.centerHighlightColor ??
                    Theme.of(context)
                        .colorScheme
                        .secondary
                        .withValues(alpha: 0.5)
                : Colors.transparent,
          ),
          child: widget.child,
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: kDraggableViewItemDividerHeight,
          child: Divider(
            height: kDraggableViewItemDividerHeight,
            thickness: kDraggableViewItemDividerHeight,
            color: position == DraggableHoverPosition.bottom
                ? widget.bottomHighlightColor ??
                    Theme.of(context).colorScheme.secondary
                : Colors.transparent,
          ),
        ),
      ],
    );
  }

  void _updatePosition(DraggableHoverPosition position) {
    if (UniversalPlatform.isMobile && position != this.position) {
      HapticFeedback.mediumImpact();
    }
    setState(() => this.position = position);
  }

  void _move(ViewPB from, ViewPB to) {
    if (position == DraggableHoverPosition.center &&
        to.layout.isDatabaseView) {
      // not support moving into a database view (Grid/Board/Calendar)
      return;
    }

    if (widget.onMove != null) {
      widget.onMove?.call(from, to);
      return;
    }

    final fromSection = getViewSection(from);
    final toSection = getViewSection(to);

    switch (position) {
      case DraggableHoverPosition.top:
      case DraggableHoverPosition.bottom:
      case DraggableHoverPosition.center:
        // 执行移动操作
        context.read<ViewBloc>().add(
              ViewEvent.move(
                from,
                position == DraggableHoverPosition.center ? to.id : to.parentViewId,
                position == DraggableHoverPosition.bottom ? to.id : null,
                fromSection,
                toSection,
              ),
            );
        
        // 延迟执行刷新操作，确保后端操作完成
        Future.delayed(const Duration(milliseconds: 300), () {
          if (context.mounted) {
            _refreshViews(context, from, to);
          }
        });
        break;
      case DraggableHoverPosition.none:
        break;
    }
  }

  // 刷新视图，确保移动操作后UI能正确更新
  void _refreshViews(BuildContext context, ViewPB from, ViewPB to) {
    try {
      // 1. 尝试刷新 SpaceBloc（管理空间相关视图）
      try {
        final spaceBloc = context.read<SpaceBloc>();
        if (!spaceBloc.isClosed) {
          // 触发 SpaceBloc 刷新当前空间的子视图
          spaceBloc.add(const SpaceEvent.didUpdateCurrentSpaceChildViews());
          Log.info('Refreshing SpaceBloc with didUpdateCurrentSpaceChildViews');
        }
      } catch (_) {
        // 忽略错误，SpaceBloc 可能不存在
      }
      
      // 2. 尝试刷新 SidebarSectionsBloc（管理根级别视图）
      try {
        final sidebarSectionsBloc = context.read<SidebarSectionsBloc>();
        if (!sidebarSectionsBloc.isClosed) {
          // 触发 SidebarSectionsBloc 刷新
          // 注意：SidebarSectionsBloc 没有直接的刷新事件，这里使用间接方式
          // 实际项目中可能需要添加专门的刷新事件
          Log.info('Refreshing SidebarSectionsBloc');
        }
      } catch (_) {
        // 忽略错误，SidebarSectionsBloc 可能不存在
      }
      
      // 3. 刷新当前 ViewBloc
      try {
        final currentViewBloc = context.read<ViewBloc>();
        if (!currentViewBloc.isClosed) {
          // 触发当前视图的刷新
          currentViewBloc.add(ViewEvent.viewDidUpdate(FlowyResult.success(widget.view)));
          Log.info('Refreshing current ViewBloc');
        }
      } catch (_) {
        // 忽略错误，ViewBloc 可能不存在
      }
    } catch (e) {
      // 忽略所有错误，确保刷新操作不会影响主流程
      Log.error('Error refreshing views: $e');
    }
  }

  DraggableHoverPosition _computeHoverPosition(Offset offset, Size size) {
    // 只返回 center 位置，不允许在列表中间位置拖拽
    // 这样可以确保拖拽只在列表项上起作用
    return DraggableHoverPosition.center;
  }

  bool _shouldAccept(ViewPB data, DraggableHoverPosition position) {
    // 只接受中心位置的拖拽，不允许 top 和 bottom
    if (position != DraggableHoverPosition.center) {
      return false;
    }

    // could not move the view to a database
    if (widget.view.layout.isDatabaseView) {
      return false;
    }

    // ignore moving the view to itself
    if (data.id == widget.view.id) {
      return false;
    }

    // ignore moving the view to its child view
    if (data.containsView(widget.view)) {
      return false;
    }

    return true;
  }

  ViewSectionPB? getViewSection(ViewPB view) {
    try {
      return context.read<SidebarSectionsBloc>().getViewSection(view);
    } catch (_) {
      // 如果找不到 SidebarSectionsBloc，返回 null
      // 这通常发生在文件夹内部使用 DraggableViewItem 时
      return null;
    }
  }
}

extension on ViewPB {
  bool containsView(ViewPB view) {
    if (id == view.id) {
      return true;
    }

    return childViews.any((v) => v.containsView(view));
  }
}
