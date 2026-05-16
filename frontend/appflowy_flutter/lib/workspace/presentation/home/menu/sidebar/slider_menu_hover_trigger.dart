import 'package:flutter/material.dart';

class SliderMenuHoverTrigger extends StatefulWidget {
  const SliderMenuHoverTrigger({
    super.key,
    required this.onOpen,
    required this.touchOptimized,
  });

  final VoidCallback onOpen;
  final bool touchOptimized;

  @override
  State<SliderMenuHoverTrigger> createState() => _SliderMenuHoverTriggerState();
}

class _SliderMenuHoverTriggerState extends State<SliderMenuHoverTrigger> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visualSize = widget.touchOptimized ? 48.0 : 40.0;
    final hitWidth = widget.touchOptimized ? 72.0 : 56.0;
    final hitHeight = widget.touchOptimized ? 80.0 : 64.0;
    final opacity = widget.touchOptimized || _isHovered ? 1.0 : 0.72;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Tooltip(
        message: '打开侧边栏',
        child: Semantics(
          button: true,
          label: '打开侧边栏',
          child: SizedBox(
            width: hitWidth,
            height: hitHeight,
            child: Center(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: opacity,
                child: Material(
                  color: theme.colorScheme.surface,
                  elevation: _isHovered ? 8 : 4,
                  shadowColor: Colors.black.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: widget.onOpen,
                    child: SizedBox(
                      width: visualSize,
                      height: visualSize,
                      child: Icon(
                        Icons.keyboard_double_arrow_right_rounded,
                        size: widget.touchOptimized ? 24 : 21,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.74),
                      ),
                    ),
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
