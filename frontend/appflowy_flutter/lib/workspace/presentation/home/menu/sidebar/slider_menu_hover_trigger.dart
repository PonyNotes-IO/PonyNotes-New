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
    final visualSize = widget.touchOptimized ? 44.0 : 36.0;
    final hitSize = widget.touchOptimized ? 48.0 : 44.0;
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
            width: hitSize,
            height: hitSize,
            child: Center(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: opacity,
                child: Material(
                  color: theme.colorScheme.surface,
                  elevation: _isHovered ? 8 : 4,
                  shadowColor: Colors.black.withOpacity(0.14),
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
                        color: theme.colorScheme.onSurface.withOpacity(0.74),
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
