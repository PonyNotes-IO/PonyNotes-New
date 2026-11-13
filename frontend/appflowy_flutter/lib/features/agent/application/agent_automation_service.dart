import 'dart:convert';

import 'package:http/http.dart' as http;

import 'agent_automation.dart';
import 'agent_internal_service.dart';

/// Thin client for the Cloud automation proxy. Cloud owns the WeKnora session
/// and the model credentials, so the client only ever sees workspace-scoped
/// automation records.
class AgentAutomationService {
  AgentAutomationService({
    http.Client? client,
    Future<AgentCloudAccount> Function()? account,
  })  : _client = client,
        _account = account ?? AgentCloudAccount.current;

  final http.Client? _client;
  final Future<AgentCloudAccount> Function() _account;

  Future<List<AgentAutomation>> list(String workspace) async {
    final data = await _send('GET', workspace, '');
    final items = data['automations'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map(AgentAutomation.fromJson)
        .toList(growable: false);
  }

  Future<AgentAutomation> detail(String workspace, String id) async {
    final data = await _send('GET', workspace, '/${Uri.encodeComponent(id)}');
    return AgentAutomation.fromJson(Map.from(data['automation'] as Map));
  }

  Future<AgentAutomation> create(
    String workspace,
    Map<String, dynamic> body,
  ) async {
    final data = await _send('POST', workspace, '', body);
    return AgentAutomation.fromJson(Map.from(data['automation'] as Map));
  }

  Future<AgentAutomation> update(
    String workspace,
    String id,
    Map<String, dynamic> body,
  ) async {
    final data = await _send(
      'PUT',
      workspace,
      '/${Uri.encodeComponent(id)}',
      body,
    );
    return AgentAutomation.fromJson(Map.from(data['automation'] as Map));
  }

  Future<void> remove(String workspace, String id) =>
      _send('DELETE', workspace, '/${Uri.encodeComponent(id)}');

  /// Pause, resume and "run now" all return upstream envelopes whose shape
  /// differs per action; callers reload the list instead of reading them.
  Future<void> control(String workspace, String id, String action) async {
    await _send('POST', workspace, '/${Uri.encodeComponent(id)}/$action');
  }

  Future<List<AgentAutomationRun>> runs(
    String workspace,
    String id, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final data = await _send(
      'GET',
      workspace,
      '/${Uri.encodeComponent(id)}/runs?page=$page&page_size=$pageSize',
    );
    final items = data['runs'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map(AgentAutomationRun.fromJson)
        .toList(growable: false);
  }

  Future<void> cancelRun(String workspace, String runId) => _send(
        'POST',
        workspace,
        '/runs/${Uri.encodeComponent(runId)}/cancel',
      );

  /// Returns the next three scheduled times, already rendered by WeKnora.
  Future<List<String>> validateTrigger(
    String workspace,
    Map<String, dynamic> trigger,
  ) async {
    final data = await _send(
      'POST',
      workspace,
      '/validate-trigger',
      {'trigger': trigger},
    );
    final items = data['next_runs'];
    if (items is! List) return const [];
    return items.whereType<String>().toList(growable: false);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String workspace,
    String suffix, [
    Map<String, dynamic>? body,
  ]) async {
    final account = await _account();
    final base = account.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse(
      '$base/api/ai/agent/automations/${Uri.encodeComponent(workspace)}$suffix',
    );
    final request = http.Request(method, uri)..followRedirects = false;
    request.headers['Authorization'] = 'Bearer ${account.accessToken}';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final client = _client ?? http.Client();
    try {
      final response = await http.Response.fromStream(await client.send(request))
          .timeout(const Duration(seconds: 60));
      final text = utf8.decode(response.bodyBytes);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _fail(response.statusCode, text);
      }
      if (response.statusCode == 204 || text.trim().isEmpty) {
        return const {};
      }
      return Map<String, dynamic>.from(jsonDecode(text) as Map);
    } finally {
      if (_client == null) client.close();
    }
  }

  static Never _fail(int status, String body) {
    if (status == 401) throw StateError('登录已过期，请重新登录');
    if (status == 403) throw StateError('无权访问此工作区');
    var message = body.trim();
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final value = decoded['message'] ?? decoded['error'];
        if (value != null) message = value.toString();
      }
    } catch (_) {
      // Non-JSON error bodies are already readable enough.
    }
    throw StateError(
      message.isEmpty ? '自动化请求失败（$status）' : message,
    );
  }
}
