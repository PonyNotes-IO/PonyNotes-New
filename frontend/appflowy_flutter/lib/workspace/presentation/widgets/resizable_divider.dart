import 'dart:async';

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
    this.dividerWidth = 6.0,
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

  @override
  State<ResizableDivider> createState() => _ResizableDividerState();
}

class _ResizableDividerState extends State<ResizableDivider> {
  bool _isHovered = false;
  bool _isDragging = false;
  Timer? _hoverTimer;
  double _currentLeftWidth = 0.0;

  @override
  void initState() {
    super.initState();
    _currentLeftWidth = widget.initialLeftWidth;
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLightMode = Theme.of(context).isLightMode;

    // 计算分界线颜色
    // 默认状态：稍微明显的灰色，便于识别但不刺眼
    // 悬停/拖动状态：主色调，更加醒目
    Color dividerColor;
    if (_isDragging) {
      dividerColor = Theme.of(context).colorScheme.primary;
    } else if (_isHovered) {
      dividerColor = Theme.of(context).colorScheme.primary.withValues(alpha: 0.8);
    } else {
      // 默认状态下的分界线颜色 - 提高对比度
      dividerColor = isLightMode
          ? const Color(0xFFD0D5DD) // 浅色模式下用更深的灰色
          : const Color(0xFF404040); // 深色模式下用较亮的灰色
    }

    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) {
        _hoverTimer = Timer(const Duration(milliseconds: 200), () {
          if (mounted) {
            setState(() => _isHovered = true);
          }
        });
      },
      onExit: (_) {
        _hoverTimer?.cancel();
        if (mounted) {
          setState(() => _isHovered = false);
        }
      },
      child: GestureDetector(
        // 使用 translucent，允许文档拖拽穿透，避免拦截文档拖拽
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (details) {
          // 只有在分隔线区域内开始水平拖动时才处理
          setState(() => _isDragging = true);
        },
        onHorizontalDragUpdate: (details) {
          // 只有在拖动分隔线时才更新宽度
          if (_isDragging) {
            final newWidth = _currentLeftWidth + details.delta.dx;
            if (newWidth >= widget.minLeftWidth &&
                newWidth <= widget.maxLeftWidth) {
              _currentLeftWidth = newWidth;
              widget.onResize(newWidth);
            }
          }
        },
        onHorizontalDragEnd: (_) {
          setState(() => _isDragging = false);
        },
        onHorizontalDragCancel: () {
          // 确保在拖拽取消时重置状态，防止阴影残留
          setState(() => _isDragging = false);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: widget.dividerWidth,
          decoration: BoxDecoration(
            // 添加微妙的阴影效果，增加层次感
            boxShadow: _isDragging || _isHovered
                ? [
                    BoxShadow(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.15),
                      blurRadius: 4,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: _isDragging || _isHovered ? 3.0 : 1.0,
              decoration: BoxDecoration(
                color: dividerColor,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}









