import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../third_party/saber_core/components/canvas/image/editor_image.dart';

/// ✅ 画布图片组件 - 支持选中、移动、缩放和旋转
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
    this.onDragStart,
    this.onDragEnd,
  });

  final EditorImage image;
  final Size pageSize;
  final double scale;
  final bool readOnly;
  final bool selected;
  final VoidCallback onImageChanged;
  final VoidCallback onImageDeleted;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  @override
  State<CanvasImageWidget> createState() => _CanvasImageWidgetState();
}

class _CanvasImageWidgetState extends State<CanvasImageWidget> {
  bool _isHovering = false;
  Rect _panStartRect = Rect.zero;
  Offset _panStartPosition = Offset.zero;

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
          onEnter: (_) => setState(() => _isHovering = true),
          onExit: (_) => setState(() => _isHovering = false),
          cursor: widget.selected ? SystemMouseCursors.move : MouseCursor.defer,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 图片内容
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  // 切换选中状态
                  widget.onImageChanged();
                },
                onPanStart: widget.selected
                    ? (details) {
                        _panStartRect = image.dstRect!;
                        widget.onDragStart?.call();
                      }
                    : null,
                onPanUpdate: widget.selected
                    ? (details) {
                        setState(() {
                          // 将屏幕坐标的 delta 转换为页面坐标
                          final pageDelta = details.delta / widget.scale;

                          // 限制在页面范围内
                          final fivePercent = math.min(
                            widget.pageSize.width * 0.05,
                            widget.pageSize.height * 0.05,
                          );

                          image.dstRect = Rect.fromLTWH(
                            (image.dstRect!.left + pageDelta.dx)
                                .clamp(
                                  fivePercent - image.dstRect!.width,
                                  widget.pageSize.width - fivePercent,
                                )
                                .toDouble(),
                            (image.dstRect!.top + pageDelta.dy)
                                .clamp(
                                  fivePercent - image.dstRect!.height,
                                  widget.pageSize.height - fivePercent,
                                )
                                .toDouble(),
                            image.dstRect!.width,
                            image.dstRect!.height,
                          );
                        });
                      }
                    : null,
                onPanEnd: widget.selected
                    ? (details) {
                        if (_panStartRect != image.dstRect) {
                          widget.onImageChanged();
                        }
                        _panStartRect = Rect.zero;
                        widget.onDragEnd?.call();
                      }
                    : null,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: widget.selected
                          ? Colors.blue
                          : _isHovering
                              ? Colors.blue.withValues(alpha: 0.5)
                              : Colors.transparent,
                      width: widget.selected ? 2 : 1,
                    ),
                  ),
                  child: imageContent,
                ),
              ),
              // 调整大小手柄（只在选中时显示）
              if (widget.selected) ...[
                _buildResizeHandle(context, const Offset(-1, -1)), // 左上
                _buildResizeHandle(context, const Offset(1, -1)), // 右上
                _buildResizeHandle(context, const Offset(-1, 1)), // 左下
                _buildResizeHandle(context, const Offset(1, 1)), // 右下
                _buildResizeHandle(context, const Offset(0, -1)), // 上
                _buildResizeHandle(context, const Offset(0, 1)), // 下
                _buildResizeHandle(context, const Offset(-1, 0)), // 左
                _buildResizeHandle(context, const Offset(1, 0)), // 右
              ],
              // 删除按钮（只在选中时显示）
              if (widget.selected) _buildDeleteButton(context),
              // 旋转按钮（只在选中时显示）
              if (widget.selected) _buildRotateButton(context),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建旋转按钮
  Widget _buildRotateButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Positioned(
      left: -10,
      top: -10,
      child: GestureDetector(
        onTap: () {
          // 旋转 90 度
          _rotateImage();
        },
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

    setState(() {
      widget.image.dstRect = Rect.fromLTWH(
        newLeft,
        newTop,
        newWidth,
        newHeight,
      );
    });

    widget.onImageChanged();
  }

  /// 构建调整大小手柄
  Widget _buildResizeHandle(BuildContext context, Offset position) {
    final colorScheme = Theme.of(context).colorScheme;

    return Positioned(
      left: (position.dx.sign + 1) / 2 * screenWidth - 10,
      top: (position.dy.sign + 1) / 2 * screenHeight - 10,
      child: MouseRegion(
        cursor: _getResizeCursor(position),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) {
            _panStartRect = widget.image.dstRect!;
            _panStartPosition = details.localPosition;
          },
          onPanUpdate: (details) {
            final delta = details.localPosition - _panStartPosition;
            final pageDelta = delta / widget.scale;

            double newWidth = _panStartRect.width;
            double newHeight = _panStartRect.height;
            double newLeft = _panStartRect.left;
            double newTop = _panStartRect.top;

            // 根据手柄位置计算新尺寸
            if (position.dx < 0) {
              // 左边
              newWidth = _panStartRect.width - pageDelta.dx;
              newLeft = _panStartRect.left + pageDelta.dx;
            } else if (position.dx > 0) {
              // 右边
              newWidth = _panStartRect.width + pageDelta.dx;
            }

            if (position.dy < 0) {
              // 上边
              newHeight = _panStartRect.height - pageDelta.dy;
              newTop = _panStartRect.top + pageDelta.dy;
            } else if (position.dy > 0) {
              // 下边
              newHeight = _panStartRect.height + pageDelta.dy;
            }

            // 限制最小尺寸
            if (newWidth < 50 || newHeight < 50) return;

            // 保持宽高比（对角线拖拽时）
            if (position.dx != 0 && position.dy != 0) {
              final aspectRatio = _panStartRect.width / _panStartRect.height;
              if (newWidth / newHeight > aspectRatio) {
                newHeight = newWidth / aspectRatio;
              } else {
                newWidth = newHeight * aspectRatio;
              }

              // 重新计算 left 和 top
              if (position.dx < 0) {
                newLeft = _panStartRect.right - newWidth;
              }
              if (position.dy < 0) {
                newTop = _panStartRect.bottom - newHeight;
              }
            }

            setState(() {
              widget.image.dstRect = Rect.fromLTWH(
                newLeft,
                newTop,
                newWidth,
                newHeight,
              );
            });
          },
          onPanEnd: (details) {
            if (_panStartRect != widget.image.dstRect) {
              widget.onImageChanged();
            }
            _panStartRect = Rect.zero;
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

  /// 构建删除按钮
  Widget _buildDeleteButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Positioned(
      right: -10,
      top: -10,
      child: GestureDetector(
        onTap: () {
          _showDeleteDialog(context);
        },
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

  double get screenWidth => (widget.image.dstRect?.width ?? 0) * widget.scale;
  double get screenHeight => (widget.image.dstRect?.height ?? 0) * widget.scale;
}
