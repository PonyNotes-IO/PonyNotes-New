import 'dart:async';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/core/config/kv_keys.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_settings_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_setting.pb.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'notification_settings_cubit.freezed.dart';

class NotificationSettingsCubit extends Cubit<NotificationSettingsState> {
  NotificationSettingsCubit() : super(NotificationSettingsState.initial()) {
    _initialize();
  }

  final Completer<void> _initCompleter = Completer();

  late final NotificationSettingsPB _notificationSettings;

  Future<void> _initialize() async {
    _notificationSettings =
        await UserSettingsBackendService().getNotificationSettings();

    final showNotificationSetting = await getIt<KeyValueStorage>()
        .getWithFormat(KVKeys.showNotificationIcon, (v) => bool.parse(v));

    // load per-type notification settings from local KV (frontend first)
    final atMe = await getIt<KeyValueStorage>()
        .getWithFormat(KVKeys.notificationAtMe, (v) => bool.parse(v));
    final pending = await getIt<KeyValueStorage>()
        .getWithFormat(KVKeys.notificationPending, (v) => bool.parse(v));
    final permissionChange = await getIt<KeyValueStorage>()
        .getWithFormat(KVKeys.notificationPermissionChange, (v) => bool.parse(v));
    final joinTeam = await getIt<KeyValueStorage>()
        .getWithFormat(KVKeys.notificationJoinTeam, (v) => bool.parse(v));
    final clip = await getIt<KeyValueStorage>()
        .getWithFormat(KVKeys.notificationClip, (v) => bool.parse(v));

    emit(
      state.copyWith(
        isNotificationsEnabled: _notificationSettings.notificationsEnabled,
        isShowNotificationsIconEnabled: showNotificationSetting ?? true,
        isAtMeEnabled: atMe ?? true,
        isPendingEnabled: pending ?? true,
        isPermissionChangeEnabled: permissionChange ?? true,
        isJoinTeamEnabled: joinTeam ?? true,
        isClipEnabled: clip ?? true,
      ),
    );

    _initCompleter.complete();
  }

  Future<void> toggleNotificationsEnabled() async {
    await _initCompleter.future;

    _notificationSettings.notificationsEnabled = !state.isNotificationsEnabled;

    emit(
      state.copyWith(
        isNotificationsEnabled: _notificationSettings.notificationsEnabled,
      ),
    );

    await _saveNotificationSettings();
  }

  Future<void> toggleAtMeEnabled() async {
    await _initCompleter.future;
    final newVal = !state.isAtMeEnabled;
    emit(state.copyWith(isAtMeEnabled: newVal));
    await getIt<KeyValueStorage>().set(KVKeys.notificationAtMe, newVal.toString());
  }

  Future<void> togglePendingEnabled() async {
    await _initCompleter.future;
    final newVal = !state.isPendingEnabled;
    emit(state.copyWith(isPendingEnabled: newVal));
    await getIt<KeyValueStorage>().set(KVKeys.notificationPending, newVal.toString());
  }

  Future<void> togglePermissionChangeEnabled() async {
    await _initCompleter.future;
    final newVal = !state.isPermissionChangeEnabled;
    emit(state.copyWith(isPermissionChangeEnabled: newVal));
    await getIt<KeyValueStorage>().set(KVKeys.notificationPermissionChange, newVal.toString());
  }

  Future<void> toggleJoinTeamEnabled() async {
    await _initCompleter.future;
    final newVal = !state.isJoinTeamEnabled;
    emit(state.copyWith(isJoinTeamEnabled: newVal));
    await getIt<KeyValueStorage>().set(KVKeys.notificationJoinTeam, newVal.toString());
  }

  Future<void> toggleClipEnabled() async {
    await _initCompleter.future;
    final newVal = !state.isClipEnabled;
    emit(state.copyWith(isClipEnabled: newVal));
    await getIt<KeyValueStorage>().set(KVKeys.notificationClip, newVal.toString());
  }

  Future<void> toggleShowNotificationIconEnabled() async {
    await _initCompleter.future;

    emit(
      state.copyWith(
        isShowNotificationsIconEnabled: !state.isShowNotificationsIconEnabled,
      ),
    );
  }

  Future<void> _saveNotificationSettings() async {
    await _initCompleter.future;

    await getIt<KeyValueStorage>().set(
      KVKeys.showNotificationIcon,
      state.isShowNotificationsIconEnabled.toString(),
    );

    final result = await UserSettingsBackendService()
        .setNotificationSettings(_notificationSettings);
    result.fold(
      (r) => null,
      (error) => Log.error(error),
    );
  }
}

@freezed
class NotificationSettingsState with _$NotificationSettingsState {
  const NotificationSettingsState._();

  const factory NotificationSettingsState({
    required bool isNotificationsEnabled,
    required bool isShowNotificationsIconEnabled,
    required bool isAtMeEnabled,
    required bool isPendingEnabled,
    required bool isPermissionChangeEnabled,
    required bool isJoinTeamEnabled,
    required bool isClipEnabled,
  }) = _NotificationSettingsState;

  factory NotificationSettingsState.initial() =>
      const NotificationSettingsState(
        isNotificationsEnabled: true,
        isShowNotificationsIconEnabled: true,
        isAtMeEnabled: true,
        isPendingEnabled: true,
        isPermissionChangeEnabled: true,
        isJoinTeamEnabled: true,
        isClipEnabled: true,
      );
}
