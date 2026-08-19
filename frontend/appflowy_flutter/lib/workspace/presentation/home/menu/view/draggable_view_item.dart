import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/cross_space_move.dart';
import 'package:appflowy/workspace/presentation/widgets/draggable_item/draggable_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:flowy_infra/platform_extension.dart';

enum DraggableHoverPosition {
  none,
  top,
  center,
  bottom,
}

({String targetParentId, String? prevViewId})? draggableViewMoveTarget({
  required DraggableHoverPosition position,
  required ViewPB target,
  required String? previousViewId,
}) =>
    switch (position) {
      DraggableHoverPosition.top => (
          targetParentId: target.parentViewId,
          prevViewId: previousViewId,
        ),
      DraggableHoverPosition.center => (
          targetParentId: target.id,
          prevViewId: null,
        ),
      DraggableHoverPosition.bottom => (
          targetParentId: target.parentViewId,
          prevViewId: target.id,
        ),
      DraggableHoverPosition.none => null,
    };

const kDraggableViewItemDividerHeight = 1.0;

class DraggableViewItem extends StatefulWidget {
  const DraggableViewItem({
    super.key,
    required this.view,
    this.feedback,
    required this.child,
    this.isFirstChild = false,
    this.previousViewId,
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

  /// 同级列表中排在本项**前面**那一项的 id；本项为首项时为 null。
  ///
  /// 有了它，「插到本项之前」才能表达为「插到前一项之后」（prevViewId=前一项）。
  /// 缺少它时 top 落点只能把 prevViewId 置 null（插到最前），所以此前
  /// 只有首项的 top 有意义 —— 中间位置全靠 bottom，可用落点少且易误入 center，
  /// 表现为「只能拖到列表最顶端或最下面」。
  final String? previousViewId;
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
    // 在移动端和平板端使用移动端逻辑，避免滑动被识别为拖动
    final isMobileOrTablet = PlatformInfo.isMobile || PlatformInfo.isTablet;
    final child = isMobileOrTablet
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
      onAcceptWithDetails: (details) async {
        final dropPosition = position;
        _updatePosition(DraggableHoverPosition.none);
        await _move(details.data, widget.view, dropPosition);
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
    final topIndicatorColor = position == DraggableHoverPosition.top
        ? widget.topHighlightColor ?? Theme.of(context).colorScheme.primary
        : Colors.transparent;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 首项的顶部线占布局高度，保持原有间距不变。
        if (widget.isFirstChild)
          Divider(
            height: kDraggableViewItemDividerHeight,
            thickness: kDraggableViewItemDividerHeight,
            color: topIndicatorColor,
          ),
        Stack(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6.0),
                color: position == DraggableHoverPosition.center
                    ? widget.centerHighlightColor ??
                        Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.5)
                    : Colors.transparent,
              ),
              child: widget.child,
            ),
            // 非首项的顶部落点同样需要提示，否则用户看不出会插到哪里。
            // 这里用叠加层而不是再插一条 Divider：Divider 会占 1px 布局高度，
            // 给每个条目都加会整体撑高列表并与上一项的底部线叠成 2px。
            if (!widget.isFirstChild)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: kDraggableViewItemDividerHeight,
                child: ColoredBox(color: topIndicatorColor),
              ),
          ],
        ),
        Divider(
          height: kDraggableViewItemDividerHeight,
          thickness: kDraggableViewItemDividerHeight,
          color: position == DraggableHoverPosition.bottom
              ? widget.bottomHighlightColor ??
                  Theme.of(context).colorScheme.primary
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
    if (PlatformInfo.isMobile && position != this.position) {
      HapticFeedback.mediumImpact();
    }
    setState(() => this.position = position);
  }

  Future<void> _move(
    ViewPB from,
    ViewPB to,
    DraggableHoverPosition dropPosition,
  ) async {
    if (dropPosition == DraggableHoverPosition.center &&
        to.layout.isDatabaseView) {
      // not support moving into a database view (Grid/Board/Calendar)
      return;
    }

    if (widget.onMove != null) {
      widget.onMove?.call(from, to);
      return;
    }

    final target = draggableViewMoveTarget(
      position: dropPosition,
      target: to,
      previousViewId: widget.previousViewId,
    );
    if (target == null) {
      return;
    }

    final fromSection = await resolveViewSection(context, from);
    if (!mounted) return;
    final toSection = await resolveViewSection(context, to);
    if (!mounted) return;

    final viewBloc = context.read<ViewBloc>();

    final outcome = await coordinateViewMove(
      context,
      viewBloc: viewBloc,
      view: from,
      targetParentId: target.targetParentId,
      prevViewId: target.prevViewId,
      fromSection: fromSection,
      toSection: toSection,
    );
    if (outcome == CrossSpaceMoveOutcome.aborted) {
      return;
    }
    if (mounted) {
      refreshSidebarMoveState(context);
    }
  }

  DraggableHoverPosition _computeHoverPosition(Offset offset, Size size) {
    final y = offset.dy;
    final height = size.height;
    // 上 30%：插到本项**之前**。首项靠 prevViewId=null 实现，其余项靠
    // previousViewId（插到前一项之后）实现 —— 两者合起来才覆盖到所有位置。
    if ((widget.isFirstChild || widget.previousViewId != null) &&
        y <= height * 0.30) {
      return DraggableHoverPosition.top;
    }
    // 下 30%：插到本项之后。
    if (y >= height * 0.70) {
      return DraggableHoverPosition.bottom;
    }
    // 中间 40%：放入本项成为子级。
    return DraggableHoverPosition.center;
  }

  bool _shouldAccept(ViewPB data, DraggableHoverPosition position) {
    // center 位置不能拖入数据库视图（Grid/Board/Calendar），但 top/bottom 可以作为同级
    if (position == DraggableHoverPosition.center &&
        widget.view.layout.isDatabaseView) {
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
}

extension on ViewPB {
  bool containsView(ViewPB view) {
    if (id == view.id) {
      return true;
    }

    return childViews.any((v) => v.containsView(view));
  }
}
