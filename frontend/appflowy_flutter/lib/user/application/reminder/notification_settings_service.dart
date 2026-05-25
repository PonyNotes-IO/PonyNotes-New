import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_backend/protobuf/flowy-error/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';

import '../../../core/config/kv.dart';

class NotificationSettingsService {
  const NotificationSettingsService();

  static const String _notificationPermissionDismissedKey = 'notification_permission_dismissed';

  // 检查通知权限是否被用户取消
  Future<bool> isNotificationPermissionDismissed() async {
    try {
      final value = await getIt<KeyValueStorage>().get(_notificationPermissionDismissedKey);
      return value == 'true';
    } catch (e) {
      // 出错时默认为未取消
      return false;
    }
  }

  // 标记通知权限为已取消
  Future<void> markNotificationPermissionAsDismissed() async {
    try {
      await getIt<KeyValueStorage>().set(_notificationPermissionDismissedKey, 'true');
    } catch (e) {
      // 忽略错误
    }
  }

  // 重置通知权限状态
  Future<void> resetNotificationPermissionStatus() async {
    try {
      await getIt<KeyValueStorage>().remove(_notificationPermissionDismissedKey);
    } catch (e) {
      // 忽略错误
    }
  }
}