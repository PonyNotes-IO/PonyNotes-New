import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:appflowy/features/agent/application/agent_controller.dart';
import 'package:appflowy/features/agent/application/agent_credits.dart';
import 'package:appflowy/features/agent/presentation/agent_workspace.dart';
import 'package:appflowy/features/agent/presentation/agent_composer.dart';
import 'package:appflowy/features/agent/presentation/ai_mode_button.dart';
import 'package:appflowy/features/agent/presentation/agent_artifact_panel.dart';
import 'package:appflowy/features/ai_internal/application/ai_provider_config.dart';
import 'package:appflowy/features/agent/application/agent_internal_service.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'artifact_test_helpers.dart';

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
  test(
      'old documents keep Chat mode and Agent documents keep their entry point',
      () {
    expect(isAgentDocument(''), false);
    expect(isAgentDocument('{"ai_mode":"chat"}'), false);
    expect(isAgentDocument('{"ai_mode":"agent"}'), true);
    expect(isAgentDocument('{"ai_engine":"weknora","ai_mode":"chat"}'), true);
  });
  for (final variant in [
    (name: 'desktop-light', size: const Size(1360, 900), dark: false),
    (name: 'desktop-dark', size: const Size(1360, 900), dark: true),
    (name: 'phone-dark', size: const Size(390, 844), dark: true),
  ]) {
    testWidgets(
        'knowledge Agent renders and clears private drafts on ${variant.name}',
        (tester) async {
      tester.view.physicalSize = variant.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = await tester.runAsync(() async {
        final files =
            await Directory.systemTemp.createTemp('artifact-sidebar-');
        final file = File('${files.path}/行动清单.md');
        await file.writeAsString(
          '# 项目行动清单\n\n根据会议记录整理，接下来完成：\n\n## 产品方案\n\n- 周五前完成评审\n- 确认发布范围\n\n## 接口联调\n\n等待服务端确认返回格式。\n',
        );
        return (files, file, await file.length());
      });
      addTearDown(() => fixture!.$1.delete(recursive: true));
      final artifactFile = fixture!.$2;
      final controller = AgentController(
        chatId: 'visual-test',
        internalService: AgentInternalService(
          account: () async => const AgentCloudAccount(
            baseUrl: 'https://cloud.test',
            accessToken: 'token',
            userId: '1',
          ),
          client: MockClient(
            (_) async => http.Response('{"data":[{"id":"DeepSeek"}]}', 200),
          ),
        ),
      )
        ..connected = true
        ..model = 'DeepSeek'
        ..providerConfig =
            const AiProviderConfig(modelName: 'DeepSeek', isInternal: true)
        ..credits = const AgentCredits(usd: 0.99735828);
      controller.sources['note'] = {
        'title': '项目会议记录',
        'url': 'ponynotes://open?viewId=page&workspaceId=workspace',
      };
      controller.messages.addAll([
        {
          'role': 'user',
          'content': '对比项目会议记录，列出还没有完成的事项。',
          'attachments': [
            {
              'id': 'pdf',
              'file_name': '扫描件.pdf',
              'file_size': 532480,
              'status': 'ready',
            }
          ],
        },
        {
          'id': 'answer',
          'role': 'assistant',
          'content':
              '会议记录中还有两项待办：\n\n- **产品方案**：周五前完成评审。\n- **接口联调**：等待服务端确认返回格式。\n\n文件 `扫描件.pdf` 已读取，结果保存在 `/workspace/output`。',
          'agent_steps': [
            {
              'tool_calls': [
                {
                  'id': 'read-pdf',
                  'name': 'read_file',
                  'target': {
                    'name': 'read_file',
                    'args': {'path': 'attachment://pdf'},
                  },
                  'result': {'success': true, 'output': '读取完成'},
                }
              ],
            }
          ],
          'knowledge_references': [
            {'knowledge_id': 'note'},
          ],
          'artifacts': [
            {'index': 0, 'file_name': '项目行动清单.md', 'file_size': fixture.$3},
          ],
        }
      ]);
      controller.artifactFiles['answer/0'] = artifactFile;
      final boundary = GlobalKey();
      final screenBoundary = GlobalKey();
      final theme = AppFlowyDefaultTheme();
      await tester.pumpWidget(
        RepaintBoundary(
          key: screenBoundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: variant.dark ? Brightness.dark : Brightness.light,
              fontFamily: 'AgentTestFont',
            ),
            home: Material(
              child: AppFlowyTheme(
                data: variant.dark ? theme.dark() : theme.light(),
                child: RepaintBoundary(
                  key: boundary,
                  child: AgentWorkspace(controller: controller),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
      expect(find.text('项目会议记录'), findsOneWidget);
      expect(find.text('99.74 积分'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(AiModeButton), findsOneWidget);
      expect(find.textContaining('项目行动清单.md'), findsOneWidget);
      expect(find.text('产物云同步'), findsOneWidget);
      for (final control in [
        find.byTooltip('添加图片或文件'),
        find.byTooltip('发送'),
        find.byKey(const Key('agent-approval-mode')),
        find.text('产物云同步'),
        find.byType(AiModeButton),
        find.byTooltip('笔记工具设置'),
      ]) {
        expect(
          tester.getRect(find.byType(AgentComposer)).contains(
                tester.getCenter(control),
              ),
          isTrue,
        );
      }
      final markdown =
          tester.widgetList<MarkdownWidget>(find.byType(MarkdownWidget)).last;
      final ink = theme.dark().textColorScheme.primary;
      final paper = markdown.config!.code.style.backgroundColor!;
      if (variant.dark) {
        final contrast =
            (ink.computeLuminance() + .05) / (paper.computeLuminance() + .05);
        expect(contrast, greaterThanOrEqualTo(4.5));
      }
      await tester.tap(find.byType(AiModeButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('快问快答').last);
      await tester.pumpAndSettle();
      expect(controller.mode, 'quick-answer');
      expect(controller.chatId, 'visual-test');
      expect(controller.messages.length, 2);
      controller.configureMode(true);
      await tester.pump();
      await tester.tap(find.textContaining('项目行动清单.md'));
      await tester.pump(const Duration(milliseconds: 350));
      await settleArtifactFiles(tester);
      expect(find.byType(AgentArtifactPanel), findsOneWidget);
      expect(find.byType(AgentArtifactPreview), findsOneWidget);
      expect(find.text('另存为'), findsOneWidget);
      expect(find.textContaining('本地文件已移走'), findsNothing);
      expect(tester.takeException(), isNull);
      final previewOutput = Platform.environment['PONYNOTES_AGENT_SCREENSHOTS'];
      if (previewOutput != null) {
        await tester.runAsync(() async {
          final image = await (screenBoundary.currentContext!
                  .findRenderObject()! as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(previewOutput).create(recursive: true);
          await File('$previewOutput/artifact-sidebar-${variant.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.byTooltip('关闭产物侧边栏'));
      await tester.pumpAndSettle();
      expect(find.textContaining('工作目录'), findsNothing);
      expect(find.textContaining('执行器'), findsNothing);
      final approval = Completer<bool>();
      controller.running = true;
      controller.interactions.add({
        'id': 'pending',
        'title': 'append_content',
        'arguments': {'page_id': 'page', 'content': '项目行动清单'},
        'before': '原有会议记录',
        'confirmation': approval,
      });
      controller.changed();
      await tester.pump();
      expect(find.text('允许这次'), findsOneWidget);
      expect(find.text('拒绝'), findsOneWidget);
      expect(find.byTooltip('停止任务'), findsOneWidget);
      final output = Platform.environment['PONYNOTES_AGENT_SCREENSHOTS'];
      if (output != null) {
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File('$output/${variant.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.enterText(find.byType(TextField), '退出后应清空的草稿');
      await controller.disconnect();
      expect(await approval.future, false);
      await tester.pump();
      expect(find.text('退出后应清空的草稿'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await tester.pump(const Duration(seconds: 1));
    });
  }

  testWidgets(
      'history opens at latest and output follows until the user scrolls up',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AgentController(chatId: 'scroll-test')..connected = true;
    controller.messages.addAll(
      List.generate(
        30,
        (i) => {
          'role': i.isEven ? 'user' : 'assistant',
          'content': '历史消息 $i\n\n这是一段用于验证滚动位置的完整对话。',
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: AppFlowyTheme(
            data: AppFlowyDefaultTheme().dark(),
            child: AgentWorkspace(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final timeline =
        tester.widget<ListView>(find.byKey(const Key('agent-timeline')));
    final position = timeline.controller!.position;
    expect(position.extentAfter, lessThan(2));
    controller.running = true;
    controller.streamingText = List.filled(15, '正在输出新的内容。\n\n').join();
    controller.changed();
    await tester.pump();
    await tester.pump();
    expect(position.extentAfter, lessThan(2));
    await tester.drag(
      find.byKey(const Key('agent-timeline')),
      const Offset(0, 400),
    );
    await tester.pumpAndSettle();
    final readingOffset = position.pixels;
    expect(find.text('回到最新'), findsOneWidget);
    controller.streamingText += List.filled(10, '追加内容。\n\n').join();
    controller.changed();
    await tester.pump();
    await tester.pump();
    expect(position.pixels, closeTo(readingOffset, 1));
    await tester.tap(find.text('回到最新'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(position.extentAfter, lessThan(2));
    expect(find.text('回到最新'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await tester.pump(const Duration(seconds: 1));
  });
}
