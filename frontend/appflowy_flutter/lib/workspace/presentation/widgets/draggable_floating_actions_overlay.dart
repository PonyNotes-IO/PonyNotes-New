import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class DraggableFloatingActionsOverlay extends StatefulWidget {
  const DraggableFloatingActionsOverlay({
    super.key,
    required this.child,
    required this.edgeInsets,
    this.fallbackChildSize = const Size(188, 52),
  });

  final Widget child;
  final EdgeInsets edgeInsets;
  final Size fallbackChildSize;

  @override
  State<DraggableFloatingActionsOverlay> createState() =>
      _DraggableFloatingActionsOverlayState();
}

class _DraggableFloatingActionsOverlayState
    extends State<DraggableFloatingActionsOverlay> {
  late Size _childSize = widget.fallbackChildSize;
  Offset? _normalizedPosition;
  Offset? _dragStartGlobalPosition;
  Offset? _dragStartTopLeft;
  Offset? _dragTopLeft;

  bool get _isDragging => _dragStartGlobalPosition != null;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = constraints.biggest;
        final insets = _effectiveInsets(context);
        final resolvedTopLeft = _dragTopLeft ??
            _resolveTopLeft(
              viewportSize: viewportSize,
              insets: insets,
            );

        return Stack(
          children: [
            Positioned(
              left: resolvedTopLeft.dx,
              top: resolvedTopLeft.dy,
              child: _MeasureSize(
                onChange: _handleChildSizeChanged,
                child: MouseRegion(
                  cursor: _isDragging
                      ? SystemMouseCursors.grabbing
                      : SystemMouseCursors.grab,
                  child: GestureDetector(
                    behavior: HitTestBehavior.deferToChild,
                    onPanStart: (details) =>
                        _handlePanStart(details, viewportSize, insets),
                    onPanUpdate: (details) =>
                        _handlePanUpdate(details, viewportSize, insets),
                    onPanEnd: (_) => _handlePanEnd(),
                    onPanCancel: _handlePanEnd,
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  EdgeInsets _effectiveInsets(BuildContext context) {
    final safePadding = MediaQuery.paddingOf(context);
    return EdgeInsets.fromLTRB(
      widget.edgeInsets.left + safePadding.left,
      widget.edgeInsets.top + safePadding.top,
      widget.edgeInsets.right + safePadding.right,
      widget.edgeInsets.bottom + safePadding.bottom,
    );
  }

  void _handleChildSizeChanged(Size size) {
    if (!mounted || size == Size.zero || size == _childSize) {
      return;
    }

    setState(() {
      _childSize = size;
      _dragTopLeft = null;
    });
  }

  void _handlePanStart(
    DragStartDetails details,
    Size viewportSize,
    EdgeInsets insets,
  ) {
    final currentTopLeft = _resolveTopLeft(
      viewportSize: viewportSize,
      insets: insets,
    );
    setState(() {
      _dragStartGlobalPosition = details.globalPosition;
      _dragStartTopLeft = currentTopLeft;
      _dragTopLeft = currentTopLeft;
    });
  }

  void _handlePanUpdate(
    DragUpdateDetails details,
    Size viewportSize,
    EdgeInsets insets,
  ) {
    final dragStartGlobalPosition = _dragStartGlobalPosition;
    final dragStartTopLeft = _dragStartTopLeft;
    if (dragStartGlobalPosition == null || dragStartTopLeft == null) {
      return;
    }

    final delta = details.globalPosition - dragStartGlobalPosition;
    final nextTopLeft = _clampTopLeft(
      dragStartTopLeft + delta,
      viewportSize: viewportSize,
      insets: insets,
    );

    setState(() {
      _dragTopLeft = nextTopLeft;
      _normalizedPosition = _normalizePosition(
        nextTopLeft,
        viewportSize: viewportSize,
        insets: insets,
      );
    });
  }

  void _handlePanEnd() {
    if (!_isDragging) {
      return;
    }

    setState(() {
      _dragStartGlobalPosition = null;
      _dragStartTopLeft = null;
      _dragTopLeft = null;
    });
  }

  Offset _resolveTopLeft({
    required Size viewportSize,
    required EdgeInsets insets,
  }) {
    final movementRect = _movementRect(
      viewportSize: viewportSize,
      insets: insets,
    );
    final normalizedPosition = _normalizedPosition;
    if (normalizedPosition == null) {
      return Offset(movementRect.right, movementRect.top);
    }

    final availableWidth = movementRect.right - movementRect.left;
    final availableHeight = movementRect.bottom - movementRect.top;
    return Offset(
      movementRect.left + availableWidth * normalizedPosition.dx,
      movementRect.top + availableHeight * normalizedPosition.dy,
    );
  }

  Offset _clampTopLeft(
    Offset topLeft, {
    required Size viewportSize,
    required EdgeInsets insets,
  }) {
    final movementRect = _movementRect(
      viewportSize: viewportSize,
      insets: insets,
    );
    return Offset(
      topLeft.dx.clamp(movementRect.left, movementRect.right).toDouble(),
      topLeft.dy.clamp(movementRect.top, movementRect.bottom).toDouble(),
    );
  }

  Offset _normalizePosition(
    Offset topLeft, {
    required Size viewportSize,
    required EdgeInsets insets,
  }) {
    final movementRect = _movementRect(
      viewportSize: viewportSize,
      insets: insets,
    );
    final availableWidth = movementRect.right - movementRect.left;
    final availableHeight = movementRect.bottom - movementRect.top;
    return Offset(
      availableWidth <= 0
          ? 1.0
          : ((topLeft.dx - movementRect.left) / availableWidth).clamp(0.0, 1.0),
      availableHeight <= 0
          ? 0.0
          : ((topLeft.dy - movementRect.top) / availableHeight).clamp(0.0, 1.0),
    );
  }

  Rect _movementRect({
    required Size viewportSize,
    required EdgeInsets insets,
  }) {
    final left = insets.left;
    final top = insets.top;
    final right = (viewportSize.width - insets.right - _childSize.width)
        .clamp(left, double.infinity)
        .toDouble();
    final bottom = (viewportSize.height - insets.bottom - _childSize.height)
        .clamp(top, double.infinity)
        .toDouble();
    return Rect.fromLTRB(left, top, right, bottom);
  }
}

class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({
    required this.onChange,
    required super.child,
  });

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _MeasureSizeRenderObject(onChange);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _MeasureSizeRenderObject renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class _MeasureSizeRenderObject extends RenderProxyBox {
  _MeasureSizeRenderObject(this.onChange);

  ValueChanged<Size> onChange;
  Size? _lastSize;

  @override
  void performLayout() {
    super.performLayout();
    final nextSize = child?.size;
    if (nextSize == null || nextSize == _lastSize) {
      return;
    }

    _lastSize = nextSize;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(nextSize));
  }
}
