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

class McpClientConnection {
  const McpClientConnection({
    required this.name,
    this.firstConnectedAt,
    this.lastUsedAt,
  });

  factory McpClientConnection.fromJson(Map<String, dynamic> json) =>
      McpClientConnection(
        name: json['name'] as String,
        firstConnectedAt:
            DateTime.tryParse(json['firstConnectedAt'] as String? ?? ''),
        lastUsedAt: DateTime.tryParse(json['lastUsedAt'] as String? ?? ''),
      );

  final String name;
  final DateTime? firstConnectedAt;
  final DateTime? lastUsedAt;

  Map<String, dynamic> toJson() => {
        'name': name,
        'firstConnectedAt': firstConnectedAt?.toIso8601String(),
        'lastUsedAt': lastUsedAt?.toIso8601String(),
      };
}

/// 本地 MCP Server：生命周期、Bearer Token 鉴权与工具注册。
///
/// 只绑定回环地址；Token 只保存 SHA-256 摘要，并绑定生成时的账号，
/// 切换账号或重置 Token 后旧凭据失效。
class McpServerService extends ChangeNotifier {
  McpServerService._() {
    McpAuditLog.instance.addListener(_updateClientUsage);
  }

  static final McpServerService instance = McpServerService._();

  static const int port = 27861;
  static const String path = '/mcp';
  static const String version = '0.6.9';

  static const String _prefsEnabled = 'mcp_server_enabled';
  static const String _prefsTokenHash = 'mcp_token_hash';
  static const String _prefsTokenPlain = 'mcp_token_plain';
  static const String _prefsTokenUserId = 'mcp_token_user_id';
  static const String _prefsTokenBackend = 'mcp_token_backend';
  static const String _prefsClients = 'mcp_clients';
  static const int _maxRequestBytes = 1024 * 1024;

  StreamableMcpServer? _server;
  String? _tokenHash;
  String? _tokenPlain;

  // ponytail: 同名客户端合并展示；需要区分设备时再增加客户端实例标识。
  final _clients = <String, McpClientConnection>{};
  final _sessions = <McpServer, String>{};
  final _onlineSessions = <McpServer>{};
  final _statelessLastSeen = <String, DateTime>{};
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

  List<McpClientConnection> get clients {
    final clients = _clients.values.toList();
    clients.sort(
      (a, b) => (b.lastUsedAt ?? b.firstConnectedAt ?? DateTime(0))
          .compareTo(a.lastUsedAt ?? a.firstConnectedAt ?? DateTime(0)),
    );
    return clients;
  }

  McpClientConnection? client(String name) => _clients[name];

  bool isClientOnline(String name) =>
      _onlineSessions.any((server) => _sessions[server] == name) ||
      (_statelessLastSeen[name] != null &&
          DateTime.now().difference(_statelessLastSeen[name]!) <
              const Duration(minutes: 1));

  bool isStatelessClient(String name) =>
      _statelessLastSeen.containsKey(name) && !_sessions.containsValue(name);

  /// MCP 会话可能在客户端意外退出后仍存在，使用协议 ping 检查存活。
  Future<void> refreshClientStatus(String name) async {
    final sessions = _sessions.entries.where((e) => e.value == name).toList();
    await Future.wait(
      sessions.map((entry) async {
        var online = false;
        try {
          await entry.key.server.ping(
            const RequestOptions(timeout: Duration(seconds: 3)),
          );
          online = true;
        } catch (_) {
          // 保留会话，允许临时超时的客户端在下次检测时恢复。
        }
        if (_sessions[entry.key] != name) return;
        if (online) {
          _onlineSessions.add(entry.key);
        } else {
          _onlineSessions.remove(entry.key);
        }
      }),
    );
    notifyListeners();
  }

  /// 启动时恢复上次的开关状态与 Token。
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    _tokenHash = prefs.getString(_prefsTokenHash);
    _tokenPlain = prefs.getString(_prefsTokenPlain);
    _tokenUserId = prefs.getString(_prefsTokenUserId);
    _tokenBackend = prefs.getString(_prefsTokenBackend);
    await McpPermissions.instance.load();
    _clients.clear();
    try {
      final stored = jsonDecode(prefs.getString(_prefsClients) ?? '[]') as List;
      for (final json in stored) {
        final client =
            McpClientConnection.fromJson(json as Map<String, dynamic>);
        _clients[client.name] = client;
      }
    } catch (e) {
      Log.warn('[MCP] client history load failed: $e');
    }
    await McpAuditLog.instance.load();
    _updateClientUsage();
    notifyListeners();
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
    _sessions.clear();
    _onlineSessions.clear();
    _statelessLastSeen.clear();
    notifyListeners();
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
    _sessions.clear();
    _onlineSessions.clear();
    _statelessLastSeen.clear();
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
    String? requestAgent;
    final server = _McpTrackedServer(
      const Implementation(name: 'ponynotes-mcp', version: version),
      onRequest: (request) {
        final protocol = request.meta?[McpMetaKey.protocolVersion];
        if (protocol is! String || !isStatelessProtocolVersion(protocol)) {
          return;
        }
        final info = request.meta?[McpMetaKey.clientInfo] as Map?;
        final name = (info?['name'] as String?)?.trim() ?? '';
        requestAgent = name.isEmpty ? '未识别客户端' : name;
        final now = DateTime.now();
        _statelessLastSeen[requestAgent!] = now;
        final isNew = !_clients.containsKey(requestAgent);
        _clients.putIfAbsent(
          requestAgent!,
          () => McpClientConnection(name: requestAgent!, firstConnectedAt: now),
        );
        notifyListeners();
        if (isNew) unawaited(_persistClients());
      },
      options: const McpServerOptions(
        capabilities: ServerCapabilities(
          tools: ServerCapabilitiesTools(),
        ),
      ),
    );
    String agentName() {
      final name =
          server.server.getClientVersion()?.name.trim() ?? requestAgent ?? '';
      return name.isEmpty ? '未识别客户端' : name;
    }

    server.server.oninitialized = () {
      final name = agentName();
      _sessions[server] = name;
      _onlineSessions.add(server);
      _clients.putIfAbsent(
        name,
        () => McpClientConnection(name: name, firstConnectedAt: DateTime.now()),
      );
      notifyListeners();
      unawaited(_persistClients());
    };
    server.server.onclose = () {
      _sessions.remove(server);
      _onlineSessions.remove(server);
      notifyListeners();
    };
    McpTools(
      endpoint: endpoint,
      version: version,
      isAgentChannel: true,
      agentName: agentName,
    ).registerAll(server);
    return server;
  }

  void _updateClientUsage() {
    var changed = false;
    for (final entry in McpAuditLog.instance.entries) {
      final name = entry.agent.trim();
      if (name.isEmpty) continue;
      final previous = _clients[name];
      if (previous?.lastUsedAt != null &&
          !entry.at.isAfter(previous!.lastUsedAt!)) {
        continue;
      }
      // 历史日志无法还原首次握手时间，未知值保留为空。
      _clients[name] = McpClientConnection(
        name: name,
        firstConnectedAt: previous?.firstConnectedAt,
        lastUsedAt: entry.at,
      );
      changed = true;
    }
    if (!changed) return;
    notifyListeners();
    unawaited(_persistClients());
  }

  Future<void> _persistClients() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsClients,
        jsonEncode(_clients.values.map((client) => client.toJson()).toList()),
      );
    } catch (e) {
      Log.warn('[MCP] client history save failed: $e');
    }
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

/// 保留 SDK 的传输和校验，仅观察请求以记录无会话客户端的首次访问。
class _McpTrackedServer extends McpServer {
  _McpTrackedServer(super.serverInfo, {super.options, required this.onRequest});

  final void Function(JsonRpcRequest) onRequest;

  @override
  Future<void> connect(Transport transport) {
    // SDK 在启动传输前同步安装消息回调，保留该回调继续处理协议。
    final connected = super.connect(transport);
    final handleMessage = transport.onmessage;
    transport.onmessage = (message) {
      try {
        if (message is JsonRpcRequest &&
            server.validateIncomingRequest(message) == null) {
          onRequest(message);
        }
      } catch (e) {
        Log.warn('[MCP] client tracking failed: $e');
      }
      handleMessage?.call(message);
    };
    return connected;
  }
}
