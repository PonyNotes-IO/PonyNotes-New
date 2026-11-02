import 'package:appflowy/util/keyboard_inset.dart';
import 'package:flowy_infra/platform_extension.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => PlatformInfo.setIsTablet(false));

  // 复刻 AppWidget 在平板端对 MediaQuery 的处理：viewInsets 被固定为 0。
  Widget buildFrozenMediaQuery(Widget child) {
    return MediaQuery(
      data: const MediaQueryData(),
      child: child,
    );
  }

  testWidgets('no keyboard reported when IME is hidden', (tester) async {
    PlatformInfo.setIsTablet(true);
    double? inset;

    await tester.pumpWidget(
      buildFrozenMediaQuery(
        KeyboardInsetBuilder(
          builder: (context, bottomInset) {
            inset = bottomInset;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(inset, 0);
  });

  testWidgets(
    'tablet reports the real IME inset although MediaQuery is frozen',
    (tester) async {
      PlatformInfo.setIsTablet(true);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      // 400 physical px with a 2.0 dpr -> 200 logical px.
      tester.view.viewInsets = const FakeViewPadding(bottom: 400);

      double? inset;
      await tester.pumpWidget(
        buildFrozenMediaQuery(
          KeyboardInsetBuilder(
            builder: (context, bottomInset) {
              inset = bottomInset;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(inset, 200);
    },
  );

  testWidgets('phone keeps relying on MediaQuery / Scaffold resizing', (
    tester,
  ) async {
    PlatformInfo.setIsTablet(false);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    tester.view.viewInsets = const FakeViewPadding(bottom: 400);

    double? inset;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(viewInsets: EdgeInsets.only(bottom: 200)),
        child: KeyboardInsetBuilder(
          builder: (context, bottomInset) {
            inset = bottomInset;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(inset, 0);
  });
}
