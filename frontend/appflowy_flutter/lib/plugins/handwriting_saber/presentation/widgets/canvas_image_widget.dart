import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../third_party/saber_core/components/canvas/image/editor_image.dart';

/// ✅ 画布图片组件 - 完全独立处理所有手势交互
/// 关键设计：
/// 1. 总是接收手势（不依赖于 widget.selected）
/// 2. 未选中状态下点击会自动选中并开始拖拽
/// 3. 所有操作（拖动、缩放、旋转、删除）都由组件内部完全处理
class CanvasImageWidget extends StatefulWidget {
  const CanvasImageWidget({
    super.key,
    required this.image,
    required this.pageSize,
    required this.scale,
    required this.readOnly,
    required this.selected,
    required this.onImageChanged,
    required this.onImageDeleted,
  });

  final EditorImage image;
  final Size pageSize;
  final double scale;
  final bool readOnly;
  final bool selected;
  final VoidCallback onImageChanged;
  final VoidCallback onImageDeleted;

  @override
  State<CanvasImageWidget> createState() => _CanvasImageWidgetState();
}

class _CanvasImageWidgetState extends State<CanvasImageWidget> {
  /// 是否正在操作图片（拖动/缩放/旋转）
  /// 独立于父组件的 _isImageOperationInProgress
  bool _isOperating = false;

  /// 操作开始时的图片矩形
  Rect _startRect = Rect.zero;

  /// 缩放手柄的起始位置
  Offset _resizeStartPosition = Offset.zero;

  @override
  void didUpdateWidget(CanvasImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当选中状态从 false 变为 true 时，重置操作状态
    if (!oldWidget.selected && widget.selected) {
      _isOperating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.image;
    if (image.dstRect == null) return const SizedBox.shrink();

    final rect = image.dstRect!;
    final screenLeft = rect.left * widget.scale;
    final screenTop = rect.top * widget.scale;
    final screenWidth = rect.width * widget.scale;
    final screenHeight = rect.height * widget.scale;

    // 构建图片内容
    Widget imageContent;
    if (image is PngEditorImage) {
      imageContent = Image.memory(
        image.imageBytes,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Colors.grey.withValues(alpha: 0.3),
            child: const Center(
              child: Icon(Icons.error, color: Colors.red, size: 32),
            ),
          );
        },
      );
    } else if (image is SvgEditorImage) {
      imageContent = Container(
        color: Colors.purple.withValues(alpha: 0.3),
        child: const Center(
          child: Icon(Icons.image, color: Colors.white, size: 32),
        ),
      );
    } else {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: screenLeft,
      top: screenTop,
      width: screenWidth,
      height: screenHeight,
      child: IgnorePointer(
        ignoring: widget.readOnly,
        child: MouseRegion(
          onEnter: (_) => _setHovering(true),
          onExit: (_) => _setHovering(false),
          cursor: _getCursor(),
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) => _handlePointerDown(event),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 图片内容
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: widget.selected
                          ? Colors.blue
                          : _isOperating
                              ? Colors.blue.withValues(alpha: 0.7)
                              : Colors.transparent,
                      width: widget.selected ? 2 : (_isOperating ? 2 : 0),
                    ),
                  ),
                  child: imageContent,
                ),
                // 选中时的控制手柄
                if (widget.selected) ..._buildControls(screenWidth, screenHeight),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 处理指针按下事件
  void _handlePointerDown(PointerDownEvent event) {
    if (widget.selected) {
      // 已选中状态下，开始拖拽操作
      _isOperating = true;
      _startRect = widget.image.dstRect!;
      _setHovering(true);
    } else {
      // 未选中状态下，先选中图片
      widget.onImageChanged();
      // 选中后立即开始操作
      _isOperating = true;
      _startRect = widget.image.dstRect!;
    }
  }

  /// 构建选中状态下的控制手柄
  List<Widget> _buildControls(double screenWidth, double screenHeight) {
    return [
      // 调整大小手柄 - 8个方向
      _buildResizeHandle(const Offset(-1, -1), screenWidth, screenHeight), // 左上
      _buildResizeHandle(const Offset(1, -1), screenWidth, screenHeight), // 右上
      _buildResizeHandle(const Offset(-1, 1), screenWidth, screenHeight), // 左下
      _buildResizeHandle(const Offset(1, 1), screenWidth, screenHeight), // 右下
      _buildResizeHandle(const Offset(0, -1), screenWidth, screenHeight), // 上
      _buildResizeHandle(const Offset(0, 1), screenWidth, screenHeight), // 下
      _buildResizeHandle(const Offset(-1, 0), screenWidth, screenHeight), // 左
      _buildResizeHandle(const Offset(1, 0), screenWidth, screenHeight), // 右
      // 删除按钮
      _buildDeleteButton(),
      // 旋转按钮
      _buildRotateButton(),
    ];
  }

  /// 构建调整大小手柄
  Widget _buildResizeHandle(
      Offset position, double screenWidth, double screenHeight) {
    final colorScheme = Theme.of(context).colorScheme;

    return Positioned(
      left: (position.dx.sign + 1) / 2 * screenWidth - 10,
      top: (position.dy.sign + 1) / 2 * screenHeight - 10,
      child: MouseRegion(
        cursor: _getResizeCursor(position),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) {
            _startRect = widget.image.dstRect!;
            _resizeStartPosition = details.localPosition;
          },
          onPanUpdate: (details) {
            final delta = details.localPosition - _resizeStartPosition;
            final pageDelta = delta / widget.scale;

            double newWidth = _startRect.width;
            double newHeight = _startRect.height;
            double newLeft = _startRect.left;
            double newTop = _startRect.top;

            // 根据手柄位置计算新尺寸
            if (position.dx < 0) {
              newWidth = _startRect.width - pageDelta.dx;
              newLeft = _startRect.left + pageDelta.dx;
            } else if (position.dx > 0) {
              newWidth = _startRect.width + pageDelta.dx;
            }

            if (position.dy < 0) {
              newHeight = _startRect.height - pageDelta.dy;
              newTop = _startRect.top + pageDelta.dy;
            } else if (position.dy > 0) {
              newHeight = _startRect.height + pageDelta.dy;
            }

            // 限制最小尺寸
            if (newWidth < 50 || newHeight < 50) return;

            // 保持宽高比（对角线拖拽时）
            if (position.dx != 0 && position.dy != 0) {
              final aspectRatio = _startRect.width / _startRect.height;
              if (newWidth / newHeight > aspectRatio) {
                newHeight = newWidth / aspectRatio;
              } else {
                newWidth = newHeight * aspectRatio;
              }

              // 重新计算 left 和 top
              if (position.dx < 0) {
                newLeft = _startRect.right - newWidth;
              }
              if (position.dy < 0) {
                newTop = _startRect.bottom - newHeight;
              }
            }

            _updateImageRect(newLeft, newTop, newWidth, newHeight);
          },
          onPanEnd: (details) {
            widget.onImageChanged();
          },
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              shape: BoxShape.circle,
              border: Border.all(
                color: colorScheme.surface,
                width: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 获取调整大小的鼠标样式
  MouseCursor _getResizeCursor(Offset position) {
    if (position.dx == 0 && position.dy < 0) {
      return SystemMouseCursors.resizeUp;
    }
    if (position.dx == 0 && position.dy > 0) {
      return SystemMouseCursors.resizeDown;
    }
    if (position.dx < 0 && position.dy == 0) {
      return SystemMouseCursors.resizeLeft;
    }
    if (position.dx > 0 && position.dy == 0) {
      return SystemMouseCursors.resizeRight;
    }
    if (position.dx < 0 && position.dy < 0) {
      return SystemMouseCursors.resizeUpLeft;
    }
    if (position.dx < 0 && position.dy > 0) {
      return SystemMouseCursors.resizeDownLeft;
    }
    if (position.dx > 0 && position.dy < 0) {
      return SystemMouseCursors.resizeUpRight;
    }
    if (position.dx > 0 && position.dy > 0) {
      return SystemMouseCursors.resizeDownRight;
    }
    return MouseCursor.defer;
  }

  /// 构建旋转按钮
  Widget _buildRotateButton() {
    final colorScheme = Theme.of(context).colorScheme;

    return Positioned(
      left: -10,
      top: -10,
      child: GestureDetector(
        onTap: () => _rotateImage(),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: colorScheme.primary,
            shape: BoxShape.circle,
            border: Border.all(
              color: colorScheme.surface,
              width: 2,
            ),
          ),
          child: const Icon(
            Icons.rotate_right,
            color: Colors.white,
            size: 16,
          ),
        ),
      ),
    );
  }

  /// 旋转图片 90 度
  void _rotateImage() {
    if (widget.image.dstRect == null) return;

    final rect = widget.image.dstRect!;

    // 交换宽度和高度（旋转 90 度）
    final newWidth = rect.height;
    final newHeight = rect.width;

    // 保持中心点不变
    final centerX = rect.left + rect.width / 2;
    final centerY = rect.top + rect.height / 2;
    final newLeft = centerX - newWidth / 2;
    final newTop = centerY - newHeight / 2;

    _updateImageRect(newLeft, newTop, newWidth, newHeight);
    widget.onImageChanged();
  }

  /// 构建删除按钮
  Widget _buildDeleteButton() {
    final colorScheme = Theme.of(context).colorScheme;

    return Positioned(
      right: -10,
      top: -10,
      child: GestureDetector(
        onTap: () => _showDeleteDialog(context),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.red,
            shape: BoxShape.circle,
            border: Border.all(
              color: colorScheme.surface,
              width: 2,
            ),
          ),
          child: const Icon(
            Icons.close,
            color: Colors.white,
            size: 16,
          ),
        ),
      ),
    );
  }

  /// 显示删除确认对话框
  Future<void> _showDeleteDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除图片'),
        content: const Text('确定要删除这张图片吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      widget.onImageDeleted();
    }
  }

  /// 更新图片矩形并触发重建
  void _updateImageRect(
      double left, double top, double width, double height) {
    setState(() {
      widget.image.dstRect = Rect.fromLTWH(
        left.clamp(0.0, widget.pageSize.width - width),
        top.clamp(0.0, widget.pageSize.height - height),
        width,
        height,
      );
    });
  }

  /// 设置悬停状态
  void _setHovering(bool value) {
    if (mounted) {
      setState(() {});
    }
  }

  /// 获取鼠标样式
  MouseCursor _getCursor() {
    if (_isOperating) {
      return SystemMouseCursors.move;
    }
    return widget.selected ? SystemMouseCursors.move : MouseCursor.defer;
  }
}
