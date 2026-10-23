import 'package:appflowy/plugins/document/presentation/editor_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/font/customize_font_toolbar_item.dart';
import 'package:appflowy/shared/adaptive_display.dart';
import 'package:appflowy/shared/google_fonts_extension.dart';
import 'package:appflowy/util/font_family_extension.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/settings_menu_element.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('Windows default agrees across Material and AppFlowy themes', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final theme = DesktopAppearance().getThemeData(
      AppTheme.fallback,
      Brightness.light,
      defaultFontFamily,
      builtInCodeFontFamily,
    );

    expect(defaultFontFamily.fontFamilyName, 'Microsoft YaHei UI');
    expect(
      theme.textTheme.bodyMedium!.fontFamily,
      defaultFontFamily.fontFamilyName,
    );
    expect(
      theme.textTheme.labelLarge!.fontFamily,
      defaultFontFamily.fontFamilyName,
    );
    final uiStyle = AppFlowyBaseTextStyle.customFontFamily(defaultFontFamily);
    expect(
      uiStyle.body.standard().fontFamily,
      defaultFontFamily.fontFamilyName,
    );
    expect(
      uiStyle.caption.standard().fontFamilyFallback,
      contains('Microsoft YaHei'),
    );
    expect(
      theme.textTheme.bodyMedium!.fontFamilyFallback,
      contains('Microsoft YaHei'),
    );
  });

  test('Explicit Chinese and monospace fonts retain their family and weight',
      () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    for (final family in [
      'SimSun',
      'Microsoft YaHei UI',
      builtInCodeFontFamily,
    ]) {
      final style = getGoogleFontSafely(family, fontWeight: FontWeight.w700);
      expect(style.fontFamily, family);
      expect(style.fontWeight, FontWeight.w700);
      expect(style.fontFamilyFallback, contains('Microsoft YaHei UI'));
    }
  });

  test('Latin fonts retain their family and receive a Chinese fallback', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final style = getGoogleFontSafely('Arial');
    expect(style.fontFamily, 'Arial');
    expect(style.fontFamilyFallback!.first, 'Microsoft YaHei UI');
    expect(style.fontFamilyFallback, contains('Segoe UI Emoji'));
    final uiStyle =
        AppFlowyBaseTextStyle.customFontFamily('Arial').body.standard();
    expect(uiStyle.fontFamily, 'Arial');
    expect(uiStyle.fontFamilyFallback, contains('Microsoft YaHei UI'));
  });

  test('Google fonts keep their original fallback before Windows fallbacks',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final style = getGoogleFontSafely('Poppins');
    expect(style.fontFamily, 'Poppins_regular');
    expect(style.fontFamilyFallback!.first, 'Poppins');
    expect(style.fontFamilyFallback, contains('Microsoft YaHei UI'));
    await GoogleFonts.pendingFonts();
  });

  testWidgets(
    'Selecting the default font keeps the empty persisted setting',
    (tester) async {
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: DesktopAppearance().getThemeData(
            AppTheme.fallback,
            Brightness.light,
            defaultFontFamily,
            builtInCodeFontFamily,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: FontFamilyDropDown(
                currentFontFamily: 'SimSun',
                onFontFamilyChanged: (font) => selected = font,
                child: const Text('Choose font'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Choose font'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey(defaultFontFamily)), findsOneWidget);
      expect(find.byKey(const ValueKey('Microsoft YaHei UI')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey(defaultFontFamily)));
      await tester.pumpAndSettle();
      // The popover mask has a 500ms grace-period timer.
      await tester.pump(const Duration(seconds: 1));
      expect(selected, defaultFontFamily);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'Settings menu preserves navigation and platform-specific font behavior',
    (tester) async {
      SettingsPage? selected;
      var enabled = true;
      Widget menu() => MaterialApp(
            home: Scaffold(
              body: AppFlowyTheme(
                data: AppFlowyDefaultTheme().light(fontFamily: 'SimSun'),
                child: SizedBox(
                  width: 320,
                  child: SettingsMenuElement(
                    page: SettingsPage.workspace,
                    selectedPage: SettingsPage.account,
                    label: '工作区设置',
                    trailingText: '中文说明',
                    isEnabled: enabled,
                    changeSelectedPage: (page) => selected = page,
                  ),
                ),
              ),
            ),
          );
      await tester.pumpWidget(menu());
      final label = tester.widget<Text>(find.text('工作区设置'));
      final isWindows = defaultTargetPlatform == TargetPlatform.windows;
      expect(label.style!.fontFamily, isWindows ? 'SimSun' : 'SimHei');
      expect(label.strutStyle!.fontFamily, label.style!.fontFamily);
      expect(
        label.style!.fontFamilyFallback!.first,
        isWindows ? 'Microsoft YaHei UI' : 'SimHei',
      );
      await tester.tap(find.text('工作区设置'));
      expect(selected, SettingsPage.workspace);
      selected = null;
      enabled = false;
      await tester.pumpWidget(menu());
      await tester.tap(find.text('工作区设置'));
      expect(selected, isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.macOS,
    }),
  );

  test('Other platforms retain their default and explicit font choices', () {
    for (final platform in [
      TargetPlatform.macOS,
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.linux,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(defaultFontFamily.fontFamilyName, defaultFontFamily);
      expect(getGoogleFontSafely(defaultFontFamily).fontFamily, isNull);
      expect(getGoogleFontSafely('SimSun').fontFamily, 'SimSun');
      expect(getGoogleFontSafely('SimSun').fontFamilyFallback, isNull);
      final theme = DesktopAppearance().getThemeData(
        AppTheme.fallback,
        Brightness.light,
        defaultFontFamily,
        builtInCodeFontFamily,
      );
      expect(
        theme.textTheme.labelLarge!.fontFamily,
        ThemeData(useMaterial3: false).textTheme.labelLarge!.fontFamily,
      );
    }
  });

  testWidgets(
    'Window size and DPI do not add a second Windows text scale',
    (tester) async {
      for (final dpr in [1.0, 1.25, 1.5, 2.0]) {
        for (final size in [
          const Size(500, 700),
          const Size(800, 700),
          const Size(1400, 900),
          const Size(1800, 1300),
          const Size(2560, 1600),
        ]) {
          AdaptiveDisplayMetrics? metrics;
          await tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(size: size, devicePixelRatio: dpr),
              child: Builder(
                builder: (context) {
                  metrics = AdaptiveDisplayMetrics.of(context);
                  return const SizedBox();
                },
              ),
            ),
          );

          expect(metrics!.textScale, 1.0, reason: 'size=$size, DPR=$dpr');
        }
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'Editor resolves its default without overriding document fonts',
    (tester) async {
      await tester.pumpWidget(const SizedBox());
      final editor = EditorStyleCustomizer(
        context: tester.element(find.byType(SizedBox)),
        padding: EdgeInsets.zero,
      );
      expect(editor.baseTextStyle('').fontFamily, 'Microsoft YaHei UI');
      expect(editor.baseTextStyle('SimSun').fontFamily, 'SimSun');
      expect(
        editor.baseTextStyle(builtInCodeFontFamily).fontFamily,
        builtInCodeFontFamily,
      );
      expect(editor.baseTextStyle(null).fontFamily, isNull);
      expect(
        editor.baseTextStyle(null).fontFamilyFallback,
        contains('Microsoft YaHei UI'),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'Mobile retains its adaptive text size',
    (tester) async {
      AdaptiveDisplayMetrics? metrics;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(800, 700)),
          child: Builder(
            builder: (context) {
              metrics = AdaptiveDisplayMetrics.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(metrics!.textScale, 1.02);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'Other platforms retain editor font inheritance and default family',
    (tester) async {
      await tester.pumpWidget(const SizedBox());
      final editor = EditorStyleCustomizer(
        context: tester.element(find.byType(SizedBox)),
        padding: EdgeInsets.zero,
      );
      expect(
        editor.baseTextStyle(defaultFontFamily).fontFamily,
        defaultFontFamily,
      );
      expect(editor.baseTextStyle(null).fontFamily, isNull);
      expect(
        editor.baseTextStyle(defaultFontFamily).fontFamilyFallback,
        isNull,
      );
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.linux,
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );
}
