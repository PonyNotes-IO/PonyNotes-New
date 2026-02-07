import 'dart:async';
import 'dart:convert';

import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:universal_platform/universal_platform.dart';
import 'package:appflowy/util/int64_extension.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  NotificationService._internal() {
    _initialize();
  }

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> _initialize() async {
    if (_initialized) return;

    try {
      // 初始化timezone数据
      tz.initializeTimeZones();

      // 配置初始化设置
      const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('app_icon');
      const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const LinuxInitializationSettings linuxSettings = LinuxInitializationSettings(
        defaultActionName: '查看详情',
      );

      const InitializationSettings initializationSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
        linux: linuxSettings,
      );

      // 初始化插件
      await _notificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _handleNotificationResponse,
        onDidReceiveBackgroundNotificationResponse: _handleBackgroundNotificationResponse,
      );

      // 请求通知权限
      if (UniversalPlatform.isIOS || UniversalPlatform.isMacOS) {
        final permission = await _notificationsPlugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        Log.info('iOS notification permission: $permission');
      }

      _initialized = true;
      Log.info('NotificationService initialized successfully');
    } catch (e, stackTrace) {
      Log.error('Failed to initialize NotificationService: $e', stackTrace);
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

      // 配置通知详情
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
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

      const LinuxNotificationDetails linuxDetails = LinuxNotificationDetails();

      const NotificationDetails platformDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
        linux: linuxDetails,
      );

      // 安排通知
      await _notificationsPlugin.zonedSchedule(
        int.tryParse(id) ?? id.hashCode,
        title,
        body,
        tz.TZDateTime.from(scheduledTime, tz.local),
        platformDetails,
        payload: jsonEncode(payload),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );

      Log.info('Scheduled notification: $id at $scheduledTime');
    } catch (e, stackTrace) {
      Log.error('Failed to schedule notification: $e', stackTrace);
    }
  }

  // 取消通知
  Future<void> cancelNotification(int notificationId) async {
    try {
      await _initialize();
      await _notificationsPlugin.cancel(notificationId);
      Log.info('Cancelled notification: $notificationId');
    } catch (e, stackTrace) {
      Log.error('Failed to cancel notification: $e', stackTrace);
    }
  }

  // 取消所有通知
  Future<void> cancelAllNotifications() async {
    try {
      await _initialize();
      await _notificationsPlugin.cancelAll();
      Log.info('Cancelled all notifications');
    } catch (e, stackTrace) {
      Log.error('Failed to cancel all notifications: $e', stackTrace);
    }
  }

  // 处理通知点击
  void _handleNotificationResponse(NotificationResponse response) {
    try {
      if (response.payload != null) {
        final payload = jsonDecode(response.payload!) as Map<String, dynamic>;
        Log.info('Notification clicked with payload: $payload');
        
        // 这里可以添加导航逻辑，根据payload打开对应的日程详情
      }
    } catch (e, stackTrace) {
      Log.error('Failed to handle notification response: $e', stackTrace);
    }
  }

  // 处理后台通知点击
  static void _handleBackgroundNotificationResponse(NotificationResponse response) {
    try {
      if (response.payload != null) {
        final payload = jsonDecode(response.payload!) as Map<String, dynamic>;
        Log.info('Background notification clicked with payload: $payload');
        
        // 后台点击处理逻辑
      }
    } catch (e, stackTrace) {
      Log.error('Failed to handle background notification response: $e', stackTrace);
    }
  }

  // 检查通知权限
  Future<bool> checkPermission() async {
    try {
      await _initialize();
      
      if (UniversalPlatform.isAndroid) {
        final androidImpl = _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        if (androidImpl != null) {
          // 请求权限
          final granted = await androidImpl.requestNotificationsPermission();
          return granted ?? false;
        }
      } else if (UniversalPlatform.isIOS || UniversalPlatform.isMacOS) {
        final iosImpl = _notificationsPlugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        if (iosImpl != null) {
          // 请求权限
          final granted = await iosImpl.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
          return granted ?? false;
        }
      }
      
      return true; // 默认返回true，对于其他平台
    } catch (e) {
      Log.error('Failed to check notification permission: $e');
      return false;
    }
  }

  // 为提醒安排通知
  Future<void> scheduleReminderNotification(ReminderPB reminder) async {
    try {
      final payload = {
        'reminderId': reminder.id,
        'objectId': reminder.objectId,
        'notificationType': reminder.meta['notification_type'],
        'rowId': reminder.meta['row_id'],
      };

      await scheduleNotification(
        id: reminder.id,
        title: reminder.title,
        body: reminder.message,
        scheduledTime: reminder.scheduledAt.toDateTime(),
        payload: payload.map((key, value) => MapEntry(key, value?.toString() ?? '')),
      );
    } catch (e, stackTrace) {
      Log.error('Failed to schedule reminder notification: $e', stackTrace);
    }
  }
}
