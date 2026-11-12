import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:appflowy/features/agent/application/agent_controller.dart';
import 'package:appflowy/features/agent/application/agent_prompt.dart';
import 'package:appflowy/features/agent/application/agent_service.dart';
import 'package:appflowy/features/agent/presentation/agent_prompt_card.dart';
import 'package:appflowy/features/agent/presentation/agent_workspace.dart';
import 'package:appflowy/features/ai_internal/application/ai_provider_config.dart';
import 'package:appflowy/features/mcp/application/mcp_tools.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

const pageId = '11111111-1111-4111-8111-111111111111';

class _Service extends AgentService {
  final calls = <(String, String, Map<String, dynamic>?)>[];
  Completer<void>? history;
  int polls = 0;
  Map<String, dynamic>? sent;
  String? resumePath;
  List<Map<String, dynamic>> messages = [];

  @override
  Future<String> identity(String workspace) async => 'server|user|$workspace';

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String workspace,
    String document,
    String suffix, [
    Map<String, dynamic>? body,
  ]) async {
    calls.add((method, suffix, body));
    if (suffix.startsWith('/tools?') && method == 'GET') polls++;
    if (suffix.isEmpty) await history?.future;
    if (suffix == '/prompt-response') return {'resumed': true};
    return {'messages': messages, 'sources': {}, 'calls': []};
  }

  @override
  Stream<Map<String, dynamic>> stream(
    String method,
    String workspace,
    String document,
    String suffix, [
    Map<String, dynamic>? body,
  ]) async* {
    if (method == 'POST') sent = body;
    if (method == 'GET') resumePath = suffix;
    yield {
      'response_type': 'scope',
      'data': {'sources': {}},
    };
    yield {'response_type': 'complete', 'data': {}};
  }
}

class _Tools extends McpTools {
  _Tools() : super(endpoint: 'test', version: '1');
  final calls = <String>[];
  Completer<void>? reading;
  @override
  List<McpToolSpec> get toolSpecs => [
        for (final name in ['search_notes', 'get_page'])
          McpToolSpec(
            name: name,
            description: name,
            readOnly: true,
            inputSchema: JsonObject(
              properties: {
                'workspace_id': JsonString(),
                'query': JsonString(),
                'limit': JsonInteger(),
                'page_id': JsonString(),
              },
            ),
            handler: (_) async {
              calls.add(name);
              if (name == 'get_page') await reading?.future;
              return CallToolResult(
                content: [
                  TextContent(
                    text: jsonEncode(
                      name == 'search_notes'
                          ? {
                              'complete': true,
                              'results': [
                                {'page_id': pageId, 'title': '项目会议'},
                              ],
                            }
                          : {'content_supported': true, 'text': '方案周五评审。'},
                    ),
                  ),
                ],
              );
            },
          ),
      ];
}

class _Controller extends AgentController {
  _Controller(_Service service, {super.mode = 'quick-answer'})
      : super(
          chatId: 'conversation',
          service: service,
          workspaceId: () async => 'workspace',
        ) {
    providerConfig = const AiProviderConfig(modelName: 'test');
  }
  final tools = _Tools();
  @override
  McpTools get noteTools => tools;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (await font.exists()) {
      await (FontLoader('AgentTestFont')
            ..addFont(font.readAsBytes().then(ByteData.sublistView)))
          .load();
    }
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('quick answer retrieves live notes without opening MCP', () async {
    final service = _Service();
    final agent = _Controller(service);
    final sending = agent.send('项目还有什么待办？');
    await Future<void>.delayed(Duration.zero);
    expect(await sending, true);
    await Future<void>.delayed(Duration.zero);
    expect(agent.tools.calls, ['search_notes', 'get_page']);
    expect(service.sent!['query'], '项目还有什么待办？');
    expect(service.sent!['mode'], 'quick-answer');
    expect(service.sent!['note_search_status'], 'complete');
    expect(
      (service.sent!['note_context'] as List).single['content'],
      '方案周五评审。',
    );
    expect(
      service.calls.where((c) => c.$2 == '/tools' && c.$1 == 'POST'),
      isEmpty,
    );
    await agent.disconnect();
    agent.dispose();
    await Future<void>.delayed(Duration.zero);
  });

  test('disabled note retrieval is explicit and still queries knowledge',
      () async {
    final service = _Service();
    final agent = _Controller(service);
    await agent.connect();
    agent.permissions.disabledTools.add('search_notes');
    final sending = agent.send('问题');
    await Future<void>.delayed(Duration.zero);
    expect(await sending, true);
    expect(agent.tools.calls, isEmpty);
    expect(service.sent!['note_search_status'], 'disabled');
    await agent.disconnect();
    agent.dispose();
    await Future<void>.delayed(Duration.zero);
  });

  testWidgets(
      'disconnect during note reading never submits or restores private data',
      (tester) async {
    final service = _Service();
    final agent = _Controller(service);
    agent.tools.reading = Completer<void>();
    final sending = agent.send('问题');
    await tester.pump();
    expect(agent.preparingNotes, true);
    await agent.disconnect();
    agent.tools.reading!.complete();
    expect(await sending, false);
    expect(service.sent, isNull);
    expect(agent.sources, isEmpty);
    agent.dispose();
    await tester.pump();
  });

  testWidgets('stopping note retrieval leaves the question unsent',
      (tester) async {
    final service = _Service();
    final agent = _Controller(service);
    agent.tools.reading = Completer<void>();
    final sending = agent.send('停止前的问题');
    await tester.pump();
    await agent.stop();
    agent.tools.reading!.complete();
    expect(await sending, false);
    expect(service.sent, isNull);
    expect(agent.messages, isEmpty);
    expect(agent.notice, contains('尚未发送'));
    await agent.disconnect();
    agent.dispose();
    await tester.pump();
  });

  testWidgets('MCP heartbeat starts while history is still loading',
      (tester) async {
    final service = _Service()..history = Completer<void>();
    final agent = _Controller(service, mode: 'smart-reasoning');
    final connecting = agent.connect();
    await tester.pump();
    for (var i = 0; i < 17; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(service.polls, greaterThan(10));
    service.history!.complete();
    await connecting;
    await agent.disconnect();
    agent.dispose();
    await tester.pump();
  });

  test('answering a suspended question resumes the same message', () async {
    final service = _Service();
    final agent = _Controller(service, mode: 'smart-reasoning');
    await agent.connect();
    agent.receive({
      'response_type': 'agent_prompt_required',
      'assistant_message_id': 'message',
      'data': {
        'pending_id': 'prompt',
        'kind': 'ask_user',
        'request': {
          'question': '输出哪种格式？',
          'options': ['PDF', 'Word'],
        },
      },
    });
    agent.receive({
      'response_type': 'complete',
      'data': {
        'suspended': {'pending_id': 'prompt'},
      },
    });
    expect(agent.prompts.length, 1);
    await agent.answerPrompt(agent.prompts.values.single, {
      'selected': ['PDF'],
    });
    await Future<void>.delayed(Duration.zero);
    expect(
      service.calls
          .where((c) => c.$2 == '/prompt-response')
          .single
          .$3!['message_id'],
      'message',
    );
    expect(
      service.resumePath,
      '/stream?message_id=message&resume_pending_id=prompt',
    );
    expect(agent.prompts, isEmpty);
    await agent.disconnect();
    agent.dispose();
    await Future<void>.delayed(Duration.zero);
  });

  test('live prompt history restores a question before the run suspends',
      () async {
    final service = _Service()
      ..messages = [
        {
          'id': 'message',
          'role': 'assistant',
          'is_completed': true,
          'prompt_history': [
            {
              'id': 'prompt',
              'kind': 'ask_user',
              'status': 'pending',
              'request': {
                'question': '选择格式',
                'options': ['PDF', 'Word'],
              },
            },
            {
              'id': 'old',
              'kind': 'ask_user',
              'status': 'answered',
              'request': {'question': '已回答的问题'},
            },
          ],
        },
      ];
    final agent = _Controller(service);
    await agent.connect();
    expect(agent.prompts.keys, ['prompt']);
    expect(agent.prompts.values.single.messageId, 'message');
    await agent.disconnect();
    agent.dispose();
  });

  testWidgets('structured question validates choices and numeric fields',
      (tester) async {
    Map<String, dynamic>? answer;
    final prompt = AgentPrompt(
      id: 'ask',
      kind: 'ask_user',
      messageId: 'message',
      request: {
        'question': '你希望怎样安排这次汇报？',
        'options': ['精简版', '完整分析'],
        'allow_free_text': true,
        'fields': [
          {'name': 'pages', 'label': '页数', 'type': 'number', 'required': true},
        ],
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentPromptCard(
            prompt: prompt,
            onAnswer: (value) async {
              answer = value;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('继续'));
    await tester.pump();
    expect(answer, isNull);
    await tester.tap(find.text('完整分析'));
    await tester.enterText(find.byType(TextFormField).first, '8');
    await tester.tap(find.text('继续'));
    await tester.pump();
    expect(answer!['selected'], ['完整分析']);
    expect(answer!['values'], {'pages': 8});
  });

  for (final size in [const Size(1200, 860), const Size(390, 844)]) {
    testWidgets('interactive question renders at ${size.width}',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final agent = AgentController(chatId: 'preview')..connected = true;
      agent.messages
          .add({'role': 'user', 'content': '结合知识库和会议笔记，帮我整理一份项目进展汇报。'});
      agent.messages.add({
        'role': 'assistant',
        'content': '我找到了知识库中的项目方案和最新会议记录。汇报前，还需要确认一个细节。',
      });
      agent.receive({
        'response_type': 'agent_prompt_required',
        'assistant_message_id': 'message',
        'data': {
          'pending_id': 'prompt',
          'kind': 'ask_user',
          'request': {
            'question': '这份汇报主要给谁看？',
            'options': ['项目团队', '管理层', '外部客户'],
            'allow_free_text': true,
          },
        },
      });
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'AgentTestFont'),
          home: RepaintBoundary(
            key: boundary,
            child: Material(
              child: AppFlowyTheme(
                data: AppFlowyDefaultTheme().light(),
                child: AgentWorkspace(controller: agent),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.text('这份汇报主要给谁看？'), findsOneWidget);
      final output = Platform.environment['PONYNOTES_AGENT_SCREENSHOTS'];
      if (output != null) {
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File('$output/prompt-${size.width.toInt()}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
      agent.dispose();
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
