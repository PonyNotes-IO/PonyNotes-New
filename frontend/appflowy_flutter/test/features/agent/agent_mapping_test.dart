import 'dart:async';
import 'dart:convert';

import 'package:appflowy/features/agent/application/agent_definition.dart';
import 'package:appflowy/features/agent/application/agent_controller.dart';
import 'package:appflowy/features/agent/application/agent_internal_service.dart';
import 'package:appflowy/features/agent/application/agent_service.dart';
import 'package:appflowy/features/agent/presentation/ai_mode_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  const account = AgentCloudAccount(
    baseUrl: 'https://cloud.test',
    accessToken: 'login',
    userId: 'one',
  );
  const own = AgentDefinition(
    id: 'same-id',
    name: '团队助手',
    mode: 'smart-reasoning',
    group: 'private',
  );
  const shared = AgentDefinition(
    id: 'same-id',
    name: '团队助手',
    mode: 'smart-reasoning',
    group: 'shared',
    sourceTenantId: 17,
    description: '共享知识助手',
  );

  test('catalog authenticates through Cloud and preserves shared identities',
      () async {
    var current = account;
    final service = AgentService(
      account: () async => current,
      client: MockClient((request) async {
        expect(
          request.url.path,
          '/api/ai/agent/conversations/workspace/agents',
        );
        expect(request.headers['Authorization'], 'Bearer login');
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'items': [own.toJson(), shared.toJson()],
            }),
          ),
          200,
        );
      }),
    );
    final items = await service.agents('workspace');
    expect(items.map((a) => a.key), ['0:same-id', '17:same-id']);
    expect(items.last.name, '团队助手');
    current = const AgentCloudAccount(
      baseUrl: 'https://cloud.test',
      accessToken: 'login',
      userId: 'two',
    );
    expect(items.last.toJson()['source_tenant_id'], 17);
  });

  test('catalog discards data returned after an account change', () async {
    var current = account;
    final service = AgentService(
      account: () async => current,
      client: MockClient((_) async {
        current = const AgentCloudAccount(
          baseUrl: 'https://cloud.test',
          accessToken: 'other',
          userId: 'two',
        );
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'items': [shared.toJson()],
            }),
          ),
          200,
        );
      }),
    );
    await expectLater(service.agents('workspace'), throwsStateError);
  });

  test(
      'history restores a shared agent and sends its source without a local model',
      () async {
    SharedPreferences.setMockInitialValues({});
    final restored = AgentDefinition.fromJson({
      ...shared.toJson(),
      'mode': 'quick-answer',
    });
    Map? sent;
    final client = MockClient.streaming((request, body) async {
      if (request.url.path.endsWith('/tools')) {
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(request.method == 'GET' ? '{"calls":[]}' : ''),
          ),
          request.method == 'GET' ? 200 : 204,
        );
      }
      if (request.method == 'GET') {
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(
              jsonEncode({
                'mode': 'quick-answer',
                'selected_agent': restored.toJson(),
                'messages': [],
              }),
            ),
          ),
          200,
        );
      }
      sent = jsonDecode(await body.bytesToString()) as Map;
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            'data: {"response_type":"scope"}\n\ndata: {"response_type":"complete"}\n\n',
          ),
        ),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    final controller = AgentController(
      chatId: 'document',
      workspaceId: () async => 'workspace',
      service: AgentService(client: client, account: () async => account),
      internalService: AgentInternalService(
        account: () async => account,
        client: MockClient(
          (_) async => http.Response(
            '{"unit":"USD","remaining":1,"credits_per_usd":100}',
            200,
          ),
        ),
      ),
    );
    addTearDown(() async {
      await controller.disconnect();
      controller.dispose();
      client.close();
    });
    await controller.connect();
    expect(controller.connected, true, reason: controller.error);
    expect(controller.selectedAgent?.key, '17:same-id');
    expect(controller.providerConfig, isNull);
    expect(await controller.send('查询团队资料'), true);
    expect((sent?['agent'] as Map)['source_tenant_id'], 17);
    expect((sent?['agent'] as Map)['id'], shared.id);
  });

  testWidgets('selects the shared identity and refreshes the catalog on reopen',
      (tester) async {
    AgentDefinition selected = AgentDefinition.quick;
    var loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: StatefulBuilder(
              builder: (_, update) => AiModeButton(
                agentMode: selected.smart,
                selectedAgent: selected,
                loadAgents: () async {
                  loads++;
                  return [AgentDefinition.quick, own, shared];
                },
                onAgentSelected: (agent) => update(() => selected = agent),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(AiModeButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agent-mode-17:same-id')));
    await tester.pumpAndSettle();
    expect(selected.key, '17:same-id');
    expect(find.byKey(const ValueKey('agent-mode-panel')), findsNothing);
    expect(find.text('团队助手'), findsOneWidget);
    await tester.tap(find.byType(AiModeButton));
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(find.text('使用共享方配置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed catalog can be retried without showing sample agents',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiModeButton(
            agentMode: false,
            loadAgents: () async {
              if (++calls == 1) throw StateError('offline');
              return [shared];
            },
            onAgentSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.byType(AiModeButton));
    await tester.pumpAndSettle();
    expect(find.text('智能体加载失败，请重试'), findsOneWidget);
    expect(find.text('我的RAG回答'), findsNothing);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('agent-mode-17:same-id')), findsOneWidget);
    expect(find.text('智能体加载失败，请重试'), findsNothing);
  });
}
