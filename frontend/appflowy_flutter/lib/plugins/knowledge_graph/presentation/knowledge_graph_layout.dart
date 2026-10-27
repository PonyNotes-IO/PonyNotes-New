import 'dart:math' as math;
import 'dart:ui';

/// Simple values allow the layout to run in an isolate, away from the UI thread.
class GraphLayoutInput {
  const GraphLayoutInput(this.ids, this.links);
  final List<String> ids;
  final List<(String, String)> links;
}

Map<String, Offset> layoutKnowledgeGraph(GraphLayoutInput input) {
  final count = input.ids.length;
  if (count == 0) return {};
  final indices = {for (var i = 0; i < count; i++) input.ids[i]: i};
  final links = input.links
      .where(
        (link) => indices.containsKey(link.$1) && indices.containsKey(link.$2),
      )
      .map((link) => (indices[link.$1]!, indices[link.$2]!))
      .toList();
  final positions = List.generate(count, (i) {
    final angle = i * 2.399963229728653;
    final radius = 65 * math.sqrt(i + 1);
    return Offset(math.cos(angle) * radius, math.sin(angle) * radius);
  });
  // A spatial grid bounds repulsion work for larger workspaces.
  const cellSize = 180.0;
  for (var iteration = 0; iteration < 160; iteration++) {
    final cells = <(int, int), List<int>>{};
    for (var i = 0; i < count; i++) {
      final cell = (
        (positions[i].dx / cellSize).floor(),
        (positions[i].dy / cellSize).floor()
      );
      (cells[cell] ??= []).add(i);
    }
    final forces = List.generate(count, (i) => -positions[i] * 0.012);
    for (var i = 0; i < count; i++) {
      final cx = (positions[i].dx / cellSize).floor();
      final cy = (positions[i].dy / cellSize).floor();
      for (var x = cx - 1; x <= cx + 1; x++) {
        for (var y = cy - 1; y <= cy + 1; y++) {
          for (final j in cells[(x, y)] ?? const <int>[]) {
            if (j <= i) continue;
            final delta = positions[i] - positions[j];
            final distance = math.max(1.0, delta.distance);
            final force = delta / distance * (14000 / (distance * distance));
            forces[i] += force;
            forces[j] -= force;
          }
        }
      }
    }
    for (final (a, b) in links) {
      final delta = positions[b] - positions[a];
      final distance = math.max(1.0, delta.distance);
      final force = delta / distance * ((distance - 120) * 0.035);
      forces[a] += force;
      forces[b] -= force;
    }
    final maxStep = 12 * (1 - iteration / 180);
    for (var i = 0; i < count; i++) {
      final length = forces[i].distance;
      positions[i] +=
          length > maxStep ? forces[i] / length * maxStep : forces[i];
    }
  }
  var minX = positions.first.dx;
  var minY = positions.first.dy;
  for (final position in positions) {
    minX = math.min(minX, position.dx);
    minY = math.min(minY, position.dy);
  }
  return {
    for (var i = 0; i < count; i++)
      input.ids[i]: positions[i] - Offset(minX, minY) + const Offset(180, 120),
  };
}
