import 'package:appflowy/plugins/whiteboard/application/whiteboard_sync_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'whiteboard sync gate blocks auto sync until both readiness signals arrive',
      () async {
    final gate = WhiteboardSyncGate();

    gate.hold();

    expect(gate.canAutoSync, isFalse);

    gate.markInitialDataReady();
    expect(gate.canAutoSync, isFalse);

    gate.markWebViewReady();
    expect(gate.canAutoSync, isTrue);
  });

  test(
      'whiteboard sync gate opens by fallback timeout when readiness never arrives',
      () async {
    WhiteboardSyncGateOpenReason? openedReason;
    final gate = WhiteboardSyncGate(
      fallbackTimeout: const Duration(milliseconds: 20),
    );
    gate.onOpened = (reason) => openedReason = reason;

    gate.hold();
    expect(gate.canAutoSync, isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 35));

    expect(gate.canAutoSync, isTrue);
    expect(gate.openReason, WhiteboardSyncGateOpenReason.fallbackTimeout);
    expect(openedReason, WhiteboardSyncGateOpenReason.fallbackTimeout);
  });

  test('whiteboard sync gate reports ready reason when both signals arrive',
      () {
    final gate = WhiteboardSyncGate();

    gate.hold();
    gate.markWebViewReady();
    gate.markInitialDataReady();

    expect(gate.canAutoSync, isTrue);
    expect(gate.openReason, WhiteboardSyncGateOpenReason.ready);
  });
}
