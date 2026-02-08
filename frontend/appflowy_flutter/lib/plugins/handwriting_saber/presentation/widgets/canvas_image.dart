import 'dart:math' as math;

import 'package:defer_pointer/defer_pointer.dart';
import 'package:flutter/material.dart';
import '../../third_party/saber_core/components/canvas/image/editor_image.dart';
import '../../third_party/saber_core/data/extensions/change_notifier_extensions.dart';

/// ✅ CanvasImage 组件（从 Saber 项目移植）
/// 支持图片的选中、拖动、缩放等交互操作
class CanvasImage extends StatefulWidget {
  const CanvasImage({
    super.key,
    required this.image,
    required this.pageSize,
    this.selected = false,
    this.readOnly = false,
    this.shouldActivate = false,
    this.onMoveImage,
    this.onDeleteImage,
    this.onTap,
  });

  final EditorImage image;
  final Size pageSize;
  final bool selected;
  final bool readOnly;
  /// ✅ 当此值为 true 时，图片将被激活（可拖动）
  /// 父组件可以通过改变此值来控制图片的激活状态
  final bool shouldActivate;
  final void Function(EditorImage image, Rect offset)? onMoveImage;
  final void Function(EditorImage image)? onDeleteImage;
  /// ✅ 点击回调，用于通知父组件更新选中状态
  final VoidCallback? onTap;

  /// 当被通知时，所有 [CanvasImages] 的 [active] 属性都会被设置为 false
  /// 用于在绘制开始时取消所有图片的激活状态
  static var activeListener = ChangeNotifier();

  /// 交互区域的最小尺寸
  static const double minInteractiveSize = 50;

  /// 图片本身的最小尺寸
  static const double minImageSize = 10;

  @override
  State<CanvasImage> createState() => _CanvasImageState();
}

class _CanvasImageState extends State<CanvasImage> {
  var _active = false;
  var _wasManuallyActivated = false;

  /// 图片是否处于活动状态（可拖动）
  bool get active => _active;
  set active(bool value) {
    if (active == value) return;

    if (value) {
      // 当激活一个图片时，取消所有其他图片的激活状态
      CanvasImage.activeListener
          .notifyListenersPlease();
      
      // 标记为手动激活
      _wasManuallyActivated = true;
    }

    _active = value;

    if (mounted) {
      try {
        setState(() {});
      } catch (e) {
        // setState 在 widget 正在构建时可能会抛出错误
      }
    }
  }

  /// 拖拽开始时的矩形
  Rect panStartRect = Rect.zero;

  /// 拖拽开始时的位置
  Offset panStartPosition = Offset.zero;

  @override
  void initState() {
    super.initState();

    // 如果是新图片，自动激活
    if (widget.image.newImage) {
      active = true;
      widget.image.newImage = false;
      _wasManuallyActivated = false;
    }

    // 添加监听器
    widget.image.addListener(_onImageChanged);
    // 添加全局激活状态监听器
    CanvasImage.activeListener.addListener(_disableActive);
  }

  void _disableActive() {
    active = false;
    _wasManuallyActivated = false;
  }

  void _onImageChanged() {
    if (mounted) {
      try {
        setState(() {});
      } catch (e) {
        // 忽略构建过程中的错误
      }
    }
  }

  @override
  void didUpdateWidget(covariant CanvasImage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.image != widget.image) {
      oldWidget.image.removeListener(_onImageChanged);
      widget.image.addListener(_onImageChanged);
    }

    // ✅ 监听 shouldActivate 变化，自动激活/取消激活图片
    if (widget.shouldActivate) {
      // 当 shouldActivate 为 true 时，激活图片
      if (!active) {
        active = true;
        _wasManuallyActivated = false;
      }
    } else if (!widget.shouldActivate && _wasManuallyActivated) {
      // 当 shouldActivate 为 false 且是手动激活时，取消激活
      // 这样点击图片切换激活状态后才能正常工作
      active = false;
      _wasManuallyActivated = false;
    }

    // 只读模式下取消激活
    if (widget.readOnly && active) {
      active = false;
      _wasManuallyActivated = false;
    }
  }

  @override
  void dispose() {
    widget.image.removeListener(_onImageChanged);
    CanvasImage.activeListener.removeListener(_disableActive);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final image = widget.image;

    // 计算屏幕位置和尺寸
    final screenLeft = image.dstRect.left;
    final screenTop = image.dstRect.top;
    final screenWidth = math.max(image.dstRect.width, CanvasImage.minInteractiveSize);
    final screenHeight = math.max(image.dstRect.height, CanvasImage.minInteractiveSize);

    final Widget unpositioned = IgnorePointer(
      ignoring: widget.readOnly,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 图片内容层
          _buildImageContent(context, colorScheme),
          // 选中时显示的半透明遮罩
          if (widget.selected)
            ColoredBox(color: colorScheme.primary.withValues(alpha: 0.3)),
          // 控制手柄（拖动手柄和缩放手柄）
          if (!widget.readOnly)
            _buildControls(context, colorScheme, screenWidth, screenHeight),
        ],
      ),
    );

    // ✅ 使用 AnimatedPositioned，并确保拖动时无动画
    return AnimatedPositioned(
      // ✅ 拖动时或选中时无动画
      duration: (panStartRect != Rect.zero || widget.selected)
          ? Duration.zero
          : const Duration(milliseconds: 300),
      curve: Curves.fastLinearToSlowEaseIn,
      left: screenLeft,
      top: screenTop,
      width: screenWidth,
      height: screenHeight,
      child: unpositioned,
    );
  }

  Widget _buildImageContent(BuildContext context, ColorScheme colorScheme) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        // ✅ 切换激活状态
        active = !active;
        debugPrint('🦋[CanvasImage] onTap: imageId=${widget.image.id}, active=$active, selected=${widget.selected}');
        // ✅ 通知父组件点击事件，用于更新选中状态
        widget.onTap?.call();
        debugPrint('🦋[CanvasImage] onTap: 父组件回调已调用');
      },
      onLongPress: active ? _showOptionsMenu : null,
      onSecondaryTap: active ? _showOptionsMenu : null,
      onPanStart: active
          ? (details) {
              panStartRect = widget.image.dstRect;
            }
          : null,
      onPanUpdate: active
          ? (details) {
              setState(() {
                final fivePercent = math.min(
                  widget.pageSize.width * 0.05,
                  widget.pageSize.height * 0.05,
                );

                widget.image.dstRect = Rect.fromLTWH(
                  (widget.image.dstRect.left + details.delta.dx)
                      .clamp(
                        fivePercent - widget.image.dstRect.width,
                        widget.pageSize.width - fivePercent,
                      )
                      .toDouble(),
                  (widget.image.dstRect.top + details.delta.dy)
                      .clamp(
                        fivePercent - widget.image.dstRect.height,
                        widget.pageSize.height - fivePercent,
                      )
                      .toDouble(),
                  widget.image.dstRect.width,
                  widget.image.dstRect.height,
                );
              });
            }
          : null,
      onPanEnd: active
          ? (details) {
              if (panStartRect == widget.image.dstRect) return;
              if (panStartRect != widget.image.dstRect) {
                // 通知图片位置已更改
                widget.onMoveImage?.call(
                  widget.image,
                  Rect.fromLTRB(
                    widget.image.dstRect.left - panStartRect.left,
                    widget.image.dstRect.top - panStartRect.top,
                    widget.image.dstRect.right - panStartRect.right,
                    widget.image.dstRect.bottom - panStartRect.bottom,
                  ),
                );
              }
              panStartRect = Rect.zero;
            }
          : null,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: active ? colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Center(
          child: SizedBox(
            width: math.max(widget.image.dstRect.width, CanvasImage.minImageSize),
            height: math.max(widget.image.dstRect.height, CanvasImage.minImageSize),
            child: _buildImageWidget(),
          ),
        ),
      ),
    );
  }

  /// 构建图片 widget
  Widget _buildImageWidget() {
    final image = widget.image;
    if (image is PngEditorImage) {
      return Image.memory(
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
      return Container(
        color: Colors.purple.withValues(alpha: 0.3),
        child: const Center(
          child: Icon(Icons.image, color: Colors.white, size: 32),
        ),
      );
    } else {
      return const SizedBox.shrink();
    }
  }

  Widget _buildControls(
      BuildContext context, ColorScheme colorScheme, double screenWidth, double screenHeight) {
    final handles = <Widget>[];

    // 8个方向的缩放手柄
    for (double x = -20; x <= 20; x += 20) {
      for (double y = -20; y <= 20; y += 20) {
        if (x == 0 && y == 0) continue; // 跳过中心点

        handles.add(
          Positioned(
            left: (x / 20 + 1) / 2 * screenWidth - 10,
            top: (y / 20 + 1) / 2 * screenHeight - 10,
            // ✅ 使用 DeferPointer 包裹 resize handle，实现点击穿透
            child: DeferPointer(
              paintOnTop: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: active
                    ? (details) {
                        panStartRect = widget.image.dstRect;
                        panStartPosition = details.localPosition;
                        debugPrint('🦋[CanvasImage] resizeHandle onPanStart: active=$active, x=$x, y=$y');
                      }
                    : null,
                onPanUpdate: active
                    ? (details) {
                        debugPrint('🦋[CanvasImage] resizeHandle onPanUpdate: active=$active');
                        final delta = details.localPosition - panStartPosition;
                        panStartPosition = details.localPosition;

                        double newWidth = panStartRect.width;
                        double newHeight = panStartRect.height;
                        double left = panStartRect.left;
                        double top = panStartRect.top;

                        // 根据手柄位置调整宽度
                        if (x < 0) {
                          newWidth = panStartRect.width - delta.dx;
                          left = panStartRect.right - newWidth;
                        } else if (x > 0) {
                          newWidth = panStartRect.width + delta.dx;
                        }

                        // 根据手柄位置调整高度
                        if (y < 0) {
                          newHeight = panStartRect.height - delta.dy;
                          top = panStartRect.bottom - newHeight;
                        } else if (y > 0) {
                          newHeight = panStartRect.height + delta.dy;
                        }

                        // 限制最小尺寸
                        if (newWidth < CanvasImage.minImageSize ||
                            newHeight < CanvasImage.minImageSize) {
                          return;
                        }

                        // 保持宽高比（对角线拖拽时）
                        if (x != 0 && y != 0) {
                          final aspectRatio = panStartRect.width / panStartRect.height;
                          if (newWidth / newHeight > aspectRatio) {
                            newHeight = newWidth / aspectRatio;
                          } else {
                            newWidth = newHeight * aspectRatio;
                          }
                          // 重新计算 left 和 top
                          if (x < 0) {
                            left = panStartRect.right - newWidth;
                          }
                          if (y < 0) {
                            top = panStartRect.bottom - newHeight;
                          }
                        }

                        setState(() {
                          widget.image.dstRect = Rect.fromLTWH(
                            left,
                            top,
                            newWidth,
                            newHeight,
                          );
                        });
                      }
                    : null,
                onPanEnd: active
                    ? (details) {
                        debugPrint('🦋[CanvasImage] resizeHandle onPanEnd: active=$active');
                        if (panStartRect == widget.image.dstRect) return;
                        if (panStartRect != widget.image.dstRect) {
                          widget.onMoveImage?.call(
                            widget.image,
                            Rect.fromLTRB(
                              widget.image.dstRect.left - panStartRect.left,
                              widget.image.dstRect.top - panStartRect.top,
                              widget.image.dstRect.right - panStartRect.right,
                              widget.image.dstRect.bottom - panStartRect.bottom,
                            ),
                          );
                        }
                        panStartRect = Rect.zero;
                      }
                    : null,
                // ✅ 使用 AnimatedOpacity 控制 resize handle 的可见性（基于 active 状态）
                child: AnimatedOpacity(
                  opacity: active ? 1 : 0,
                  duration: const Duration(milliseconds: 100),
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
            ),
          ),
        );
      }
    }

    // 删除按钮
    handles.add(
      Positioned(
        right: -10,
        top: -10,
        // ✅ 使用 DeferPointer 包裹按钮，实现点击穿透
        child: DeferPointer(
          paintOnTop: true,
          child: GestureDetector(
            onTap: () => _showDeleteConfirm(context),
            child: AnimatedOpacity(
              opacity: active ? 1 : 0,
              duration: const Duration(milliseconds: 100),
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
                child: const Icon(Icons.close, color: Colors.white, size: 16),
              ),
            ),
          ),
        ),
      ),
    );

    // 旋转按钮
    handles.add(
      Positioned(
        left: -10,
        top: -10,
        // ✅ 使用 DeferPointer 包裹按钮，实现点击穿透
        child: DeferPointer(
          paintOnTop: true,
          child: GestureDetector(
            onTap: () => _rotateImage(),
            child: AnimatedOpacity(
              opacity: active ? 1 : 0,
              duration: const Duration(milliseconds: 100),
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
                child: const Icon(Icons.rotate_right, color: Colors.white, size: 16),
              ),
            ),
          ),
        ),
      ),
    );

    return Stack(children: handles);
  }

  void _showOptionsMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        height: 100,
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildOptionButton(
              icon: Icons.delete,
              label: '删除',
              color: Colors.red,
              onTap: () {
                Navigator.pop(context);
                _showDeleteConfirm(context);
              },
            ),
            _buildOptionButton(
              icon: Icons.rotate_right,
              label: '旋转',
              onTap: () {
                Navigator.pop(context);
                _rotateImage();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = Colors.blue,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(label),
        ],
      ),
    );
  }

  Future<void> _showDeleteConfirm(BuildContext context) async {
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
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      widget.onDeleteImage?.call(widget.image);
    }
  }

  void _rotateImage() {
    final rect = widget.image.dstRect;

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
  }
}
