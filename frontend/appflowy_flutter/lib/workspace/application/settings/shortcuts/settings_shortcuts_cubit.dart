import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/settings/shortcuts/shortcut_registry.dart';
import 'package:appflowy/workspace/application/settings/shortcuts/settings_shortcuts_service.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'settings_shortcuts_cubit.freezed.dart';

@freezed
class ShortcutsState with _$ShortcutsState {
  const factory ShortcutsState({
    @Default(<CommandShortcutEvent>[])
    List<CommandShortcutEvent> commandShortcutEvents,
    @Default(ShortcutsStatus.initial) ShortcutsStatus status,
    @Default('') String error,
  }) = _ShortcutsState;
}

enum ShortcutsStatus {
  initial,
  updating,
  success,
  failure;

  /// Helper getter for when the [ShortcutsStatus] signifies
  /// that the shortcuts have not been loaded yet.
  ///
  bool get isLoading => [initial, updating].contains(this);

  /// Helper getter for when the [ShortcutsStatus] signifies
  /// a failure by itself being [ShortcutsStatus.failure]
  ///
  bool get isFailure => this == ShortcutsStatus.failure;

  /// Helper getter for when the [ShortcutsStatus] signifies
  /// a success by itself being [ShortcutsStatus.success]
  ///
  bool get isSuccess => this == ShortcutsStatus.success;
}

class ShortcutsCubit extends Cubit<ShortcutsState> {
  ShortcutsCubit(this.service) : super(const ShortcutsState());

  final SettingsShortcutService service;

  Future<void> fetchShortcuts() async {
    emit(
      state.copyWith(
        status: ShortcutsStatus.updating,
        error: '',
      ),
    );

    try {
      final customizeShortcuts = await service.getCustomizeShortcuts();
      await service.updateCommandShortcuts(
        allShortcutEvents,
        customizeShortcuts,
      );
      notifyShortcutChanges();

      //sort the shortcuts
      final sorted = allShortcutEvents.map((event) => event.copyWith()).toList()
        ..sort(
          (a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()),
        );

      emit(
        state.copyWith(
          status: ShortcutsStatus.success,
          commandShortcutEvents: sorted,
          error: '',
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: ShortcutsStatus.failure,
          error: LocaleKeys.settings_shortcutsPage_couldNotLoadErrorMsg.tr(),
        ),
      );
    }
  }

  Future<void> updateAllShortcuts() async {
    emit(state.copyWith(status: ShortcutsStatus.updating, error: ''));

    try {
      await service.saveAllShortcuts(state.commandShortcutEvents);
      notifyShortcutChanges();
      emit(state.copyWith(status: ShortcutsStatus.success, error: ''));
    } catch (e) {
      emit(
        state.copyWith(
          status: ShortcutsStatus.failure,
          error: LocaleKeys.settings_shortcutsPage_couldNotSaveErrorMsg.tr(),
        ),
      );
    }
  }

  Future<void> resetToDefault() async {
    emit(state.copyWith(status: ShortcutsStatus.updating, error: ''));

    try {
      await service.saveAllShortcuts(allDefaultShortcutEvents);
      await fetchShortcuts();
    } catch (e) {
      emit(
        state.copyWith(
          status: ShortcutsStatus.failure,
          error: LocaleKeys.settings_shortcutsPage_couldNotSaveErrorMsg.tr(),
        ),
      );
    }
  }

  List<CommandShortcutEvent> conflictsFor(
    CommandShortcutEvent current,
    String command,
  ) {
    if (command.isEmpty) return [];
    final bindings = command.split(',').map(Keybinding.parse).toSet();
    final existing = allShortcutEvents
        .firstWhere((event) => event.key == current.key)
        .keybindings
        .toSet();
    if (bindings.length == existing.length && bindings.containsAll(existing)) {
      return [];
    }
    return allShortcutEvents
        .where(
          (other) =>
              other.key != current.key &&
              shortcutScopesOverlap(current, other) &&
              other.keybindings.any(bindings.contains),
        )
        .toList();
  }

  Future<bool> rebind(CommandShortcutEvent current, String command) async {
    if (!isSupportedShortcutCommand(current, command)) return false;
    if (shortcutFor(current.key).command == command) return true;
    final conflicts = conflictsFor(current, command).map((e) => e.key).toSet();
    final bindings = command.isEmpty
        ? <Keybinding>{}
        : command.split(',').map(Keybinding.parse).toSet();
    final updated = allShortcutEvents.map((event) {
      final copy = event.copyWith();
      if (event.key == current.key) {
        setShortcutCommand(copy, command);
      } else if (conflicts.contains(event.key)) {
        setShortcutCommand(
          copy,
          event.command
              .split(',')
              .where((part) => !bindings.contains(Keybinding.parse(part)))
              .join(','),
        );
      }
      return copy;
    }).toList();
    try {
      await service.saveAllShortcuts(updated);
      for (var i = 0; i < updated.length; i++) {
        setShortcutCommand(allShortcutEvents[i], updated[i].command);
      }
      notifyShortcutChanges();
      emit(
        state.copyWith(
          commandShortcutEvents: updated
            ..sort(
              (a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()),
            ),
          status: ShortcutsStatus.success,
          error: '',
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Checks the current command against shortcuts with overlapping scopes.
  CommandShortcutEvent? getConflict(
    CommandShortcutEvent currentShortcut,
    String command,
  ) {
    for (final shortcut in state.commandShortcutEvents) {
      if (shortcut.key == currentShortcut.key || command.isEmpty) continue;
      final keybindings = shortcut.keybindings;
      if (keybindings.contains(Keybinding.parse(command)) &&
          shortcutScopesOverlap(currentShortcut, shortcut)) {
        return shortcut;
      }
    }

    return null;
  }
}
