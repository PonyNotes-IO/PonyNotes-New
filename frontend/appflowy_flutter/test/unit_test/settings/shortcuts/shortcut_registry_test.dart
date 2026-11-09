import 'package:appflowy/plugins/database/application/cell/bloc/text_cell_bloc.dart';
import 'package:appflowy/plugins/database/widgets/cell/desktop_row_detail/desktop_row_detail_text_cell.dart';
import 'package:appflowy/plugins/database/widgets/row/cells/cell_container.dart';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy/workspace/application/settings/shortcuts/settings_shortcuts_cubit.dart';
import 'package:appflowy/workspace/application/settings/shortcuts/settings_shortcuts_service.dart';
import 'package:appflowy/workspace/application/settings/shortcuts/shortcut_registry.dart';
import 'package:appflowy/workspace/application/settings/shortcuts/shortcuts_model.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy/workspace/presentation/home/hotkeys.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:mocktail/mocktail.dart';

class MockApplicationDataStorage extends Mock
    implements ApplicationDataStorage {}

class MockTextCellBloc extends Mock implements TextCellBloc {}

class FailingShortcutService extends SettingsShortcutService {
  FailingShortcutService()
      : super(file: MemoryFileSystem().file('/shortcuts.json')..createSync());

  @override
  Future<void> saveAllShortcuts(dynamic shortcuts) async =>
      throw const FormatException('write failed');
}

void main() {
  late SettingsShortcutService service;
  late ShortcutsCubit cubit;

  setUp(() async {
    final file = MemoryFileSystem().file('/shortcuts.json')..createSync();
    service = SettingsShortcutService(file: file);
    for (final event in allShortcutEvents) {
      final original =
          allDefaultShortcutEvents.firstWhere((e) => e.key == event.key);
      setShortcutCommand(event, original.command);
    }
    isRecordingShortcut = false;
    cubit = ShortcutsCubit(service);
    await cubit.fetchShortcuts();
  });

  tearDown(() async {
    await cubit.close();
    isRecordingShortcut = false;
  });

  test(
      'all registered defaults are valid, uniquely identified and platform parsable',
      () {
    expect(allShortcutEvents.map((e) => e.key).toSet().length,
        allShortcutEvents.length,);
    for (final event in allShortcutEvents) {
      expect(isValidShortcutCommand(event.command), isTrue,
          reason: '${event.key}: ${event.command}',);
      expect(isSupportedShortcutCommand(event, event.command), isTrue,
          reason: event.key,);
      for (final binding in event.keybindings) {
        expect(binding.keyCode, isPositive);
      }
    }
    expect(shortcutFor('app.theme').command, contains('alt+shift+l'));
    expect(shortcutFor('app.settings').keybindings.single.keyCode,
        LogicalKeyboardKey.comma.keyId,);
  });

  test('opening settings preserves editor dispatch priority', () async {
    final order = commandShortcutEvents.map((e) => e.key).toList();
    await cubit.fetchShortcuts();
    expect(commandShortcutEvents.map((e) => e.key), order);
  });

  test(
      'saving an unchanged contextual binding preserves its companion handlers',
      () async {
    final before = allShortcutEvents.map((e) => e.command).toList();
    final backspace = allShortcutEvents.firstWhere((e) => e.key == 'backspace');
    expect(cubit.conflictsFor(backspace, backspace.command), isEmpty);
    expect(await cubit.rebind(backspace, backspace.command), isTrue);
    expect(allShortcutEvents.map((e) => e.command), before);
  });

  test('each edit emits a fresh UI snapshot', () async {
    final before = cubit.state;
    await cubit.rebind(shortcutFor('app.newPage'), 'ctrl+alt+f8');
    final first = cubit.state;
    await cubit.rebind(shortcutFor('app.newPage'), 'ctrl+alt+f9');
    expect(
        before.commandShortcutEvents
            .firstWhere((e) => e.key == 'app.newPage')
            .command,
        'ctrl+n',);
    expect(
        first.commandShortcutEvents
            .firstWhere((e) => e.key == 'app.newPage')
            .command,
        'ctrl+alt+f8',);
    expect(
        cubit.state.commandShortcutEvents
            .firstWhere((e) => e.key == 'app.newPage')
            .command,
        'ctrl+alt+f9',);
  });

  test('custom bindings and cleared commands survive reload and reset live',
      () async {
    final sidebar = shortcutFor('app.sidebar');
    expect(await cubit.rebind(sidebar, 'ctrl+alt+f9'), isTrue);
    final saved = await service.getCustomizeShortcuts();
    expect(
        saved.firstWhere((s) => s.key == sidebar.key).command, 'ctrl+alt+f9',);
    expect(await cubit.rebind(sidebar, ''), isTrue);
    setShortcutCommand(sidebar, 'ctrl+backslash');
    await service.updateCommandShortcuts(
        allShortcutEvents, await service.getCustomizeShortcuts(),);
    expect(sidebar.command, isEmpty);
    expect(sidebar.keybindings, isEmpty);
    await cubit.resetToDefault();
    expect(sidebar.command, contains('backslash'));
    expect(sidebar.keybindings.length, 2);
  });

  test('cross-layer conflicts remove only the matching alternative', () async {
    final current = shortcutFor('app.newPage');
    final sidebar = shortcutFor('app.sidebar');
    expect(cubit.conflictsFor(current, 'ctrl+period'), contains(sidebar));
    expect(await cubit.rebind(current, 'ctrl+period'), isTrue);
    expect(sidebar.command, 'ctrl+backslash');
    expect(current.command, 'ctrl+period');
  });

  test('context-local defaults coexist and modifier aliases conflict', () {
    expect(
        cubit
            .conflictsFor(shortcutFor('board.open'), 'enter')
            .map((e) => e.key),
        isNot(contains('cell.submit')),);
    setShortcutCommand(shortcutFor('app.closeTab'), 'meta+alt+w');
    expect(cubit.conflictsFor(shortcutFor('app.newPage'), 'alt+cmd+w'),
        contains(shortcutFor('app.closeTab')),);
  });

  test('failed save preserves current bindings and conflict owners', () async {
    final failure = ShortcutsCubit(FailingShortcutService());
    expect(await failure.rebind(shortcutFor('app.newPage'), 'ctrl+period'),
        isFalse,);
    expect(shortcutFor('app.newPage').command, 'ctrl+n');
    expect(shortcutFor('app.sidebar').command, contains('ctrl+period'));
    await failure.close();
  });

  test('atomic persistence replaces an existing file on disk', () async {
    final directory = await Directory.systemTemp.createTemp('ponynotes-shortcut-save-');
    try {
      final file = File(directory.path + '/shortcuts.json')..writeAsStringSync('{}');
      final diskService = SettingsShortcutService(file: file);
      await diskService.saveAllShortcuts(allShortcutEvents);
      expect((await diskService.getCustomizeShortcuts()).length, allShortcutEvents.length);
      expect(File(file.path + '.tmp').existsSync(), isFalse);
    } finally { await directory.delete(recursive: true); }
  });

  test('empty, damaged and structurally invalid files fall back to defaults',
      () async {
    for (final content in [
      '',
      '{broken',
      '{}',
      '[]',
      '{"commandShortcuts": null}',
      '{"commandShortcuts":[{"key":3}]}',
    ]) {
      final file = MemoryFileSystem().file('/shortcuts.json')
        ..writeAsStringSync(content);
      expect(await SettingsShortcutService(file: file).getCustomizeShortcuts(),
          isEmpty,
          reason: content,);
    }
    expect(
        service.getShortcutsFromJson(jsonEncode({
          'commandShortcuts': [
            {'key': 'app.newPage', 'command': 'ctrl+not a key'},
            {'key': 'app.sidebar', 'command': ''},
          ],
        }),),
        const [CommandShortcutModel(key: 'app.sidebar', command: '')],);
    expect(isValidShortcutCommand('ctrl+'), isFalse);
    expect(isValidShortcutCommand('shift+control left'), isFalse);
  });

  testWidgets(
      'focused component reacts to live remapping without rebuilding, old binding stops',
      (tester) async {
    var invoked = 0;
    await tester.pumpWidget(MaterialApp(
        home: CallbackShortcuts(
      bindings: {const ConfiguredActivator('board.open'): () => invoked++},
      child: const Focus(autofocus: true, child: SizedBox()),
    ),),);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(invoked, 1);
    expect(
        await tester
            .runAsync(() => cubit.rebind(shortcutFor('board.open'), 'f8')),
        isTrue,);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(invoked, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.f8);
    expect(invoked, 2);
    isRecordingShortcut = true;
    await tester.sendKeyEvent(LogicalKeyboardKey.f8);
    expect(invoked, 2);
  });

  testWidgets(
      'dialog dismiss binding is live and previous Escape stops dismissing',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      builder: (_, child) => ConfiguredDialogShortcuts(child: child!),
      home: Builder(
          builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) =>
                        const AlertDialog(content: Text('test dialog')),
                  ),
              child: const Text('open'),),),
    ),);
    expect(
        await tester
            .runAsync(() => cubit.rebind(shortcutFor('dialog.close'), 'f8')),
        isTrue,);
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('test dialog'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.f8);
    await tester.pumpAndSettle();
    expect(find.text('test dialog'), findsNothing);
  });

  testWidgets('shortcut hints update after each edit and hide cleared bindings', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ShortcutConfiguration(child: Builder(builder: (context) => Text(shortcutLabel(context, 'app.newPage'))))));
    expect(find.text('Ctrl + N'), findsOneWidget);
    await tester.runAsync(() => cubit.rebind(shortcutFor('app.newPage'), 'ctrl+alt+f9'));
    await tester.pump();
    expect(find.text('Ctrl + Alt + F9'), findsOneWidget);
    await tester.runAsync(() => cubit.rebind(shortcutFor('app.newPage'), ''));
    await tester.pump();
    expect(find.text('Ctrl + Alt + F9'), findsNothing);
    expect(displayShortcut('ctrl+comma'), 'Ctrl + ,');
  });

  testWidgets('text cells use remapped bindings and preserve IME composition', (tester) async {
    final controller = TextEditingController(text: 'abc');
    final focus = FocusNode();
    final notifier = CellContainerNotifier();
    final compact = ValueNotifier(false);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
      DesktopRowDetailTextCellSkin().build(context, notifier, compact, MockTextCellBloc(), focus, controller),
    ))));
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    expect(await tester.runAsync(() => cubit.rebind(shortcutFor('cell.cancel'), 'f8')), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(focus.hasFocus, isTrue);
    controller.value = const TextEditingValue(text: 'abc', selection: TextSelection.collapsed(offset: 3), composing: TextRange(start: 0, end: 3));
    await tester.sendKeyEvent(LogicalKeyboardKey.f8);
    expect(focus.hasFocus, isTrue);
    controller.clearComposing();
    await tester.sendKeyEvent(LogicalKeyboardKey.f8);
    await tester.pump();
    expect(focus.hasFocus, isFalse);
    await tester.pumpWidget(const SizedBox());
    controller.dispose(); focus.dispose(); notifier.dispose(); compact.dispose();
  });

  testWidgets(
      'application hotkeys register, remap, pause while recording and unregister',
      (tester) async {
    final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('ponynotes-shortcut-test-'),))!;
    final storage = MockApplicationDataStorage();
    when(() => storage.getPath()).thenAnswer((_) async => directory.path);
    getIt.registerSingleton<ApplicationDataStorage>(storage);
    addTearDown(() async {
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox());
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await getIt.unregister<ApplicationDataStorage>();
      await directory.delete(recursive: true);
    });
    final previousCount = hotKeyManager.registeredHotKeyList.length;
    final previousPages = createNewPageNotifier.value;
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
          home: HomeHotKeys(
        userProfile: UserProfilePB(),
        child: const Focus(autofocus: true, child: SizedBox()),
      ),),);
      for (var attempt = 0; attempt < 100 && hotKeyManager.registeredHotKeyList.length == previousCount; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(
        hotKeyManager.registeredHotKeyList.length, greaterThan(previousCount),);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft,
        platform: 'windows',);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN, platform: 'windows');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft,
        platform: 'windows',);
    expect(createNewPageNotifier.value, previousPages + 1);
    await tester.runAsync(() async {
      await cubit.rebind(shortcutFor('app.newPage'), 'ctrl+alt+f9');
      await Future<void>.delayed(Duration.zero);
    });
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft,
        platform: 'windows',);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN, platform: 'windows');
    expect(createNewPageNotifier.value, previousPages + 1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft,
        platform: 'windows',);
    await tester.sendKeyEvent(LogicalKeyboardKey.f9, platform: 'windows');
    expect(createNewPageNotifier.value, previousPages + 2);
    isRecordingShortcut = true;
    await tester.sendKeyEvent(LogicalKeyboardKey.f9, platform: 'windows');
    expect(createNewPageNotifier.value, previousPages + 2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft,
        platform: 'windows',);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft,
        platform: 'windows',);
    await tester.runAsync(() async {
      await tester.pumpWidget(const SizedBox());
      await Future<void>.delayed(Duration.zero);
    });
    expect(hotKeyManager.registeredHotKeyList.length, previousCount);
  });
}
