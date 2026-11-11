import 'dart:convert';

import 'package:appflowy/shared/af_user_profile_extension.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

String kbText(BuildContext context, String zh, String en) =>
    Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

enum KnowledgeBaseCategory {
  private,
  shared,
  favorites;

  String label(BuildContext context) => switch (this) {
        private => kbText(context, '私有知识库', 'Private knowledge bases'),
        shared => kbText(context, '共享知识库', 'Shared knowledge bases'),
        favorites => kbText(context, '最爱知识库', 'Favorite knowledge bases'),
      };

  IconData get icon => switch (this) {
        private => Icons.lock_outline,
        shared => Icons.people_outline,
        favorites => Icons.star_border,
      };

  bool includes(KnowledgeBase base) => switch (this) {
        private => base.visibility == 'private',
        shared => base.visibility == 'shared',
        favorites => base.isFavorite,
      };
}

class KnowledgeBase {
  KnowledgeBase.fromJson(Map<String, dynamic> json)
      : workspaceId = json['workspace_id'] as String,
        name = json['name'] as String,
        visibility = json['visibility'] as String,
        isFavorite = json['is_favorite'] == true,
        canManage = json['can_manage'] == true,
        ready = json['ready'] == true;

  final String workspaceId;
  final String name;
  final String visibility;
  final bool isFavorite;
  final bool canManage;
  final bool ready;
}

class KnowledgeBaseException implements Exception {
  const KnowledgeBaseException(this.status);
  final int status;
}

String kbError(BuildContext context, Object? error) {
  final status = error is KnowledgeBaseException ? error.status : 503;
  return switch (status) {
    401 => kbText(context, '请登录云端账号后使用知识库。', 'Sign in to use knowledge bases.'),
    403 => kbText(
        context,
        '你没有此知识库的访问或管理权限，请刷新列表。',
        'Access denied. Refresh your knowledge bases.',
      ),
    _ => kbText(
        context,
        '知识库暂时无法连接，请稍后重试。',
        'Cannot connect to knowledge bases. Please try again.',
      ),
  };
}

class KnowledgeBaseService {
  KnowledgeBaseService(this.credentials, {http.Client? client})
      : _client = client ?? http.Client();

  factory KnowledgeBaseService.forUser(String userId) => KnowledgeBaseService(
        () async {
          final config = (await UserEventGetCloudConfig().send()).fold(
            (value) => value,
            (error) => throw const KnowledgeBaseException(503),
          );
          final profile =
              (await UserBackendService.getCurrentUserProfile()).fold(
            (value) => value,
            (error) => throw const KnowledgeBaseException(401),
          );
          final token = profile.authorizationAccessToken;
          if (profile.id.toString() != userId || token == null) {
            throw const KnowledgeBaseException(401);
          }
          if (config.serverUrl.isEmpty) {
            throw const KnowledgeBaseException(503);
          }
          return (config.serverUrl, token);
        },
      );

  final Future<(String, String)> Function() credentials;
  final http.Client _client;
  bool _closed = false;

  Future<Map<String, dynamic>> post(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    final (baseUrl, token) = await credentials();
    if (_closed) throw const KnowledgeBaseException(401);
    final response = await _client
        .post(
          Uri.parse(
            '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/knowledge/$action',
          ),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 120));
    if (_closed) throw const KnowledgeBaseException(401);
    if (response.statusCode != 200) {
      throw KnowledgeBaseException(response.statusCode);
    }
    final result =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (result['success'] != true) throw const KnowledgeBaseException(503);
    return result['data'] as Map<String, dynamic>;
  }

  Future<List<KnowledgeBase>> bases() async {
    final data = await post('bases');
    return (data['bases'] as List)
        .map((item) => KnowledgeBase.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  void close() {
    _closed = true;
    _client.close();
  }
}
