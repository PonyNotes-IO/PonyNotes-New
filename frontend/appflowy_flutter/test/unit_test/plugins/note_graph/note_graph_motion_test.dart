import 'package:appflowy/plugins/note_graph/presentation/note_graph_motion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('entrance springs overshoot gently and stop scheduling frames', () {
    final motion = NoteGraphMotion(
      targets: {'a': const Offset(200, 0)},
      positions: {'a': Offset.zero},
      edges: [],
    );
    var furthest = 0.0;
    var moving = true;
    for (var frame = 0; frame < 600 && moving; frame++) {
      moving = motion.step(1 / 60);
      if (motion.positions['a']!.dx > furthest) {
        furthest = motion.positions['a']!.dx;
      }
    }
    expect(furthest, greaterThan(200));
    expect(furthest, lessThan(235));
    expect(moving, isFalse);
    expect(
      (motion.positions['a']! - const Offset(200, 0)).distance,
      lessThan(.5),
    );
  });

  test(
      'drag attracts linked neighbors without moving distant independent notes',
      () {
    final rest = {
      'a': Offset.zero,
      'b': const Offset(170, 0),
      'c': const Offset(1000, 0),
    };
    final motion = NoteGraphMotion(
      targets: rest,
      positions: rest,
      edges: [('a', 'b'), ('b', 'a')],
    );
    motion.drag('a', const Offset(-100, 0));
    for (var frame = 0; frame < 40; frame++) {
      motion.step(1 / 60);
    }
    expect(motion.positions['a'], const Offset(-100, 0));
    expect(motion.positions['b']!.dx, lessThan(160));
    expect(motion.positions['c'], const Offset(1000, 0));
    motion.release();
    var moving = true;
    for (var frame = 0; frame < 600 && moving; frame++) {
      moving = motion.step(1 / 60);
    }
    expect(moving, isFalse);
    expect(
      motion.positions.values
          .every((point) => point.dx.isFinite && point.dy.isFinite),
      isTrue,
    );
  });

  test('nearby unlinked dots repel and settle without invented graph edges',
      () {
    final rest = {'a': Offset.zero, 'b': const Offset(140, 0)};
    final motion = NoteGraphMotion(targets: rest, positions: rest, edges: []);
    motion.drag('a', const Offset(120, 0));
    for (var frame = 0; frame < 30; frame++) {
      motion.step(1 / 60);
    }
    expect(motion.positions['b']!.dx, greaterThan(150));
    motion.release();
    var moving = true;
    for (var frame = 0; frame < 600 && moving; frame++) {
      moving = motion.step(1 / 60);
    }
    expect(moving, isFalse);
  });

  test('reduced motion snaps to targets with no residual velocity', () {
    final motion = NoteGraphMotion(
      targets: {'a': const Offset(200, 0)},
      positions: {'a': Offset.zero},
      edges: [],
    );
    motion.step(1 / 60);
    motion.snap();
    expect(motion.positions['a'], const Offset(200, 0));
    expect(motion.velocities['a'], Offset.zero);
    expect(motion.step(1 / 60), isFalse);
  });

  test('a resumed frame and coincident nodes remain finite', () {
    final motion = NoteGraphMotion(
      targets: {'a': Offset.zero, 'b': const Offset(150, 0)},
      positions: {'a': Offset.zero, 'b': Offset.zero},
      edges: [('a', 'b')],
    );
    motion.step(40);
    for (var frame = 0; frame < 300; frame++) {
      motion.step(1 / 30);
    }
    expect(
      motion.positions.values
          .every((point) => point.dx.isFinite && point.dy.isFinite),
      isTrue,
    );
    expect(
      (motion.positions['a']! - motion.positions['b']!).distance,
      greaterThan(60),
    );
  });
}
