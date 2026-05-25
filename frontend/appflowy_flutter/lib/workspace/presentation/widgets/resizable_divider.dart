import 'package:appflowy/util/theme_extension.dart';
import 'package:flutter/material.dart';

/// 可拖动的分界线组件
/// 用于在左右两栏之间提供明显的分隔线，并支持拖动调整大小
class ResizableDivider extends StatefulWidget {
  const ResizableDivider({
    super.key,
    required this.onResize,
    this.minLeftWidth = 200.0,
    this.maxLeftWidth = 500.0,
    this.initialLeftWidth = 260.0,
    this.dividerWidth = 4.0,
    this.dividerLineWidth = 2.0,
  });

  /// 当拖动时的回调，参数为新的左侧宽度
  final ValueChanged<double> onResize;

  /// 左侧最小宽度
  final double minLeftWidth;

  /// 左侧最大宽度
  final double maxLeftWidth;

  /// 左侧初始宽度
  final double initialLeftWidth;

  /// 分界线可点击区域宽度
  final double dividerWidth;

  /// 分界线可视线宽度
  final double dividerLineWidth;

  @override
  State<ResizableDivider> createState() => _ResizableDividerState();
}

class _ResizableDividerState extends State<ResizableDivider> {
  bool _isHovered = false;
  bool _isDragging = false;
  double _currentLeftWidth = 0.0;

  @override
  void initState() {
    super.initState();
    _currentLeftWidth = widget.initialLeftWidth;
  }

  @override
  Widget build(BuildContext context) {
    final dividerColor = _isHovered || _isDragging
        ? Theme.of(context).colorScheme.primary
        : Colors.transparent;

    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) {
        if (mounted) setState(() => _isHovered = false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) {
          // 只有在分隔线区域内开始水平拖动时才处理
          setState(() => _isDragging = true);
        },
        onHorizontalDragUpdate: (details) {
          final newWidth = _currentLeftWidth + details.delta.dx;
          if (newWidth >= widget.minLeftWidth &&
              newWidth <= widget.maxLeftWidth) {
            _currentLeftWidth = newWidth;
            widget.onResize(newWidth);
          }
        },
        onHorizontalDragEnd: (_) {
          setState(() => _isDragging = false);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: widget.dividerWidth,
          child: Align(
            alignment: Alignment.centerLeft,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: widget.dividerLineWidth,
              decoration: BoxDecoration(
                color: dividerColor,
                borderRadius: BorderRadius.circular(widget.dividerLineWidth / 2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}









