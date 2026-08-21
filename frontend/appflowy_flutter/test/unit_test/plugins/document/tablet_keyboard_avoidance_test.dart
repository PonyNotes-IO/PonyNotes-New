import 'package:appflowy/plugins/document/presentation/tablet_keyboard_avoidance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tabletKeyboardScrollDelta', () {
    test('does not scroll when the keyboard is hidden', () {
      expect(
        tabletKeyboardScrollDelta(
          selectionBottom: 900,
          viewportHeight: 1000,
          keyboardInset: 0,
        ),
        0,
      );
    });

    test('does not scroll content already above the keyboard safe area', () {
      expect(
        tabletKeyboardScrollDelta(
          selectionBottom: 650,
          viewportHeight: 1000,
          keyboardInset: 300,
        ),
        0,
      );
    });

    test('moves obscured content above the keyboard with clearance', () {
      expect(
        tabletKeyboardScrollDelta(
          selectionBottom: 850,
          viewportHeight: 1000,
          keyboardInset: 300,
        ),
        174,
      );
    });

    test('uses the current viewport height after orientation or window changes',
        () {
      expect(
        tabletKeyboardScrollDelta(
          selectionBottom: 450,
          viewportHeight: 600,
          keyboardInset: 180,
        ),
        54,
      );
    });
  });
}
