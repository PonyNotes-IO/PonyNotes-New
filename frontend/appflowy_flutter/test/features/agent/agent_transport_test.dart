import 'dart:convert';
import 'dart:io';
import 'package:appflowy/features/agent/application/agent_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Dart pipe transport runs real pi, streams Unicode and restores the persisted session',
    () async {
      final directory =
          await Directory.systemTemp.createTemp('ponynotes-agent-transport-');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        await utf8.decoder.bind(request).join();
        request.response.headers.contentType =
            ContentType('text', 'event-stream', charset: 'utf-8');
        for (final choice in [
          {
            'delta': {'role': 'assistant', 'content': '你好\u2028世界'},
            'finish_reason': null,
          },
          {'delta': {}, 'finish_reason': 'stop'},
        ]) {
          request.response.write('data: ${jsonEncode({
                'id': 'one',
                'object': 'chat.completion.chunk',
                'created': 1,
                'model': 'test',
                'choices': [
                  {'index': 0, ...choice},
                ],
              })}\n\n');
        }
        request.response.write('data: ${jsonEncode({
              'id': 'one',
              'object': 'chat.completion.chunk',
              'choices': [],
              'usage': {
                'prompt_tokens': 40,
                'completion_tokens': 8,
                'total_tokens': 48,
              },
            })}\n\n');
        request.response.write('data: [DONE]\n\n');
        await request.response.close();
      });
      final transport = AgentTransport();
      final records = <Map<String, dynamic>>[];
      final errors = <Object>[];
      final subscription =
          transport.records.listen(records.add, onError: errors.add);
      Future<Map<String, dynamic>> waitFor(
        bool Function(Map<String, dynamic>) predicate,
      ) async {
        final existing = records.where(predicate).firstOrNull;
        if (existing != null) return existing;
        return transport.records
            .firstWhere(predicate)
            .timeout(const Duration(seconds: 20));
      }

      final config = {
        'scope': 'test-user-workspace-chat',
        'workspaceId': 'workspace',
        'baseUrl': 'http://127.0.0.1:${server.port}/v1',
        'model': 'test',
        'apiKey': 'fake-key',
      };
      try {
        await transport.connect(dataDirectory: directory.path);
        transport.send({'type': 'initialize', 'id': 'init', 'config': config});
        final initialized = await waitFor((r) => r['id'] == 'init');
        expect(initialized['success'], true, reason: '${initialized['error']}');
        transport.send(
          {'type': 'prompt', 'id': 'prompt', 'message': '测试 Unicode：\u2028'},
        );
        await waitFor((r) => r['type'] == 'settled');
        expect(records.any((r) => jsonEncode(r).contains('你好')), true);
        final state = records.lastWhere((r) => r['type'] == 'state')['data'];
        final answer = (state['messages'] as List)
            .lastWhere((m) => m['role'] == 'assistant');
        expect(
          answer['stopReason'],
          'stop',
          reason: '${answer['errorMessage']}',
        );
        expect(answer['usage']['input'], 40);
        expect(answer['usage']['output'], 8);
        await transport.close();
        await transport.connect(dataDirectory: directory.path);
        transport
            .send({'type': 'initialize', 'id': 'restore', 'config': config});
        final restored = await waitFor((r) => r['id'] == 'restore');
        expect(restored['success'], true);
        expect(jsonEncode(restored['data']['messages']), contains('你好'));
        expect(errors, isEmpty);
      } finally {
        await transport.dispose();
        await subscription.cancel();
        await server.close(force: true);
        await directory.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
