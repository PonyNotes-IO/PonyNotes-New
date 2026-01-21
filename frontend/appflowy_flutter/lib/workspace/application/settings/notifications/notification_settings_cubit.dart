import 'dart:async';

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
    // 从 Rust 获取服务端通知设置（Flutter 不做本地持久化）
    try {
      _notificationSettings =
          await UserSettingsBackendService().getNotificationSettings();
    } catch (_) {
      // fallback to defaults
      _notificationSettings = NotificationSettingsPB();
    }

    emit(
      state.copyWith(
        isNotificationsEnabled: _notificationSettings.notificationsEnabled,
        // 该开关目前仅影响前端展示，不做本地持久化（按产品需要可后续纳入 PB 并由服务端同步）
        isShowNotificationsIconEnabled: true,
        isAtMeEnabled: _notificationSettings.notifyAtMe,
        isPendingEnabled: _notificationSettings.notifyPending,
        isPermissionChangeEnabled: _notificationSettings.notifyPermissionChange,
        isJoinTeamEnabled: _notificationSettings.notifyJoinTeam,
        isClipEnabled: _notificationSettings.notifyClip,
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

    // 更新 PB，持久化交给 Rust（Rust 再同步服务端）
    _notificationSettings.notifyAtMe = newVal;
    await _saveNotificationSettings();
  }

  Future<void> togglePendingEnabled() async {
    await _initCompleter.future;
    final newVal = !state.isPendingEnabled;
    emit(state.copyWith(isPendingEnabled: newVal));

    _notificationSettings.notifyPending = newVal;
    await _saveNotificationSettings();
  }

  Future<void> togglePermissionChangeEnabled() async {
    await _initCompleter.future;
    final newVal = !state.isPermissionChangeEnabled;
    emit(state.copyWith(isPermissionChangeEnabled: newVal));

    _notificationSettings.notifyPermissionChange = newVal;
    await _saveNotificationSettings();
  }

  Future<void> toggleJoinTeamEnabled() async {
    await _initCompleter.future;
    final newVal = !state.isJoinTeamEnabled;
    emit(state.copyWith(isJoinTeamEnabled: newVal));

    _notificationSettings.notifyJoinTeam = newVal;
    await _saveNotificationSettings();
  }

  Future<void> toggleClipEnabled() async {
    await _initCompleter.future;
    final newVal = !state.isClipEnabled;
    emit(state.copyWith(isClipEnabled: newVal));

    _notificationSettings.notifyClip = newVal;
    await _saveNotificationSettings();
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
