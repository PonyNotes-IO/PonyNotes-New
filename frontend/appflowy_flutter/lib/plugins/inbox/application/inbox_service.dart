import 'dart:convert';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/plugins/inbox/domain/models/inbox_item.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:fixnum/fixnum.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class InboxService {
  InboxService();

  /// 从服务端拉取当前用户的最近通知（最多 50 条）
  Future<List<InboxItem>> loadItems() async {
    final notifications = await _loadNotifications();
    return notifications?.map(_toInboxItem).toList() ?? [];
  }

  /// 拉取账号级系统通知，转换为通知页使用的提醒模型。
  /// 返回 null 表示请求失败，调用方应保留已显示的全局通知。
  Future<List<ReminderPB>?> loadGlobalReminders() async {
    final notifications = await _loadNotifications();
    return notifications?.map(_toGlobalReminder).toList();
  }

  Future<List<Map<String, dynamic>>?> _loadNotifications() async {
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;
      if (baseUrl.isEmpty) {
        Log.warn(
          '[InboxService] baseUrl is empty, skipping notification fetch',
        );
        return null;
      }

      // 获取 access token
      final userResult = await UserBackendService.getCurrentUserProfile();
      final rawToken = userResult.fold(
        (user) => user.token,
        (error) {
          Log.error('[InboxService] Failed to get user profile: $error');
          return '';
        },
      );
      final token = _normalizeToken(rawToken);
      if (token.isEmpty) {
        Log.warn('[InboxService] access token is empty');
        return null;
      }

      final uri = Uri.parse('$baseUrl/api/user/notifications');
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body) as Map<String, dynamic>;
        final List<dynamic> notifications =
            (jsonData['notifications'] as List<dynamic>?) ?? [];
        return notifications.map((n) => n as Map<String, dynamic>).toList();
      } else {
        Log.error(
          '[InboxService] Failed to fetch notifications: HTTP ${response.statusCode}',
        );
        return null;
      }
    } catch (e) {
      Log.error('[InboxService] Error fetching notifications: $e');
      return null;
    }
  }

  ReminderPB _toGlobalReminder(Map<String, dynamic> notification) {
    final id = (notification['id'] as String?) ?? '';
    final notificationType =
        (notification['notification_type'] as String?) ?? 'system';
    final payload = notification['payload'] as Map<String, dynamic>? ?? {};
    final createdAt = _parseCreatedAt(notification['created_at'] as String?);

    // 注意:ReminderPB.meta 是 $pb.PbMap<String, String>,其构造器参数期望
    // Iterable<MapEntry<String, String>>,而不是普通 Map<String, String>。
    // Flutter 3.35 (Dart 3.8+) 对 map literal 与 spread 表达式在
    // 模糊类型推断时报 ambiguous,因此显式构造 MapEntry 列表传入。
    final metaEntries = <MapEntry<String, String>>[
      MapEntry<String, String>(
        'notification_type',
        notificationType == 'mention' ? 'mention' : 'system',
      ),
      MapEntry<String, String>('cloud_notification_type', notificationType),
      MapEntry<String, String>('payload', jsonEncode(payload)),
      MapEntry<String, String>(
        'created_at',
        createdAt.millisecondsSinceEpoch.toString(),
      ),
    ];

    return ReminderPB(
      id: id,
      objectId: (notification['workspace_id'] as String?) ?? '',
      scheduledAt: Int64(createdAt.millisecondsSinceEpoch),
      isAck: true,
      isRead: (notification['is_read'] as bool?) ?? false,
      title: (payload['title'] as String?) ?? _defaultTitle(notificationType),
      message: (payload['message'] as String?) ?? '',
      meta: metaEntries,
    );
  }

  InboxItem _toInboxItem(Map<String, dynamic> n) {
    final id = (n['id'] as String?) ?? '';
    final notificationType = (n['notification_type'] as String?) ?? '';
    final payload = n['payload'] as Map<String, dynamic>? ?? {};
    final title =
        (payload['title'] as String?) ?? _defaultTitle(notificationType);
    final message = (payload['message'] as String?) ?? '';
    // 已读以服务端 is_read 为准（processed 只表示"已投递"，不是已读）。
    final isRead = (n['is_read'] as bool?) ?? false;

    final createdAt = _parseCreatedAt(n['created_at'] as String?);

    return InboxItem(
      id: id,
      title: title,
      description: message,
      content: message,
      date: _formatDate(createdAt),
      createdAt: createdAt,
      updatedAt: createdAt,
      isRead: isRead,
      source: _sourceFromType(notificationType),
      tags: _tagsFromType(notificationType),
    );
  }

  String _defaultTitle(String notificationType) {
    switch (notificationType) {
      case 'reminder':
        return '工作区邀请';
      case 'workspace_member_removed':
        return '工作区成员移除';
      case 'workspace_member_role_changed':
        return '角色变更';
      case 'mention':
        return '有人@了你';
      case 'collab_shared':
        return '文档共享';
      case 'collab_share_link_opened':
        return '分享链接被打开';
      case 'collab_permission_changed':
        return '文档权限变更';
      default:
        return '系统通知';
    }
  }

  DateTime _parseCreatedAt(String? value) {
    if (value == null) return DateTime.now();
    try {
      return DateTime.parse(value).toLocal();
    } catch (_) {
      return DateTime.now();
    }
  }

  String _sourceFromType(String notificationType) {
    switch (notificationType) {
      case 'reminder':
        return '邀请';
      case 'workspace_member_removed':
        return '成员';
      case 'workspace_member_role_changed':
        return '角色';
      case 'mention':
        return '提及';
      case 'collab_shared':
        return '共享';
      case 'collab_share_link_opened':
        return '分享';
      case 'collab_permission_changed':
        return '权限';
      default:
        return '系统';
    }
  }

  List<String> _tagsFromType(String notificationType) {
    switch (notificationType) {
      case 'reminder':
        return ['工作区', '邀请'];
      case 'workspace_member_removed':
        return ['工作区', '成员'];
      case 'workspace_member_role_changed':
        return ['工作区', '角色'];
      case 'mention':
        return ['提及'];
      case 'collab_shared':
        return ['文档', '共享'];
      case 'collab_share_link_opened':
        return ['文档', '分享'];
      case 'collab_permission_changed':
        return ['文档', '权限'];
      default:
        return [];
    }
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return DateFormat('MM月dd日').format(dt);
  }

  String _normalizeToken(String rawToken) {
    if (rawToken.isEmpty) return '';
    if (rawToken.trim().startsWith('{')) {
      try {
        final map = json.decode(rawToken) as Map<String, dynamic>;
        final token = map['access_token'] as String?;
        if (token != null && token.isNotEmpty) return token;
      } catch (_) {}
    }
    return rawToken;
  }

  /// 标记单条通知为已读（账号级持久化到服务端，避免刷新后又变未读）。
  Future<bool> markAsRead(String itemId) async {
    if (itemId.isEmpty) return false;
    return _postNotification('/api/user/notifications/$itemId/read');
  }

  /// 全部标记已读。
  Future<bool> markAllAsRead() async {
    return _postNotification('/api/user/notifications/read-all');
  }

  /// 向通知相关接口发 POST（自动带 baseUrl + Bearer token）。
  Future<bool> _postNotification(String path) async {
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;
      if (baseUrl.isEmpty) return false;

      final userResult = await UserBackendService.getCurrentUserProfile();
      final rawToken = userResult.fold((user) => user.token, (_) => '');
      final token = _normalizeToken(rawToken);
      if (token.isEmpty) return false;

      final uri = Uri.parse('$baseUrl$path');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        Log.error(
          '[InboxService] POST $path failed: HTTP ${response.statusCode}',
        );
        return false;
      }
      return true;
    } catch (e) {
      Log.error('[InboxService] POST $path error: $e');
      return false;
    }
  }

  Future<void> toggleStar(String itemId, bool isStarred) async {
    // 本地状态，暂不持久化到服务端
  }

  Future<void> toggleImportant(String itemId, bool isImportant) async {
    // 本地状态，暂不持久化到服务端
  }

  Future<void> deleteItem(String itemId) async {
    // 暂不支持服务端删除
  }
}
