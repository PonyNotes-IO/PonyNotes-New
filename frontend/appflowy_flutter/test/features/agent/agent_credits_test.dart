import 'package:appflowy/features/agent/application/agent_credits.dart';
import 'package:appflowy/features/ai_internal/application/ai_provider_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const config = AiProviderConfig(
    baseUrl: 'http://gateway.test/v1',
    modelName: 'm',
    apiKey: 'sk-test',
  );

  test('credit labels keep two decimals without dropping fractional usage', () {
    expect(const AgentCredits(usd: 1).label, '100.00 积分');
    expect(const AgentCredits(usd: 0).label, '0.00 积分');
    expect(const AgentCredits(usd: 0.99735828).label, '99.74 积分');
    expect(const AgentCredits(usd: 0.0001).credits, greaterThan(0));
    expect(const AgentCredits(usd: -1, unlimited: true).label, '积分不限额');
  });

  test('gateway USD balance maps to credits with the fixed rate', () async {
    Uri? called;
    String? auth;
    final client = MockClient((request) async {
      called = request.url;
      auth = request.headers['Authorization'];
      return http.Response(
        '{"mode":"unrestricted","unit":"USD","balance":10,"remaining":10}',
        200,
      );
    });
    final credits = await fetchAgentCredits(config, client: client);
    expect(called.toString(), 'http://gateway.test/v1/usage');
    expect(auth, 'Bearer sk-test');
    expect(credits!.usd, 10);
    expect(credits.credits, 10 * creditsPerUsd);
  });

  test('endpoints without a credit balance show nothing', () async {
    final notFound = MockClient((_) async => http.Response('nope', 404));
    expect(await fetchAgentCredits(config, client: notFound), isNull);
    final other = MockClient((_) async => http.Response('{"object":"x"}', 200));
    expect(await fetchAgentCredits(config, client: other), isNull);
    expect(await fetchAgentCredits(const AiProviderConfig()), isNull);
  });

  test('gateway model list is read with the configured key', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'http://gateway.test/v1/models');
      return http.Response(
        '{"object":"list","data":[{"id":"deepseek-flash"},{"id":"deepseek-v4-pro"}]}',
        200,
      );
    });
    expect(
      await fetchGatewayModels(config, client: client),
      ['deepseek-flash', 'deepseek-v4-pro'],
    );
    final denied = MockClient((_) async => http.Response('{}', 401));
    expect(await fetchGatewayModels(config, client: denied), isEmpty);
  });

  test('gateway errors become readable messages', () {
    expect(
      friendlyModelError(
        '403 {"code":"INSUFFICIENT_BALANCE","message":"Insufficient account balance"}',
      ),
      contains('积分不足'),
    );
    expect(friendlyModelError('429 insufficient_quota'), contains('积分不足'));
    expect(friendlyModelError('USAGE_LIMIT_EXCEEDED'), contains('使用上限'));
    expect(friendlyModelError('401 INVALID_API_KEY'), contains('API Key'));
    expect(friendlyModelError('timeout'), 'timeout');
  });
}
