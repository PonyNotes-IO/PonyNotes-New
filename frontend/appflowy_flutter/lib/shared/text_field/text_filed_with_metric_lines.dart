import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TextFieldWithMetricLines extends StatefulWidget {
  const TextFieldWithMetricLines({
    super.key,
    this.controller,
    this.focusNode,
    this.maxLines,
    this.maxLength,
    this.inputFormatters,
    this.style,
    this.decoration,
    this.onLineCountChange,
    this.onDoubleTap,
    this.enabled = true,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final int? maxLines;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final TextStyle? style;
  final InputDecoration? decoration;
  final void Function(int count)? onLineCountChange;
  final VoidCallback? onDoubleTap;
  final bool enabled;

  @override
  State<TextFieldWithMetricLines> createState() =>
      _TextFieldWithMetricLinesState();
}

class _TextFieldWithMetricLinesState extends State<TextFieldWithMetricLines> {
  static const _doubleTapTimeout = Duration(milliseconds: 300);
  static const _doubleTapSlop = 24.0;

  final key = GlobalKey();
  late final controller = widget.controller ?? TextEditingController();
  Offset? _tapDownPosition;
  Offset? _lastTapPosition;
  Duration? _lastTapTimestamp;
  int? _activePointer;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      updateDisplayedLineCount(context);
    });
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      // dispose the controller if it was created by this widget
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: TextField(
        key: key,
        enabled: widget.enabled,
        controller: widget.controller,
        focusNode: widget.focusNode,
        maxLines: widget.maxLines,
        maxLength: widget.maxLength,
        inputFormatters: widget.inputFormatters,
        style: widget.style,
        decoration: widget.decoration,
        onChanged: (_) => updateDisplayedLineCount(context),
      ),
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    if (widget.onDoubleTap == null ||
        !widget.enabled ||
        !_isPrimaryTap(event)) {
      return;
    }

    _activePointer = event.pointer;
    _tapDownPosition = event.position;
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointer) {
      return;
    }

    final tapDownPosition = _tapDownPosition;
    _activePointer = null;
    _tapDownPosition = null;
    if (tapDownPosition == null ||
        (event.position - tapDownPosition).distance > _doubleTapSlop) {
      _resetTapTracking();
      return;
    }

    final lastTapTimestamp = _lastTapTimestamp;
    final lastTapPosition = _lastTapPosition;
    final isDoubleTap = lastTapTimestamp != null &&
        lastTapPosition != null &&
        event.timeStamp - lastTapTimestamp <= _doubleTapTimeout &&
        (event.position - lastTapPosition).distance <= _doubleTapSlop;

    if (!isDoubleTap) {
      _lastTapTimestamp = event.timeStamp;
      _lastTapPosition = event.position;
      return;
    }

    _resetTapTracking();
    // Run after the TextField's own gesture handling so its word-selection
    // result cannot overwrite the title's full-selection behavior.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onDoubleTap?.call();
      }
    });
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer == _activePointer) {
      _activePointer = null;
      _tapDownPosition = null;
    }
  }

  bool _isPrimaryTap(PointerDownEvent event) {
    return event.kind != PointerDeviceKind.mouse ||
        (event.buttons & kPrimaryMouseButton) != 0;
  }

  void _resetTapTracking() {
    _lastTapTimestamp = null;
    _lastTapPosition = null;
  }

  // calculate the number of lines that would be displayed in the text field
  void updateDisplayedLineCount(BuildContext context) {
    if (widget.onLineCountChange == null) {
      return;
    }

    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject == null || renderObject is! RenderBox) {
      return;
    }

    final size = renderObject.size;
    final text = controller.buildTextSpan(
      context: context,
      style: widget.style,
      withComposing: false,
    );
    final textPainter = TextPainter(
      text: text,
      textDirection: Directionality.of(context),
    );

    textPainter.layout(minWidth: size.width, maxWidth: size.width);

    final lines = textPainter.computeLineMetrics().length;
    widget.onLineCountChange?.call(lines);
  }
}
