import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/reminder/notification_service.dart';
import 'package:appflowy/user/application/reminder/notification_settings_service.dart';
import 'package:appflowy/util/log_utils.dart';
import 'package:appflowy_backend/log.dart';

class NotificationServiceTask extends LaunchTask {
  const NotificationServiceTask();

  @override
  Future<void> initialize(LaunchContext context) async {
    await super.initialize(context);
    LogUtils.info(
      'NotificationServiceTask: Initializing notification service...',
    );

    try {
      final notificationService = NotificationService();
      final hasPermission =
          await notificationService.checkAndRequestPermission();
      LogUtils.info(
        'NotificationServiceTask: Permission status: $hasPermission',
      );

      if (!hasPermission) {
        LogUtils.warning(
          'NotificationServiceTask: Notification permission not granted',
        );
        const notificationSettingsService = NotificationSettingsService();
        await notificationSettingsService.resetNotificationPermissionStatus();
      }

      LogUtils.info(
        'NotificationServiceTask: Notification service initialized successfully',
      );
    } catch (e, stackTrace) {
      Log.error(
        'NotificationServiceTask: Failed to initialize notification service: $e',
        stackTrace,
      );
    }
  }

  @override
  Future<void> dispose() async {
    LogUtils.info(
      'NotificationServiceTask: Disposing notification service task',
    );
    // Notification service is singleton-based, no explicit teardown here.
    // 通知服务为单例，这里不做额外销毁。
    await super.dispose();
  }
}
