import 'dart:io';
import 'dart:ui' as ui;
import 'package:appflowy/features/agent/application/agent_artifacts.dart';
import 'package:appflowy/features/agent/application/agent_controller.dart';
import 'package:appflowy/features/agent/presentation/agent_artifact_panel.dart';
import 'package:appflowy/features/agent/presentation/agent_artifact_library.dart';
import 'package:appflowy/features/agent/presentation/agent_artifact_plugin.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_artifacts_button.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'artifact_test_helpers.dart';

class _ArtifactTabs extends MockBloc<TabsEvent, TabsState> implements TabsBloc {
  final events = <TabsEvent>[];
  @override
  void add(TabsEvent event) => events.add(event);
}

void main() {
  late Directory folder;
  late List<AgentArtifact> files;
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
  setUp(() async {
    folder = await Directory.systemTemp.createTemp('artifact-panel-');
    files = [];
    for (final entry in [
      (
        'report.md',
        '项目行动清单.md',
        '# 项目行动清单\n\n会议资料已整理为三项任务。\n\n## 产品评审\n\n周五前完成方案评审，确认需求范围。\n\n## 接口联调\n\n核对服务端返回格式。\n\n## 发布准备\n\n整理回归记录和交付说明。'
      ),
      ('data.json', '分析结果.json', '{"status":"ready","tasks":3}'),
    ]) {
      final file = File('${folder.path}/${entry.$1}');
      await file.writeAsString(entry.$3);
      files.add(
        AgentArtifact(
          document: 'document-${files.length}',
          message: 'answer',
          index: 0,
          name: entry.$2,
          size: await file.length(),
          file: file,
          createdAt: DateTime(2026, 11, 12),
          documentName: files.isEmpty ? '项目会议记录' : '数据整理',
        ),
      );
    }
  });
  tearDown(() async => folder.delete(recursive: true));

  test('artifact plugin is a separate sidebar destination, not a note layout',
      () {
    final builder = AgentArtifactPluginBuilder();
    expect(builder.pluginType, PluginType.agentArtifacts);
    expect(builder.layoutType, isNull);
    expect(AgentArtifactPluginConfig().creatable, false);
    expect(builder.build(null).id, 'agent_artifacts');
  });

  for (final variant in [
    (name: 'desktop-light', size: const Size(1360, 900), dark: false),
    (name: 'phone-dark', size: const Size(390, 844), dark: true),
  ]) {
    testWidgets(
        'all artifacts search, switch previews and protect account data on ${variant.name}',
        (tester) async {
      tester.view.physicalSize = variant.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: variant.dark ? Brightness.dark : Brightness.light,
            fontFamily: 'AgentTestFont',
          ),
          home: RepaintBoundary(
            key: boundary,
            child: AgentArtifactLibrary(load: () async => files),
          ),
        ),
      );
      await settleArtifactFiles(tester);
      expect(find.text('全部产物 · 2'), findsOneWidget);
      expect(find.byType(AgentArtifactPreview), findsOneWidget);
      expect(find.text('另存为'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final output = Platform.environment['PONYNOTES_AGENT_SCREENSHOTS'];
      if (output != null) {
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File('$output/artifact-library-${variant.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.widgetWithText(ListTile, '分析结果.json'));
      await settleArtifactFiles(tester);
      expect(find.text('{"status":"ready","tasks":3}'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '会议');
      await settleArtifactFiles(tester);
      expect(find.widgetWithText(ListTile, '项目行动清单.md'), findsOneWidget);
      expect(find.widgetWithText(ListTile, '分析结果.json'), findsNothing);
      await tester.enterText(find.byType(TextField), '不存在的文件');
      await tester.pumpAndSettle();
      expect(find.text('没有匹配的产物'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '');
      await settleArtifactFiles(tester);
      await AgentController.revokeAll();
      await tester.pumpAndSettle();
      expect(find.text('账号已切换，请重新打开全部产物'), findsOneWidget);
      expect(find.byType(AgentArtifactPreview), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('sidebar and Ask AI entries open the same artifact plugin',
      (tester) async {
    final tabs = _ArtifactTabs();
    getIt.registerSingleton<TabsBloc>(tabs);
    getIt.registerSingleton<PluginSandbox>(PluginSandbox());
    registerPlugin(
      builder: AgentArtifactPluginBuilder(),
      config: AgentArtifactPluginConfig(),
    );
    addTearDown(() async {
      await getIt.unregister<TabsBloc>();
      await getIt.unregister<PluginSandbox>();
      await tabs.close();
    });
    await tester.pumpWidget(
      BlocProvider<TabsBloc>.value(
        value: tabs,
        child: AppFlowyTheme(
          data: AppFlowyDefaultTheme().light(),
          child: const MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  SidebarArtifactsButton(),
                  AllAgentArtifactsButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('产物'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部产物'));
    await tester.pumpAndSettle();
    expect(tabs.events.length, 2);
    for (final event in tabs.events) {
      event.maybeWhen(
        openPlugin: (plugin, _, __) =>
            expect(plugin.pluginType, PluginType.agentArtifacts),
        orElse: () => fail('Expected artifact plugin navigation'),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'missing local files and unsupported formats keep a clear recovery path',
      (tester) async {
    final missing = AgentArtifact(
      document: 'document',
      message: 'answer',
      index: 0,
      name: 'missing.txt',
      size: 10,
      file: File('${folder.path}/missing.txt'),
      createdAt: DateTime(2026),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AgentArtifactPreview(artifact: missing)),
      ),
    );
    await settleArtifactFiles(tester);
    expect(find.text('本地文件已移走或删除，请回到来源对话重新下载'), findsOneWidget);
    final unsupported = AgentArtifact(
      document: 'document',
      message: 'answer',
      index: 1,
      name: 'output.bin',
      size: files[1].size,
      file: files[1].file,
      createdAt: DateTime(2026),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentArtifactPreview(
            key: const ValueKey('binary'),
            artifact: unsupported,
          ),
        ),
      ),
    );
    await settleArtifactFiles(tester);
    expect(find.text('此格式可用关联应用打开，原始文件已保存在本地'), findsOneWidget);
  });

  testWidgets('load failures retry and an empty library offers a useful state',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AgentArtifactLibrary(
          load: () async {
            if (attempts++ == 0) throw const FileSystemException('unavailable');
            return [];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('无法加载本地产物'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('还没有文件产物'), findsOneWidget);
  });
}
