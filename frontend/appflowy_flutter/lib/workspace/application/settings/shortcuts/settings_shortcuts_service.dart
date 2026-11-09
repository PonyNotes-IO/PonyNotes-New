import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

import 'shortcuts_model.dart';
import 'shortcut_registry.dart';

class SettingsShortcutService {
  /// If file is non null then the SettingsShortcutService uses that
  /// file to store all the shortcuts, otherwise uses the default
  /// Document Directory.
  /// Typically we only intend to pass a file during testing.
  SettingsShortcutService({
    File? file,
  }) {
    _initializeService(file);
  }

  late final File _file;
  final _initCompleter = Completer<void>();

  /// Takes in commandShortcuts as an input and saves them to the shortcuts.JSON file.
  Future<void> saveAllShortcuts(
    List<CommandShortcutEvent> commandShortcuts,
  ) async {
    await _initCompleter.future;
    final shortcuts = EditorShortcuts(
      commandShortcuts: commandShortcuts.toCommandShortcutModelList(),
    );

    final pending = await _file.copy('${_file.path}.tmp');
    await pending.writeAsString(jsonEncode(shortcuts.toJson()), flush: true);
    await pending.rename(_file.path);
  }

  /// Checks the file for saved shortcuts. If shortcuts do NOT exist then returns
  /// an empty list. If shortcuts exist
  /// then calls an utility method i.e getShortcutsFromJson which returns the saved shortcuts.
  Future<List<CommandShortcutModel>> getCustomizeShortcuts() async {
    await _initCompleter.future;
    final shortcutsInJson = await _file.readAsString();

    if (shortcutsInJson.isEmpty) {
      return [];
    } else {
      try {
        return getShortcutsFromJson(shortcutsInJson);
      } on FormatException {
        return [];
      } on TypeError {
        return [];
      }
    }
  }

  // Extracts shortcuts from the saved json file. The shortcuts in the saved file consist of [List<CommandShortcutModel>].
  // This list needs to be converted to List<CommandShortcutEvent\>. This function is intended to facilitate the same.
  List<CommandShortcutModel> getShortcutsFromJson(String savedJson) {
    final shortcuts = EditorShortcuts.fromJson(jsonDecode(savedJson));
    return shortcuts.commandShortcuts
        .where((s) => isValidShortcutCommand(s.command))
        .toList();
  }

  Future<void> updateCommandShortcuts(
    List<CommandShortcutEvent> commandShortcuts,
    List<CommandShortcutModel> customizeShortcuts,
  ) async {
    for (final shortcut in customizeShortcuts) {
      final shortcutEvent = commandShortcuts.firstWhereOrNull(
        (s) => s.key == shortcut.key && s.command != shortcut.command,
      );
      if (shortcutEvent != null &&
          isSupportedShortcutCommand(shortcutEvent, shortcut.command)) {
        setShortcutCommand(shortcutEvent, shortcut.command);
      }
    }
  }

  Future<void> resetToDefaultShortcuts() async {
    await _initCompleter.future;
    await saveAllShortcuts(allDefaultShortcutEvents);
    await updateCommandShortcuts(
      allShortcutEvents,
      allDefaultShortcutEvents
          .map(CommandShortcutModel.fromCommandEvent)
          .toList(),
    );
    notifyShortcutChanges();
  }

  // Accesses the shortcuts.json file within the default AppFlowy Document Directory or creates a new file if it already doesn't exist.
  Future<void> _initializeService(File? file) async {
    try {
      _file = file ?? await _defaultShortcutFile();
      _initCompleter.complete();
    } catch (error, stackTrace) {
      _initCompleter.completeError(error, stackTrace);
    }
  }

  //returns the default file for storing shortcuts
  Future<File> _defaultShortcutFile() async {
    final path = await getIt<ApplicationDataStorage>().getPath();
    return File(
      p.join(path, 'shortcuts', 'shortcuts.json'),
    )..createSync(recursive: true);
  }
}

extension on List<CommandShortcutEvent> {
  /// Utility method for converting a CommandShortcutEvent List to a
  /// CommandShortcutModal List. This is necessary for creating shortcuts
  /// object, which is used for saving the shortcuts list.
  List<CommandShortcutModel> toCommandShortcutModelList() =>
      map((e) => CommandShortcutModel.fromCommandEvent(e)).toList();
}
