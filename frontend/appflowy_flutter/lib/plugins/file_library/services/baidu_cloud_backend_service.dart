import 'dart:convert';
import 'package:appflowy_backend/log.dart';
import 'package:http/http.dart' as http;

/// Proxy service that calls backend endpoints to perform Baidu Cloud operations.
class BaiduCloudBackendService {
  final String backendBase;

  BaiduCloudBackendService({this.backendBase = '/api/integrations/baidu'});

  /// Request backend to create an authorization URL (or redirect).
  Future<String> getAuthorizationUrl() async {
    try {
      final resp = await http.get(Uri.parse('$backendBase/authorize-url'));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        return data['url'] ?? '';
      }
    } catch (e) {
      Log.error('Failed to get authorization url from backend: $e');
    }
    return '';
  }

  /// Ask backend to exchange code for token and store tokens server-side.
  Future<bool> exchangeCodeForToken(String code) async {
    try {
      final resp = await http.post(
        Uri.parse('$backendBase/exchange'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'code': code}),
      );
      return resp.statusCode == 200;
    } catch (e) {
      Log.error('Failed to exchange code via backend: $e');
      return false;
    }
  }

  /// Migrate local tokens stored in frontend to backend (server-side storage).
  Future<bool> migrateLocalTokens({
    String? accessToken,
    String? refreshToken,
    String? expiresAtIso,
    String? scopes,
    Map<String, dynamic>? meta,
  }) async {
    try {
      final body = json.encode({
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at': expiresAtIso,
        'scopes': scopes,
        'meta': meta ?? {},
      });
      final resp = await http.post(
        Uri.parse('$backendBase/migrate'),
        headers: {'Content-Type': 'application/json'},
        body: body,
      );
      return resp.statusCode == 200;
    } catch (e) {
      Log.error('Failed to migrate tokens via backend: $e');
      return false;
    }
  }

  /// Get file list via backend proxy.
  Future<List<dynamic>> getFileList(String dir) async {
    try {
      final resp = await http.get(Uri.parse('$backendBase/files?dir=${Uri.encodeComponent(dir)}'));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        return data['files'] as List<dynamic>;
      }
    } catch (e) {
      Log.error('Failed to get file list from backend: $e');
    }
    return [];
  }

  /// Ask backend for a download link or stream proxy.
  Future<String?> getFileDownloadUrl(String fsId) async {
    try {
      final resp = await http.get(Uri.parse('$backendBase/download?fsId=${Uri.encodeComponent(fsId)}'));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        return data['downloadUrl'] as String?;
      }
    } catch (e) {
      Log.error('Failed to get download url from backend: $e');
    }
    return null;
  }
}


