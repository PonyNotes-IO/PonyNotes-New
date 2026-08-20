import 'dart:async';
import 'dart:convert';

import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:universal_platform/universal_platform.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:appflowy/util/int64_extension.dart';

import 'reminder_extension.dart';

import '../../../util/log_utils.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  static const _reminderNotificationType = 'reminder';

  NotificationService._internal() {
    _initialize();
  }

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> _initialize() async {
    if (_initialized) return;

    try {
      // 初始化timezone数据
      tz.initializeTimeZones();

      // 配置初始化设置
      // 使用已存在的 ic_launcher 图标作为通知图标
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const DarwinInitializationSettings iosSettings =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const DarwinInitializationSettings macosSettings =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const LinuxInitializationSettings linuxSettings =
          LinuxInitializationSettings(
        defaultActionName: '查看详情',
      );

      const InitializationSettings initializationSettings =
          InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
        macOS: macosSettings, // 使用专门的 macOS 配置
        linux: linuxSettings,
      );

      // 初始化插件
      await _notificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _handleNotificationResponse,
        onDidReceiveBackgroundNotificationResponse:
            _handleBackgroundNotificationResponse,
      );

      // 请求通知权限
      if (UniversalPlatform.isIOS) {
        final iosImpl =
            _notificationsPlugin.resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>();
        if (iosImpl != null) {
          // 请求权限
          final granted = await iosImpl.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
          LogUtils.info('iOS notification permission: $granted');

          // 检查权限状态
          if (granted == false) {
            LogUtils.warning('Notification permission not granted for iOS');
          }
        } else {
          LogUtils.warning('IOSFlutterLocalNotificationsPlugin is null on iOS');
        }
      } else if (UniversalPlatform.isMacOS) {
        // 在 macOS 上，尝试使用 macOS 特定的实现
        LogUtils.info('Requesting notification permissions on macOS');
        // 注意：在 macOS 上，flutter_local_notifications 可能使用不同的实现
        // 直接尝试发送一个测试通知来触发权限请求
        try {
          const NotificationDetails platformDetails = NotificationDetails(
            macOS: DarwinNotificationDetails(
              sound: 'default',
            ),
          );
        } catch (e) {
          LogUtils.error(
              'Failed to request notification permissions on macOS: $e');
        }
      }

      _initialized = true;
      LogUtils.info('NotificationService initialized successfully');
    } catch (e, stackTrace) {
      LogUtils.error('Failed to initialize NotificationService: $e');

      // 即使初始化失败，也设置_initialized为true，避免重复初始化尝试
      _initialized = true;
    }
  }

  // 安排本地通知
  Future<void> scheduleNotification({
    required String id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    required Map<String, String> payload,
  }) async {
    try {
      await _initialize();

      // Only schedule notifications for future time points.
      if (!scheduledTime.isAfter(DateTime.now())) {
        LogUtils.warning('Skip non-future notification time: $scheduledTime');
        return;
      }

      // 配置通知详情
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'schedule_reminders',
        '日程提醒',
        channelDescription: '用于提醒您的日程安排',
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'ticker',
        sound: null, // 使用默认声音
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        sound: 'default',
      );

      const DarwinNotificationDetails macosDetails = DarwinNotificationDetails(
        sound: 'default',
      );

      const LinuxNotificationDetails linuxDetails = LinuxNotificationDetails();

      const NotificationDetails platformDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
        macOS: macosDetails,
        linux: linuxDetails,
      );

      // 安排通知
      await _notificationsPlugin.zonedSchedule(
        _notificationId(id),
        title,
        body,
        tz.TZDateTime.from(scheduledTime, tz.local),
        platformDetails,
        payload: jsonEncode(payload),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );

      LogUtils.info('Scheduled notification: $id at $scheduledTime');
    } catch (e, stackTrace) {
      LogUtils.error('Failed to schedule notification: $e');
    }
  }

  // 使用稳定的 31 位 FNV-1a 哈希，确保重启后仍能定位同一条系统通知。
  static int _notificationId(String id) {
    final numericId = int.tryParse(id);
    if (numericId != null && numericId >= 0) {
      return numericId;
    }

    var hash = 0x811C9DC5;
    for (final codeUnit in id.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    return hash == 0 ? 1 : hash;
  }

  static int _legacyNotificationId(String id) =>
      int.tryParse(id) ?? id.hashCode;

  // 取消通知
  Future<void> cancelNotification(int notificationId) async {
    try {
      await _initialize();
      await _notificationsPlugin.cancel(notificationId);
      LogUtils.info('Cancelled notification: $notificationId');
    } catch (e, stackTrace) {
      LogUtils.error('Failed to cancel notification: $e');
    }
  }

  // 取消所有通知
  Future<void> cancelAllNotifications() async {
    try {
      await _initialize();
      await _notificationsPlugin.cancelAll();
      LogUtils.info('Cancelled all notifications');
    } catch (e, stackTrace) {
      LogUtils.error('Failed to cancel all notifications: $e');
    }
  }

  // 处理通知点击
  void _handleNotificationResponse(NotificationResponse response) {
    try {
      if (response.payload != null) {
        final payload = jsonDecode(response.payload!) as Map<String, dynamic>;
        LogUtils.info('Notification clicked with payload: $payload');

        // 这里可以添加导航逻辑，根据payload打开对应的日程详情
      }
    } catch (e, stackTrace) {
      LogUtils.error('Failed to handle notification response: $e');
    }
  }

  // 处理后台通知点击
  static void _handleBackgroundNotificationResponse(
      NotificationResponse response) {
    try {
      if (response.payload != null) {
        final payload = jsonDecode(response.payload!) as Map<String, dynamic>;
        LogUtils.info('Background notification clicked with payload: $payload');

        // 后台点击处理逻辑
      }
    } catch (e, stackTrace) {
      LogUtils.error('Failed to handle background notification response: $e');
    }
  }

  // 打开系统设置页面，引导用户开启通知权限
  Future<void> openNotificationSettings() async {
    try {
      String url;

      if (UniversalPlatform.isIOS) {
        // iOS 系统设置
        url = 'app-settings:';
      } else if (UniversalPlatform.isMacOS) {
        // macOS 系统通知设置
        url = 'x-apple.systempreferences:com.apple.preference.notifications';
      } else if (UniversalPlatform.isAndroid) {
        // Android 系统通知设置
        url = 'app-settings:notification_id';
      } else {
        // 其他平台
        LogUtils.warning(
            'Opening notification settings is not supported on this platform');
        return;
      }

      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        LogUtils.info('Opened notification settings: $url');
      } else {
        LogUtils.error('Could not open notification settings: $url');
      }
    } catch (e, stackTrace) {
      LogUtils.error('Failed to open notification settings: $e');
    }
  }

  static bool isSchedulableReminder(ReminderPB reminder) =>
      reminder.notificationType == _reminderNotificationType &&
      !reminder.isRead &&
      !reminder.isArchived &&
      reminder.scheduledAt.toDateTime().isAfter(DateTime.now());

  /// 取消一个日程提醒对应的本机系统通知。
  ///
  /// 同时兼容旧版本使用 `String.hashCode` 生成通知 ID 的遗留任务。
  Future<void> cancelReminderNotification(String reminderId) async {
    await cancelNotification(_notificationId(reminderId));

    final legacyId = _legacyNotificationId(reminderId);
    if (legacyId != _notificationId(reminderId)) {
      await cancelNotification(legacyId);
    }
  }

  /// 将操作系统中的日程通知收敛为当前同步到本机的提醒集合。
  ///
  /// 日程提醒经协作数据同步后，并不会自动进入另一台设备的操作系统通知队列；
  /// 因此每次刷新提醒列表都必须在本机补注册未来提醒，并清理已删除、已读或
  /// 已归档的旧任务。普通云端消息通知不会进入此流程。
  Future<void> synchronizeReminderNotifications(
    Iterable<ReminderPB> reminders,
  ) async {
    final expected = <String, ReminderPB>{
      for (final reminder in reminders)
        if (isSchedulableReminder(reminder)) reminder.id: reminder,
    };

    await _initialize();

    final scheduledAtByReminderId = <String, String>{};
    try {
      final pending = await _notificationsPlugin.pendingNotificationRequests();
      for (final request in pending) {
        final payload = _decodeReminderPayload(request.payload);
        final reminderId = payload?['reminderId'];
        if (payload?['notificationType'] != _reminderNotificationType ||
            reminderId == null) {
          continue;
        }

        // ID 不匹配说明是旧 hashCode 方案留下的任务，需要迁移为稳定 ID。
        if (!expected.containsKey(reminderId) ||
            request.id != _notificationId(reminderId)) {
          await _notificationsPlugin.cancel(request.id);
          LogUtils.info('Cancelled stale reminder notification: $reminderId');
        } else {
          scheduledAtByReminderId[reminderId] = payload?['scheduledAt'] ?? '';
        }
      }
    } catch (e) {
      // 个别桌面平台可能不支持读取待执行任务；仍继续注册目标提醒。
      LogUtils.warning('Failed to inspect pending reminder notifications: $e');
    }

    for (final reminder in expected.values) {
      final scheduledAt = reminder.scheduledAt.toDateTime();
      if (scheduledAtByReminderId[reminder.id] ==
          scheduledAt.millisecondsSinceEpoch.toString()) {
        continue;
      }
      await scheduleReminderNotification(reminder);
    }
  }

  Map<String, String>? _decodeReminderPayload(String? rawPayload) {
    if (rawPayload == null || rawPayload.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(rawPayload);
      if (decoded is! Map) {
        return null;
      }
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
      );
    } catch (_) {
      return null;
    }
  }

  // 为提醒安排通知
  Future<void> scheduleReminderNotification(ReminderPB reminder) async {
    try {
      if (!isSchedulableReminder(reminder)) {
        await cancelReminderNotification(reminder.id);
        return;
      }

      // 清理升级前用 hashCode 创建的同一提醒任务，避免双重提醒。
      final legacyId = _legacyNotificationId(reminder.id);
      if (legacyId != _notificationId(reminder.id)) {
        await cancelNotification(legacyId);
      }

      final payload = {
        'reminderId': reminder.id,
        'objectId': reminder.objectId,
        'notificationType': _reminderNotificationType,
        'rowId': reminder.meta['row_id'],
        'scheduledAt': reminder.scheduledAt.toDateTime().millisecondsSinceEpoch,
      };

      await scheduleNotification(
        id: reminder.id,
        title: reminder.title,
        body: reminder.message,
        scheduledTime: reminder.scheduledAt.toDateTime(),
        payload:
            payload.map((key, value) => MapEntry(key, value?.toString() ?? '')),
      );
    } catch (e, stackTrace) {
      LogUtils.error('Failed to schedule reminder notification: $e');
    }
  }

  // 检查通知权限并引导用户开启
  Future<bool> checkAndRequestPermission() async {
    try {
      await _initialize();

      bool hasPermission = false;

      if (UniversalPlatform.isAndroid) {
        final androidImpl =
            _notificationsPlugin.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        if (androidImpl != null) {
          // 请求权限
          final granted = await androidImpl.requestNotificationsPermission();
          hasPermission = granted ?? false;
        }
      } else if (UniversalPlatform.isIOS) {
        final iosImpl =
            _notificationsPlugin.resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>();
        if (iosImpl != null) {
          // 请求权限
          final granted = await iosImpl.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
          hasPermission = granted ?? false;
        }
      } else if (UniversalPlatform.isMacOS) {
        // 在 macOS 上，权限请求会在发送第一个通知时触发
        final macOSImpl =
            _notificationsPlugin.resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin>();
        if (macOSImpl != null) {
          // 请求权限
          final granted = await macOSImpl.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
              provisional: true,
              critical: true);
          return granted ?? false;
        }
      }

      return hasPermission;
    } catch (e) {
      LogUtils.error('Failed to check and request notification permission: $e');
      return false;
    }
  }
}
