import 'package:appflowy/mobile/presentation/bottom_sheet/bottom_sheet_buttons.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/import/import_panel.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../test_material_app.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('mobile import uses a bottom sheet with four ordered options', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      WidgetTestApp(
        child: AppFlowyTheme(
          data: AppFlowyDefaultTheme().light(),
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showImportPanel(
                'workspace-id',
                context,
                (_, __, ___, ____) {},
                isMobile: true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final closeButton = find.byType(BottomSheetCloseButton);
    final csv = find.byKey(const ValueKey('mobile-import-option-csv'));
    final pdf = find.byKey(const ValueKey('mobile-import-option-pdf'));
    final markdown =
        find.byKey(const ValueKey('mobile-import-option-markdownOrText'));
    final html = find.byKey(const ValueKey('mobile-import-option-html'));

    expect(closeButton, findsOneWidget);
    expect(csv, findsOneWidget);
    expect(pdf, findsOneWidget);
    expect(markdown, findsOneWidget);
    expect(html, findsOneWidget);
    for (final option in [csv, pdf, markdown, html]) {
      final optionText = tester.widget<Text>(
        find.descendant(of: option, matching: find.byType(Text)),
      );
      expect(optionText.style?.color, Colors.black);
    }
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>)
                .value
                .startsWith('mobile-import-option-'),
      ),
      findsNWidgets(4),
    );

    expect(
      tester.getCenter(closeButton).dy,
      lessThan(tester.getCenter(csv).dy),
    );
    expect(tester.getCenter(csv).dy, lessThan(tester.getCenter(pdf).dy));
    expect(tester.getCenter(pdf).dy, lessThan(tester.getCenter(markdown).dy));
    expect(tester.getCenter(markdown).dy, lessThan(tester.getCenter(html).dy));
    expect(tester.getSize(csv).height, 64);
    expect(tester.getBottomRight(html).dy, lessThanOrEqualTo(800));

    await tester.tap(closeButton);
    await tester.pumpAndSettle();
    expect(csv, findsNothing);
  });
}
