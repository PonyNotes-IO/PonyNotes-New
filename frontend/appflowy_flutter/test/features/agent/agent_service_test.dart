import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:appflowy/features/agent/application/agent_artifacts.dart';
import 'package:appflowy/features/agent/application/agent_controller.dart';
import 'package:appflowy/features/agent/application/agent_service.dart';
import 'package:appflowy/features/agent/application/agent_reference.dart';
import 'package:appflowy/features/agent/application/agent_internal_service.dart';
import 'package:appflowy/features/ai_internal/application/ai_provider_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
  test(
      'reference catalog uses login credentials and discards an account change',
      () async {
    var current = account;
    final service = AgentService(
      account: () async => current,
      client: MockClient((request) async {
        expect(
          request.url.path,
          '/api/ai/agent/conversations/workspace/references',
        );
        expect(request.headers['Authorization'], 'Bearer login');
        current = const AgentCloudAccount(
          baseUrl: 'https://cloud.test',
          accessToken: 'other',
          userId: 'two',
        );
        return http.Response(
          '{"items":[{"kind":"file","id":"file","name":"private.pdf","knowledge_ids":["file"]}]}',
          200,
        );
      }),
    );
    await expectLater(service.references('workspace'), throwsStateError);
  });
  test('SSE preserves split UTF8, multiline data and complete boundaries',
      () async {
    final encoded = utf8.encode(
      ': ping\r\ndata: {"response_type":"answer",\r\ndata: "content":"笔记😀"}\r\n\r\ndata: {"response_type":"complete"}\n\ndata: [DONE]\n\n',
    );
    final events = await AgentService.decodeEvents(
      Stream.fromIterable(encoded.map((byte) => [byte])),
    ).toList();
    expect(
      events.map((event) => event['response_type']),
      ['answer', 'complete'],
    );
    expect(events.first['content'], '笔记😀');
    await expectLater(
      AgentService.decodeEvents(
        Stream.value(utf8.encode('data: invalid\n\n')),
      ).toList(),
      throwsFormatException,
    );
  });

  test(
      'Cloud owns conversation identity and receives a model choice, not a pi token',
      () async {
    final stream = StreamController<List<int>>();
    String? registeredClient;
    final client = MockClient.streaming((request, body) async {
      expect(request.headers['Authorization'], 'Bearer login');
      expect(
        request.url.path
            .startsWith('/api/ai/agent/conversations/workspace/document'),
        true,
      );
      if (request.url.path.endsWith('/tools')) {
        if (request.method == 'POST') {
          final registration = jsonDecode(await body.bytesToString()) as Map;
          registeredClient = registration['client_id'] as String;
          expect(
            (registration['tools'] as List)
                .any((tool) => tool['name'] == 'create_page'),
            true,
          );
          expect(
            (registration['tools'] as List)
                .any((tool) => tool['name'] == 'update_database_cell'),
            true,
          );
        }
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(request.method == 'GET' ? '{"calls":[]}' : ''),
          ),
          request.method == 'GET' ? 200 : 204,
        );
      }
      if (request.method == 'GET') {
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"messages":[],"sources":{}}')),
          200,
        );
      }
      expect(request.url.path.endsWith('/messages'), true);
      final data = jsonDecode(await body.bytesToString()) as Map;
      expect(registeredClient, isNotEmpty);
      expect(data['client_id'], registeredClient);
      expect(data['mode'], 'quick-answer');
      expect(data['model'], {
        'model_name': 'managed',
        'is_internal': true,
        'supports_reasoning': false,
      });
      expect(data['query'], '分析笔记');
      expect(data['attachments'], [
        {'file_name': '扫描.pdf', 'file_size': 4, 'data': 'JVBERg=='},
      ]);
      expect(data['references'], [
        {'kind': 'note', 'id': 'selected-note'},
      ]);
      expect(data['images'], [
        {'data': 'data:image/png;base64,aW1hZ2U='},
      ]);
      return http.StreamedResponse(
        stream.stream,
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
    )..providerConfig =
        const AiProviderConfig(modelName: 'managed', isInternal: true);
    await controller.connect();
    controller.configureMode(false);
    controller.permissions.disabledTools.add('search_notes');
    final accepted = controller.send(
      '分析笔记',
      contextReferences: const [
        AgentReference(kind: 'note', id: 'selected-note', name: '项目笔记'),
      ],
      images: [
        {'mimeType': 'image/png', 'data': 'aW1hZ2U='},
      ],
      attachments: [
        {'file_name': '扫描.pdf', 'file_size': 4, 'data': 'JVBERg=='},
      ],
    );
    await Future<void>.delayed(Duration.zero);
    stream.add(
      utf8.encode(
        'data: {"response_type":"scope","data":{"sources":{"doc":{"title":"笔记","url":""}},"attachments":[{"id":"upload-id","file_name":"扫描.pdf","file_size":4,"status":"processing"}]}}\n\n',
      ),
    );
    expect(await accepted, true);
    final uploaded =
        (controller.messages.single['attachments'] as List).single as Map;
    expect(uploaded['id'], 'upload-id');
    expect(uploaded['status'], 'processing');
    expect(uploaded.containsKey('data'), false);
    expect(controller.running, true);
    await expectLater(
      controller.send(
        '补充',
        behavior: 'steer',
        contextReferences: const [
          AgentReference(kind: 'file', id: 'file', name: '报告'),
        ],
      ),
      throwsStateError,
    );
    stream.add(
      utf8.encode(
        'data: {"response_type":"answer","assistant_message_id":"answer","content":"结果"}\n\n',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.streamingText, '结果');
    await stream.close();
    await Future<void>.delayed(Duration.zero);
    expect(controller.connected, false);
    expect(controller.error, contains('重新连接'));
    await controller.disconnect();
    expect(controller.messages, isEmpty);
    controller.dispose();
    client.close();
  });

  test('Agent mode switches per turn and survives delayed history refresh',
      () async {
    final streams = <StreamController<List<int>>>[];
    final sentModes = <String>[];
    final refreshRequested = Completer<void>();
    final history = Completer<String>();
    var historyReads = 0;
    final client = MockClient.streaming((request, body) async {
      expect(
        request.url.path,
        startsWith('/api/ai/agent/conversations/workspace/document'),
      );
      if (request.url.path.endsWith('/tools')) {
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(request.method == 'GET' ? '{"calls":[]}' : ''),
          ),
          request.method == 'GET' ? 200 : 204,
        );
      }
      if (request.method == 'GET') {
        historyReads++;
        if (historyReads == 2) refreshRequested.complete();
        final data = historyReads == 2
            ? await history.future
            : '{"mode":"quick-answer","messages":[],"sources":{}}';
        return http.StreamedResponse(Stream.value(utf8.encode(data)), 200);
      }
      expect(request.url.path.endsWith('/messages'), true);
      final data = jsonDecode(await body.bytesToString()) as Map;
      sentModes.add(data['mode'] as String);
      final stream = StreamController<List<int>>();
      streams.add(stream);
      stream.add(utf8.encode('data: {"response_type":"scope"}\n\n'));
      return http.StreamedResponse(
        stream.stream,
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
    )..providerConfig =
        const AiProviderConfig(modelName: 'managed', isInternal: true);
    addTearDown(() async {
      for (final stream in streams) {
        await stream.close();
      }
      await controller.disconnect();
      controller.dispose();
      client.close();
    });
    await controller.connect();
    expect(controller.mode, 'quick-answer');
    controller.configureMode(true);
    controller.permissions.disabledTools.add('search_notes');
    expect(await controller.send('第一轮'), true);
    expect(controller.running, true);
    controller.configureMode(false);
    expect(controller.mode, 'quick-answer');
    expect(controller.running, true);
    expect(controller.messages.single['content'], '第一轮');
    streams.first.add(utf8.encode('data: {"response_type":"complete"}\n\n'));
    await streams.first.close();
    await refreshRequested.future.timeout(const Duration(seconds: 5));
    final historyApplied = Completer<void>();
    void refreshed() {
      if (controller.messages.any((m) => m['id'] == 'answer') &&
          !historyApplied.isCompleted) {
        historyApplied.complete();
      }
    }

    controller.addListener(refreshed);
    history.complete(
      jsonEncode({
        'mode': 'smart-reasoning',
        'messages': [
          {'id': 'question', 'role': 'user', 'content': '第一轮'},
          {'id': 'answer', 'role': 'assistant', 'content': '回答'},
        ],
        'sources': {},
      }),
    );
    await historyApplied.future.timeout(const Duration(seconds: 5));
    controller.removeListener(refreshed);
    expect(controller.mode, 'quick-answer');
    expect(controller.messages.length, 2);
    expect(await controller.send('第二轮'), true);
    expect(sentModes, ['smart-reasoning', 'quick-answer']);
    expect(controller.chatId, 'document');
    expect(controller.messages.length, 3);
  });

  test('generated files stay local until cloud sync is explicitly enabled',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('agent-local-output-');
    addTearDown(() => directory.delete(recursive: true));
    var uploads = 0;
    final client = MockClient.streaming((request, body) async {
      if (request.method == 'PUT') {
        await body.drain<void>();
        uploads++;
        return http.StreamedResponse(
          Stream.value(
            utf8.encode('{"code":1028,"message":"quota exceeded"}'),
          ),
          200,
        );
      }
      if (request.url.path.endsWith('/tools')) {
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(request.method == 'GET' ? '{"calls":[]}' : ''),
          ),
          request.method == 'GET' ? 200 : 204,
        );
      }
      if (request.url.path.endsWith('/artifacts/0')) {
        return http.StreamedResponse(Stream.value(utf8.encode('local')), 200);
      }
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            jsonEncode({
              'messages': [
                {
                  'id': 'answer',
                  'role': 'assistant',
                  'content': '文件已生成',
                  'artifacts': [
                    {'index': 0, 'file_name': 'report.txt', 'file_size': 5},
                  ],
                }
              ],
              'sources': {},
            }),
          ),
        ),
        200,
      );
    });
    final controller = AgentController(
      chatId: 'collaborative-document',
      workspaceId: () async => 'workspace',
      artifacts: AgentArtifacts(directory: () async => directory),
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
    )..providerConfig =
        const AiProviderConfig(modelName: 'managed', isInternal: true);
    addTearDown(() async {
      await controller.disconnect();
      controller.dispose();
      client.close();
    });
    await controller.connect();
    final timeout = DateTime.now().add(const Duration(seconds: 5));
    while (controller.savingArtifacts && DateTime.now().isBefore(timeout)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(controller.cloudSync, false);
    expect(uploads, 0);
    expect(controller.artifactError, isNull);
    expect(await controller.artifactFiles['answer/0']!.readAsString(), 'local');
    expect(
      (controller.messages.single['artifacts'] as List).single,
      isNot(contains('cloud_url')),
    );
    await controller.configureCloudSync(true);
    expect(controller.cloudSync, true);
    expect(uploads, 1);
    expect(controller.artifactError, contains('quota exceeded'));
    expect(await controller.artifactFiles['answer/0']!.readAsString(), 'local');
    expect(
      (await SharedPreferences.getInstance()).getBool(
        'ponynotes.agent.artifacts.https://cloud.test|one|workspace|collaborative-document',
      ),
      true,
    );
  });

  test(
      'a second device restores cloud files even when model credits are unavailable',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('agent-cloud-restore-');
    addTearDown(() => directory.delete(recursive: true));
    final downloaded = Completer<void>();
    final client = MockClient.streaming((request, body) async {
      if (request.url.path.startsWith('/api/file_storage/')) {
        expect(request.headers['Authorization'], 'Bearer login');
        downloaded.complete();
        return http.StreamedResponse(Stream.value(utf8.encode('saved')), 200);
      }
      if (request.url.path.endsWith('/tools')) {
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(request.method == 'GET' ? '{"calls":[]}' : ''),
          ),
          request.method == 'GET' ? 200 : 204,
        );
      }
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"messages":[],"sources":{}}')),
        200,
      );
    });
    final controller = AgentController(
      chatId: 'document',
      workspaceId: () async => 'workspace',
      artifacts: AgentArtifacts(directory: () async => directory),
      cloudArtifacts: {
        'answer/0': {
          'message_id': 'answer',
          'index': 0,
          'file_name': 'report.txt',
          'file_size': 5,
          'cloud_url':
              'https://cloud.test/api/file_storage/workspace/blob/report.txt',
        },
      },
      service: AgentService(client: client, account: () async => account),
      internalService: AgentInternalService(
        account: () async => account,
        client: MockClient((_) async => http.Response('积分不足', 403)),
      ),
    );
    addTearDown(() async {
      await controller.disconnect();
      controller.dispose();
      client.close();
    });
    await controller.connect();
    await downloaded.future.timeout(const Duration(seconds: 5));
    final timeout = DateTime.now().add(const Duration(seconds: 5));
    while (controller.savingArtifacts && DateTime.now().isBefore(timeout)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(controller.cloudSync, false);
    expect(controller.artifactError, isNull);
    expect(await controller.artifactFiles['answer/0']!.readAsString(), 'saved');
    expect(controller.messages.single['id'], 'answer');
  });

  test('tool preamble, replacement and references follow WeKnora events',
      () async {
    final controller = AgentController(chatId: 'doc');
    controller
        .receive({'response_type': 'answer', 'id': 'a', 'content': '先查一下'});
    controller.receive({
      'response_type': 'tool_call',
      'data': {
        'tool_call_id': 't',
        'tool_name': 'search_knowledge',
        'arguments': {'query': '会议'},
      },
    });
    expect(controller.streamingText, isEmpty);
    controller.receive({
      'response_type': 'tool_result',
      'content': '3 篇',
      'data': {
        'tool_call_id': 't',
        'tool_name': 'search_knowledge',
        'success': true,
      },
    });
    expect(controller.activities['t']!.status, 'completed');
    controller
        .receive({'response_type': 'answer', 'id': 'b', 'content': '旧答案'});
    controller.receive({
      'response_type': 'answer',
      'id': 'b',
      'content': '新答案',
      'data': {'replace': true},
    });
    expect(controller.streamingText, '新答案');
    controller.receive({
      'response_type': 'references',
      'data': {
        'references': [
          {'knowledge_id': 'doc'},
        ],
      },
    });
    expect(controller.references.single['knowledge_id'], 'doc');
    controller.dispose();
  });
}
