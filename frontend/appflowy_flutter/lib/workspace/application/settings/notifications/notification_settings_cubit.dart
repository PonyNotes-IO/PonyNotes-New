import 'dart:async';

import 'dart:convert';
import 'package:appflowy/core/config/kv.dart';
import 'package:http/http.dart' as http;
import 'package:appflowy/core/config/kv_keys.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/env/cloud_env.dart';
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
    // load master settings from backend
    try {
      _notificationSettings =
          await UserSettingsBackendService().getNotificationSettings();
    } catch (_) {
      // fallback to defaults
      _notificationSettings = NotificationSettingsPB();
    }

    final showNotificationSetting = await getIt<KeyValueStorage>()
        .getWithFormat(KVKeys.showNotificationIcon, (v) => bool.parse(v));

    // Try fetch per-type settings from backend first
    bool? atMeServer;
    bool? pendingServer;
    bool? permissionChangeServer;
    bool? joinTeamServer;
    bool? clipServer;
    try {
      final resp = await http.get(Uri.parse('${getIt<AppFlowyCloudSharedEnv>().appflowyCloudConfig.base_url}/api/user/notification-preferences'));
      if (resp.statusCode == 200) {
        final map = json.decode(resp.body);
        atMeServer = map['notify_at_me'] as bool?;
        pendingServer = map['notify_pending'] as bool?;
        permissionChangeServer = map['notify_permission_change'] as bool?;
        joinTeamServer = map['notify_join_team'] as bool?;
        clipServer = map['notify_clip'] as bool?;
      }
    } catch (_) {}

    // load per-type notification settings from local KV (frontend first), fallback to server, else default true
    final atMeLocal = await getIt<KeyValueStorage>()
        .getWithFormat(KVKeys.notificationAtMe, (v) => bool.parse(v));
    final pendingLocal = await getIt<KeyValueStorage>()
        .getWithFormat(KVKeys.notificationPending, (v) => bool.parse(v));
    final permissionChangeLocal = await getIt<KeyValueStorage>()
        .getWithFormat(KVKeys.notificationPermissionChange, (v) => bool.parse(v));
    final joinTeamLocal = await getIt<KeyValueStorage>()
        .getWithFormat(KVKeys.notificationJoinTeam, (v) => bool.parse(v));
    final clipLocal = await getIt<KeyValueStorage>()
        .getWithFormat(KVKeys.notificationClip, (v) => bool.parse(v));

    emit(
      state.copyWith(
        isNotificationsEnabled: _notificationSettings.notificationsEnabled,
        isShowNotificationsIconEnabled: showNotificationSetting ?? true,
        isAtMeEnabled: atMeLocal ?? atMeServer ?? true,
        isPendingEnabled: pendingLocal ?? pendingServer ?? true,
        isPermissionChangeEnabled: permissionChangeLocal ?? permissionChangeServer ?? true,
        isJoinTeamEnabled: joinTeamLocal ?? joinTeamServer ?? true,
        isClipEnabled: clipLocal ?? clipServer ?? true,
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
    // sync to backend
    try {
      await http.post(
        Uri.parse('${getIt<AppFlowyCloudSharedEnv>().appflowyCloudConfig.base_url}/api/user/notification-preferences'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'notify_at_me': newVal}),
      );
    } catch (_) {}
  }

  Future<void> togglePendingEnabled() async {
    await _initCompleter.future;
    final newVal = !state.isPendingEnabled;
    emit(state.copyWith(isPendingEnabled: newVal));
    await getIt<KeyValueStorage>().set(KVKeys.notificationPending, newVal.toString());
    try {
      await http.post(
        Uri.parse('${getIt<AppFlowyCloudSharedEnv>().appflowyCloudConfig.base_url}/api/user/notification-preferences'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'notify_pending': newVal}),
      );
    } catch (_) {}
  }

  Future<void> togglePermissionChangeEnabled() async {
    await _initCompleter.future;
    final newVal = !state.isPermissionChangeEnabled;
    emit(state.copyWith(isPermissionChangeEnabled: newVal));
    await getIt<KeyValueStorage>().set(KVKeys.notificationPermissionChange, newVal.toString());
    try {
      await http.post(
        Uri.parse('${getIt<AppFlowyCloudSharedEnv>().appflowyCloudConfig.base_url}/api/user/notification-preferences'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'notify_permission_change': newVal}),
      );
    } catch (_) {}
  }

  Future<void> toggleJoinTeamEnabled() async {
    await _initCompleter.future;
    final newVal = !state.isJoinTeamEnabled;
    emit(state.copyWith(isJoinTeamEnabled: newVal));
    await getIt<KeyValueStorage>().set(KVKeys.notificationJoinTeam, newVal.toString());
    try {
      await http.post(
        Uri.parse('${getIt<AppFlowyCloudSharedEnv>().appflowyCloudConfig.base_url}/api/user/notification-preferences'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'notify_join_team': newVal}),
      );
    } catch (_) {}
  }

  Future<void> toggleClipEnabled() async {
    await _initCompleter.future;
    final newVal = !state.isClipEnabled;
    emit(state.copyWith(isClipEnabled: newVal));
    await getIt<KeyValueStorage>().set(KVKeys.notificationClip, newVal.toString());
    try {
      await http.post(
        Uri.parse('${getIt<AppFlowyCloudSharedEnv>().appflowyCloudConfig.base_url}/api/user/notification-preferences'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'notify_clip': newVal}),
      );
    } catch (_) {}
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
