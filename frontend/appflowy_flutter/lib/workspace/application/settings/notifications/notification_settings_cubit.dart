import 'dart:async';

import 'dart:convert';
import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:http/http.dart' as http;
import 'package:appflowy/core/config/kv_keys.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/user/application/user_settings_service.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_setting.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
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

    // Try fetch per-type settings from backend first
    bool? atMeServer;
    bool? pendingServer;
    bool? permissionChangeServer;
    bool? joinTeamServer;
    bool? clipServer;
    try {
      final headers = await _getAuthHeaders();
      final resp = await http.get(Uri.parse('${getIt<AppFlowyCloudSharedEnv>().appflowyCloudConfig.base_url}/api/user/notification-preferences'), headers: headers);
      if (resp.statusCode == 200) {
        final map = json.decode(resp.body) as Map?;
        if (map != null && map.isNotEmpty){
          final mapNew = map['data'] as Map?;
          if(mapNew != null && mapNew.isNotEmpty){
            atMeServer = mapNew['notify_at_me'] as bool?;
            pendingServer = mapNew['notify_pending'] as bool?;
            permissionChangeServer = mapNew['notify_permission_change'] as bool?;
            joinTeamServer = mapNew['notify_join_team'] as bool?;
            clipServer = mapNew['notify_clip'] as bool?;
          } else {
            atMeServer = _notificationSettings.notifyAtMe;
            pendingServer = _notificationSettings.notifyPending;
            permissionChangeServer = _notificationSettings.notifyPermissionChange;
            joinTeamServer = _notificationSettings.notifyJoinTeam;
            clipServer = _notificationSettings.notifyClip;
          }
        } else {
          atMeServer = _notificationSettings.notifyAtMe;
          pendingServer = _notificationSettings.notifyPending;
          permissionChangeServer = _notificationSettings.notifyPermissionChange;
          joinTeamServer = _notificationSettings.notifyJoinTeam;
          clipServer = _notificationSettings.notifyClip;
        }
      } else {
        atMeServer = _notificationSettings.notifyAtMe;
        pendingServer = _notificationSettings.notifyPending;
        permissionChangeServer = _notificationSettings.notifyPermissionChange;
        joinTeamServer = _notificationSettings.notifyJoinTeam;
        clipServer = _notificationSettings.notifyClip;
      }
    } catch (_) {}

    emit(
      state.copyWith(
        isNotificationsEnabled: _notificationSettings.notificationsEnabled,
        isAtMeEnabled: atMeServer ?? true,
        isPendingEnabled: pendingServer ?? true,
        isPermissionChangeEnabled: permissionChangeServer ?? true,
        isJoinTeamEnabled: joinTeamServer ?? true,
        isClipEnabled: clipServer ?? true,
      ),
    );

    _initCompleter.complete();
  }

  Future<void> toggleNotificationsEnabled() async {
    await _initCompleter.future;

    final originalVal = state.isNotificationsEnabled;
    final newVal = !originalVal;

    _notificationSettings.notificationsEnabled = newVal;

    final result = await UserSettingsBackendService()
        .setNotificationSettings(_notificationSettings);
    
    final success = result.fold(
      (r) => true,
      (error) {
        Log.error(error);
        _notificationSettings.notificationsEnabled = originalVal;
        return false;
      },
    );
    
    if (success) {
      emit(
        state.copyWith(
          isNotificationsEnabled: newVal,
        ),
      );
    }
  }

  Future<void> toggleAtMeEnabled() async {
    await _initCompleter.future;
    final originalVal = state.isAtMeEnabled;
    final newVal = !originalVal;
    emit(state.copyWith(isAtMeEnabled: newVal));
    // 先发送API请求
    final success = await _updateNotificationPreference({'notify_at_me': newVal});
    if (!success) {
      emit(state.copyWith(isAtMeEnabled: originalVal));
      showToastNotification(message: "请求失败，请重试",type: ToastificationType.error);
    } else {
      _notificationSettings.notifyAtMe = newVal;

      final result = await UserSettingsBackendService()
          .setNotificationSettings(_notificationSettings);
    }
  }

  Future<void> togglePendingEnabled() async {
    await _initCompleter.future;
    final originalVal = state.isPendingEnabled;
    final newVal = !originalVal;
    emit(state.copyWith(isPendingEnabled: newVal));
    final success = await _updateNotificationPreference({'notify_pending': newVal});
    if (!success) {
      emit(state.copyWith(isPendingEnabled: originalVal));
      showToastNotification(message: "请求失败，请重试",type: ToastificationType.error);
    } else {
      _notificationSettings.notifyPending = newVal;

      final result = await UserSettingsBackendService()
          .setNotificationSettings(_notificationSettings);
    }
  }

  Future<void> togglePermissionChangeEnabled() async {
    await _initCompleter.future;
    final originalVal = state.isPermissionChangeEnabled;
    final newVal = !originalVal;
    emit(state.copyWith(isPermissionChangeEnabled: newVal));
    final success = await _updateNotificationPreference({'notify_permission_change': newVal});
    
    if (!success) {
      emit(state.copyWith(isPermissionChangeEnabled: originalVal));
      showToastNotification(message: "请求失败，请重试",type: ToastificationType.error);
    } else {
      _notificationSettings.notifyPermissionChange = newVal;

      final result = await UserSettingsBackendService()
          .setNotificationSettings(_notificationSettings);
    }
  }

  Future<void> toggleJoinTeamEnabled() async {
    await _initCompleter.future;
    final originalVal = state.isJoinTeamEnabled;
    final newVal = !originalVal;
    emit(state.copyWith(isJoinTeamEnabled: newVal));
    final success = await _updateNotificationPreference({'notify_join_team': newVal});
    
    if (!success) {
      emit(state.copyWith(isJoinTeamEnabled: originalVal));
      showToastNotification(message: "请求失败，请重试",type: ToastificationType.error);
    } else {
      _notificationSettings.notifyJoinTeam = newVal;

      final result = await UserSettingsBackendService()
          .setNotificationSettings(_notificationSettings);
    }
  }

  Future<void> toggleClipEnabled() async {
    await _initCompleter.future;
    final originalVal = state.isClipEnabled;
    final newVal = !originalVal;
    emit(state.copyWith(isClipEnabled: newVal));
    final success = await _updateNotificationPreference({'notify_clip': newVal});
    
    if (!success) {
      emit(state.copyWith(isClipEnabled: originalVal));
      showToastNotification(message: "请求失败，请重试",type: ToastificationType.error);
    } else {
      _notificationSettings.notifyClip = newVal;

      final result = await UserSettingsBackendService()
          .setNotificationSettings(_notificationSettings);
    }
  }

  Future<void> toggleShowNotificationIconEnabled() async {
    await _initCompleter.future;

    emit(
      state.copyWith(
        isShowNotificationsIconEnabled: !state.isShowNotificationsIconEnabled,
      ),
    );
  }

  Future<Map<String, String>> _getAuthHeaders() async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    
    final userResult = await UserBackendService.getCurrentUserProfile();
    final rawToken = userResult.fold(
      (user) => user.token,
      (error) {
        Log.error('[NotificationSettingsCubit] Failed to get user profile: $error');
        return '';
      },
    );
    
    if (rawToken.isNotEmpty) {
      final token = _normalizeToken(rawToken);
      if (token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    
    return headers;
  }

  String _normalizeToken(String token) {
    if (token.isEmpty) return token;
    if (token.trim().startsWith('{')) {
      try {
        final map = json.decode(token);
        if (map is Map && map['access_token'] is String) {
          return map['access_token'] as String;
        }
      } catch (_) {
        // ignore parse errors, fallback to raw token
      }
    }
    return token;
  }

  Future<bool> _updateNotificationPreference(Map<String, dynamic> data) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.post(
        Uri.parse('${getIt<AppFlowyCloudSharedEnv>().appflowyCloudConfig.base_url}/api/user/notification-preferences'),
        headers: headers,
        body: json.encode(data),
      );
      await Future.delayed(Duration(milliseconds: 500));
      return response.statusCode == 200;
    } catch (e) {
      Log.error('[NotificationSettingsCubit] Failed to update notification preference: $e');
      return false;
    }
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
