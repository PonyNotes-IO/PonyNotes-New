import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:appflowy/features/agent/application/agent_controller.dart';
import 'package:appflowy/features/agent/application/agent_conversations.dart';
import 'package:appflowy/features/agent/application/agent_internal_service.dart';
import 'package:appflowy/features/agent/application/agent_service.dart';
import 'package:appflowy/features/agent/presentation/agent_conversations_page.dart';
import 'package:appflowy/features/agent/presentation/agent_workspace.dart';
import 'package:appflowy/features/ai_internal/application/ai_provider_config.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (await font.exists()) {
      await (FontLoader('ReferenceFlowFont')
            ..addFont(font.readAsBytes().then(ByteData.sublistView)))
          .load();
    }
  });
  testWidgets('welcome references and mixed file types reach the first message',
      (tester) async {
    tester.view.physicalSize = const Size(1360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    const account = AgentCloudAccount(
      baseUrl: 'https://cloud.test',
      accessToken: 'token',
      userId: 'one',
    );
    Map? sent;
    var created = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/references')) {
        return http.Response(
          jsonEncode({
            'items': [
              {
                'kind': 'base',
                'id': 'base',
                'name': '项目资料库',
                'knowledge_ids': ['file'],
              },
              {
                'kind': 'file',
                'id': 'file',
                'name': '项目方案.pdf',
                'knowledge_ids': ['file'],
              },
              {
                'kind': 'note',
                'id': 'note',
                'name': '项目会议',
                'knowledge_ids': [],
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (request.url.path.endsWith('/tools')) {
        return http.Response(
          request.method == 'GET' ? '{"calls":[]}' : '',
          request.method == 'GET' ? 200 : 204,
        );
      }
      if (request.url.path.endsWith('/messages')) {
        sent = jsonDecode(request.body) as Map;
        return http.Response(
          'data: {"response_type":"scope","data":{"sources":{}}}\n\ndata: {"response_type":"complete"}\n\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }
      if (request.url.path.endsWith('/workspace')) {
        if (request.method == 'POST') {
          created++;
          return http.Response(
            request.body,
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('{"conversations":[]}', 200);
      }
      return http.Response('{"messages":[],"sources":{}}', 200);
    });
    final service = AgentService(client: client, account: () async => account);
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
    });
    final capture = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: AppFlowyTheme(
          data: AppFlowyDefaultTheme().light(),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'ReferenceFlowFont'),
            home: AgentConversationsPage(
              conversations: sessions,
              initialAttachments: [
                for (final name in [
                  'photo.jpg',
                  'plan.docx',
                  'data.xlsx',
                  'main.dart',
                ])
                  PlatformFile(
                      name: name,
                      size: 4,
                      bytes: Uint8List.fromList([1, 2, 3, 4]),),
              ],
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
                  modelName: 'DeepSeek', isInternal: true,),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '对比这些资料');
    for (final item in [('知识库', '项目资料库'), ('文件', '项目方案.pdf'), ('笔记', '项目会议')]) {
      await tester.tap(find.byTooltip('引用知识库、文件或笔记'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('关闭引用选择'), findsOneWidget);
      expect(find.text('引用列表加载失败，请重试'), findsNothing);
      await tester.tap(find.text(item.$1));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item.$2));
      await tester.pumpAndSettle();
    }
    expect(find.byType(InputChip), findsNWidgets(7));
    final output = Platform.environment['PONYNOTES_REFERENCE_SCREENSHOTS'];
    if (output != null) {
      await tester.runAsync(() async {
        final image = await (capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(output).create(recursive: true);
        await File('$output/references-welcome.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.tap(find.byTooltip('发送消息'));
    await tester.pumpAndSettle();
    expect(created, 1);
    expect(find.byType(AgentWorkspace), findsOneWidget);
    expect(sent?['query'], '对比这些资料');
    expect(sent?['images'], isEmpty);
    expect((sent?['attachments'] as List).map((f) => f['file_name']),
        ['photo.jpg', 'plan.docx', 'data.xlsx', 'main.dart'],);
    for (final file in sent?['attachments'] as List) {
      expect(base64Decode(file['data'] as String), [1, 2, 3, 4]);
      expect(file['file_size'], 4);
    }
    expect(sent?['references'], [
      {'kind': 'base', 'id': 'base'},
      {'kind': 'file', 'id': 'file'},
      {'kind': 'note', 'id': 'note'},
    ]);
    expect(find.byType(InputChip), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
