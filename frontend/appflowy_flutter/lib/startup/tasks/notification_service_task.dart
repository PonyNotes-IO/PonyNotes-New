import 'dart:async';

import 'package:appflowy/util/log_utils.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/reminder/notification_service.dart';
import 'package:flutter/widgets.dart';

import '../../user/application/reminder/notification_settings_service.dart';

class NotificationServiceTask extends LaunchTask {
  bool _disposed = false;

  @override
  Future<void> initialize(LaunchContext context) async {
    await super.initialize(context);

    if (context.env.isTest) {
      return _initialize();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) {
        unawaited(_initialize());
      }
    });
  }

  Future<void> _initialize() async {
    LogUtils.info(
      'NotificationServiceTask: Initializing notification service...',
    );

    try {
      // 初始化通知服务
      final notificationService = NotificationService();

      // 检查并请求通知权限
      final hasPermission =
          await notificationService.checkAndRequestPermission();
      LogUtils.info(
        'NotificationServiceTask: Permission status: $hasPermission',
      );

      if (!hasPermission) {
        LogUtils.warning(
          'NotificationServiceTask: Notification permission not granted',
        );
        // 这里可以添加逻辑，在应用启动后显示一个提示，引导用户开启权限
        final notificationSettingsService = const NotificationSettingsService();
        await notificationSettingsService.resetNotificationPermissionStatus();
      }

      LogUtils.info(
        'NotificationServiceTask: Notification service initialized successfully',
      );
    } catch (e) {
      LogUtils.error(
        'NotificationServiceTask: Failed to initialize notification service: $e',
      );
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await super.dispose();
    LogUtils.info(
      'NotificationServiceTask: Disposing notification service task',
    );
    // 通知服务是单例，不需要在这里销毁
  }
}
