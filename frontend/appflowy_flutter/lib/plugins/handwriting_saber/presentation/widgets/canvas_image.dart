import 'dart:math' as math;

import 'package:defer_pointer/defer_pointer.dart';
import 'package:flutter/material.dart';
import '../../third_party/saber_core/components/canvas/image/editor_image.dart';
import '../../third_party/saber_core/data/extensions/change_notifier_extensions.dart';

/// CanvasImage 组件
/// 支持图片的选中、拖动、缩放、旋转等交互操作
class CanvasImage extends StatefulWidget {
  const CanvasImage({
    super.key,
    required this.image,
    required this.pageSize,
    this.scale = 1.0,
    this.selected = false,
    this.readOnly = false,
    this.shouldActivate = false,
    this.onMoveImage,
    this.onDeleteImage,
    this.onTap,
  });

  final EditorImage image;
  final Size pageSize;

  /// 页面坐标到屏幕坐标的缩放比例
  final double scale;
  final bool selected;
  final bool readOnly;
  final bool shouldActivate;
  final void Function(EditorImage image, Rect offset)? onMoveImage;
  final void Function(EditorImage image)? onDeleteImage;
  final VoidCallback? onTap;

  /// 当通知时，所有 CanvasImage 的 active 都会被取消
  static var activeListener = ChangeNotifier();

  static const double minInteractiveSize = 50;
  static const double minImageSize = 10;

  static const double _handleSize = 14.0;
  static const double _buttonSize = 26.0;
  static const double _rotationHandleDistance = 36.0;

  /// 旋转吸附阈值（弧度，约5度）
  static const double _snapAngle = 5.0 * math.pi / 180.0;

  static const List<double> _snapAngles = [
    0,
    math.pi / 4,
    math.pi / 2,
    3 * math.pi / 4,
    math.pi,
    -3 * math.pi / 4,
    -math.pi / 2,
    -math.pi / 4,
  ];

  @override
  State<CanvasImage> createState() => _CanvasImageState();
}

class _CanvasImageState extends State<CanvasImage> {
  var _active = false;
  var _wasManuallyActivated = false;

  bool get active => _active;
  set active(bool value) {
    if (active == value) return;
    if (value) {
      CanvasImage.activeListener.notifyListenersPlease();
      _wasManuallyActivated = true;
    }
    _active = value;
    if (mounted) {
      try {
        setState(() {});
      } catch (_) {}
    }
  }

  Rect _panStartRect = Rect.zero;

  Offset? _rotationCenter;
  double _rotationStartAngle = 0.0;
  double _initialPointerAngle = 0.0;

  @override
  void initState() {
    super.initState();
    if (widget.image.newImage) {
      active = true;
      widget.image.newImage = false;
      _wasManuallyActivated = false;
    }
    widget.image.addListener(_onImageChanged);
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
      } catch (_) {}
    }
  }

  @override
  void didUpdateWidget(covariant CanvasImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) {
      oldWidget.image.removeListener(_onImageChanged);
      widget.image.addListener(_onImageChanged);
    }
    if (widget.shouldActivate && !active) {
      active = true;
      _wasManuallyActivated = false;
    } else if (!widget.shouldActivate && _wasManuallyActivated) {
      active = false;
      _wasManuallyActivated = false;
    }
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

  double get _screenWidth => math.max(
        widget.image.dstRect.width * widget.scale,
        CanvasImage.minInteractiveSize,
      );
  double get _screenHeight => math.max(
        widget.image.dstRect.height * widget.scale,
        CanvasImage.minInteractiveSize,
      );
  double get _imgWidth => math.max(
        widget.image.dstRect.width * widget.scale,
        CanvasImage.minImageSize,
      );
  double get _imgHeight => math.max(
        widget.image.dstRect.height * widget.scale,
        CanvasImage.minImageSize,
      );

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final image = widget.image;
    final s = widget.scale;

    final screenLeft = image.dstRect.left * s;
    final screenTop = image.dstRect.top * s;

    return Positioned(
      left: screenLeft,
      top: screenTop,
      width: _screenWidth,
      height: _screenHeight,
      child: IgnorePointer(
        ignoring: widget.readOnly,
        child: Transform.rotate(
          angle: image.rotation,
          child: Stack(
            clipBehavior: Clip.none,
            fit: StackFit.expand,
            children: [
              _buildImageContent(context, colorScheme),
              if (widget.selected)
                ColoredBox(
                  color: colorScheme.primary.withValues(alpha: 0.15),
                ),
              if (!widget.readOnly) _buildControls(context, colorScheme),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────── 图片内容层 ────────────────────────

  Widget _buildImageContent(BuildContext context, ColorScheme colorScheme) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        active = !active;
        widget.onTap?.call();
      },
      onLongPress: active ? _showOptionsMenu : null,
      onSecondaryTap: active ? _showOptionsMenu : null,
      onPanStart: active ? _onMovePanStart : null,
      onPanUpdate: active ? _onMovePanUpdate : null,
      onPanEnd: active ? _onMovePanEnd : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: active ? colorScheme.primary : Colors.transparent,
            width: active ? 2 : 0,
          ),
        ),
        child: Center(
          child: SizedBox(
            width: _imgWidth,
            height: _imgHeight,
            child: _buildImageWidget(),
          ),
        ),
      ),
    );
  }

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
    }
    return const SizedBox.shrink();
  }

  // ──────────────────────── 移动手势 ────────────────────────

  void _onMovePanStart(DragStartDetails details) {
    _panStartRect = widget.image.dstRect;
  }

  void _onMovePanUpdate(DragUpdateDetails details) {
    final s = widget.scale;
    if (s <= 0) return;

    final pageDx = details.delta.dx / s;
    final pageDy = details.delta.dy / s;

    final fivePercent = math.min(
      widget.pageSize.width * 0.05,
      widget.pageSize.height * 0.05,
    );
    final rect = widget.image.dstRect;

    widget.image.dstRect = Rect.fromLTWH(
      (rect.left + pageDx)
          .clamp(
            fivePercent - rect.width,
            widget.pageSize.width - fivePercent,
          )
          .toDouble(),
      (rect.top + pageDy)
          .clamp(
            fivePercent - rect.height,
            widget.pageSize.height - fivePercent,
          )
          .toDouble(),
      rect.width,
      rect.height,
    );
  }

  void _onMovePanEnd(DragEndDetails details) {
    _notifyMoveIfChanged();
  }

  // ──────────────────────── 控制手柄层 ────────────────────────

  Widget _buildControls(BuildContext context, ColorScheme colorScheme) {
    if (!active) {
      return const SizedBox.shrink();
    }

    final hs = CanvasImage._handleSize;
    final sw = _screenWidth;
    final sh = _screenHeight;
    final handles = <Widget>[];

    for (int xi = -1; xi <= 1; xi++) {
      for (int yi = -1; yi <= 1; yi++) {
        if (xi == 0 && yi == 0) continue;
        final left = (xi + 1) / 2 * sw - hs / 2;
        final top = (yi + 1) / 2 * sh - hs / 2;
        handles.add(
          _buildResizeHandle(
            colorScheme,
            left,
            top,
            xi.toDouble(),
            yi.toDouble(),
          ),
        );
      }
    }

    handles.add(_buildRotationHandle(colorScheme, sw, sh));
    handles.add(_buildDeleteButton(context, colorScheme, sw));
    handles.add(_buildQuickRotateButton(colorScheme));

    return Stack(clipBehavior: Clip.none, children: handles);
  }

  // ──────────────────────── 缩放手柄 ────────────────────────

  Widget _buildResizeHandle(
    ColorScheme colorScheme,
    double left,
    double top,
    double hx,
    double hy,
  ) {
    final hs = CanvasImage._handleSize;
    return Positioned(
      left: left,
      top: top,
      child: DeferPointer(
        paintOnTop: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) {
            _panStartRect = widget.image.dstRect;
          },
          onPanUpdate: (details) => _onResizePanUpdate(details, hx, hy),
          onPanEnd: (_) => _notifyMoveIfChanged(),
          child: MouseRegion(
            cursor: _resizeCursor(hx, hy),
            child: Container(
              width: hs,
              height: hs,
              decoration: BoxDecoration(
                color: colorScheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: colorScheme.surface, width: 2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onResizePanUpdate(DragUpdateDetails details, double hx, double hy) {
    final s = widget.scale;
    if (s <= 0) return;

    final pageDelta = Offset(details.delta.dx / s, details.delta.dy / s);

    // 将页面 delta 转换到图片本地坐标系（反向旋转）
    final rot = widget.image.rotation;
    final cosA = math.cos(-rot);
    final sinA = math.sin(-rot);
    final localDx = pageDelta.dx * cosA - pageDelta.dy * sinA;
    final localDy = pageDelta.dx * sinA + pageDelta.dy * cosA;

    final rect = widget.image.dstRect;
    double newLeft = rect.left;
    double newTop = rect.top;
    double newWidth = rect.width;
    double newHeight = rect.height;

    if (hx < 0) {
      newWidth -= localDx;
      newLeft = rect.right - newWidth;
    } else if (hx > 0) {
      newWidth += localDx;
    }

    if (hy < 0) {
      newHeight -= localDy;
      newTop = rect.bottom - newHeight;
    } else if (hy > 0) {
      newHeight += localDy;
    }

    // 角点手柄保持宽高比
    if (hx != 0 && hy != 0 && rect.height > 0) {
      final aspectRatio = rect.width / rect.height;
      if (newWidth / newHeight > aspectRatio) {
        newHeight = newWidth / aspectRatio;
      } else {
        newWidth = newHeight * aspectRatio;
      }
      if (hx < 0) {
        newLeft = rect.right - newWidth;
      }
      if (hy < 0) {
        newTop = rect.bottom - newHeight;
      }
    }

    if (newWidth < CanvasImage.minImageSize) {
      newWidth = CanvasImage.minImageSize;
      if (hx < 0) {
        newLeft = rect.right - newWidth;
      }
    }
    if (newHeight < CanvasImage.minImageSize) {
      newHeight = CanvasImage.minImageSize;
      if (hy < 0) {
        newTop = rect.bottom - newHeight;
      }
    }

    widget.image.dstRect = Rect.fromLTWH(newLeft, newTop, newWidth, newHeight);
  }

  MouseCursor _resizeCursor(double hx, double hy) {
    if (hx == 0 && hy != 0) return SystemMouseCursors.resizeUpDown;
    if (hx != 0 && hy == 0) return SystemMouseCursors.resizeLeftRight;
    if ((hx > 0 && hy > 0) || (hx < 0 && hy < 0)) {
      return SystemMouseCursors.resizeUpLeftDownRight;
    }
    return SystemMouseCursors.resizeUpRightDownLeft;
  }

  // ──────────────────────── 旋转手柄 ────────────────────────

  Widget _buildRotationHandle(
    ColorScheme colorScheme,
    double sw,
    double sh,
  ) {
    final hs = CanvasImage._handleSize;
    final dist = CanvasImage._rotationHandleDistance;

    return Positioned(
      left: sw / 2 - hs / 2,
      top: -dist - hs / 2,
      child: DeferPointer(
        paintOnTop: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: _onRotationPanStart,
          onPanUpdate: _onRotationPanUpdate,
          onPanEnd: _onRotationPanEnd,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: hs,
                  height: hs,
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colorScheme.surface,
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.rotate_right,
                    color: Colors.white,
                    size: 10,
                  ),
                ),
                Container(
                  width: 1.5,
                  height: dist - hs / 2,
                  color: Colors.orange.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onRotationPanStart(DragStartDetails details) {
    _panStartRect = widget.image.dstRect;
    _rotationStartAngle = widget.image.rotation;

    final box = context.findRenderObject() as RenderBox?;
    if (box != null) {
      _rotationCenter = box.localToGlobal(
        Offset(_screenWidth / 2, _screenHeight / 2),
      );
    } else {
      _rotationCenter = null;
    }

    if (_rotationCenter != null) {
      _initialPointerAngle = math.atan2(
        details.globalPosition.dy - _rotationCenter!.dy,
        details.globalPosition.dx - _rotationCenter!.dx,
      );
    }
  }

  void _onRotationPanUpdate(DragUpdateDetails details) {
    if (_rotationCenter == null) return;

    final currentAngle = math.atan2(
      details.globalPosition.dy - _rotationCenter!.dy,
      details.globalPosition.dx - _rotationCenter!.dx,
    );
    var newRotation =
        _rotationStartAngle + (currentAngle - _initialPointerAngle);

    while (newRotation > math.pi) {
      newRotation -= 2 * math.pi;
    }
    while (newRotation < -math.pi) {
      newRotation += 2 * math.pi;
    }

    for (final snap in CanvasImage._snapAngles) {
      if ((newRotation - snap).abs() < CanvasImage._snapAngle) {
        newRotation = snap;
        break;
      }
    }

    widget.image.rotation = newRotation;
  }

  void _onRotationPanEnd(DragEndDetails details) {
    _notifyMoveIfChanged();
  }

  // ──────────────────────── 删除按钮 ────────────────────────

  Widget _buildDeleteButton(
    BuildContext context,
    ColorScheme colorScheme,
    double sw,
  ) {
    final bs = CanvasImage._buttonSize;
    return Positioned(
      right: -bs / 2,
      top: -bs / 2,
      child: DeferPointer(
        paintOnTop: true,
        child: GestureDetector(
          onTap: () => _showDeleteConfirm(context),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              width: bs,
              height: bs,
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                border: Border.all(color: colorScheme.surface, width: 2),
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 14),
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────────────── 快速 90° 旋转按钮 ────────────────────────

  Widget _buildQuickRotateButton(ColorScheme colorScheme) {
    final bs = CanvasImage._buttonSize;
    return Positioned(
      left: -bs / 2,
      top: -bs / 2,
      child: DeferPointer(
        paintOnTop: true,
        child: GestureDetector(
          onTap: _quickRotate90,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              width: bs,
              height: bs,
              decoration: BoxDecoration(
                color: colorScheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: colorScheme.surface, width: 2),
              ),
              child: const Icon(
                Icons.rotate_90_degrees_cw_outlined,
                color: Colors.white,
                size: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _quickRotate90() {
    _panStartRect = widget.image.dstRect;
    var newRotation = widget.image.rotation + math.pi / 2;
    if (newRotation > math.pi) {
      newRotation -= 2 * math.pi;
    }
    widget.image.rotation = newRotation;
    _notifyMoveIfChanged();
  }

  // ──────────────────────── 通用工具方法 ────────────────────────

  void _notifyMoveIfChanged() {
    if (_panStartRect == widget.image.dstRect &&
        _rotationStartAngle == widget.image.rotation) {
      return;
    }

    widget.onMoveImage?.call(
      widget.image,
      Rect.fromLTRB(
        widget.image.dstRect.left - _panStartRect.left,
        widget.image.dstRect.top - _panStartRect.top,
        widget.image.dstRect.right - _panStartRect.right,
        widget.image.dstRect.bottom - _panStartRect.bottom,
      ),
    );
    _panStartRect = Rect.zero;
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
              icon: Icons.rotate_90_degrees_cw_outlined,
              label: '旋转90°',
              onTap: () {
                Navigator.pop(context);
                _quickRotate90();
              },
            ),
            _buildOptionButton(
              icon: Icons.restart_alt,
              label: '重置旋转',
              onTap: () {
                Navigator.pop(context);
                _panStartRect = widget.image.dstRect;
                widget.image.rotation = 0.0;
                _notifyMoveIfChanged();
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
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
            child: const Text(
              '删除',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      widget.onDeleteImage?.call(widget.image);
    }
  }
}
