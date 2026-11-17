import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/features/agent/application/agent_controller.dart';
import 'package:appflowy/features/agent/application/agent_conversations.dart';
import 'package:appflowy/features/agent/application/agent_internal_service.dart';
import 'package:appflowy/features/agent/application/agent_service.dart';
import 'package:appflowy/features/agent/presentation/agent_composer.dart';
import 'package:appflowy/features/agent/presentation/agent_conversations_page.dart';
import 'package:appflowy/features/agent/presentation/agent_workspace.dart';
import 'package:appflowy/features/agent/presentation/ai_mode_button.dart';
import 'package:appflowy/features/ai_internal/application/ai_provider_config.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      await (FontLoader('ComposerTestFont')
            ..addFont(font.readAsBytes().then(ByteData.sublistView)))
          .load();
    }
  });

  for (final variant in [
    (name: 'desktop-light', size: const Size(1360, 900), dark: false),
    (name: 'desktop-dark', size: const Size(1360, 900), dark: true),
    (name: 'reference-dark', size: const Size(951, 480), dark: true),
    (name: 'medium-light', size: const Size(927, 754), dark: false),
    (name: 'phone-dark', size: const Size(390, 844), dark: true),
    (name: 'compact-light', size: const Size(320, 640), dark: false),
  ]) {
    testWidgets('composer stays fixed through first send on ${variant.name}',
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
      final events = StreamController<List<int>>();
      Map? sent;
      Map? steered;
      var stopped = false;
      var completed = false;
      final client = MockClient.streaming((request, body) async {
        final requestBody = await body.bytesToString();
        if (request.url.path.endsWith('/messages')) {
          sent = jsonDecode(requestBody) as Map;
          events.add(
            utf8.encode(
              'data: {"response_type":"scope","assistant_message_id":"answer","data":{"sources":{}}}\n\n',
            ),
          );
          return http.StreamedResponse(
            events.stream,
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }
        if (request.url.path.endsWith('/steer')) {
          steered = jsonDecode(requestBody) as Map;
        }
        if (request.url.path.endsWith('/stop')) stopped = true;
        final data = request.url.path.endsWith('/workspace')
            ? request.method == 'POST'
                ? requestBody
                : '{"conversations":[]}'
            : request.url.path.endsWith('/tools')
                ? '{"calls":[]}'
                : jsonEncode({
                    'messages': [
                      if (sent != null) ...[
                        {'role': 'user', 'content': sent!['query']},
                        if (completed)
                          {
                            'id': 'answer',
                            'role': 'assistant',
                            'content': '会议记录已整理。',
                          },
                      ],
                    ],
                    'sources': {},
                  });
        return http.StreamedResponse(
          Stream.value(utf8.encode(data)),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final service =
          AgentService(client: client, account: () async => account);
      final sessions = AgentConversations(
        service: service,
        workspace: () async => 'workspace',
      );
      final internalClient = MockClient(
        (_) async => http.Response(
          '{"unit":"USD","remaining":1,"credits_per_usd":100}',
          200,
        ),
      );
      addTearDown(() {
        sessions.dispose();
        client.close();
        internalClient.close();
        unawaited(events.close());
      });
      final capture = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: AppFlowyTheme(
            data: variant.dark
                ? AppFlowyDefaultTheme().dark()
                : AppFlowyDefaultTheme().light(),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                brightness: variant.dark ? Brightness.dark : Brightness.light,
                fontFamily: 'ComposerTestFont',
              ),
              home: AgentConversationsPage(
                conversations: sessions,
                controllerFactory: (row, workspace) => AgentController(
                  chatId: row.id,
                  independent: true,
                  service: service,
                  workspaceId: () async => workspace,
                  internalService: AgentInternalService(
                    client: internalClient,
                    account: () async => account,
                  ),
                )..providerConfig = const AiProviderConfig(
                    modelName: 'DeepSeek',
                    isInternal: true,
                  ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final composer = find.byType(AgentComposer);
      final before = tester.getRect(composer);
      final mode = tester.getRect(find.byType(AiModeButton));
      final reference = tester.getRect(find.byTooltip('引用知识库、文件或笔记'));
      final attach = tester.getRect(find.byTooltip('上传文件'));
      final send = tester.getRect(find.byTooltip('发送消息'));

      Future<void> screenshot(String state) async {
        final output = Platform.environment['PONYNOTES_COMPOSER_SCREENSHOTS'];
        if (output == null) return;
        final rect = tester.getRect(composer);
        await tester.runAsync(() async {
          final image = await (capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          final path = '$output/${variant.name}-$state';
          await File('$path.png').writeAsBytes(bytes!.buffer.asUint8List());
          await File('$path.json').writeAsString(
            jsonEncode({
              'left': rect.left,
              'top': rect.top,
              'width': rect.width,
              'height': rect.height,
            }),
          );
          image.dispose();
        });
      }

      void expectStable(Finder primary) {
        expect(tester.getRect(composer), before);
        expect(tester.getRect(find.byType(AiModeButton)), mode);
        expect(tester.getRect(find.byTooltip('引用知识库、文件或笔记')), reference);
        expect(tester.getRect(find.byTooltip('添加图片或文件')), attach);
        expect(tester.getRect(primary), send);
        expect(find.text('产物云同步'), findsNothing);
        expect(find.byKey(const Key('agent-approval-mode')), findsNothing);
        expect(tester.takeException(), isNull);
      }

      await screenshot('welcome');
      await tester.enterText(find.byType(TextField), '帮我整理会议记录');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      // The running answer intentionally keeps its progress animation active.
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(sent?['query'], '帮我整理会议记录');
      expectStable(find.byTooltip('停止任务'));
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.attach_file),
            )
            .onPressed,
        isNull,
      );
      await screenshot('running');
      await tester.enterText(find.byType(TextField), '请再简短一些');
      await tester.pump();
      expectStable(find.byTooltip('发送指令'));
      await tester.tap(find.byTooltip('发送指令'));
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(steered?['query'], '请再简短一些');
      expect(steered?['delivery'], 'inject');
      expectStable(find.byTooltip('停止任务'));
      expect(find.text('待处理 1 条补充'), findsOneWidget);
      completed = true;
      events.add(
        utf8.encode(
          'data: {"response_type":"complete","data":{"final_content":"会议记录已整理。"}}\n\n',
        ),
      );
      await events.close();
      await tester.pumpAndSettle();
      expectStable(find.byTooltip('发送'));
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.arrow_upward),
            )
            .onPressed,
        isNull,
      );
      await screenshot('complete');

      final controller =
          tester.widget<AgentWorkspace>(find.byType(AgentWorkspace)).controller;
      controller.running = true;
      controller.changed();
      await tester.pump();
      expectStable(find.byTooltip('停止任务'));
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.stop_rounded),
            )
            .onPressed,
        controller.stop,
      );
      await tester.runAsync(controller.stop);
      await tester.pump();
      expect(controller.error, isNull);
      expect(stopped, true);
      expect(controller.running, false);
      expectStable(find.byTooltip('发送'));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
