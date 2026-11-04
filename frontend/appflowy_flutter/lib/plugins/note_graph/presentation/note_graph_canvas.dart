import 'dart:math' as math;

import 'package:appflowy/plugins/note_graph/application/note_graph_data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'note_graph_layout.dart';
import 'note_graph_motion.dart';

class NoteGraphCanvas extends StatefulWidget {
  const NoteGraphCanvas({
    super.key,
    required this.data,
    required this.onSelectNote,
    required this.onOpenNote,
    required this.onSelectEdge,
    this.selectedNote,
    this.selectedEdge,
    this.focusNote,
    this.labels = true,
    this.untitled = 'Untitled',
    this.externalNotes = const {},
  });
  final NoteGraphData data;
  final Set<String> externalNotes;
  final ValueChanged<String> onSelectNote;
  final ValueChanged<String> onOpenNote;
  final ValueChanged<NoteGraphEdge> onSelectEdge;
  final String? selectedNote;
  final (String, String)? selectedEdge;
  final String? focusNote;
  final bool labels;
  final String untitled;
  @override
  State<NoteGraphCanvas> createState() => NoteGraphCanvasState();
}

class NoteGraphCanvasState extends State<NoteGraphCanvas>
    with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  Map<String, Offset> _positions = {};
  NoteGraphMotion? _motion;
  late final Ticker _ticker;
  Duration? _lastFrame;
  bool _reduceMotion = false;
  int? _pointer;
  String? _pressed;
  String? _dragged;
  Offset? _pressLocation;
  Offset _dragOffset = Offset.zero;
  bool _suppressTap = false;
  Size _viewport = Size.zero;
  int _generation = 0;
  String? _hovered;
  Offset? _lastTap;
  bool _loading = false;
  static const _sceneCenter = Offset(2400, 2400);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    _layout();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce && !_reduceMotion && _motion != null) {
      _ticker.stop();
      _motion!.snap();
      _positions = Map.of(_motion!.positions);
    }
    _reduceMotion = reduce;
  }

  void _tick(Duration elapsed) {
    final motion = _motion;
    if (motion == null) {
      _ticker.stop();
      return;
    }
    final delta = _lastFrame == null
        ? 1 / 60
        : (elapsed - _lastFrame!).inMicroseconds /
            Duration.microsecondsPerSecond;
    _lastFrame = elapsed;
    final moving = motion.step(delta);
    setState(() => _positions = Map.of(motion.positions));
    if (!moving) {
      _ticker.stop();
      _lastFrame = null;
    }
  }

  void _animate() {
    if (_reduceMotion) return;
    if (!_ticker.isActive) {
      _lastFrame = null;
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(NoteGraphCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.data, widget.data)) _layout();
  }

  Future<void> _layout() async {
    final generation = ++_generation;
    final firstLayout = _positions.isEmpty;
    if (firstLayout) setState(() => _loading = true);
    final positions = await compute(
      layoutNoteGraph,
      NoteGraphLayoutInput(
        widget.data.notes.keys.toList(),
        widget.data.edges.map((edge) => edge.key).toList(),
      ),
    );
    if (!mounted || generation != _generation) return;
    _ticker.stop();
    _pointer = null;
    _pressed = _dragged = null;
    final targets = {
      for (final entry in positions.entries)
        entry.key: entry.value + _sceneCenter,
    };
    final origin = _positions.isEmpty
        ? _sceneCenter
        : _positions.values.reduce((a, b) => a + b) /
            _positions.length.toDouble();
    _motion = NoteGraphMotion(
      targets: targets,
      positions: {
        for (final entry in targets.entries)
          entry.key: _positions[entry.key] ??
              origin + (entry.value - _sceneCenter) * .55,
      },
      edges: widget.data.edges.map((edge) => edge.key),
    );
    if (_reduceMotion) _motion!.snap();
    setState(() {
      _positions = Map.of(_motion!.positions);
      _loading = false;
    });
    if (firstLayout) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) fit();
      });
    }
    _animate();
  }

  void fit() {
    final points = _motion?.targets.values ?? _positions.values;
    if (points.isEmpty || _viewport.isEmpty) return;
    final left = points.map((point) => point.dx).reduce(math.min) - 95;
    final top = points.map((point) => point.dy).reduce(math.min) - 65;
    final right = points.map((point) => point.dx).reduce(math.max) + 95;
    final bottom = points.map((point) => point.dy).reduce(math.max) + 65;
    final scale = math
        .min(
          _viewport.width / (right - left),
          _viewport.height / (bottom - top),
        )
        .clamp(.15, 1.6);
    _transform.value = Matrix4.identity()
      ..translateByDouble(_viewport.width / 2, _viewport.height / 2, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1)
      ..translateByDouble(-(left + right) / 2, -(top + bottom) / 2, 0, 1);
  }

  void zoom(double factor) {
    final center = _transform.toScene(_viewport.center(Offset.zero));
    final scale =
        (_transform.value.getMaxScaleOnAxis() * factor).clamp(.1, 3.0);
    _transform.value = Matrix4.identity()
      ..translateByDouble(_viewport.width / 2, _viewport.height / 2, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1);
  }

  String? _hitNote(Offset point) {
    for (final entry in _positions.entries) {
      if ((point - entry.value).distance < 24) return entry.key;
    }
    return null;
  }

  NoteGraphEdge? _hitEdge(Offset point) {
    NoteGraphEdge? closest;
    var distance = 11 / _transform.value.getMaxScaleOnAxis();
    final keys = widget.data.edges.map((edge) => edge.key).toSet();
    for (final edge in widget.data.edges) {
      var start = _positions[edge.source];
      var end = _positions[edge.target];
      if (start == null || end == null) continue;
      final delta = end - start;
      if (delta.distanceSquared < 1) continue;
      if (keys.contains((edge.target, edge.source))) {
        final normal = Offset(-delta.dy, delta.dx) / delta.distance * 5;
        start += normal;
        end += normal;
      }
      final t =
          (((point - start).dx * delta.dx + (point - start).dy * delta.dy) /
                  delta.distanceSquared)
              .clamp(0.0, 1.0);
      final value = (point - start - delta * t).distance;
      if (value < distance) {
        closest = edge;
        distance = value;
      }
    }
    return closest;
  }

  void _pointerDown(PointerDownEvent event) {
    if (_pointer != null) {
      _releasePointer();
      return;
    }
    final id = _hitNote(_transform.toScene(event.localPosition));
    _suppressTap = false;
    if (id == null || event.buttons != kPrimaryButton) return;
    setState(() {
      _pointer = event.pointer;
      _pressed = id;
      _pressLocation = event.localPosition;
      _dragOffset = _positions[id]! - _transform.toScene(event.localPosition);
    });
  }

  void _pointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer || _pressed == null || _motion == null) {
      return;
    }
    if (_dragged == null &&
        (event.localPosition - _pressLocation!).distance < 6) {
      return;
    }
    final point = _transform.toScene(event.localPosition) + _dragOffset;
    final constrained =
        Offset(point.dx.clamp(30, 4770), point.dy.clamp(30, 4770));
    setState(() {
      _dragged = _pressed;
      _suppressTap = true;
      _motion!.drag(_dragged!, constrained);
      _positions = Map.of(_motion!.positions);
    });
    _animate();
  }

  void _releasePointer() {
    if (_pointer == null) return;
    if (_dragged != null) {
      _motion?.release();
      _animate();
    }
    setState(() {
      _pointer = null;
      _pressed = _dragged = null;
    });
  }

  @override
  void dispose() {
    _generation++;
    _ticker.dispose();
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final viewport = constraints.biggest;
          if (_viewport != viewport) {
            _viewport = viewport;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) fit();
            });
          }
          if (_loading) return const Center(child: CircularProgressIndicator());
          final theme = Theme.of(context);
          return Stack(
            children: [
              MouseRegion(
                cursor: _dragged != null
                    ? SystemMouseCursors.grabbing
                    : _hovered == null
                        ? SystemMouseCursors.grab
                        : SystemMouseCursors.click,
                onHover: (event) {
                  final note =
                      _hitNote(_transform.toScene(event.localPosition));
                  if (_hovered != note) setState(() => _hovered = note);
                },
                onExit: (_) => setState(() => _hovered = null),
                child: Listener(
                  onPointerDown: _pointerDown,
                  onPointerMove: _pointerMove,
                  onPointerUp: (event) {
                    if (event.pointer == _pointer) _releasePointer();
                  },
                  onPointerCancel: (event) {
                    if (event.pointer == _pointer) _releasePointer();
                  },
                  child: GestureDetector(
                    onTapUp: (event) {
                      if (_suppressTap) return;
                      _lastTap = event.localPosition;
                      final point = _transform.toScene(event.localPosition);
                      final id = _hitNote(point);
                      if (id != null) {
                        widget.onSelectNote(id);
                        return;
                      }
                      final edge = _hitEdge(point);
                      if (edge != null) widget.onSelectEdge(edge);
                    },
                    onDoubleTapDown: (event) => _lastTap = event.localPosition,
                    onDoubleTap: () {
                      if (_suppressTap) return;
                      final point = _lastTap;
                      if (point == null) return;
                      final id = _hitNote(_transform.toScene(point));
                      if (id != null) widget.onOpenNote(id);
                    },
                    child: InteractiveViewer(
                      transformationController: _transform,
                      panEnabled: _pressed == null,
                      constrained: false,
                      boundaryMargin: const EdgeInsets.all(4000),
                      minScale: .1,
                      maxScale: 3,
                      child: CustomPaint(
                        size: const Size(4800, 4800),
                        painter: _NoteGraphPainter(
                          data: widget.data,
                          externalNotes: widget.externalNotes,
                          positions: _positions,
                          selected: widget.selectedNote,
                          selectedEdge: widget.selectedEdge,
                          focus: widget.focusNote,
                          hovered: _hovered,
                          labels: widget.labels,
                          color: theme.colorScheme.primary,
                          ink: theme.colorScheme.onSurface,
                          textStyle:
                              theme.textTheme.bodySmall ?? const TextStyle(),
                          background: theme.scaffoldBackgroundColor,
                          untitled: widget.untitled,
                          onSelectNote: widget.onSelectNote,
                          onSelectEdge: widget.onSelectEdge,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_hovered != null)
                PositionedDirectional(
                  start: 16,
                  bottom: 16,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(
                        widget.data.notes[_hovered]?.name ?? widget.untitled,
                      ),
                    ),
                  ),
                ),
              // Keyboard-accessible alternatives also expose the graph to screen readers.
              PositionedDirectional(
                end: 12,
                bottom: 12,
                child: SizedBox(
                  width: 40,
                  child: PopupMenuButton<String>(
                    tooltip:
                        Localizations.localeOf(context).languageCode == 'zh'
                            ? '选择笔记'
                            : 'Select a note',
                    icon: const Icon(Icons.list_alt_outlined),
                    onSelected: widget.onSelectNote,
                    itemBuilder: (_) => [
                      for (final note in widget.data.notes.values)
                        PopupMenuItem(
                          value: note.id,
                          child: Text(
                            note.name.isEmpty ? widget.untitled : note.name,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );
}

class _NoteGraphPainter extends CustomPainter {
  _NoteGraphPainter({
    required this.data,
    required this.externalNotes,
    required this.positions,
    required this.color,
    required this.ink,
    required this.textStyle,
    required this.background,
    required this.untitled,
    required this.labels,
    required this.onSelectNote,
    required this.onSelectEdge,
    this.selected,
    this.selectedEdge,
    this.focus,
    this.hovered,
  });
  final NoteGraphData data;
  final Set<String> externalNotes;
  final ValueChanged<String> onSelectNote;
  final ValueChanged<NoteGraphEdge> onSelectEdge;
  final Map<String, Offset> positions;
  final Color color;
  final Color ink;
  final TextStyle textStyle;
  final Color background;
  final String untitled;
  final bool labels;
  final String? selected;
  final (String, String)? selectedEdge;
  final String? focus;
  final String? hovered;

  @override
  void paint(Canvas canvas, Size size) {
    final active = hovered ?? selected;
    final neighbors = {if (active != null) active};
    for (final edge in data.edges) {
      if (edge.source == active) neighbors.add(edge.target);
      if (edge.target == active) neighbors.add(edge.source);
    }
    final reciprocal = data.edges.map((edge) => edge.key).toSet();
    final degrees = <String, int>{};
    for (final edge in data.edges) {
      degrees.update(edge.source, (value) => value + 1, ifAbsent: () => 1);
      degrees.update(edge.target, (value) => value + 1, ifAbsent: () => 1);
      var a = positions[edge.source];
      var b = positions[edge.target];
      if (a == null || b == null || (b - a).distance < 1) continue;
      final delta = b - a;
      final direction = delta / delta.distance;
      final normal = Offset(-direction.dy, direction.dx);
      if (reciprocal.contains((edge.target, edge.source))) {
        a += normal * 5;
        b += normal * 5;
      }
      final highlighted = selectedEdge == edge.key ||
          edge.source == active ||
          edge.target == active;
      final paint = Paint()
        ..color = highlighted
            ? color
            : ink.withValues(alpha: active == null ? .22 : .07)
        ..strokeWidth = highlighted ? 2.5 : 1.2;
      final start = a + direction * 18;
      final end = b - direction * 22;
      canvas.drawLine(start, end, paint);
      canvas.drawPath(
        Path()
          ..moveTo(end.dx, end.dy)
          ..lineTo(
            (end - direction * 9 + normal * 4).dx,
            (end - direction * 9 + normal * 4).dy,
          )
          ..lineTo(
            (end - direction * 9 - normal * 4).dx,
            (end - direction * 9 - normal * 4).dy,
          )
          ..close(),
        paint,
      );
    }
    for (final note in data.notes.values) {
      final point = positions[note.id];
      if (point == null) continue;
      final faded = active != null && !neighbors.contains(note.id);
      final radius = (10 + math.sqrt((degrees[note.id] ?? 0).toDouble()) * 2)
          .clamp(10.0, 19.0);
      final selectedNode = note.id == selected || note.id == focus;
      if (selectedNode) {
        canvas.drawCircle(
          point,
          radius + 6,
          Paint()..color = color.withValues(alpha: .15),
        );
      }
      canvas.drawCircle(
        point,
        radius,
        Paint()
          ..color = (degrees[note.id] ?? 0) == 0
              ? ink.withValues(alpha: faded ? .16 : .45)
              : color.withValues(alpha: faded ? .2 : 1)
          ..style = externalNotes.contains(note.id)
              ? PaintingStyle.stroke
              : PaintingStyle.fill
          ..strokeWidth = 2,
      );
      if (!externalNotes.contains(note.id)) {
        canvas.drawCircle(
          point,
          radius,
          Paint()
            ..color = background
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      if (labels || selectedNode || note.id == hovered) {
        final text = TextPainter(
          text: TextSpan(
            text:
                '${externalNotes.contains(note.id) ? '↗ ' : ''}${note.name.isEmpty ? untitled : note.name}',
            style: textStyle.copyWith(
              color: ink.withValues(alpha: faded ? .25 : 1),
              fontSize: 12,
              fontWeight: selectedNode ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 2,
          ellipsis: '…',
        )..layout(maxWidth: 130);
        text.paint(canvas, point + Offset(-text.width / 2, radius + 8));
        text.dispose();
      }
    }
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder => (_) => [
        for (final note in data.notes.values)
          if (positions[note.id] != null)
            CustomPainterSemantics(
              key: ValueKey('note-graph-node-${note.id}'),
              rect: Rect.fromCircle(center: positions[note.id]!, radius: 24),
              properties: SemanticsProperties(
                label: note.name.isEmpty ? untitled : note.name,
                textDirection: TextDirection.ltr,
                button: true,
                onTap: () => onSelectNote(note.id),
              ),
            ),
        for (final edge in data.edges)
          if (positions[edge.source] != null && positions[edge.target] != null)
            CustomPainterSemantics(
              key: ValueKey('note-graph-edge-${edge.source}-${edge.target}'),
              rect: Rect.fromCenter(
                center: (positions[edge.source]! + positions[edge.target]!) / 2,
                width: 24,
                height: 24,
              ),
              properties: SemanticsProperties(
                label:
                    '${data.notes[edge.source]!.name} → ${data.notes[edge.target]!.name}',
                textDirection: TextDirection.ltr,
                button: true,
                onTap: () => onSelectEdge(edge),
              ),
            ),
      ];

  @override
  bool shouldRepaint(_NoteGraphPainter oldDelegate) => true;
}
