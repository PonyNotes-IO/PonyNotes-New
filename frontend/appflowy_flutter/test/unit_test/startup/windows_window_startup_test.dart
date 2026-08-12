import 'dart:async';
import 'dart:ui';

import 'package:appflowy/startup/tasks/windows.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('applies the prepared Windows state only after Flutter rasterizes',
      () async {
    final firstFrame = Completer<void>();
    final events = <String>[];
    final coordinator = WindowsWindowStartupCoordinator(
      isWindows: () => true,
      waitForFirstFrame: () async {
        await firstFrame.future;
        events.add('first-frame');
      },
      applyState: (state) async {
        events.add(
          'state:${state.size.width.toInt()}x${state.size.height.toInt()}',
        );
      },
    )..prepare(
        const WindowsStartupWindowState(size: Size(1280, 720)),
      );

    final applying = coordinator.applyAfterFirstFrame();
    await Future<void>.delayed(Duration.zero);

    expect(events, isEmpty);

    firstFrame.complete();
    await applying;

    expect(events, [
      'first-frame',
      'state:1280x720',
    ]);
  });

  test('applies the prepared Windows state at most once', () async {
    var applications = 0;
    final coordinator = WindowsWindowStartupCoordinator(
      isWindows: () => true,
      waitForFirstFrame: () async {},
      applyState: (_) async => applications++,
    )..prepare(
        const WindowsStartupWindowState(size: Size(1280, 720)),
      );

    await Future.wait([
      coordinator.applyAfterFirstFrame(),
      coordinator.applyAfterFirstFrame(),
    ]);
    await coordinator.applyAfterFirstFrame();

    expect(applications, 1);
  });

  test('clamps a stored Windows size to the safe startup bounds', () {
    expect(
      clampWindowsStartupSize(const Size(1440, 900)),
      const Size(1280, 720),
    );
    expect(
      clampWindowsStartupSize(const Size(1200, 720)),
      const Size(1200, 720),
    );
  });
}
