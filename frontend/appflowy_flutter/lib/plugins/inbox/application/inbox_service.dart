import 'dart:convert';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/plugins/inbox/domain/models/inbox_item.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class InboxService {
  InboxService();

  /// 从服务端拉取当前用户的最近通知（最多 50 条）
  Future<List<InboxItem>> loadItems() async {
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;
      if (baseUrl.isEmpty) {
        Log.warn('[InboxService] baseUrl is empty, skipping notification fetch');
        return [];
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
        return [];
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
        return notifications
            .map((n) => _toInboxItem(n as Map<String, dynamic>))
            .toList();
      } else {
        Log.error(
          '[InboxService] Failed to fetch notifications: HTTP ${response.statusCode}',
        );
        return [];
      }
    } catch (e) {
      Log.error('[InboxService] Error fetching notifications: $e');
      return [];
    }
  }

  InboxItem _toInboxItem(Map<String, dynamic> n) {
    final id = (n['id'] as String?) ?? '';
    final notificationType = (n['notification_type'] as String?) ?? '';
    final payload = n['payload'] as Map<String, dynamic>? ?? {};
    final title =
        (payload['title'] as String?) ?? _defaultTitle(notificationType);
    final message = (payload['message'] as String?) ?? '';
    final processed = (n['processed'] as bool?) ?? false;

    DateTime createdAt = DateTime.now();
    try {
      final createdAtStr = n['created_at'] as String?;
      if (createdAtStr != null) {
        createdAt = DateTime.parse(createdAtStr).toLocal();
      }
    } catch (_) {}

    return InboxItem(
      id: id,
      title: title,
      description: message,
      content: message,
      date: _formatDate(createdAt),
      createdAt: createdAt,
      updatedAt: createdAt,
      isRead: processed,
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

  Future<void> markAsRead(String itemId) async {
    // processed 标志由服务端在 WS 推送时自动更新，客户端无需额外请求
  }

  Future<void> markAllAsRead() async {
    // 同上
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
