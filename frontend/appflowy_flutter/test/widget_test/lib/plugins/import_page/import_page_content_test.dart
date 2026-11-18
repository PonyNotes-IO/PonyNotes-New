import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/plugins/import_page/import_page_widgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EmptyTranslations extends AssetLoader {
  const _EmptyTranslations();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => {};
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    final iconFont =
        FontLoader('packages/font_awesome_flutter/FontAwesomeRegular');
    iconFont.addFont(
      rootBundle.load(
        'packages/font_awesome_flutter/lib/fonts/fa-regular-400.ttf',
      ),
    );
    await iconFont.load();
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (await font.exists()) {
      await (FontLoader('ImportTestFont')
            ..addFont(font.readAsBytes().then(ByteData.sublistView)))
          .load();
    }
  });

  for (final variant in [
    (name: 'reference', size: const Size(820, 662), dark: false, scale: 1.0),
    (name: 'desktop', size: const Size(1360, 900), dark: false, scale: 1.0),
    (name: 'tablet', size: const Size(600, 700), dark: false, scale: 1.0),
    (name: 'phone', size: const Size(390, 844), dark: false, scale: 1.0),
    (name: 'compact', size: const Size(320, 640), dark: false, scale: 1.6),
    (name: 'dark', size: const Size(820, 662), dark: true, scale: 1.0),
  ]) {
    testWidgets('import actions and sync work on ${variant.name}',
        (tester) async {
      tester.view.physicalSize = variant.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final capture = GlobalKey();
      final imports = <String>[];
      var syncOpened = 0;
      final theme = variant.dark ? ThemeData.dark() : ThemeData.light();
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('zh', 'CN')],
          startLocale: const Locale('zh', 'CN'),
          path: 'assets/translations',
          assetLoader: const _EmptyTranslations(),
          saveLocale: false,
          child: Builder(
            builder: (context) => MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: context.locale,
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              theme: theme.copyWith(
                textTheme: theme.textTheme.apply(fontFamily: 'ImportTestFont'),
                colorScheme: theme.colorScheme.copyWith(
                  surface:
                      variant.dark ? const Color(0xFF1E1E1E) : Colors.white,
                  onSurface:
                      variant.dark ? Colors.white : const Color(0xFF37352F),
                ),
              ),
              home: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(variant.scale),
                ),
                child: RepaintBoundary(
                  key: capture,
                  child: ImportPageContent(
                    onFileImport: imports.add,
                    onNotionImport: () => imports.add('notion'),
                    onObsidianImport: () => imports.add('obsidian'),
                    onOpenSync: () => syncOpened++,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      Future<void> screenshot(String state) async {
        final output = Platform.environment['PONYNOTES_IMPORT_SCREENSHOTS'];
        if (output == null) return;
        final previous = debugDisableShadows;
        final boundary = capture.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        try {
          debugDisableShadows = false;
          boundary.markNeedsPaint();
          await tester.pump();
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            await Directory(output).create(recursive: true);
            await File('$output/import-${variant.name}-$state.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        } finally {
          debugDisableShadows = previous;
        }
      }

      await screenshot('files');
      if (variant.name == 'reference') {
        final csv =
            tester.getTopLeft(find.byKey(const ValueKey('import-file-csv')));
        final html =
            tester.getTopLeft(find.byKey(const ValueKey('import-file-html')));
        expect(csv.dy, html.dy);
        // Keyboard users can reach and activate a file card.
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(imports, ['csv']);
        imports.clear();
      }

      for (final type in ['csv', 'pdf', 'markdown', 'html']) {
        final card = find.byKey(ValueKey('import-file-$type'));
        await tester.ensureVisible(card);
        await tester.tap(card);
        await tester.pumpAndSettle();
      }
      for (final service in ['Notion', 'Obsidian']) {
        await tester.ensureVisible(find.text(service));
        await tester.tap(find.text(service));
        await tester.pumpAndSettle();
      }
      expect(imports, ['csv', 'pdf', 'markdown', 'html', 'notion', 'obsidian']);
      await tester.ensureVisible(find.widgetWithText(TextButton, '同步'));
      await tester.tap(find.widgetWithText(TextButton, '同步'));
      await tester.pumpAndSettle();
      expect(find.text('CSV'), findsNothing);
      expect(find.text('同步到知识库'), findsOneWidget);
      await screenshot('sync');
      await tester.tap(find.text('前往知识库'));
      expect(syncOpened, 1);
      await tester.tap(find.widgetWithText(TextButton, '导入'));
      await tester.pumpAndSettle();
      expect(find.text('CSV'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
