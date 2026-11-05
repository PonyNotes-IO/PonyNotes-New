import 'dart:convert';

import 'package:appflowy/features/ai_internal/application/ai_provider_config.dart';
import 'package:http/http.dart' as http;

/// shortcut: fixed client-side rate until the Agent subscription is decided; move to the server with the plan.
const creditsPerUsd =
    int.fromEnvironment('PONYNOTES_CREDITS_PER_USD', defaultValue: 100);

class AgentCredits {
  const AgentCredits({required this.usd});
  final double usd;
  int get credits => (usd * creditsPerUsd).floor();
}

/// Reads the gateway balance for the configured key. Returns null when the
/// model endpoint is not a credit gateway (plain OpenAI-compatible services have no /v1/usage).
Future<AgentCredits?> fetchAgentCredits(
  AiProviderConfig config, {
  http.Client? client,
}) async {
  if (!config.isComplete) return null;
  final base = Uri.tryParse(
    config.baseUrl
        .trim()
        .replaceAll(RegExp(r'/+$'), '')
        .replaceFirst(RegExp(r'/chat/completions$'), '')
        .replaceFirst(RegExp(r'/v1$'), ''),
  );
  if (base == null || !{'http', 'https'}.contains(base.scheme)) return null;
  final owned = client == null;
  final http.Client c = client ?? http.Client();
  try {
    final response = await c.get(
      base.replace(path: '${base.path}/v1/usage'),
      headers: {'Authorization': 'Bearer ${config.apiKey.trim()}'},
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is! Map || body['unit'] != 'USD') return null;
    final usd = body['balance'] ?? body['remaining'];
    return usd is num ? AgentCredits(usd: usd.toDouble()) : null;
  } catch (_) {
    // Balance display is advisory; the gateway still enforces it on every request.
    return null;
  } finally {
    if (owned) c.close();
  }
}

/// Gateway error codes become plain-language messages; anything else is passed through.
String friendlyModelError(String raw) {
  if (raw.contains('INSUFFICIENT_BALANCE') ||
      raw.contains('insufficient_quota') ||
      raw.contains('API_KEY_QUOTA_EXHAUSTED')) {
    return '积分不足，充值后可继续使用 Agent。';
  }
  if (raw.contains('USAGE_LIMIT_EXCEEDED')) {
    return '已达到当前周期的使用上限，请稍后再试。';
  }
  if (raw.contains('INVALID_API_KEY') ||
      raw.contains('API_KEY_DISABLED') ||
      raw.contains('API_KEY_EXPIRED') ||
      raw.contains('USER_INACTIVE')) {
    return 'AI 额度凭证无效或已停用，请检查模型配置中的 API Key。';
  }
  return raw;
}
