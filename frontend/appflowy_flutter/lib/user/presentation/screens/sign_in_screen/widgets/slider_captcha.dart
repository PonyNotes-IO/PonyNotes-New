import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

/// 滑动验证组件，防止自动脚本无限制发送验证码
///
/// 用法：将组件内嵌到表单中，在 [onVerified] 回调后才允许发送验证码。
/// 重置：修改 [resetKey] 的值即可恢复初始未验证状态。
class SliderCaptcha extends StatefulWidget {
  const SliderCaptcha({
    super.key,
    required this.onVerified,
    this.resetKey,
  });

  final VoidCallback onVerified;

  /// 修改此值可重置滑块为初始状态（如发送成功后重置）
  final Object? resetKey;

  @override
  State<SliderCaptcha> createState() => _SliderCaptchaState();
}

class _SliderCaptchaState extends State<SliderCaptcha>
    with SingleTickerProviderStateMixin {
  static const double _trackHeight = 44.0;
  static const double _thumbSize = 40.0;
  // 滑到 88% 即视为验证通过
  static const double _verifyThreshold = 0.88;

  double _dragX = 0.0;
  double _trackWidth = 0.0;
  bool _verified = false;

  late AnimationController _resetController;
  late Animation<double> _resetAnimation;

  @override
  void initState() {
    super.initState();
    _resetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _resetAnimation = Tween<double>(begin: 0, end: 0).animate(_resetController);
    _resetController.addListener(() {
      if (mounted) {
        setState(() => _dragX = _resetAnimation.value);
      }
    });
  }

  @override
  void didUpdateWidget(SliderCaptcha oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resetKey != oldWidget.resetKey) {
      _resetToStart();
    }
  }

  @override
  void dispose() {
    _resetController.dispose();
    super.dispose();
  }

  double get _maxDrag => (_trackWidth - _thumbSize).clamp(0, double.infinity);
  double get _progress => _maxDrag > 0 ? _dragX / _maxDrag : 0.0;

  void _resetToStart({bool animated = true}) {
    _resetController.stop();
    if (!animated || _dragX == 0) {
      if (_dragX == 0 && !_verified) {
        return;
      }
      setState(() {
        _dragX = 0;
        _verified = false;
      });
      return;
    }

    setState(() => _verified = false);
    _resetAnimation = Tween<double>(begin: _dragX, end: 0).animate(
      CurvedAnimation(parent: _resetController, curve: Curves.easeOut),
    );
    _resetController.forward(from: 0);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_verified || _trackWidth == 0) return;
    setState(() {
      _dragX = (_dragX + details.delta.dx).clamp(0.0, _maxDrag);
    });
    if (_progress >= _verifyThreshold) {
      _resetController.stop();
      setState(() {
        _dragX = _maxDrag;
        _verified = true;
      });
      widget.onVerified();
    }
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_verified) {
      _resetToStart();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final primaryColor = Theme.of(context).colorScheme.primary;

    return LayoutBuilder(
      builder: (context, constraints) {
        _trackWidth = constraints.maxWidth;
        final maxDrag = _maxDrag;

        return SizedBox(
          height: _trackHeight,
          child: Stack(
            children: [
              // 轨道背景
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _verified
                        ? primaryColor.withValues(alpha: 0.08)
                        : theme.fillColorScheme.contentHover,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _verified
                          ? primaryColor.withValues(alpha: 0.6)
                          : theme.borderColorScheme.tertiary,
                    ),
                  ),
                  child: _verified
                      ? _buildVerifiedLabel(primaryColor)
                      : _buildHintLabel(theme),
                ),
              ),
              // 已滑过区域高亮
              if (_dragX > 0)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: (_dragX + _thumbSize / 2).clamp(0, _trackWidth),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _verified
                          ? primaryColor.withValues(alpha: 0.18)
                          : primaryColor.withValues(alpha: 0.12),
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(6),
                      ),
                    ),
                  ),
                ),
              // 滑块
              Positioned(
                left: _dragX.clamp(0, maxDrag),
                top: (_trackHeight - _thumbSize) / 2,
                child: GestureDetector(
                  onHorizontalDragUpdate: _verified ? null : _onDragUpdate,
                  onHorizontalDragEnd: _verified ? null : _onDragEnd,
                  child: Container(
                    width: _thumbSize,
                    height: _thumbSize,
                    decoration: BoxDecoration(
                      color: _verified ? primaryColor : Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      _verified
                          ? Icons.check
                          : Icons.keyboard_double_arrow_right,
                      color: _verified ? Colors.white : primaryColor,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHintLabel(AppFlowyThemeData theme) {
    return Center(
      child: Text(
        '按住滑块向右滑动验证',
        style: TextStyle(
          fontSize: 13,
          color: theme.textColorScheme.tertiary,
          letterSpacing: 0,
        ),
      ),
    );
  }

  Widget _buildVerifiedLabel(Color primaryColor) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_outlined, color: primaryColor, size: 17),
          const SizedBox(width: 5),
          Text(
            '验证通过',
            style: TextStyle(
              fontSize: 13,
              color: primaryColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
