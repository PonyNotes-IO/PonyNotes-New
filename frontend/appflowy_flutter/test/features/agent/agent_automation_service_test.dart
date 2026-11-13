import 'dart:convert';

import 'package:appflowy/features/agent/application/agent_automation_service.dart';
import 'package:appflowy/features/agent/application/agent_internal_service.dart';
import 'package:appflowy/features/agent/presentation/agent_automations_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../../widget_test/widget_test_wrapper.dart';

const _account = AgentCloudAccount(
  baseUrl: 'https://cloud.example',
  accessToken: 'token',
  userId: '1',
);

http.Response _json(Object value, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(value)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  test('scopes every call to the workspace and parses the payload', () async {
    final seen = <http.Request>[];
    final client = MockClient((request) async {
      seen.add(request);
      if (request.method == 'GET' &&
          request.url.path == '/api/ai/agent/automations/ws') {
        return _json({
          'automations': [
            {
              'id': 'a1',
              'name': '每日汇总',
              'enabled': true,
              'trigger': {'type': 'cron', 'expr': '0 9 * * *'},
            },
          ],
        });
      }
      if (request.url.path.endsWith('/a1/runs')) {
        return _json({
          'runs': [
            {'id': 'r1', 'status': 'succeeded', 'answer': '完成'},
          ],
          'total': 1,
        });
      }
      if (request.url.path.endsWith('/a1/run')) {
        return _json({
          'data': {'id': 'r2', 'status': 'queued'},
        });
      }
      return _json({'error': 'not found'}, 404);
    });
    final service = AgentAutomationService(
      client: client,
      account: () async => _account,
    );

    final items = await service.list('ws');
    expect(items.single.name, '每日汇总');
    expect(seen.first.url.path, '/api/ai/agent/automations/ws');
    expect(seen.first.headers['Authorization'], 'Bearer token');

    final runs = await service.runs('ws', 'a1');
    expect(runs.single.statusLabel, '成功');

    await service.control('ws', 'a1', 'run');
    expect(seen.last.url.path, '/api/ai/agent/automations/ws/a1/run');
  });

  test('surfaces the server message instead of a bare status code', () async {
    final service = AgentAutomationService(
      client: MockClient(
        (_) async => _json({'message': '思考程度无效'}, 400),
      ),
      account: () async => _account,
    );

    expect(
      () => service.list('ws'),
      throwsA(predicate((error) => '$error'.contains('思考程度无效'))),
    );
  });

  testWidgets('lists automations and toggles one through the proxy',
      (tester) async {
    final updates = <String>[];
    final client = MockClient((request) async {
      if (request.method == 'PUT') {
        updates.add(request.body);
      }
      if (request.method == 'GET' &&
          request.url.path.endsWith('/automations/ws')) {
        return _json({
          'automations': [
            {
              'id': 'a1',
              'name': '每日汇总',
              'enabled': true,
              'instruction': '总结昨天的笔记',
              'trigger': {'type': 'cron', 'expr': '0 9 * * *'},
              'session_mode': 'per_run',
              'next_run_at': '2026-11-14T01:00:00Z',
              'last_run_status': 'succeeded',
            },
          ],
        });
      }
      return _json({'automations': []});
    });
    final service = AgentAutomationService(
      client: client,
      account: () async => _account,
    );

    await tester.pumpWidget(
      WidgetTestWrapper(
        child: AgentAutomationsPage(
          service: service,
          workspace: () async => 'ws',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('每日汇总'), findsOneWidget);
    expect(find.text('0 9 * * *'), findsOneWidget);
    expect(find.text('成功'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(updates, hasLength(1));
    final body = jsonDecode(updates.single) as Map;
    expect(body['enabled'], false);
    expect(body['name'], '每日汇总');
    expect(body.containsKey('model'), false);
  });
}
