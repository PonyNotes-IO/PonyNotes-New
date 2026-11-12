import 'dart:convert';
import 'dart:async';
import 'package:appflowy/features/agent/application/agent_conversations.dart';
import 'package:appflowy/features/agent/application/agent_service.dart';
import 'package:appflowy/features/agent/application/agent_internal_service.dart';
import 'package:appflowy/features/agent/application/agent_legacy_space.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const account = AgentCloudAccount(
      baseUrl: 'https://cloud.test', accessToken: 'token', userId: 'one');
  test(
      'independent history paginates and creating a conversation never creates a note',
      () async {
    var page = 0;
    final service = AgentService(
        account: () async => account,
        client: MockClient((request) async {
          expect(request.url.path, '/api/ai/agent/conversations/workspace');
          expect(request.headers['Authorization'], 'Bearer token');
          if (request.method == 'GET') {
            expect(request.url.queryParameters['offset'], '${page * 100}');
            return http.Response(
                jsonEncode({
                  'conversations': List.generate(page++ == 0 ? 100 : 1,
                      (i) => {'id': '$page-$i', 'title': '对话$i'})
                }),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'});
          }
          final body = jsonDecode(request.body) as Map;
          expect(body['title'], '分析笔记内容');
          return http.Response(
              jsonEncode({'id': body['id'], 'title': body['title']}), 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }));
    final store = AgentConversations(
        service: service, workspace: () async => 'workspace');
    addTearDown(store.dispose);
    await store.load();
    expect(store.error, isNull);
    expect(store.entries.length, 101);
    final created = await store.create(' 分析笔记内容 ');
    expect(created!.title, '分析笔记内容');
    expect(store.entries.first.id, created.id);
    expect(store.error, isNull);
  });
  test(
      'a failed create retries the same identity and account switches discard in-flight results',
      () async {
    var tries = 0;
    String? id;
    var user = account;
    final pending = Completer<http.Response>();
    final service = AgentService(
        account: () async => user,
        client: MockClient((request) async {
          if (request.method == 'GET')
            return http.Response('{"conversations":[]}', 200);
          final body = jsonDecode(request.body) as Map;
          id ??= body['id'] as String;
          expect(body['id'], id);
          if (tries++ == 0) return http.Response('temporary unavailable', 503);
          return pending.future;
        }));
    final store = AgentConversations(
        service: service, workspace: () async => 'workspace');
    addTearDown(store.dispose);
    await store.load();
    expect(await store.create('first'), isNull);
    expect(store.error, isNotNull);
    final retry = store.create('first');
    await Future<void>.delayed(Duration.zero);
    await store.load();
    expect(store.creating, true);
    user = const AgentCloudAccount(
        baseUrl: 'https://cloud.test', accessToken: 'other', userId: 'two');
    pending
        .complete(http.Response(jsonEncode({'id': id, 'title': 'first'}), 200));
    expect(await retry, isNull);
    expect(store.entries, isEmpty);
    expect(store.creating, false);
  });
  test('legacy AI spaces hide from note navigation without modifying the views',
      () {
    final legacy =
        ViewPB(id: 'old', name: '我的AI会话', extra: '{"is_space":true}');
    expect(isLegacyAiSpace(legacy), true);
    expect(isLegacyAiSpace(ViewPB(name: '我的AI会话')), false);
    expect(isLegacyAiSpace(ViewPB(name: '团队笔记', extra: '{"is_space":true}')),
        false);
    expect(legacy.id, 'old');
  });
  for (final creating in [false, true]) {
    test(
        'clear discards results during the final identity check: create=$creating',
        () async {
      var checks = 0;
      final checking = Completer<void>();
      final release = Completer<void>();
      final service = AgentService(
        account: () async {
          if (++checks == (creating ? 6 : 3)) {
            checking.complete();
            await release.future;
          }
          return account;
        },
        client: MockClient((request) async => http.Response(
              request.method == 'POST'
                  ? request.body
                  : '{"conversations":[{"id":"history","title":"history"}]}',
              200,
            )),
      );
      final store = AgentConversations(
          service: service, workspace: () async => 'workspace');
      addTearDown(store.dispose);
      if (creating) await store.load();
      final operation = creating ? store.create('new') : store.load();
      await checking.future;
      store.clear();
      release.complete();
      await operation;
      expect(store.entries, isEmpty);
      expect(store.workspaceId, isNull);
      expect(store.creating, false);
      expect(store.loading, false);
    });
  }
}
