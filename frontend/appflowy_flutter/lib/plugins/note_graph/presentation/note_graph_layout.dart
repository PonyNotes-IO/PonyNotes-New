import 'dart:math' as math;
import 'dart:ui';

class NoteGraphLayoutInput {
  const NoteGraphLayoutInput(this.ids, this.edges);
  final List<String> ids;
  final List<(String, String)> edges;
}

/// Deterministic force layout with a local grid, bounded by the graph's display limit.
Map<String, Offset> layoutNoteGraph(NoteGraphLayoutInput input) {
  final ids = input.ids.toList()..sort();
  final indices = {for (var i = 0; i < ids.length; i++) ids[i]: i};
  final pairs = <(int, int)>{};
  for (final (source, target) in input.edges) {
    final a = indices[source];
    final b = indices[target];
    if (a != null && b != null && a != b) pairs.add(a < b ? (a, b) : (b, a));
  }
  final positions = List.generate(ids.length, (index) {
    final radius = 90 * math.sqrt(index + 1);
    final angle = index * 2.3999632297;
    return Offset(math.cos(angle) * radius, math.sin(angle) * radius);
  });
  for (var step = 0; step < 150; step++) {
    final forces =
        List.generate(ids.length, (index) => -positions[index] * .009);
    final cells = <(int, int), List<int>>{};
    for (var i = 0; i < positions.length; i++) {
      final point = positions[i];
      (cells[((point.dx / 210).floor(), (point.dy / 210).floor())] ??= [])
          .add(i);
    }
    for (var i = 0; i < positions.length; i++) {
      final cellX = (positions[i].dx / 210).floor();
      final cellY = (positions[i].dy / 210).floor();
      for (var x = cellX - 1; x <= cellX + 1; x++) {
        for (var y = cellY - 1; y <= cellY + 1; y++) {
          for (final j in cells[(x, y)] ?? <int>[]) {
            if (j <= i) continue;
            final delta = positions[i] - positions[j];
            final distance = math.max(delta.distance, 1.0);
            if (distance > 210) continue;
            final repulsion =
                delta / distance * (16000 / math.max(100, distance * distance));
            forces[i] += repulsion;
            forces[j] -= repulsion;
          }
        }
      }
    }
    for (final (a, b) in pairs) {
      final delta = positions[b] - positions[a];
      final distance = math.max(delta.distance, 1.0);
      final attraction = delta / distance * (distance - 170) * .035;
      forces[a] += attraction;
      forces[b] -= attraction;
    }
    for (var i = 0; i < positions.length; i++) {
      final force = forces[i];
      positions[i] += force.distance > 9 ? force / force.distance * 9 : force;
    }
  }
  return {for (var i = 0; i < ids.length; i++) ids[i]: positions[i]};
}
