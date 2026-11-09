import 'dart:convert';
import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/workspace/application/settings/shortcuts/settings_shortcuts_cubit.dart';
import 'package:appflowy/workspace/application/settings/shortcuts/settings_shortcuts_service.dart';
import 'package:appflowy/workspace/application/settings/shortcuts/shortcut_registry.dart';
import 'package:appflowy/workspace/presentation/settings/pages/settings_shortcuts_view.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    Localization.load(const Locale('zh', 'CN'),
        translations: Translations(jsonDecode(
            await File('assets/translations/zh-CN.json').readAsString(),),),);
    final systemFont = File('C:/Windows/Fonts/msyh.ttc');
    await (FontLoader('ShortcutTestFont')
          ..addFont(await systemFont.exists()
              ? systemFont.readAsBytes().then(ByteData.sublistView)
              : rootBundle.load('assets/fonts/chinese.ttf'),))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  late SettingsShortcutService service;
  setUp(() {
    service = SettingsShortcutService(
        file: MemoryFileSystem().file('/shortcuts.json')..createSync(),);
    for (final event in allShortcutEvents) {
      setShortcutCommand(
          event,
          allDefaultShortcutEvents
              .firstWhere((e) => e.key == event.key)
              .command,);
    }
    isRecordingShortcut = false;
  });

  Future<void> pumpPage(WidgetTester tester,
      {bool dark = false, double width = 840,}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await tester.pumpWidget(AppFlowyTheme(
        data: dark
            ? AppFlowyDefaultTheme().dark(fontFamily: 'ShortcutTestFont')
            : AppFlowyDefaultTheme().light(fontFamily: 'ShortcutTestFont'),
        child: RepaintBoundary(
            key: const ValueKey('shortcuts-preview'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                  brightness: dark ? Brightness.dark : Brightness.light,
                  fontFamily: 'ShortcutTestFont',),
              home: Scaffold(body: SettingsShortcutsView(service: service)),
            ),),
      ),);
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('SHORTCUT_SCREENSHOTS')) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('shortcuts-preview')),);
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory('build/shortcut-previews')
        ..createSync(recursive: true);
      await File('${directory.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
      'settings list searches all scopes and fits light/dark narrow windows',
      (tester) async {
    await pumpPage(tester);
    expect(find.text('一键恢复默认'), findsOneWidget);
    expect(find.text('应用'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, 'settings-light');
    await tester.enterText(find.byType(TextField).first, 'Ctrl');
    await tester.pumpAndSettle();
    expect(find.byType(ShortcutSettingTile), findsWidgets);
    await tester.enterText(find.byType(TextField).first, '不存在的功能');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的快捷键'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await pumpPage(tester, dark: true, width: 420);
    expect(tester.takeException(), isNull);
    await capture(tester, 'settings-dark-narrow');
  });

  testWidgets(
      'recorder captures Enter and Escape, cancels safely, and saves with keyboard',
      (tester) async {
    await pumpPage(tester);
    await tester.enterText(find.byType(TextField).first, '新建页面');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    expect(isRecordingShortcut, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Esc'), findsOneWidget);
    expect(find.byType(ShortcutRecorderDialog), findsOneWidget);
    await capture(tester, 'recorder-conflict');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(shortcutFor('app.newPage').command, 'ctrl+n');
    expect(isRecordingShortcut, isFalse);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(ShortcutRecorderDialog), findsOneWidget);
    await tester.tap(find.byWidgetPredicate((widget) =>
        widget is Semantics && widget.properties.label == '快捷键录制区',),);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(shortcutFor('app.newPage').command, 'ctrl+alt+f9');
    expect(find.byType(ShortcutRecorderDialog), findsNothing);
    expect(isRecordingShortcut, isFalse);
    expect(tester.takeException(), isNull);
  });
}
