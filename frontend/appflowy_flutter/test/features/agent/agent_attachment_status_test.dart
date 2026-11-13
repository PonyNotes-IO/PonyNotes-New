import 'dart:async';
import 'dart:convert';

import 'package:appflowy/features/agent/application/agent_controller.dart';
import 'package:appflowy/features/agent/application/agent_internal_service.dart';
import 'package:appflowy/features/agent/application/agent_service.dart';
import 'package:appflowy/features/ai_internal/application/ai_provider_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
const _account = AgentCloudAccount(
  baseUrl: 'https://cloud.test',
  accessToken: 'login',
  userId: 'one',
);

http.StreamedResponse _history() => http.StreamedResponse(
      Stream.value(utf8.encode('{"messages":[],"sources":{}}')),
      200,
    );

AgentController _controller(http.Client client) => AgentController(
      chatId: 'document',
      workspaceId: () async => 'workspace',
      service: AgentService(client: client, account: () async => _account),
      internalService: AgentInternalService(
        account: () async => _account,
        client: MockClient(
          (_) async => http.Response(
            '{"unit":"USD","remaining":1,"credits_per_usd":100}',
            200,
          ),
        ),
      ),
    )..providerConfig =
        const AiProviderConfig(modelName: 'managed', isInternal: true);

Map<String, dynamic> _attachment(AgentController controller) =>
    ((controller.messages.firstWhere((m) => m['role'] == 'user')['attachments']
            as List)
        .single as Map)
        .cast<String, dynamic>();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('polls parse state until WeKnora reports a terminal status', () async {
    final stream = StreamController<List<int>>();
    var statusReads = 0;
    final client = MockClient.streaming((request, body) async {
      if (request.url.path.endsWith('/tools')) {
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(request.method == 'GET' ? '{"calls":[]}' : ''),
          ),
          request.method == 'GET' ? 200 : 204,
        );
      }
      if (request.url.path.endsWith('/attachments')) {
        statusReads++;
        final status = statusReads == 1 ? 'processing' : 'ready';
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(
              '{"attachments":[{"id":"uploaded","file_name":"扫描.pdf","status":"$status"}]}',
            ),
          ),
          200,
        );
      }
      if (request.method == 'GET') return _history();
      return http.StreamedResponse(
        stream.stream,
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    final controller = _controller(client)
      ..attachmentPollInterval = const Duration(milliseconds: 20);
    await controller.connect();
    final accepted = controller.send(
      '看看这个文件',
      attachments: [
        {'file_name': '扫描.pdf', 'file_size': 4, 'data': 'JVBERg=='},
      ],
    );
    await Future<void>.delayed(Duration.zero);
    // Upload only stores the file; the parse result arrives later.
    stream.add(
      utf8.encode(
        'data: {"response_type":"scope","data":{"sources":{},"attachments":[{"id":"uploaded","file_name":"扫描.pdf","file_size":4,"status":"processing"}]}}\n\n',
      ),
    );
    expect(await accepted, true);
    expect(_attachment(controller)['status'], 'processing');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(_attachment(controller)['status'], 'ready');
    await stream.close();
    await controller.disconnect();
    controller.dispose();
    client.close();
  });

  test('keeps a failed upload retryable and drops the duplicate bubble', () async {
    var submissions = 0;
    final stream = StreamController<List<int>>();
    final client = MockClient.streaming((request, body) async {
      if (request.url.path.endsWith('/tools')) {
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(request.method == 'GET' ? '{"calls":[]}' : ''),
          ),
          request.method == 'GET' ? 200 : 204,
        );
      }
      if (request.url.path.endsWith('/attachments')) {
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"attachments":[]}')),
          200,
        );
      }
      if (request.method == 'GET') return _history();
      submissions++;
      if (submissions == 1) {
        return http.StreamedResponse(
          Stream.value(utf8.encode('附件「扫描.pdf」上传失败')),
          503,
        );
      }
      return http.StreamedResponse(
        stream.stream,
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    final controller = _controller(client);
    await controller.connect();
    final sent = await controller.send(
      '看看这个文件',
      attachments: [
        {'file_name': '扫描.pdf', 'file_size': 4, 'data': 'JVBERg=='},
      ],
    );
    expect(sent, false);
    expect(controller.canRetryUpload, true);
    expect(_attachment(controller)['status'], 'unconfirmed');
    expect(
      controller.messages.where((m) => m['role'] == 'user'),
      hasLength(1),
    );

    final retried = controller.retryUpload();
    await Future<void>.delayed(Duration.zero);
    stream.add(
      utf8.encode(
        'data: {"response_type":"scope","data":{"sources":{},"attachments":[{"id":"uploaded","file_name":"扫描.pdf","file_size":4,"status":"processing"}]}}\n\n',
      ),
    );
    expect(await retried, true);
    expect(controller.canRetryUpload, false);
    // The failed bubble was replaced, not duplicated.
    expect(
      controller.messages.where((m) => m['role'] == 'user'),
      hasLength(1),
    );
    expect(_attachment(controller)['id'], 'uploaded');
    await stream.close();
    await controller.disconnect();
    controller.dispose();
    client.close();
  });

  test('maps body bytes onto each attachment so progress is per file', () {
    // Chinese text before the payload means UTF-16 indices differ from bytes.
    final body = <String, dynamic>{
      'query': '总结这份文件',
      'attachments': [
        {'file_name': '扫描.pdf', 'data': 'JVBERi0xLjQK'},
        {'file_name': '表格.xlsx', 'data': 'UEsDBBQ='},
      ],
    };
    final spans = AgentController.attachmentSpans(body);
    expect(spans, hasLength(2));

    final encoded = utf8.encode(jsonEncode(body));
    final first = utf8.encode('JVBERi0xLjQK');
    final second = utf8.encode('UEsDBBQ=');
    // Each span must land exactly on its own payload bytes.
    expect(
      encoded.sublist(spans[0].$1, spans[0].$2),
      first,
    );
    expect(
      encoded.sublist(spans[1].$1, spans[1].$2),
      second,
    );
    // The spans are ordered and never overlap.
    expect(spans[0].$2 <= spans[1].$1, true);
  });

  test('reports upload progress per attachment while the body streams', () async {
    final stream = StreamController<List<int>>();
    final client = MockClient.streaming((request, body) async {
      if (request.url.path.endsWith('/tools')) {
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(request.method == 'GET' ? '{"calls":[]}' : ''),
          ),
          request.method == 'GET' ? 200 : 204,
        );
      }
      if (request.url.path.endsWith('/attachments')) {
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"attachments":[]}')),
          200,
        );
      }
      if (request.method == 'GET') {
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"messages":[],"sources":{}}')),
          200,
        );
      }
      // Consume the streamed body so progress callbacks fire.
      final consumed = await body.bytesToString();
      expect(consumed.contains('JVBERi0xLjQK'), true);
      return http.StreamedResponse(
        stream.stream,
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    final controller = _controller(client);
    await controller.connect();
    final accepted = controller.send(
      '看看这个文件',
      attachments: [
        {'file_name': '扫描.pdf', 'file_size': 4, 'data': 'JVBERi0xLjQK'},
      ],
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    stream.add(
      utf8.encode(
        'data: {"response_type":"scope","data":{"sources":{},"attachments":[{"id":"uploaded","file_name":"扫描.pdf","file_size":4,"status":"processing"}]}}\n\n',
      ),
    );
    expect(await accepted, true);
    await stream.close();
    await controller.disconnect();
    controller.dispose();
    client.close();
  });
}
