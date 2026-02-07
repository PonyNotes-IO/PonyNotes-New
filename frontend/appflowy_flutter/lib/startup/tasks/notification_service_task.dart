import 'package:appflowy/util/log_utils.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/reminder/notification_service.dart';

class NotificationServiceTask extends LaunchTask {
  const NotificationServiceTask();

  @override
  Future<void> initialize(LaunchContext context) async {
    LogUtils.info('NotificationServiceTask: Initializing notification service...');
    
    try {
      // 初始化通知服务
      final notificationService = NotificationService();
      
      // 检查并请求通知权限
      final hasPermission = await notificationService.checkAndRequestPermission();
      LogUtils.info('NotificationServiceTask: Permission status: $hasPermission');
      
      if (!hasPermission) {
        LogUtils.warning('NotificationServiceTask: Notification permission not granted');
        // 这里可以添加逻辑，在应用启动后显示一个提示，引导用户开启权限

        await notificationService.openNotificationSettings();
      }

      LogUtils.info('NotificationServiceTask: Notification service initialized successfully');
    } catch (e, stackTrace) {
      LogUtils.error('NotificationServiceTask: Failed to initialize notification service: $e');
    }
  }

  @override
  Future<void> dispose() async {
    LogUtils.info('NotificationServiceTask: Disposing notification service task');
    // 通知服务是单例，不需要在这里销毁
  }
}
