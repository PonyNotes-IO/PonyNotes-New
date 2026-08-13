import 'package:appflowy/startup/tasks/windows.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('does not activate the hidden Windows startup window', () {
    expect(
      shouldActivateWindowsWindow(isVisible: false, isMinimized: false),
      isFalse,
    );
    expect(
      shouldActivateWindowsWindow(isVisible: true, isMinimized: false),
      isTrue,
    );
    expect(
      shouldActivateWindowsWindow(isVisible: false, isMinimized: true),
      isTrue,
    );
  });
}
