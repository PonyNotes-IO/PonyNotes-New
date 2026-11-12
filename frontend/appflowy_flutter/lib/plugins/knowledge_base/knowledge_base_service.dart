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
      : id = (json['id'] ?? json['workspace_id']) as String,
        workspaceId = json['workspace_id'] as String,
        name = json['name'] as String,
        visibility = json['visibility'] as String,
        isFavorite = json['is_favorite'] == true,
        canManage = json['can_manage'] == true,
        ready = json['ready'] == true;

  final String id;
  final String workspaceId;
  final String name;
  final String visibility;
  final bool isFavorite;
  final bool canManage;
  final bool ready;

  Map<String, String> get target =>
      {'workspace_id': workspaceId, 'base_id': id};
}

class KnowledgeBaseException implements Exception {
  const KnowledgeBaseException(this.status, {this.action});
  final int status;
  final String? action;
}

String kbError(BuildContext context, Object? error) {
  final status = error is KnowledgeBaseException ? error.status : 503;
  return switch (status) {
    400 when error is KnowledgeBaseException && error.action == 'data_source' =>
      kbText(
        context,
        '数据源操作失败，请检查凭据、资源范围及同步配置。',
        'Check the credentials, resource scope and sync settings.',
      ),
    404 when error is KnowledgeBaseException && error.action == 'data_source' =>
      kbText(
        context,
        '当前服务尚不支持此数据源操作，请联系管理员更新。',
        'This data source operation requires a server update.',
      ),
    409 when error is KnowledgeBaseException && error.action == 'data_source' =>
      kbText(
        context,
        '数据源正在同步或配置已更改，请刷新后重试。',
        'The source is syncing or its settings changed. Refresh and try again.',
      ),
    400 => kbText(
        context,
        '知识库参数无效，请检查后重试。',
        'Check the knowledge base details and try again.',
      ),
    401 => kbText(context, '请登录云端账号后使用知识库。', 'Sign in to use knowledge bases.'),
    403 => kbText(
        context,
        '你没有此知识库的访问或管理权限，请刷新列表。',
        'Access denied. Refresh your knowledge bases.',
      ),
    404 when error is KnowledgeBaseException && error.action == 'create' =>
      kbText(
        context,
        '当前知识库服务尚不支持创建，请联系管理员更新。',
        'Creating knowledge bases requires a server update. Contact your administrator.',
      ),
    404
        when error is KnowledgeBaseException &&
            (error.action == 'web_import_options' ||
                error.action == 'import_url') =>
      kbText(
        context,
        '当前知识库服务尚不支持网页导入，请联系管理员更新。',
        'Importing web pages requires a server update. Contact your administrator.',
      ),
    409 => kbText(
        context,
        '该网页已存在于知识库中。',
        'This web page already exists in the knowledge base.',
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
      throw KnowledgeBaseException(response.statusCode, action: action);
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
