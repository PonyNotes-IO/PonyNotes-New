import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/features/mcp/application/mcp_audit_log.dart';
import 'package:appflowy/features/mcp/application/mcp_permissions.dart';
import 'package:appflowy/features/mcp/application/mcp_tools.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地 MCP Server：生命周期、Bearer Token 鉴权与工具注册。
///
/// 只绑定回环地址；Token 只保存 SHA-256 摘要，并绑定生成时的账号，
/// 切换账号或重置 Token 后旧凭据失效。
class McpServerService extends ChangeNotifier {
  McpServerService._();

  static final McpServerService instance = McpServerService._();

  static const int port = 27861;
  static const String path = '/mcp';
  static const String version = '0.6.8';

  static const String _prefsEnabled = 'mcp_server_enabled';
  static const String _prefsTokenHash = 'mcp_token_hash';
  static const String _prefsTokenPlain = 'mcp_token_plain';
  static const String _prefsTokenUserId = 'mcp_token_user_id';
  static const String _prefsTokenBackend = 'mcp_token_backend';
  static const int _maxRequestBytes = 1024 * 1024;

  StreamableMcpServer? _server;
  String? _tokenHash;
  String? _tokenPlain;

  /// 最近一次鉴权请求的 User-Agent，用来在审计日志里标识调用方。
  String? _lastAgentUserAgent;
  String? _tokenUserId;
  String? _tokenBackend;
  String? _lastError;
  bool _starting = false;

  bool get isRunning => _server != null;
  bool get isStarting => _starting;
  bool get hasToken => _tokenHash != null;

  /// 明文 Token，用于在设置页展示和复制 Agent 配置。
  ///
  /// 只存在本机 SharedPreferences；鉴权仍按 SHA-256 摘要比对。
  String? get token => _tokenPlain;
  String? get lastError => _lastError;
  String get endpoint => 'http://127.0.0.1:$port$path';

  /// 启动时恢复上次的开关状态与 Token。
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    _tokenHash = prefs.getString(_prefsTokenHash);
    _tokenPlain = prefs.getString(_prefsTokenPlain);
    _tokenUserId = prefs.getString(_prefsTokenUserId);
    _tokenBackend = prefs.getString(_prefsTokenBackend);
    await McpPermissions.instance.load();
    await McpAuditLog.instance.load();
    if (prefs.getBool(_prefsEnabled) != true) return;
    if (_tokenHash == null) return;
    await start();
  }

  Future<void> start() async {
    if (_server != null || _starting) return;
    _starting = true;
    _lastError = null;
    notifyListeners();
    try {
      final server = StreamableMcpServer(
        serverFactory: (_) => _createMcpServer(),
        host: '127.0.0.1',
        port: port,
        // 与 endpoint 展示保持一致，避免依赖 SDK 默认值
        // ignore: avoid_redundant_argument_values
        path: path,
        authenticator: _authenticate,
        allowedHosts: const {'127.0.0.1', 'localhost'},
      );
      await server.start();
      _server = server;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsEnabled, true);
      Log.info('[MCP] server started at $endpoint');
    } on SocketException catch (e) {
      _lastError = '端口 $port 已被占用，请关闭占用该端口的程序后重试。(${e.message})';
      Log.error('[MCP] failed to bind $endpoint: $e');
    } catch (e, st) {
      _lastError = '启动失败：$e';
      Log.error('[MCP] failed to start: $e\n$st');
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.stop();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsEnabled, false);
    Log.info('[MCP] server stopped');
    notifyListeners();
  }

  /// 应用退出/重启时停止服务，但不改变用户的开关键状态。
  Future<void> shutdown() async {
    final server = _server;
    _server = null;
    await server?.stop();
    notifyListeners();
  }

  /// 生成新 Token，返回明文（仅此一次）。旧 Token 立即失效。
  Future<String> generateToken() async {
    final profile = await _currentProfile();
    if (profile == null) {
      throw StateError('请先登录账号');
    }
    final random = Random.secure();
    final token = base64UrlEncode(
      List<int>.generate(32, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
    _tokenHash = hashToken(token);
    _tokenPlain = token;
    _tokenUserId = profile.id.toString();
    _tokenBackend = _currentBackend();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsTokenHash, _tokenHash!);
    await prefs.setString(_prefsTokenPlain, token);
    await prefs.setString(_prefsTokenUserId, _tokenUserId!);
    if (_tokenBackend != null) {
      await prefs.setString(_prefsTokenBackend, _tokenBackend!);
    } else {
      await prefs.remove(_prefsTokenBackend);
    }
    Log.info('[MCP] token generated for user ${profile.id}');
    notifyListeners();
    return token;
  }

  /// 撤销授权：停止服务并清除 Token，退出账号时调用。
  Future<void> revoke() async {
    await stop();
    _tokenHash = null;
    _tokenPlain = null;
    _tokenUserId = null;
    _tokenBackend = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsTokenHash);
    await prefs.remove(_prefsTokenPlain);
    await prefs.remove(_prefsTokenUserId);
    await prefs.remove(_prefsTokenBackend);
    Log.info('[MCP] authorization revoked');
    notifyListeners();
  }

  /// 重置 Token：关闭现有连接，签发新 Token；服务原本在运行则自动重启。
  Future<String> resetToken() async {
    final wasRunning = isRunning;
    if (wasRunning) {
      await stop();
    }
    final token = await generateToken();
    if (wasRunning) {
      await start();
    }
    return token;
  }

  Future<bool> _authenticate(dynamic rawRequest) async {
    final request = rawRequest as HttpRequest;
    if (request.contentLength > _maxRequestBytes) {
      Log.warn(
        '[MCP] rejected oversized request: ${request.contentLength} bytes',
      );
      return false;
    }
    final userAgent = request.headers.value(HttpHeaders.userAgentHeader);
    if (userAgent != null && userAgent.trim().isNotEmpty) {
      _lastAgentUserAgent = userAgent.trim();
    }
    final header = request.headers.value(HttpHeaders.authorizationHeader);
    final expected = _tokenHash;
    if (header == null || expected == null) return false;
    if (!header.startsWith('Bearer ')) return false;
    final presented = header.substring(7).trim();
    if (presented.isEmpty) return false;
    if (!constantTimeEquals(hashToken(presented), expected)) return false;
    final backend = _currentBackend();
    if (_tokenBackend != null && backend != null && backend != _tokenBackend) {
      return false;
    }
    final profile = await _currentProfile();
    return profile != null && profile.id.toString() == _tokenUserId;
  }

  /// 当前后端地址，用于让 Token 在切换后端环境后失效。
  String? _currentBackend() {
    try {
      if (!getIt.isRegistered<AppFlowyCloudSharedEnv>()) return null;
      final base = getIt<AppFlowyCloudSharedEnv>().appflowyCloudConfig.base_url;
      return base.trim().isEmpty ? 'local' : base.trim();
    } catch (_) {
      return null;
    }
  }

  /// 不带 Token 探测本地端点，确认服务可达且鉴权生效。
  Future<String?> probe() async {
    if (!isRunning) return '服务未运行';
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(endpoint));
      request.headers.contentType = ContentType.json;
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/json, text/event-stream',
      );
      request
          .write('{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}');
      final response =
          await request.close().timeout(const Duration(seconds: 5));
      await response.drain<void>();
      if (response.statusCode == HttpStatus.forbidden ||
          response.statusCode == HttpStatus.unauthorized) {
        return null;
      }
      return '服务可达，但鉴权返回了意外的状态码 ${response.statusCode}';
    } on TimeoutException {
      return '自检超时';
    } catch (e) {
      return '自检失败：$e';
    } finally {
      client.close(force: true);
    }
  }

  @visibleForTesting
  McpServer buildServer() => _createMcpServer();

  McpServer _createMcpServer() {
    final server = McpServer(
      const Implementation(name: 'ponynotes-mcp', version: version),
      options: const McpServerOptions(
        capabilities: ServerCapabilities(
          tools: ServerCapabilitiesTools(),
        ),
      ),
    );
    McpTools(
      endpoint: endpoint,
      version: version,
      isAgentChannel: true,
      agentName: () => _lastAgentUserAgent ?? '',
    ).registerAll(server);
    return server;
  }

  Future<UserProfilePB?> _currentProfile() async {
    final result = await UserBackendService.getCurrentUserProfile();
    return result.fold((profile) => profile, (_) => null);
  }

  @visibleForTesting
  static String hashToken(String token) =>
      sha256.convert(utf8.encode(token)).toString();

  @visibleForTesting
  static bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
