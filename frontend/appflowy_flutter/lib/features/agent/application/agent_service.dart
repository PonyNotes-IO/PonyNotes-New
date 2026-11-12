import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'agent_internal_service.dart';
import 'agent_reference.dart';

/// Cloud scopes requests; WeKnora runs the tool loop.
class AgentService {
  AgentService({
    http.Client? client,
    Future<AgentCloudAccount> Function()? account,
  })  : _client = client,
        _account = account ?? AgentCloudAccount.current;
  final http.Client? _client;
  final Future<AgentCloudAccount> Function() _account;
  http.Client? _streamClient;

  Future<List<AgentReference>> references(String workspace) async {
    final before = await identity(workspace);
    final data = await request('GET', workspace, '', '/references');
    if (before != await identity(workspace)) {
      throw StateError('账号已切换，请重新选择引用');
    }
    return (data['items'] as List)
        .map((item) => AgentReference.fromJson(item as Map))
        .toList();
  }

  Future<String> uploadArtifact(
    String identity,
    String workspace,
    File file,
    String name,
  ) async {
    final account = await _account();
    if ('${account.baseUrl}|${account.userId}|$workspace' != identity) {
      throw StateError('账号或工作区已切换');
    }
    final uri = Uri.parse(
      '${account.baseUrl}/api/file_storage/${Uri.encodeComponent(workspace)}/blob/${Uri.encodeComponent(name)}',
    );
    final request = http.StreamedRequest('PUT', uri)
      ..followRedirects = false
      ..contentLength = await file.length()
      ..headers.addAll({
        'Authorization': 'Bearer ${account.accessToken}',
        'Content-Type': 'application/octet-stream',
      });
    final client = _client ?? http.Client();
    try {
      final pending = client.send(request);
      await request.sink
          .addStream(file.openRead())
          .timeout(const Duration(seconds: 600));
      await request.sink.close();
      final response = await http.Response.fromStream(await pending)
          .timeout(const Duration(seconds: 600));
      _checkStatus(response.statusCode, utf8.decode(response.bodyBytes));
      final result = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
      if (result['code'] != null && result['code'] != 0) {
        throw StateError('${result['message'] ?? result['msg'] ?? '云同步失败'}');
      }
      return uri.toString();
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<void> downloadArtifact(
    String identity,
    String workspace,
    String document,
    String message,
    int index,
    File destination,
  ) async {
    final request = await _request(
      'GET',
      workspace,
      document,
      '/messages/${Uri.encodeComponent(message)}/artifacts/$index',
      null,
      identity,
    );
    await _download(request, destination);
  }

  Future<void> downloadCloudArtifact(
    String identity,
    String workspace,
    String url,
    File destination,
  ) async {
    final account = await _account();
    final base = Uri.parse(account.baseUrl);
    final uri = Uri.parse(url);
    if ('${account.baseUrl}|${account.userId}|$workspace' != identity ||
        uri.origin != base.origin ||
        !uri.path.startsWith(
          '${base.path}/api/file_storage/${Uri.encodeComponent(workspace)}/blob/',
        ) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw StateError('云端产物不属于当前工作区');
    }
    final request = http.Request('GET', uri)
      ..followRedirects = false
      ..headers['Authorization'] = 'Bearer ${account.accessToken}';
    await _download(request, destination);
  }

  Future<void> _download(http.Request request, File destination) async {
    final client = _client ?? http.Client();
    final sink = destination.openWrite();
    try {
      final response =
          await client.send(request).timeout(const Duration(seconds: 90));
      if (response.statusCode != 200) {
        _checkStatus(
          response.statusCode,
          await response.stream.bytesToString(),
        );
      }
      await sink
          .addStream(response.stream.timeout(const Duration(seconds: 90)));
      await sink.flush();
    } finally {
      await sink.close();
      if (_client == null) client.close();
    }
  }

  Future<String> identity(String workspace) async {
    final account = await _account();
    return '${account.baseUrl}|${account.userId}|$workspace';
  }

  Future<http.Request> _request(
    String method,
    String workspace,
    String document,
    String suffix, [
    Map<String, dynamic>? body,
    String? expectedIdentity,
  ]) async {
    final account = await _account();
    if (expectedIdentity != null &&
        expectedIdentity != '${account.baseUrl}|${account.userId}|$workspace') {
      throw StateError('账号或工作区已切换');
    }
    final request = http.Request(
      method,
      Uri.parse(
        '${account.baseUrl}/api/ai/agent/conversations/${Uri.encodeComponent(workspace)}${document.isEmpty ? '' : '/${Uri.encodeComponent(document)}'}$suffix',
      ),
    );
    request.followRedirects = false;
    request.headers['Authorization'] = 'Bearer ${account.accessToken}';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    return request;
  }

  Future<Map<String, dynamic>> request(
    String method,
    String workspace,
    String document,
    String suffix, [
    Map<String, dynamic>? body,
  ]) async {
    final request = await _request(method, workspace, document, suffix, body);
    final client = _client ?? http.Client();
    try {
      final response =
          await http.Response.fromStream(await client.send(request))
              .timeout(const Duration(seconds: 90));
      _checkStatus(response.statusCode, utf8.decode(response.bodyBytes));
      if (response.statusCode == 204) return {};
      return Map<String, dynamic>.from(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map,
      );
    } finally {
      if (_client == null) client.close();
    }
  }

  Stream<Map<String, dynamic>> stream(
    String method,
    String workspace,
    String document,
    String suffix, [
    Map<String, dynamic>? body,
  ]) async* {
    final request = await _request(method, workspace, document, suffix, body);
    request.headers['Accept'] = 'text/event-stream';
    final client = _client ?? http.Client();
    _streamClient = client;
    try {
      final response =
          await client.send(request).timeout(const Duration(seconds: 90));
      if (response.statusCode != 200) {
        _checkStatus(
          response.statusCode,
          await response.stream.bytesToString(),
        );
      }
      if (!(response.headers['content-type'] ?? '')
          .startsWith('text/event-stream')) {
        throw StateError('知识助手返回了无效的事件流');
      }
      yield* decodeEvents(response.stream);
    } finally {
      if (identical(_streamClient, client)) _streamClient = null;
      if (_client == null) client.close();
    }
  }

  static void _checkStatus(int status, String body) {
    if (status >= 200 && status < 300) return;
    if (status == 401) throw StateError('登录已过期，请重新登录');
    if (status == 403) throw StateError('无权访问此工作区或笔记');
    if (status == 404) throw StateError('知识助手服务或会话尚未就绪');
    throw StateError(body.isEmpty ? '知识助手请求失败（$status）' : body);
  }

  static Stream<Map<String, dynamic>> decodeEvents(
    Stream<List<int>> bytes,
  ) async* {
    final data = <String>[];
    var size = 0;
    await for (final line
        in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.isEmpty) {
        if (data.isNotEmpty) {
          final payload = data.join('\n');
          if (payload != '[DONE]') {
            yield Map<String, dynamic>.from(jsonDecode(payload) as Map);
          }
          data.clear();
          size = 0;
        }
      } else if (line.startsWith('data:')) {
        final value = line.substring(5).replaceFirst(RegExp('^ '), '');
        size += value.length;
        if (size > 4 * 1024 * 1024) throw const FormatException('知识助手事件过大');
        data.add(value);
      }
    }
    if (data.isNotEmpty && data.join('\n') != '[DONE]') {
      yield Map<String, dynamic>.from(jsonDecode(data.join('\n')) as Map);
    }
  }

  void closeStream() {
    if (_client == null) _streamClient?.close();
    _streamClient = null;
  }
}
