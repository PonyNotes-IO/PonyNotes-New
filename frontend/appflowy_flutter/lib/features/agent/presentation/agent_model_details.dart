import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/features/ai_internal/application/ai_provider_config.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

/// A passive hover card: the model menu keeps handling clicks and keyboard input.
class AgentModelDetails extends StatefulWidget {
  const AgentModelDetails({
    super.key,
    required this.config,
    required this.menuHeaderKey,
    required this.child,
  });

  final AiProviderConfig config;
  final GlobalKey menuHeaderKey;
  final Widget child;

  @override
  State<AgentModelDetails> createState() => _AgentModelDetailsState();
}

class _AgentModelDetailsState extends State<AgentModelDetails> {
  final _portal = OverlayPortalController();
  Timer? _delay;
  Rect? _menuHeader;

  void _show() {
    _delay?.cancel();
    _delay = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      final header =
          widget.menuHeaderKey.currentContext?.findRenderObject() as RenderBox?;
      final overlay = Overlay.of(context, rootOverlay: true)
          .context
          .findRenderObject()! as RenderBox;
      if (header == null || !header.attached) return;
      _menuHeader =
          header.localToGlobal(Offset.zero, ancestor: overlay) & header.size;
      _portal.show();
    });
  }

  void _hide() {
    _delay?.cancel();
    _portal.hide();
  }

  @override
  void dispose() {
    _delay?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final foreground = theme.textColorScheme.primary;
    final config = widget.config;
    return OverlayPortal.targetsRootOverlay(
      controller: _portal,
      overlayChildBuilder: (context) => IgnorePointer(
        child: CustomSingleChildLayout(
          delegate: _ModelDetailsLayout(_menuHeader!),
          child: Container(
            key: const ValueKey('agent-model-details'),
            width: 224,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: theme.surfaceColorScheme.layer01,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: foreground.withValues(alpha: .12)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x26000000),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  config.label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: foreground,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                ),
                const SizedBox(height: 10),
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: '创建人：'),
                      TextSpan(
                        text: config.creatorName.trim().isEmpty
                            ? '未知'
                            : config.creatorName,
                        style: TextStyle(
                          color: foreground.withValues(alpha: .8),
                        ),
                      ),
                    ],
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: foreground.withValues(alpha: .45),
                        fontSize: 11,
                        height: 1.4,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
      child: MouseRegion(
        onEnter: (_) => _show(),
        onExit: (_) => _hide(),
        child: Focus(
          canRequestFocus: false,
          onFocusChange: (focused) => focused ? _show() : _hide(),
          child: widget.child,
        ),
      ),
    );
  }
}

class _ModelDetailsLayout extends SingleChildLayoutDelegate {
  const _ModelDetailsLayout(this.header);

  final Rect header;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.max(0, math.min(224, constraints.maxWidth - 16)),
        maxHeight: math.max(0, constraints.maxHeight - 16),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    // Match the menu's outer padding and prefer its left side, as in the design.
    var left = header.left - 6 - 8 - childSize.width;
    var top = header.top - 6;
    if (left < 8) {
      // MenuAnchor lays out the heading at its intrinsic width; the menu itself
      // is 224 px wide. Use the menu's edge when trying the right side.
      left = header.left - 6 + 224 + 8;
      if (left + childSize.width > size.width - 8) {
        left = header.left - 6;
        top -= childSize.height + 8;
      }
    }
    return Offset(
      left.clamp(8.0, math.max(8.0, size.width - childSize.width - 8)),
      top.clamp(8.0, math.max(8.0, size.height - childSize.height - 8)),
    );
  }

  @override
  bool shouldRelayout(_ModelDetailsLayout oldDelegate) =>
      header != oldDelegate.header;
}
