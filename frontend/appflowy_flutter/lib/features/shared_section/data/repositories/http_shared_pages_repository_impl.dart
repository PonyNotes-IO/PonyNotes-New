import 'dart:convert';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/features/share_tab/data/collab_view_mapper.dart';
import 'package:appflowy/features/share_tab/data/models/share_access_level.dart';
import 'package:appflowy/features/shared_section/data/repositories/shared_pages_repository.dart';
import 'package:appflowy/features/shared_section/data/repositories/rust_shared_pages_repository_impl.dart';
import 'package:appflowy/features/shared_section/models/shared_page.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:http/http.dart' as http;

/// Uses the same sent + received endpoints as the desktop shared section.
class HttpSharedPagesRepositoryImpl implements SharedPagesRepository {
  @override
  Future<FlowyResult<SharedPages, FlowyError>> getSharedPages() async {
    try {
      final profile = await UserBackendService.getCurrentUserProfile();
      final user = profile.fold((value) => value, (error) => throw error);
      final token = _accessToken(user.token);
      if (token == null) {
        return FlowyResult.failure(FlowyError(msg: 'Access token is empty'));
      }

      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url.isNotEmpty
          ? cloudEnv.appflowyCloudConfig.base_url
          : 'http://localhost:8000';
      final combined = <String, SharedCollabView>{};
      var successfulResponses = 0;
      for (final path in const [
        '/api/collab/me/sent',
        '/api/collab/me/received',
      ]) {
        final response = await http.get(
          Uri.parse(baseUrl).replace(path: path),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ).timeout(const Duration(seconds: 10));
        if (response.statusCode == 404) continue;
        if (response.statusCode != 200) continue;
        successfulResponses++;
        for (final entry in _parse(response.body)) {
          combined.putIfAbsent(entry.view.id, () => entry);
        }
      }

      if (successfulResponses == 0) {
        return RustSharePagesRepositoryImpl().getSharedPages();
      }

      final pages = combined.values
          .map(
            (entry) => SharedPage(
              view: entry.view,
              accessLevel: ShareAccessLevel.readOnly,
            ),
          )
          .toList()
        ..sort((a, b) => b.view.createTime.compareTo(a.view.createTime));
      return FlowyResult.success(pages);
    } catch (error) {
      return FlowyResult.failure(FlowyError(msg: '$error'));
    }
  }

  String? _accessToken(String token) {
    final value = token.trim();
    if (value.isEmpty) return null;
    if (!value.startsWith('{')) return value;
    final decoded = jsonDecode(value);
    return (decoded as Map<String, dynamic>)['access_token'] as String?;
  }

  List<SharedCollabView> _parse(String body) {
    final decoded = jsonDecode(body);
    final dynamic data =
        decoded is Map<String, dynamic> ? decoded['data'] : decoded;
    final items = data is List<dynamic>
        ? data
        : data is Map<String, dynamic>
            ? data['items'] as List<dynamic>? ?? const []
            : const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(sharedCollabViewFromJson)
        .whereType<SharedCollabView>()
        .toList();
  }

  @override
  Future<FlowyResult<void, FlowyError>> leaveSharedPage(String pageId) {
    return RustSharePagesRepositoryImpl().leaveSharedPage(pageId);
  }
}
