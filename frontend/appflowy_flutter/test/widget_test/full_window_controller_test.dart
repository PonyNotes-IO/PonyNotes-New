import 'package:appflowy/workspace/presentation/home/full_window_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => FullWindowController.isFullWindow.value = false);

  tearDown(() => FullWindowController.isFullWindow.value = false);

  test('full-window transitions can reverse without a time-based lockout', () {
    FullWindowController.enter();
    expect(FullWindowController.isFullWindow.value, isTrue);

    FullWindowController.exit();
    expect(FullWindowController.isFullWindow.value, isFalse);

    FullWindowController.enter();
    FullWindowController.toggle();
    expect(FullWindowController.isFullWindow.value, isFalse);
  });
}
