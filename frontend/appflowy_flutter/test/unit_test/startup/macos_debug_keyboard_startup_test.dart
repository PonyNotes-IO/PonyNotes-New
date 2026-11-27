import 'dart:ui';

import 'package:appflowy/startup/tasks/keyboard_state_fix_task.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ignores only an unmatched synthetic Caps Lock release', () {
    final dispatcher = PlatformDispatcher.instance;
    final original = dispatcher.onKeyData!;
    final keyboard = HardwareKeyboard.instance;
    final received = <KeyEvent>[];
    bool record(KeyEvent event) {
      received.add(event);
      return false;
    }

    keyboard.addHandler(record);
    addTearDown(() {
      dispatcher.onKeyData = original;
      keyboard.removeHandler(record);
      keyboard.clearState();
    });

    KeyData capsLock(KeyEventType type) => KeyData(
          timeStamp: Duration.zero,
          type: type,
          physical: PhysicalKeyboardKey.capsLock.usbHidUsage,
          logical: LogicalKeyboardKey.capsLock.keyId,
          character: null,
          synthesized: true,
        );

    final unmatched = capsLock(KeyEventType.up);
    expect(() => original(unmatched), throwsA(isA<AssertionError>()));

    KeyboardStateFixTask.installMacOSDebugKeyDataHandler();
    final handleKeyData = dispatcher.onKeyData!;
    expect(handleKeyData(unmatched), isFalse);
    expect(received, isEmpty);

    handleKeyData(capsLock(KeyEventType.down));
    handleKeyData(unmatched);
    expect(received, [isA<KeyDownEvent>(), isA<KeyUpEvent>()]);
    expect(
      keyboard.isPhysicalKeyPressed(PhysicalKeyboardKey.capsLock),
      isFalse,
    );

    final unrelated = KeyData(
      timeStamp: Duration.zero,
      type: KeyEventType.up,
      physical: PhysicalKeyboardKey.keyA.usbHidUsage,
      logical: LogicalKeyboardKey.keyA.keyId,
      character: null,
      synthesized: true,
    );
    expect(() => handleKeyData(unrelated), throwsA(isA<AssertionError>()));
  });
}
