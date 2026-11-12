import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:appflowy/features/agent/application/agent_conversations.dart';
import 'package:appflowy/features/agent/application/agent_controller.dart';
import 'package:appflowy/features/agent/application/agent_internal_service.dart';
import 'package:appflowy/features/agent/application/agent_service.dart';
import 'package:appflowy/features/agent/presentation/agent_conversations_page.dart';
import 'package:appflowy/features/agent/presentation/agent_workspace.dart';
import 'package:appflowy/features/agent/presentation/ai_mode_button.dart';
import 'package:appflowy/features/ai_internal/application/ai_provider_config.dart';
import 'package:appflowy/plugins/standalone_ai_chat/presentation/ai_welcome_page.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
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
  testWidgets(
      'opening independent conversations exits the retained legacy mode',
      (tester) async {
    await tester.pumpWidget(AppFlowyTheme(
      data: AppFlowyDefaultTheme().light(),
      child: MaterialApp(
        home:
            AIWelcomePage(onMessageSent: (_, __, ___, ____, _____, ______) {}),
      ),
    ));
    tester
        .widget<AgentConversationsPage>(find.byType(AgentConversationsPage))
        .onLegacy!();
    AgentConversations.requestOpen();
    await tester.pumpAndSettle();
    expect(find.byType(AgentConversationsPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final variant in [
    (name: 'desktop', size: const Size(1360, 900)),
    (name: 'phone', size: const Size(390, 844)),
  ]) {
    testWidgets(
        'standalone conversations create and restore without note calls on ${variant.name}',
        (tester) async {
      tester.view.physicalSize = variant.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const account = AgentCloudAccount(
        baseUrl: 'https://cloud.test',
        accessToken: 'token',
        userId: 'one',
      );
      var created = 0;
      Completer<void>? refresh;
      final rows = <Map<String, dynamic>>[
        {'id': 'history', 'title': '最新的笔记是什么'},
        {'id': 'week', 'title': '将第一篇笔记整理为周笔记'},
      ];
      final service = AgentService(
        account: () async => account,
        client: MockClient((request) async {
          expectSync(
            request.url.path,
            startsWith('/api/ai/agent/conversations/workspace'),
          );
          if (request.url.path.endsWith('/tools')) {
            return http.Response(
              request.method == 'GET' ? '{"calls":[]}' : '',
              request.method == 'GET' ? 200 : 204,
            );
          }
          if (request.url.path == '/api/ai/agent/conversations/workspace') {
            if (request.method == 'POST') {
              created++;
              final row =
                  Map<String, dynamic>.from(jsonDecode(request.body) as Map);
              rows.insert(0, row);
              return http.Response(
                jsonEncode(row),
                200,
                headers: {
                  'content-type': 'application/json; charset=utf-8',
                },
              );
            }
            await refresh?.future;
            return http.Response(
              jsonEncode({'conversations': rows}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response(
            jsonEncode({
              'messages': request.url.path.endsWith('/history')
                  ? [
                      {'id': 'u', 'role': 'user', 'content': '最新的笔记是什么？'},
                      {
                        'id': 'a',
                        'role': 'assistant',
                        'content': '最近更新的是 **项目会议记录**。\n\n记录包含产品方案评审和接口联调两项待办。',
                      },
                    ]
                  : [],
              'sources': {},
              'mode': 'smart-reasoning',
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final store = AgentConversations(
        service: service,
        workspace: () async => 'workspace',
      );
      addTearDown(store.dispose);
      AgentController controller(AgentConversation row, String workspace) =>
          AgentController(
            chatId: row.id,
            documentName: row.title,
            independent: true,
            workspaceId: () async => workspace,
            service: service,
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
              const AiProviderConfig(modelName: 'DeepSeek', isInternal: true);
      final capture = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: AppFlowyTheme(
            data: AppFlowyDefaultTheme().light(),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'AgentTestFont'),
              home: AgentConversationsPage(
                conversations: store,
                controllerFactory: controller,
                initialAttachments: [
                  PlatformFile(
                    name: 'draft.txt',
                    size: 3,
                    bytes: Uint8List.fromList([1, 2, 3]),
                  ),
                ],
                onLegacy: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(store.error, isNull);
      await tester.enterText(find.byType(TextField), '保留输入草稿');
      await tester.tap(find.byType(AiModeButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('快问快答').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '保留输入草稿',
      );
      expect(find.text('draft.txt'), findsOneWidget);
      if (variant.name == 'phone') {
        await tester.tap(find.byTooltip('AI 历史会话'));
        await tester.pumpAndSettle();
      }
      expect(find.text('历史会话'), findsOneWidget);
      expect(find.text('我的AI会话'), findsNothing);
      await tester.tap(find.text('最新的笔记是什么'));
      await tester.pumpAndSettle();
      expect(find.text('最新的笔记是什么？'), findsOneWidget);
      expect(find.byType(AgentWorkspace), findsOneWidget);
      final active =
          tester.widget<AgentWorkspace>(find.byType(AgentWorkspace)).controller;
      expect(active.mode, 'smart-reasoning');
      await tester.enterText(find.byType(TextField), '会话内草稿');
      await tester.tap(find.byType(AiModeButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('快问快答').last);
      await tester.pumpAndSettle();
      expect(active.mode, 'quick-answer');
      expect(active.chatId, 'history');
      expect(active.messages.length, 2);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '会话内草稿',
      );
      active.running = true;
      active.changed();
      await tester.pump();
      await tester.tap(find.byType(AiModeButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text('智能推理').last);
      await tester.pump(const Duration(milliseconds: 350));
      expect(active.mode, 'smart-reasoning');
      expect(active.running, true);
      expect(active.chatId, 'history');
      active.running = false;
      active.changed();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final output = Platform.environment['PONYNOTES_AGENT_SCREENSHOTS'];
      if (output != null) {
        await tester.runAsync(() async {
          final image = await (capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File('$output/independent-conversations-${variant.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      if (variant.name == 'phone') {
        await tester.tap(find.byTooltip('AI 历史会话'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('新建对话'));
      await tester.pumpAndSettle();
      expect(created, 1);
      expect(store.entries.first.title, '新对话');
      expect(
        tester
            .widget<AgentWorkspace>(find.byType(AgentWorkspace))
            .controller
            .mode,
        'quick-answer',
      );
      expect(
        tester
            .widget<AgentWorkspace>(find.byType(AgentWorkspace))
            .controller
            .chatId,
        store.entries.first.id,
      );
      if (variant.name == 'phone') {
        await tester.tap(find.byTooltip('AI 历史会话'));
        await tester.pumpAndSettle();
      }
      refresh = Completer<void>();
      await tester.tap(find.byTooltip('刷新会话'));
      await tester.pump();
      AgentConversations.requestedPrompt.value = ('整理摘要', []);
      expect(AgentConversations.requestedPrompt.value, isNotNull);
      refresh.complete();
      await tester.pumpAndSettle();
      expect(AgentConversations.requestedPrompt.value, isNull);
      expect(created, 2);
      expect(store.entries.first.title, '整理摘要');
      expect(tester.takeException(), isNull);
      await AgentController.revokeAll();
      await tester.pumpAndSettle();
      expect(find.text('账号或工作区已切换，请重新打开问 AI'), findsOneWidget);
      expect(find.text('最新的笔记是什么？'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
