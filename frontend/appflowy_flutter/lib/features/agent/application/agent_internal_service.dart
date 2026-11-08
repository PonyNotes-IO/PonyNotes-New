import 'dart:convert';

import 'package:appflowy/features/ai_internal/application/ai_provider_config.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'agent_credits.dart';

class AgentCloudAccount {
  const AgentCloudAccount({
    required this.baseUrl,
    required this.accessToken,
    required this.userId,
  });
  final String baseUrl;
  final String accessToken;
  final String userId;
  String get selectionKey => 'ponynotes.agent.model.$baseUrl|$userId';

  static Future<AgentCloudAccount> current() async {
    if (!getIt.isRegistered<AppFlowyCloudSharedEnv>() ||
        !getIt<AppFlowyCloudSharedEnv>()
            .authenticatorType
            .isAppFlowyCloudEnabled) {
      throw StateError('请先登录后使用内部模型');
    }
    final config = (await UserEventGetCloudConfig().send())
        .fold((value) => value, (error) => throw StateError('请先登录后使用内部模型'));
    final profile = (await UserBackendService.getCurrentUserProfile())
        .fold((value) => value, (error) => throw StateError('请先登录后使用内部模型'));
    var token = profile.token.trim();
    if (token.startsWith('{')) {
      token = (jsonDecode(token) as Map<String, dynamic>)['access_token']
              as String? ??
          '';
    }
    if (config.serverUrl.isEmpty || token.isEmpty) {
      throw StateError('请先登录后使用内部模型');
    }
    return AgentCloudAccount(
      baseUrl: config.serverUrl.replaceAll(RegExp(r'/+$'), ''),
      accessToken: token,
      userId: profile.id.toString(),
    );
  }
}

class AgentInternalService {
  AgentInternalService({
    http.Client? client,
    Future<AgentCloudAccount> Function()? account,
  })  : _client = client,
        _account = account ?? AgentCloudAccount.current;
  final http.Client? _client;
  final Future<AgentCloudAccount> Function() _account;
  DateTime? _expiresAt;
  bool get sessionNeedsRefresh =>
      _expiresAt == null ||
      DateTime.now().add(const Duration(minutes: 5)).isAfter(_expiresAt!);

  Future<Map<String, dynamic>> _request(
    String path, {
    bool post = false,
    AgentCloudAccount? account,
  }) async {
    account ??= await _account();
    final client = _client ?? http.Client();
    try {
      final uri = Uri.parse('${account.baseUrl}/api/ai/agent/$path');
      final headers = {'Authorization': 'Bearer ${account.accessToken}'};
      final pending = post
          ? client.post(uri, headers: headers)
          : client.get(uri, headers: headers);
      final response = await pending.timeout(const Duration(seconds: 90));
      if (response.statusCode != 200) {
        if (response.statusCode == 401) throw StateError('登录已过期，请重新登录后使用内部模型');
        throw StateError(
          response.statusCode == 404
              ? '内部模型服务尚未上线，请联系管理员'
              : utf8.decode(response.bodyBytes),
        );
      }
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (body['code'] != null && body['code'] != 0) {
        throw StateError(
          (body['message'] ?? body['msg']) as String? ?? '内部模型请求失败',
        );
      }
      return body;
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<List<AiProviderConfig>> models({AgentCloudAccount? account}) async {
    final body = await _request('models', account: account);
    return (body['data'] as List)
        .map(
          (dynamic value) => AiProviderConfig(
            modelName: value['id'] as String,
            supportsReasoning: value['supports_reasoning'] == true,
            isInternal: true,
          ),
        )
        .toList();
  }

  Future<AiProviderConfig> preferred({
    List<AiProviderConfig>? available,
  }) async {
    final custom = await const AiProviderConfigStorage().load();
    // Existing custom endpoints keep working without a cloud account.
    AgentCloudAccount account;
    try {
      account = await _account();
    } catch (_) {
      if (custom.isComplete) return custom;
      rethrow;
    }
    final model =
        (await SharedPreferences.getInstance()).getString(account.selectionKey);
    if (model != null) {
      return available
              ?.where((value) => value.modelName == model)
              .firstOrNull ??
          AiProviderConfig(modelName: model, isInternal: true);
    }
    if (custom.isComplete) return custom;
    available ??= await models(account: account);
    if (available.isEmpty) throw StateError('暂无可用内部模型，请联系管理员');
    return available.first;
  }

  Future<void> select(AiProviderConfig config) async {
    if (!config.isInternal) {
      AgentCloudAccount? account;
      try {
        account = await _account();
      } catch (_) {
        // Local custom profiles do not require a cloud login.
      }
      await const AiProviderConfigStorage().save(config);
      if (account != null) {
        await (await SharedPreferences.getInstance())
            .remove(account.selectionKey);
      }
      return;
    }
    final account = await _account();
    await (await SharedPreferences.getInstance())
        .setString(account.selectionKey, config.modelName);
  }

  Future<AiProviderConfig> runtimeConfig(AiProviderConfig model) async {
    if (!model.isInternal) return model;
    final account = await _account();
    final available = await models(account: account);
    final selected =
        available.where((value) => value.modelName == model.modelName);
    if (selected.isEmpty) throw StateError('所选内部模型已不可用，请重新选择');
    final session = await _request('session', post: true, account: account);
    final token = session['token'] as String;
    if (!token.startsWith('pn-agent-')) throw StateError('内部模型会话响应无效');
    _expiresAt =
        DateTime.now().add(Duration(seconds: session['expires_in'] as int));
    return selected.first.copyWith(
      baseUrl: '${account.baseUrl}/api/ai/agent',
      apiKey: token,
    );
  }

  Future<AgentCredits> credits() async {
    final body = await _request('usage');
    final remaining = body['remaining'];
    final rate = body['credits_per_usd'];
    if (body['unit'] != 'USD' ||
        remaining is! num ||
        !remaining.isFinite ||
        rate is! num ||
        !rate.isFinite ||
        rate <= 0) {
      throw const FormatException('内部积分余额响应无效');
    }
    return AgentCredits(
      usd: remaining.toDouble(),
      serverCredits: remaining * rate,
      unlimited: body['unlimited'] == true,
    );
  }

  Future<void> revoke(AiProviderConfig? config) async {
    if (config == null || !config.isInternal || config.apiKey.isEmpty) return;
    final client = _client ?? http.Client();
    try {
      final response = await client.delete(
        Uri.parse('${config.baseUrl}/session'),
        headers: {'Authorization': 'Bearer ${config.apiKey}'},
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 204) throw StateError('内部模型会话撤销失败');
    } finally {
      if (_client == null) client.close();
    }
  }
}
