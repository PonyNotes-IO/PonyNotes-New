import 'dart:convert';

import 'package:appflowy/features/ai_internal/application/ai_provider_config.dart';
import 'package:appflowy/features/ai_internal/application/internal_ai_service.dart';
import 'package:appflowy/features/mcp/application/mcp_tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// 只暴露一个只读工具、一个写工具的假 McpTools，避免测试依赖真实后端。
class _FakeMcpTools extends McpTools {
  _FakeMcpTools() : super(endpoint: 'test', version: 'test');

  final List<String> executed = [];

  static const JsonObject _noArgs = JsonObject(additionalProperties: false);

  @override
  List<McpToolSpec> get toolSpecs => [
        McpToolSpec(
          name: 'get_context',
          description: '读取上下文',
          inputSchema: _noArgs,
          readOnly: true,
          handler: (_) async {
            executed.add('get_context');
            return CallToolResult(
              content: [
                TextContent(text: jsonEncode({'ok': true})),
              ],
            );
          },
        ),
        McpToolSpec(
          name: 'delete_page',
          description: '删除页面',
          inputSchema: _noArgs,
          handler: (_) async {
            executed.add('delete_page');
            return CallToolResult(
              content: [
                TextContent(text: jsonEncode({'deleted': true})),
              ],
            );
          },
        ),
      ];
}

/// 覆盖 loadConfig，绕开 FFI。
class _TestableInternalAi extends InternalAiService {
  _TestableInternalAi({
    required this.setting,
    required McpTools tools,
    required http.Client client,
    bool confirmWrites = true,
  }) : super(
          tools: tools,
          httpClient: client,
          writeConfirmationRequired: confirmWrites,
        );

  final AiProviderConfig setting;

  @override
  Future<AiProviderConfig> loadConfig() async => setting;
}

AiProviderConfig _validSetting() => const AiProviderConfig(
      baseUrl: 'https://api.example.com',
      modelName: 'gpt-4o-mini',
      apiKey: 'sk-test',
    );

http.Response _completion(Map<String, dynamic> message) {
  return http.Response(
    jsonEncode({
      'choices': [
        {'message': message},
      ],
    }),
    200,
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  test('未配置时抛 notConfigured，不发请求', () async {
    var called = false;
    final client = MockClient((_) async {
      called = true;
      return http.Response('{}', 200);
    });

    final svc = _TestableInternalAi(
      setting: const AiProviderConfig(),
      tools: _FakeMcpTools(),
      client: client,
    );

    await expectLater(
      svc.ask(question: '你好'),
      throwsA(
        isA<InternalAiException>().having(
          (e) => e.kind,
          'kind',
          InternalAiErrorKind.notConfigured,
        ),
      ),
    );
    expect(called, isFalse);
  });

  test('模型直接回答不带工具时返回文本', () async {
    final svc = _TestableInternalAi(
      setting: _validSetting(),
      tools: _FakeMcpTools(),
      client: MockClient((_) async => _completion({'content': '直接回答'})),
    );

    final result = await svc.ask(question: '你好');
    expect(result.text, '直接回答');
    expect(result.toolCalls, isEmpty);
  });

  test('多轮工具调用：只读工具连续执行后给出结论', () async {
    var round = 0;
    final client = MockClient((request) async {
      round++;
      if (round == 1) {
        return _completion({
          'tool_calls': [
            {
              'id': 'call_1',
              'type': 'function',
              'function': {'name': 'get_context', 'arguments': '{}'},
            },
          ],
        });
      }
      return _completion({'content': '当前工作区是 demo'});
    });

    final tools = _FakeMcpTools();
    final svc = _TestableInternalAi(
      setting: _validSetting(),
      tools: tools,
      client: client,
    );

    final result = await svc.ask(question: '当前工作区是什么');
    expect(result.text, '当前工作区是 demo');
    expect(result.toolCalls.length, 1);
    expect(result.toolCalls.first.name, 'get_context');
    expect(tools.executed, ['get_context']);
    expect(round, 2);
  });

  test('写操作未确认时暂停，不执行 handler', () async {
    final client = MockClient((_) async {
      return _completion({
        'tool_calls': [
          {
            'id': 'call_1',
            'type': 'function',
            'function': {'name': 'delete_page', 'arguments': '{}'},
          },
        ],
      });
    });

    final tools = _FakeMcpTools();
    final svc = _TestableInternalAi(
      setting: _validSetting(),
      tools: tools,
      client: client,
    );

    final result = await svc.ask(question: '删掉这个页面');
    expect(result.requiresConfirmation, isTrue);
    expect(result.pendingWrite?.name, 'delete_page');
    // 关键：确认之前工具绝不能被执行
    expect(tools.executed, isEmpty);
  });

  test('确认回调返回 true 时执行写操作', () async {
    var round = 0;
    final client = MockClient((_) async {
      round++;
      if (round == 1) {
        return _completion({
          'tool_calls': [
            {
              'id': 'call_1',
              'type': 'function',
              'function': {
                'name': 'delete_page',
                'arguments': '{"page_id":"p1"}',
              },
            },
          ],
        });
      }
      return _completion({'content': '已删除'});
    });

    final tools = _FakeMcpTools();
    final svc = _TestableInternalAi(
      setting: _validSetting(),
      tools: tools,
      client: client,
    );

    AiToolCallRecord? asked;
    final result = await svc.ask(
      question: '删掉 p1',
      confirmWrite: (pending) async {
        asked = pending;
        return true;
      },
    );

    expect(asked?.name, 'delete_page');
    expect(asked?.arguments['page_id'], 'p1');
    expect(tools.executed, ['delete_page']);
    expect(result.text, '已删除');
  });

  test('确认回调返回 false 时不执行写操作', () async {
    final client = MockClient((_) async {
      return _completion({
        'tool_calls': [
          {
            'id': 'call_1',
            'type': 'function',
            'function': {'name': 'delete_page', 'arguments': '{}'},
          },
        ],
      });
    });

    final tools = _FakeMcpTools();
    final svc = _TestableInternalAi(
      setting: _validSetting(),
      tools: tools,
      client: client,
    );

    final result = await svc.ask(
      question: '删掉这个页面',
      confirmWrite: (_) async => false,
    );

    expect(tools.executed, isEmpty);
    expect(result.text, contains('已取消'));
    expect(result.requiresConfirmation, isFalse);
  });

  test('超过轮次上限抛 tooManyRounds', () async {
    final client = MockClient((_) async {
      return _completion({
        'tool_calls': [
          {
            'id': 'call_x',
            'type': 'function',
            'function': {'name': 'get_context', 'arguments': '{}'},
          },
        ],
      });
    });

    final svc = _TestableInternalAi(
      setting: _validSetting(),
      tools: _FakeMcpTools(),
      client: client,
    );

    await expectLater(
      svc.ask(question: '一直调用'),
      throwsA(
        isA<InternalAiException>().having(
          (e) => e.kind,
          'kind',
          InternalAiErrorKind.tooManyRounds,
        ),
      ),
    );
  });

  test('401 映射为 unauthorized', () async {
    final svc = _TestableInternalAi(
      setting: _validSetting(),
      tools: _FakeMcpTools(),
      client: MockClient((_) async => http.Response('unauthorized', 401)),
    );

    await expectLater(
      svc.ask(question: 'x'),
      throwsA(
        isA<InternalAiException>().having(
          (e) => e.kind,
          'kind',
          InternalAiErrorKind.unauthorized,
        ),
      ),
    );
  });

  test('429 映射为 quotaExhausted，提示成本由用户承担', () async {
    final svc = _TestableInternalAi(
      setting: _validSetting(),
      tools: _FakeMcpTools(),
      client: MockClient((_) async => http.Response('rate limited', 429)),
    );

    await expectLater(
      svc.ask(question: 'x'),
      throwsA(
        isA<InternalAiException>()
            .having((e) => e.kind, 'kind', InternalAiErrorKind.quotaExhausted)
            .having((e) => e.message, 'message', contains('你自己')),
      ),
    );
  });

  test('请求体带 tools 声明与 Bearer 鉴权，地址自动补 /v1', () async {
    late http.Request captured;
    final svc = _TestableInternalAi(
      setting: _validSetting(),
      tools: _FakeMcpTools(),
      client: MockClient((request) async {
        captured = request;
        return _completion({'content': 'ok'});
      }),
    );

    await svc.ask(question: 'hi');

    expect(
      captured.url.toString(),
      'https://api.example.com/v1/chat/completions',
    );
    expect(captured.headers['Authorization'], 'Bearer sk-test');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['model'], 'gpt-4o-mini');
    final tools = body['tools'] as List<dynamic>;
    expect(tools.length, 2);
    expect(
      (tools.first as Map<String, dynamic>)['function']['name'],
      'get_context',
    );
  });

  test('模型返回非法 JSON 参数时不中断，当作空参数', () async {
    var round = 0;
    final svc = _TestableInternalAi(
      setting: _validSetting(),
      tools: _FakeMcpTools(),
      client: MockClient((_) async {
        round++;
        if (round == 1) {
          return _completion({
            'tool_calls': [
              {
                'id': 'call_1',
                'type': 'function',
                'function': {'name': 'get_context', 'arguments': '{broken'},
              },
            ],
          });
        }
        return _completion({'content': '完成'});
      }),
    );

    final result = await svc.ask(question: 'x');
    expect(result.text, '完成');
    expect(result.toolCalls.first.arguments, isEmpty);
  });
}
