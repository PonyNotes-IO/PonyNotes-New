import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/notifications/notification_settings_cubit.dart';

/// The app name used in the local notification.
///
/// DO NOT Use i18n here, because the i18n plugin is not ready
///   before the local notification is initialized.
const _localNotifierAppName = 'AppFlowy';

/// Manages Local Notifications
///
/// Currently supports:
///  - MacOS
///  - Windows
///  - Linux
///
class NotificationService {
  static Future<void> initialize() async {
    await localNotifier.setup(
      appName: _localNotifierAppName,
      // Don't create a shortcut on Windows, because the setup.exe will create a shortcut
      shortcutPolicy: ShortcutPolicy.requireNoCreate,
    );
  }
}

/// Creates and shows a Notification
///
class NotificationMessage {
  NotificationMessage({
    required String title,
    required String body,
    String? identifier,
    String? notificationType,
    VoidCallback? onClick,
  }) {
    _notification = LocalNotification(
      identifier: identifier,
      title: title,
      body: body,
    )..onClick = onClick;
    _show(notificationType: notificationType);
  }

  late final LocalNotification _notification;

  void _show({String? notificationType}) {
    try {
      final cubit = getIt<NotificationSettingsCubit>();
      final state = cubit.state;
      if (!state.isNotificationsEnabled) return;

      // If a specific type is provided, check per-type switches
      if (notificationType != null) {
        final t = notificationType.toLowerCase();
        if (t == 'mention' && !state.isAtMeEnabled) return;
        if (t == 'clip' && !state.isClipEnabled) return;
        if (t == 'pending' && !state.isPendingEnabled) return;
        if (t == 'permission_change' && !state.isPermissionChangeEnabled) return;
        if (t == 'join_team' && !state.isJoinTeamEnabled) return;
      }
    } catch (_) {
      // If cubit not available or any error, fall back to showing notification
    }

    _notification.show();
  }
}
