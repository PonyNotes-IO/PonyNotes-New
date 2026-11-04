import 'dart:math' as math;
import 'dart:ui';

/// Damped springs, with link tension and local collision avoidance.
/// Stops at rest instead of continuously spending frames on a static graph.
class NoteGraphMotion {
  NoteGraphMotion({
    required Map<String, Offset> targets,
    required Map<String, Offset> positions,
    required Iterable<(String, String)> edges,
  })  : targets = Map.of(targets),
        positions = {
          for (final entry in targets.entries)
            entry.key: positions[entry.key] ?? entry.value,
        } {
    final pairs = <(String, String)>{};
    for (final (a, b) in edges) {
      if (a == b || !targets.containsKey(a) || !targets.containsKey(b)) {
        continue;
      }
      final key = a.compareTo(b) < 0 ? (a, b) : (b, a);
      if (pairs.add(key)) {
        _links.add((key.$1, key.$2, (targets[a]! - targets[b]!).distance));
      }
    }
    velocities = {for (final id in targets.keys) id: Offset.zero};
  }

  final Map<String, Offset> targets;
  final Map<String, Offset> positions;
  late final Map<String, Offset> velocities;
  final _links = <(String, String, double)>[];
  String? pinned;
  double _quietTime = 0;

  void drag(String id, Offset position) {
    if (!positions.containsKey(id)) return;
    pinned = id;
    positions[id] = position;
    velocities[id] = Offset.zero;
    _quietTime = 0;
  }

  void release() {
    final id = pinned;
    // Keep the dropped node where it was placed; its neighbors settle around it.
    if (id != null) targets[id] = positions[id]!;
    pinned = null;
    _quietTime = 0;
  }

  void snap() {
    positions.addAll(targets);
    for (final id in velocities.keys) {
      velocities[id] = Offset.zero;
    }
    pinned = null;
    _quietTime = 1;
  }

  /// Returns true while another frame is useful. Semi-implicit substeps keep
  /// low-frame-rate devices from amplifying spring forces after a pause.
  bool step(double elapsedSeconds) {
    if (positions.isEmpty) return false;
    final elapsed = elapsedSeconds.clamp(0.0, .05);
    if (elapsed == 0) return true;
    final substeps = (elapsed / (1 / 120)).ceil();
    final dt = elapsed / substeps;
    var maxSpeed = 0.0;
    var maxForce = 0.0;
    for (var iteration = 0; iteration < substeps; iteration++) {
      final forces = {
        for (final id in positions.keys)
          id: (targets[id]! - positions[id]!) * 48 - velocities[id]! * 9.5,
      };
      for (final (a, b, rest) in _links) {
        final delta = positions[b]! - positions[a]!;
        final distance = math.max(delta.distance, .01);
        final tension = delta / distance * ((distance - rest) * 36);
        forces[a] = forces[a]! + tension;
        forces[b] = forces[b]! - tension;
      }
      const radius = 62.0;
      final cells = <(int, int), List<String>>{};
      for (final entry in positions.entries) {
        final cell = (
          (entry.value.dx / radius).floor(),
          (entry.value.dy / radius).floor()
        );
        (cells[cell] ??= []).add(entry.key);
      }
      for (final entry in positions.entries) {
        final id = entry.key;
        final x = (entry.value.dx / radius).floor();
        final y = (entry.value.dy / radius).floor();
        for (var cx = x - 1; cx <= x + 1; cx++) {
          for (var cy = y - 1; cy <= y + 1; cy++) {
            for (final other in cells[(cx, cy)] ?? <String>[]) {
              if (id.compareTo(other) >= 0) continue;
              final delta = entry.value - positions[other]!;
              final distance = delta.distance;
              if (distance >= radius) continue;
              final direction =
                  distance < .01 ? const Offset(1, 0) : delta / distance;
              final repulsion = direction * ((radius - distance) * 55);
              forces[id] = forces[id]! + repulsion;
              forces[other] = forces[other]! - repulsion;
            }
          }
        }
      }
      maxSpeed = 0;
      maxForce = 0;
      for (final id in positions.keys) {
        if (id == pinned) continue;
        final velocity = velocities[id]! + forces[id]! * dt;
        velocities[id] = velocity.distance > 1500
            ? velocity / velocity.distance * 1500
            : velocity;
        positions[id] = positions[id]! + velocities[id]! * dt;
        maxSpeed = math.max(maxSpeed, velocities[id]!.distance);
        maxForce = math.max(maxForce, forces[id]!.distance);
      }
    }
    _quietTime = maxSpeed < .8 && maxForce < 4 ? _quietTime + elapsed : 0;
    return _quietTime < .18;
  }
}
