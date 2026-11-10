import 'dart:async';
import 'dart:convert';

import 'package:appflowy/env/backend_env.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/features/agent/application/agent_controller.dart';
import 'package:appflowy/features/agent/application/agent_internal_service.dart';
import 'package:appflowy/features/ai_internal/application/ai_provider_config.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const account = AgentCloudAccount(
  baseUrl: 'https://cloud.test',
  accessToken: 'login-token',
  userId: '1',
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('new users discover managed models and give runtime only an Agent token',
      () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      expect(request.headers['Authorization'], 'Bearer login-token');
      if (request.url.path.endsWith('/models')) {
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 'gateway-reasoner', 'supports_reasoning': true},
              {'id': 'gateway-chat'},
            ],
          }),
          200,
        );
      }
      expect(request.method, 'POST');
      expect(request.url.path, '/api/ai/agent/session');
      return http.Response('{"token":"pn-agent-test","expires_in":86400}', 200);
    });
    final service =
        AgentInternalService(client: client, account: () async => account);
    final selected = await service.preferred();
    expect(selected.isInternal, true);
    expect(selected.modelName, 'gateway-reasoner');
    expect(selected.apiKey, isEmpty);
    final runtime = await service.runtimeConfig(selected);
    expect(runtime.baseUrl, 'https://cloud.test/api/ai/agent');
    expect(runtime.apiKey, 'pn-agent-test');
    expect(runtime.supportsReasoning, true);
    expect(service.sessionNeedsRefresh, false);
    await service.select(selected);
    expect((await const AiProviderConfigStorage().load()).isComplete, false);
    expect(await const AiProviderConfigStorage().loadProfiles(), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(account.selectionKey), 'gateway-reasoner');
    expect(
      prefs.getKeys().any((key) => '${prefs.get(key)}'.contains('token')),
      false,
    );
    expect(requests.every((request) => request.url.host == 'cloud.test'), true);
  });

  test(
      'internal selection is isolated by cloud account and cannot leak into custom storage',
      () async {
    var current = account;
    final service = AgentInternalService(
      account: () async => current,
      client: MockClient(
        (_) async => http.Response(
          '{"data":[{"id":"other-managed"}]}',
          200,
        ),
      ),
    );
    const selected = AiProviderConfig(modelName: 'managed', isInternal: true);
    await service.select(selected);
    expect((await service.preferred()).isInternal, true);
    current = const AgentCloudAccount(
      baseUrl: 'https://cloud.test',
      accessToken: 'other',
      userId: '2',
    );
    const custom = AiProviderConfig(
      baseUrl: 'https://custom.test/v1',
      modelName: 'custom',
      apiKey: 'own-key',
    );
    await const AiProviderConfigStorage().save(custom);
    expect((await service.preferred()).modelName, 'other-managed');
    await service.select(custom);
    expect((await service.preferred()).isInternal, false);
    await expectLater(
      const AiProviderConfigStorage().save(selected),
      throwsArgumentError,
    );
    current = account;
    expect((await service.preferred()).modelName, 'managed');
    await service.select(custom);
    expect((await service.preferred()).modelName, 'custom');
    const changedCustom = AiProviderConfig(
      baseUrl: 'https://another.test',
      modelName: 'another',
      apiKey: 'another-key',
    );
    current = const AgentCloudAccount(
      baseUrl: 'https://cloud.test',
      accessToken: 'other',
      userId: '2',
    );
    await service.select(changedCustom);
    current = account;
    expect((await service.preferred()).apiKey, 'own-key');
  });

  test('custom models stay usable without a cloud account or cloud requests',
      () async {
    const custom = AiProviderConfig(
      baseUrl: 'https://custom.test/v1',
      modelName: 'custom',
      apiKey: 'own-key',
    );
    final service = AgentInternalService(
      account: () async => throw StateError('offline'),
      client: MockClient(
        (_) async =>
            fail('custom endpoints must not need the internal service'),
      ),
    );
    await service.select(custom);
    expect((await service.preferred()).modelName, 'custom');
    expect(await service.runtimeConfig(custom), same(custom));
    await service.revoke(custom);
  });

  test('cloud identity failure never falls back to a device custom key',
      () async {
    getIt.registerSingleton<AppFlowyCloudSharedEnv>(
      AppFlowyCloudSharedEnv(
        authenticatorType: AuthenticatorType.appflowyCloud,
        appflowyCloudConfig: AppFlowyCloudConfiguration(
          base_url: 'https://cloud.test',
          ws_base_url: 'wss://cloud.test',
          gotrue_url: 'https://cloud.test',
          enable_sync_trace: false,
          base_web_domain: 'https://cloud.test',
        ),
      ),
    );
    addTearDown(() => getIt.unregister<AppFlowyCloudSharedEnv>());
    const custom = AiProviderConfig(
      baseUrl: 'https://custom.test/v1',
      modelName: 'custom',
      apiKey: 'old-account-key',
    );
    await const AiProviderConfigStorage().save(custom);
    final service = AgentInternalService(
      account: () async => throw StateError('identity unavailable'),
    );
    await expectLater(service.preferred(), throwsStateError);
    await expectLater(service.select(custom), throwsStateError);
  });

  test(
      'internal credits use the server rate and support unlimited subscriptions',
      () async {
    var body =
        '{"unit":"USD","remaining":2.5,"credits":750,"credits_per_usd":300,"unlimited":false}';
    final service = AgentInternalService(
      account: () async => account,
      client: MockClient((request) async {
        expect(request.url.path, '/api/ai/agent/usage');
        return http.Response(body, 200);
      }),
    );
    expect((await service.credits()).credits, 750);
    expect((await service.credits()).label, '750.00 积分');
    body =
        '{"unit":"USD","remaining":0.99735828,"credits":99,"credits_per_usd":100,"unlimited":false}';
    expect((await service.credits()).label, '99.74 积分');
    body =
        '{"unit":"USD","remaining":-1,"credits":null,"credits_per_usd":100,"unlimited":true}';
    expect((await service.credits()).label, '积分不限额');
    body = '{"unit":"USD","remaining":2.5}';
    await expectLater(service.credits(), throwsFormatException);
  });

  test('credit refresh queues a fresh request while one is in flight',
      () async {
    final first = Completer<http.Response>();
    var requests = 0;
    final service = AgentInternalService(
      account: () async => account,
      client: MockClient((request) async {
        requests++;
        if (requests == 1) return first.future;
        return http.Response(
          '{"unit":"USD","remaining":0.01,"credits_per_usd":100}',
          200,
        );
      }),
    );
    final controller =
        AgentController(chatId: 'credit-test', internalService: service)
          ..providerConfig =
              const AiProviderConfig(modelName: 'managed', isInternal: true)
          ..connected = true;
    final pending = controller.refreshCredits();
    await Future<void>.delayed(Duration.zero);
    await controller.refreshCredits();
    expect(requests, 1);
    first.complete(
      http.Response(
        '{"unit":"USD","remaining":0.96,"credits_per_usd":100}',
        200,
      ),
    );
    await pending;
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(requests, 2);
    expect(controller.credits?.label, '1.00 积分');

    await controller.disconnect();
    expect(controller.credits, isNull);
    controller.dispose();
  });

  test('late credit response cannot restore a disconnected balance', () async {
    final response = Completer<http.Response>();
    final controller = AgentController(
      chatId: 'credit-disconnect',
      internalService: AgentInternalService(
        account: () async => account,
        client: MockClient((_) => response.future),
      ),
    )
      ..providerConfig =
          const AiProviderConfig(modelName: 'managed', isInternal: true)
      ..connected = true;
    final pending = controller.refreshCredits();
    await Future<void>.delayed(Duration.zero);
    await controller.disconnect();
    response.complete(
      http.Response(
        '{"unit":"USD","remaining":0.96,"credits_per_usd":100}',
        200,
      ),
    );
    await pending;
    expect(controller.credits, isNull);
    controller.dispose();
  });

  test('expired login and unprovisioned service remain visible errors',
      () async {
    for (final status in [401, 403, 404, 503]) {
      final service = AgentInternalService(
        account: () async => account,
        client: MockClient(
          (_) async => http.Response('internal model unavailable', status),
        ),
      );
      await expectLater(service.models(), throwsStateError);
    }
  });

  test('revocation sends only the scoped credential to its issuing cloud',
      () async {
    final service = AgentInternalService(
      client: MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(
          request.url.toString(),
          'https://cloud.test/api/ai/agent/session',
        );
        expect(request.headers['Authorization'], 'Bearer pn-agent-test');
        return http.Response('', 204);
      }),
    );
    await service.revoke(
      const AiProviderConfig(
        baseUrl: 'https://cloud.test/api/ai/agent',
        modelName: 'managed',
        apiKey: 'pn-agent-test',
        isInternal: true,
      ),
    );
  });
}
