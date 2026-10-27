import 'dart:math' as math;

import 'package:appflowy/plugins/knowledge_graph/application/knowledge_graph_data.dart';
import 'package:appflowy/plugins/knowledge_graph/knowledge_graph_strings.dart';
import 'package:appflowy/plugins/knowledge_graph/presentation/knowledge_graph_layout.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';

class KnowledgeGraphCanvas extends StatefulWidget {
  const KnowledgeGraphCanvas({
    super.key,
    required this.data,
    required this.showLabels,
    required this.onOpen,
  });

  final KnowledgeGraphData data;
  final bool showLabels;
  final ValueChanged<GraphNode> onOpen;

  @override
  State<KnowledgeGraphCanvas> createState() => KnowledgeGraphCanvasState();
}

class KnowledgeGraphCanvasState extends State<KnowledgeGraphCanvas>
    with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  late final Ticker _springTicker;
  Map<String, Offset> _positions = {};
  Map<String, Offset> _anchors = {};
  final _velocities = <String, Offset>{};
  Map<GraphEdge, double> _restLengths = {};
  Duration? _lastFrame;
  int? _dragPointer;
  String? _dragged;
  Offset _pointerStart = Offset.zero;
  Offset _grabOffset = Offset.zero;
  bool _didDrag = false;
  Size _sceneSize = const Size(800, 600);
  Size _viewport = Size.zero;
  String? _hovered;
  int _layoutVersion = 0;

  @override
  void initState() {
    super.initState();
    _springTicker = createTicker(_animateSprings);
    _layout();
  }

  @override
  void didUpdateWidget(KnowledgeGraphCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.data, widget.data)) _layout();
  }

  Future<void> _layout() async {
    final version = ++_layoutVersion;
    _springTicker.stop();
    _dragPointer = null;
    _dragged = null;
    final positions = await compute(
      layoutKnowledgeGraph,
      GraphLayoutInput(
        widget.data.nodes.map((node) => node.id).toList(),
        widget.data.edges.map((edge) => (edge.source, edge.target)).toList(),
      ),
    );
    if (!mounted || version != _layoutVersion) return;
    setState(() {
      _positions = positions;
      _anchors = Map.of(positions);
      _velocities.clear();
      _restLengths = {
        for (final edge in widget.data.edges)
          if (positions.containsKey(edge.source) &&
              positions.containsKey(edge.target))
            edge: (positions[edge.target]! - positions[edge.source]!).distance,
      };
      _hovered = null;
      _sceneSize = Size(
        positions.values.fold(360.0, (v, p) => math.max(v, p.dx)) + 180,
        positions.values.fold(240.0, (v, p) => math.max(v, p.dy)) + 120,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      fit();
      if (!MediaQuery.disableAnimationsOf(context)) _startSprings();
    });
  }

  void _startSprings() {
    if (!_springTicker.isActive) {
      _lastFrame = null;
      _springTicker.start();
    }
  }

  void _animateSprings(Duration elapsed) {
    final seconds = _lastFrame == null
        ? 1 / 60
        : (elapsed - _lastFrame!).inMicroseconds /
            Duration.microsecondsPerSecond;
    _lastFrame = elapsed;
    // Small, bounded time steps keep the springs stable after a slow frame.
    final duration = seconds.clamp(0.0, 1 / 30);
    final steps = math.max(1, (duration * 120).ceil());
    final dt = duration / steps;
    final next = Map.of(_positions);
    final ids = next.keys.toList();
    var maxForce = 0.0;
    var maxSpeed = 0.0;
    for (var step = 0; step < steps; step++) {
      final repulsion = knowledgeGraphRepulsion(next.values.toList());
      final forces = {
        for (var i = 0; i < ids.length; i++)
          ids[i]: (_anchors[ids[i]]! - next[ids[i]]!) *
                  (ids[i] == _dragged ? 180 : 42) +
              repulsion[i] * 200,
      };
      for (final entry in _restLengths.entries) {
        final edge = entry.key;
        final delta = next[edge.target]! - next[edge.source]!;
        final distance = delta.distance;
        if (distance < 0.001) continue;
        final force = delta / distance * ((distance - entry.value) * 32);
        forces[edge.source] = forces[edge.source]! + force;
        forces[edge.target] = forces[edge.target]! - force;
      }
      maxForce = 0;
      maxSpeed = 0;
      for (final id in next.keys) {
        final force = forces[id]!;
        final damping = id == _dragged ? 18.0 : 10.0;
        final velocity = ((_velocities[id] ?? Offset.zero) + force * dt) *
            math.exp(-damping * dt);
        _velocities[id] = velocity;
        next[id] = next[id]! + velocity * dt;
        maxForce = math.max(maxForce, force.distance);
        maxSpeed = math.max(maxSpeed, velocity.distance);
      }
    }
    setState(() => _positions = next);
    if (maxSpeed < 0.4 && maxForce < 0.6) {
      _springTicker.stop();
      _velocities.clear();
    }
  }

  void _pointerDown(PointerDownEvent event) {
    if (_dragPointer != null || event.buttons != kPrimaryButton) return;
    _didDrag = false;
    final point = _transform.toScene(event.localPosition);
    final node = _hit(point);
    if (node == null) return;
    setState(() {
      _dragPointer = event.pointer;
      _dragged = _hovered = node.id;
      _anchors[node.id] = _positions[node.id]!;
      _velocities[node.id] = Offset.zero;
      _pointerStart = event.localPosition;
      _grabOffset = point - _positions[node.id]!;
    });
  }

  void _pointerMove(PointerMoveEvent event) {
    if (event.pointer != _dragPointer) return;
    if (!_didDrag && (event.localPosition - _pointerStart).distance < 4) return;
    _didDrag = true;
    final target = _transform.toScene(event.localPosition) - _grabOffset;
    _anchors[_dragged!] = target;
    if (MediaQuery.disableAnimationsOf(context)) {
      _springTicker.stop();
      _velocities.clear();
      setState(() => _positions = {..._positions, _dragged!: target});
    } else {
      _startSprings();
    }
  }

  void _pointerEnd(PointerEvent event) {
    if (event.pointer != _dragPointer) return;
    setState(() {
      _dragPointer = null;
      _dragged = null;
    });
    if (_didDrag && !MediaQuery.disableAnimationsOf(context)) _startSprings();
  }

  void fit() {
    if (_viewport.isEmpty || _positions.isEmpty) return;
    var bounds =
        Rect.fromPoints(_positions.values.first, _positions.values.first);
    for (final point in _positions.values) {
      bounds = bounds.expandToInclude(Rect.fromPoints(point, point));
    }
    bounds = bounds.inflate(100);
    final scale = math
        .min(
          _viewport.width / bounds.width,
          _viewport.height / bounds.height,
        )
        .clamp(0.02, 1.4);
    _transform.value = Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(
        _viewport.width / 2 - bounds.center.dx * scale,
        _viewport.height / 2 - bounds.center.dy * scale,
        0,
      );
  }

  void zoom(double factor) {
    final current = _transform.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(0.02, 5.0);
    final point = _transform.toScene(_viewport.center(Offset.zero));
    _transform.value = Matrix4.diagonal3Values(next, next, 1)
      ..setTranslationRaw(
        _viewport.width / 2 - point.dx * next,
        _viewport.height / 2 - point.dy * next,
        0,
      );
  }

  GraphNode? _hit(Offset point) {
    for (final node in widget.data.nodes.reversed) {
      final position = _positions[node.id];
      if (position == null) continue;
      if ((point - position).distance <= 15 ||
          widget.showLabels &&
              Rect.fromCenter(
                center: position + const Offset(0, 23),
                width: 150,
                height: 20,
              ).contains(point)) {
        return node;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _layoutVersion++;
    _springTicker.dispose();
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textStyle =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size != _viewport) {
          _viewport = size;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) fit();
          });
        }
        return MouseRegion(
          cursor: _dragged != null
              ? SystemMouseCursors.grabbing
              : _hovered == null
                  ? SystemMouseCursors.grab
                  : SystemMouseCursors.click,
          onHover: (event) {
            final id = _hit(_transform.toScene(event.localPosition))?.id;
            if (id != _hovered) setState(() => _hovered = id);
          },
          onExit: (_) {
            if (_hovered != null && _dragged == null) {
              setState(() => _hovered = null);
            }
          },
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _pointerDown,
            onPointerMove: _pointerMove,
            onPointerUp: _pointerEnd,
            onPointerCancel: _pointerEnd,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                if (_didDrag) return;
                final node = _hit(_transform.toScene(details.localPosition));
                if (node != null) widget.onOpen(node);
              },
              child: ClipRect(
                child: InteractiveViewer(
                  transformationController: _transform,
                  panEnabled: _dragged == null,
                  scaleEnabled: _dragged == null,
                  constrained: false,
                  minScale: 0.02,
                  maxScale: 5,
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  child: RepaintBoundary(
                    child: CustomPaint(
                      size: _sceneSize,
                      painter: _GraphPainter(
                        data: widget.data,
                        positions: _positions,
                        nodeColor:
                            Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xFFB8B8B8)
                                : const Color(0xFF626262),
                        textStyle: textStyle,
                        lineColor:
                            Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xFF747474)
                                : const Color(0xFFAAAAAA),
                        highlight: Theme.of(context).colorScheme.primary,
                        hovered: _hovered,
                        labels: widget.showLabels,
                        unnamed: graphText(context, 'untitled'),
                        onOpen: widget.onOpen,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.data,
    required this.positions,
    required this.nodeColor,
    required this.textStyle,
    required this.lineColor,
    required this.highlight,
    required this.hovered,
    required this.labels,
    required this.unnamed,
    required this.onOpen,
  });

  final KnowledgeGraphData data;
  final Map<String, Offset> positions;
  final Color nodeColor;
  final TextStyle textStyle;
  final Color lineColor;
  final Color highlight;
  final String? hovered;
  final bool labels;
  final String unnamed;
  final ValueChanged<GraphNode> onOpen;

  @override
  void paint(Canvas canvas, Size size) {
    final neighbors = {hovered};
    for (final edge in data.edges) {
      if (edge.source == hovered) neighbors.add(edge.target);
      if (edge.target == hovered) neighbors.add(edge.source);
    }
    final line = Paint()..strokeCap = StrokeCap.round;
    for (final edge in data.edges) {
      final a = positions[edge.source];
      final b = positions[edge.target];
      if (a == null || b == null) continue;
      final active = edge.source == hovered || edge.target == hovered;
      line.color = active
          ? highlight
          : hovered != null
              ? lineColor.withValues(alpha: 0.3)
              : lineColor;
      line.strokeWidth = active ? 2.2 : 1.4;
      canvas.drawLine(a, b, line);
    }
    for (final node in data.nodes) {
      final position = positions[node.id];
      if (position == null) continue;
      final active = hovered == node.id;
      final faded = hovered != null && !neighbors.contains(node.id);
      final color = active ? highlight : nodeColor;
      if (active) {
        canvas.drawCircle(
          position,
          15,
          Paint()..color = highlight.withValues(alpha: 0.12),
        );
      }
      canvas.drawCircle(
        position,
        7,
        Paint()..color = color.withValues(alpha: faded ? 0.25 : 1),
      );
      if (labels || active) {
        final painter = TextPainter(
          text: TextSpan(
            text: node.label.isEmpty ? unnamed : node.label,
            style: textStyle.copyWith(
              fontSize: 13,
              color: faded
                  ? textStyle.color?.withValues(alpha: 0.25)
                  : active
                      ? highlight
                      : textStyle.color,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: 150);
        painter.paint(canvas, position + Offset(-painter.width / 2, 15));
        painter.dispose();
      }
    }
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) => [
        for (final node in data.nodes)
          if (positions.containsKey(node.id))
            CustomPainterSemantics(
              rect: Rect.fromCenter(
                center: positions[node.id]!,
                width: 150,
                height: 60,
              ),
              properties: SemanticsProperties(
                label: node.label.isEmpty ? unnamed : node.label,
                button: true,
                textDirection: TextDirection.ltr,
                onTap: () => onOpen(node),
              ),
            ),
      ];

  @override
  bool shouldRepaint(_GraphPainter oldDelegate) => true;

  @override
  bool shouldRebuildSemantics(_GraphPainter oldDelegate) =>
      !identical(data, oldDelegate.data) ||
      !identical(positions, oldDelegate.positions);
}
