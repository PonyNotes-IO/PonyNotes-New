import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/plugins/knowledge_base/knowledge_base_cubit.dart';
import 'package:appflowy/plugins/knowledge_base/knowledge_base_page.dart';
import 'package:appflowy/plugins/knowledge_base/knowledge_base_plugin.dart';
import 'package:appflowy/plugins/knowledge_base/knowledge_base_service.dart';
import 'package:appflowy/plugins/knowledge_base/knowledge_base_web_import_dialog.dart';
import 'package:appflowy/plugins/knowledge_graph/presentation/knowledge_graph_canvas.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_knowledge_base_button.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CapturingTabs extends MockBloc<TabsEvent, TabsState>
    implements TabsBloc {
  final events = <TabsEvent>[];
  @override
  void add(TabsEvent event) => events.add(event);
}

class _Workspace extends MockBloc<UserWorkspaceEvent, UserWorkspaceState>
    implements UserWorkspaceBloc {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> selectCategory(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip('知识库分类'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    getIt.registerSingleton<PluginSandbox>(PluginSandbox());
    registerPlugin(builder: KnowledgeBasePluginBuilder());
  });
  tearDownAll(() => getIt.unregister<PluginSandbox>());

  testWidgets(
      'whole knowledge bases support categories, favorites, access and preview',
      (tester) async {
    tester.view.physicalSize = const Size(1180, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const screenshot = String.fromEnvironment('KB_SCREENSHOT');
    if (screenshot.isNotEmpty) {
      final font = FontLoader('Microsoft YaHei')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File('C:/Windows/Fonts/msyh.ttc').readAsBytesSync(),
            ),
          ),
        );
      await font.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File(
                'E:/fly/FlyEnv-Data/env/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
              ).readAsBytesSync(),
            ),
          ),
        );
      await icons.load();
    }
    final bases = <Map<String, dynamic>>[
      {
        'workspace_id': 'team',
        'name': '产品资料',
        'visibility': 'shared',
        'is_favorite': false,
        'can_manage': true,
        'ready': true,
      },
      {
        'workspace_id': 'personal',
        'name': '我的研究',
        'visibility': 'private',
        'is_favorite': false,
        'can_manage': true,
        'ready': false,
      },
      {
        'workspace_id': 'member',
        'name': '团队手册',
        'visibility': 'shared',
        'is_favorite': false,
        'can_manage': false,
        'ready': true,
      },
    ];
    var updates = 0;
    final service = KnowledgeBaseService(
      () async => ('https://notes.example/', 'session-token'),
      client: MockClient((request) async {
        expectSync(request.headers['Authorization'], 'Bearer session-token');
        expectSync(request.url.path, startsWith('/api/knowledge/'));
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        final action = request.url.path.split('/').last;
        final Map<String, dynamic> data;
        if (action == 'bases') {
          data = {'bases': bases};
        } else if (action == 'favorite' || action == 'visibility') {
          final base = bases.firstWhere(
            (base) => base['workspace_id'] == payload['workspace_id'],
          );
          expectSync(
            base['can_manage'] == true || action == 'favorite',
            isTrue,
          );
          final field = action == 'favorite' ? 'is_favorite' : 'visibility';
          base[field] = payload[field];
          updates++;
          data = {'updated': true};
        } else if (action == 'documents') {
          data = {
            'status': 'ready',
            'documents': [
              {'id': 'doc', 'title': '项目计划'},
            ],
          };
        } else if (action == 'document') {
          expectSync(payload['workspace_id'], 'team');
          expectSync(payload['document_id'], 'doc');
          data = {'content': '下周完成知识库联调。', 'truncated': false};
        } else if (action == 'sources') {
          data = {'sources': [], 'status': 'ready'};
        } else {
          throw StateError(action);
        }
        return http.Response(
          jsonEncode({'success': true, 'data': data}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final cubit = KnowledgeBaseCubit(service);
    unawaited(cubit.load());
    addTearDown(cubit.close);
    final tabs = _CapturingTabs();
    addTearDown(tabs.close);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TabsBloc>.value(value: tabs),
          BlocProvider<KnowledgeBaseCubit>.value(value: cubit),
        ],
        child: AppFlowyTheme(
          data: AppFlowyDefaultTheme().light(),
          child: MaterialApp(
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: ThemeData(
              fontFamily: screenshot.isEmpty ? null : 'Microsoft YaHei',
              colorSchemeSeed: const Color(0xFFEF633F),
              scaffoldBackgroundColor: Colors.white,
            ),
            home: RepaintBoundary(
              key: boundary,
              child: Scaffold(
                body: Row(
                  children: [
                    Container(
                      width: 220,
                      color: const Color(0xFFF8F8F8),
                      padding: const EdgeInsets.all(10),
                      alignment: Alignment.topLeft,
                      child: const SidebarKnowledgeBaseButton(),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: const KnowledgeBaseView(
                        category: KnowledgeBaseCategory.shared,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      cubit.state.hasError,
      isFalse,
      reason: '${cubit.state.error}\n${cubit.state.stackTrace}',
    );
    final sidebar = find.byType(SidebarKnowledgeBaseButton);
    expect(
      find.descendant(of: sidebar, matching: find.text('私有知识库')),
      findsNothing,
    );
    await tester.tap(find.descendant(of: sidebar, matching: find.text('知识库')));
    await tester.pumpAndSettle();
    expect(tabs.events, hasLength(1));
    tabs.events.single.maybeWhen(
      openPlugin: (plugin, _, __) =>
          expect(plugin.pluginType, PluginType.knowledgeBase),
      orElse: () => fail('Clicking Knowledge bases must open the middle pane'),
    );
    expect(
      find.descendant(of: sidebar, matching: find.text('私有知识库')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sidebar, matching: find.text('共享知识库')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sidebar, matching: find.text('最爱知识库')),
      findsOneWidget,
    );
    expect(find.text('产品资料'), findsOneWidget);
    expect(find.text('团队手册'), findsOneWidget);
    expect(find.text('我的研究'), findsNothing);
    expect(find.byTooltip('知识库权限'), findsOneWidget); // owner only
    expect(find.byType(ChoiceChip), findsNothing);
    for (final label in ['文件', 'Wiki', '图谱']) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.byTooltip('加入最爱').first);
    await tester.pumpAndSettle();
    await selectCategory(tester, '最爱知识库  1');
    expect(find.text('产品资料'), findsOneWidget);
    expect(find.text('团队手册'), findsNothing);

    if (screenshot.isNotEmpty) {
      await tester.runAsync(() async {
        final render = boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await render.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(screenshot).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await tester.tap(find.byTooltip('知识库权限'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设为私有（仅自己可见）'));
    await tester.pumpAndSettle();
    await selectCategory(tester, '共享知识库  1');
    expect(find.text('产品资料'), findsNothing);
    await selectCategory(tester, '私有知识库  2');
    expect(find.text('产品资料'), findsOneWidget);
    expect(find.text('我的研究'), findsOneWidget);
    expect(find.textContaining('等待同步'), findsOneWidget);
    await tester.tap(find.text('产品资料'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('项目计划'));
    await tester.pumpAndSettle();
    expect(find.text('下周完成知识库联调。'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('项目计划'), findsOneWidget);
    await tester.tap(find.byTooltip('返回知识库列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('取消最爱'));
    await tester.pumpAndSettle();
    await selectCategory(tester, '最爱知识库  0');
    expect(find.textContaining('暂无最爱知识库'), findsOneWidget);
    expect(updates, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'sidebar categories expand libraries and open the selected library',
      (tester) async {
    tester.view.physicalSize = const Size(1180, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bases = <Map<String, dynamic>>[
      {
        'workspace_id': 'personal',
        'name': '我的研究',
        'visibility': 'private',
        'ready': true,
      },
      {
        'workspace_id': 'team',
        'name': '团队手册',
        'visibility': 'shared',
        'ready': true,
      },
    ];
    var denied = false;
    final creationFailures = [404, 503];
    final creations = <Map<String, dynamic>>[];
    final requests = <(String, String?)>[];
    final cubit = KnowledgeBaseCubit(
      KnowledgeBaseService(
        () async => ('https://notes.example', 'token'),
        client: MockClient((request) async {
          final action = request.url.path.split('/').last;
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          final id = (payload['base_id'] ?? payload['workspace_id']) as String?;
          requests.add((action, id));
          if (denied) return http.Response('', 403);
          Map<String, dynamic>? created;
          if (action == 'create') {
            creations.add(payload);
            if (creationFailures.isNotEmpty) {
              return http.Response('', creationFailures.removeAt(0));
            }
            created = {
              'id': 'created-${payload['visibility']}',
              'workspace_id': payload['workspace_id'],
              'name': payload['name'],
              'visibility': payload['visibility'],
              'can_manage': true,
              'ready': true,
            };
            bases.add(created);
          }
          return http.Response(
            jsonEncode({
              'success': true,
              'data': switch (action) {
                'bases' => {'bases': bases},
                'create' => {'base': created},
                'documents' => {
                    'status': 'ready',
                    'documents': [
                      {'id': id, 'title': '$id 的文件'},
                    ],
                  },
                'sources' => {'status': 'ready', 'sources': []},
                _ => throw StateError(action),
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
    addTearDown(cubit.close);
    final tabs = _CapturingTabs();
    addTearDown(tabs.close);
    final workspace = _Workspace();
    whenListen(
      workspace,
      const Stream<UserWorkspaceState>.empty(),
      initialState: UserWorkspaceState(
        userProfile: UserProfilePB(),
        currentWorkspace: UserWorkspacePB(workspaceId: 'team'),
      ),
    );
    addTearDown(workspace.close);
    final selected = ValueNotifier<Plugin?>(null);
    addTearDown(selected.dispose);
    final boundary = GlobalKey();
    const screenshot = String.fromEnvironment('KB_TREE_SCREENSHOT');
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TabsBloc>.value(value: tabs),
          BlocProvider<UserWorkspaceBloc>.value(value: workspace),
          BlocProvider<KnowledgeBaseCubit>.value(value: cubit),
        ],
        child: AppFlowyTheme(
          data: AppFlowyDefaultTheme().light(),
          child: MaterialApp(
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: ThemeData(
              fontFamily: screenshot.isEmpty ? null : 'Microsoft YaHei',
              scaffoldBackgroundColor: Colors.white,
            ),
            home: RepaintBoundary(
              key: boundary,
              child: Scaffold(
                body: Row(
                  children: [
                    Container(
                      width: 220,
                      color: const Color(0xFFF8F8F8),
                      padding: const EdgeInsets.all(10),
                      alignment: Alignment.topLeft,
                      child: const SidebarKnowledgeBaseButton(),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: ValueListenableBuilder<Plugin?>(
                        valueListenable: selected,
                        builder: (_, plugin, __) =>
                            plugin?.widgetBuilder.buildWidget(
                              context: PluginContext(),
                              shrinkWrap: false,
                            ) ??
                            const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final sidebar = find.byType(SidebarKnowledgeBaseButton);
    Finder entry(String label) =>
        find.descendant(of: sidebar, matching: find.text(label));
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1000, 700));
    addTearDown(mouse.removePointer);
    Future<void> hover(String label) async {
      await mouse.moveTo(tester.getCenter(entry(label)));
      await tester.pumpAndSettle();
    }

    expect(requests, isEmpty);
    await tester.tap(entry('知识库'));
    await tester.pumpAndSettle();
    expect(cubit.state.hasError, isFalse, reason: '${cubit.state.error}');
    expect(entry('我的研究'), findsNothing);
    expect(entry('团队手册'), findsNothing);
    expect(find.byTooltip('创建私有知识库'), findsNothing);
    expect(find.byTooltip('创建共享知识库'), findsNothing);
    await hover('私有知识库');
    expect(find.byTooltip('创建私有知识库'), findsOneWidget);
    expect(tabs.events, hasLength(1));
    expect(entry('我的研究'), findsNothing);
    await mouse.moveTo(tester.getCenter(find.byTooltip('创建私有知识库')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('创建私有知识库'), findsOneWidget);
    await tester.tap(entry('私有知识库'));
    await tester.pumpAndSettle();
    expect(entry('我的研究'), findsOneWidget);
    expect(entry('团队手册'), findsNothing);
    expect(find.byTooltip('创建私有知识库'), findsOneWidget);
    expect(find.byTooltip('创建共享知识库'), findsNothing);
    await hover('我的研究');
    expect(find.byTooltip('创建私有知识库'), findsNothing);
    final privateAdd =
        find.byKey(const ValueKey('knowledge-base-add-private-personal'));
    final sharedAdd =
        find.byKey(const ValueKey('knowledge-base-add-shared-team'));
    expect(privateAdd, findsOneWidget);
    await mouse.moveTo(tester.getCenter(privateAdd));
    await tester.pumpAndSettle();
    expect(privateAdd, findsOneWidget);
    expect(tester.getSize(privateAdd), const Size(28, 28));
    await tester.tap(privateAdd);
    await tester.pumpAndSettle();
    await mouse.moveTo(tester.getCenter(find.text('上传文件')));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<String>), findsNWidgets(6));
    for (final label in [
      '选择笔记',
      '上传文件',
      '上传文件夹',
      '导入网页',
      '在线编辑',
      '链接数据源',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byType(AlertDialog), findsNothing);
    expect(tabs.events, hasLength(2));
    expect(creations, isEmpty);
    await tester.tap(find.text('导入网页'));
    await tester.pumpAndSettle();
    expect(find.byType(KnowledgeBaseWebImportDialog), findsOneWidget);
    expect(find.text('URL 地址'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<String>), findsNothing);
    await hover('共享知识库');
    expect(privateAdd, findsNothing);
    expect(find.byTooltip('创建共享知识库'), findsOneWidget);
    expect(find.byTooltip('创建私有知识库'), findsNothing);
    expect(tabs.events, hasLength(2));
    expect(entry('团队手册'), findsNothing);
    await tester.tap(entry('共享知识库'));
    await tester.pumpAndSettle();
    expect(entry('我的研究'), findsOneWidget);
    expect(entry('团队手册'), findsOneWidget);
    expect(find.byTooltip('创建共享知识库'), findsOneWidget);
    expect(find.byTooltip('创建私有知识库'), findsNothing);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('knowledge-base-create-shared')))
          .height,
      lessThanOrEqualTo(32),
    );
    expect(sharedAdd, findsNothing);
    await hover('团队手册');
    expect(sharedAdd, findsOneWidget);
    expect(privateAdd, findsNothing);
    expect(find.byTooltip('创建共享知识库'), findsNothing);
    await mouse.moveTo(const Offset(1000, 700));
    await tester.pumpAndSettle();
    expect(sharedAdd, findsNothing);
    expect(find.byTooltip('创建共享知识库'), findsNothing);

    Future<void> open(String name, String id) async {
      await tester.tap(entry(name));
      await tester.pumpAndSettle();
      final plugin = tabs.events.last.maybeWhen<Plugin>(
        openPlugin: (plugin, _, __) => plugin,
        orElse: () => throw StateError('Expected a knowledge base plugin'),
      );
      expect(plugin.id, 'knowledge_base:$id');
      expect(plugin.widgetBuilder.viewName, name);
      selected.value = plugin;
      await tester.pumpAndSettle();
      expect(find.text('$id 的文件'), findsOneWidget);
    }

    await open('我的研究', 'personal');
    await open('团队手册', 'team');
    expect(find.text('personal 的文件'), findsNothing);
    expect(requests.where((request) => request.$1 == 'bases'), hasLength(1));
    if (screenshot.isNotEmpty) {
      await tester.runAsync(() async {
        final render = boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await render.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(screenshot).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.tap(entry('私有知识库'));
    await tester.pumpAndSettle();
    expect(entry('我的研究'), findsNothing);
    expect(entry('团队手册'), findsOneWidget);
    await tester.tap(entry('私有知识库'));
    await tester.pumpAndSettle();
    expect(entry('我的研究'), findsOneWidget);
    bases.first['visibility'] = 'shared';
    await cubit.load();
    await tester.pumpAndSettle();
    expect(entry('暂无知识库'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('knowledge-base-private-personal')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('knowledge-base-shared-personal')),
      findsOneWidget,
    );
    denied = true;
    await cubit.load();
    await tester.pumpAndSettle();
    expect(entry('我的研究'), findsNothing);
    expect(entry('团队手册'), findsNothing);
    expect(find.text('team 的文件'), findsNothing);
    denied = false;
    bases.removeLast();
    await tester.tap(entry('重试').first);
    await tester.pumpAndSettle();
    expect(entry('我的研究'), findsOneWidget);
    expect(entry('团队手册'), findsNothing);
    expect(find.text('personal 的文件'), findsNothing);
    expect(requests.where((request) => request.$1 == 'bases'), hasLength(4));
    await tester.tap(entry('私有知识库'));
    await tester.pumpAndSettle();
    await hover('私有知识库');
    await tester.tap(find.byTooltip('创建私有知识库'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    final name = find.descendant(of: dialog, matching: find.byType(TextField));
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.enterText(name, '   ');
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(creations, isEmpty);
    await hover('私有知识库');
    await tester.tap(find.byTooltip('创建私有知识库'));
    await tester.pumpAndSettle();
    await tester.enterText(name, '  私有项目  ');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '创建'));
    await tester.pumpAndSettle();
    expect(dialog, findsOneWidget);
    expect(find.text('当前知识库服务尚不支持创建，请联系管理员更新。'), findsOneWidget);
    expect(find.text('知识库暂时无法连接，请稍后重试。'), findsNothing);
    expect(tester.widget<TextField>(name).controller!.text, '  私有项目  ');
    await tester.tap(find.widgetWithText(FilledButton, '创建'));
    await tester.pumpAndSettle();
    expect(dialog, findsOneWidget);
    expect(find.text('知识库暂时无法连接，请稍后重试。'), findsOneWidget);
    expect(tester.widget<TextField>(name).controller!.text, '  私有项目  ');
    await tester.tap(find.widgetWithText(FilledButton, '创建'));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(creations, hasLength(3));
    expect(creations[0]['request_id'], creations[1]['request_id']);
    expect(creations[1]['request_id'], creations[2]['request_id']);
    expect(creations.last['name'], '私有项目');
    expect(creations.last['visibility'], 'private');
    expect(creations.last['workspace_id'], 'team');
    expect(entry('私有项目'), findsOneWidget);
    tabs.events.last.maybeWhen(
      openPlugin: (plugin, _, __) =>
          expect(plugin.id, 'knowledge_base:created-private'),
      orElse: () => fail('Creating a library must open it'),
    );
    await open('私有项目', 'created-private');
    await tester.tap(entry('共享知识库'));
    await tester.pumpAndSettle();
    await hover('共享知识库');
    await tester.tap(find.byTooltip('创建共享知识库'));
    await tester.pumpAndSettle();
    await tester.enterText(name, '团队项目');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '创建'));
    await tester.pumpAndSettle();
    expect(creations.last['visibility'], 'shared');
    expect(entry('团队项目'), findsOneWidget);
    await open('团队项目', 'created-shared');
    expect(find.text('created-private 的文件'), findsNothing);
    await tester.tap(entry('最爱知识库'));
    await tester.pumpAndSettle();
    await hover('最爱知识库');
    expect(
      find.descendant(of: sidebar, matching: find.byIcon(Icons.add)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'current library keeps files, sources, Wiki and graph in a middle pane',
      (tester) async {
    tester.view.physicalSize = const Size(1180, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var sourceFails = true;
    var denied = false;
    final calls = <(String, String?)>[];
    final service = KnowledgeBaseService(
      () async => ('https://notes.example', 'token'),
      client: MockClient((request) async {
        final action = request.url.path.split('/').last;
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        final wid = payload['workspace_id'] as String?;
        calls.add((action, wid));
        if (action == 'bases' && denied || action == 'sources' && sourceFails) {
          return http.Response('', 503);
        }
        final Map<String, dynamic> data;
        switch (action) {
          case 'bases':
            data = {
              'bases': [
                for (final id in ['other', 'current'])
                  {
                    'workspace_id': id,
                    'name': id == 'current' ? '产品知识库' : '另一知识库',
                    'visibility': id == 'current' ? 'private' : 'shared',
                    'ready': true,
                  },
              ],
            };
          case 'documents':
            data = {
              'status': 'ready',
              'documents': wid == 'current'
                  ? [
                      {
                        'id': 'roadmap',
                        'title': '产品路线图.pdf',
                        'status': 'completed',
                      },
                      {
                        'id': 'interview',
                        'title': '访谈记录.md',
                        'status': 'processing',
                      },
                      {'id': 'website', 'title': '官网参考', 'status': 'completed'},
                    ]
                  : [
                      {'id': 'other-file', 'title': '另一库的文件'},
                    ],
            };
          case 'sources':
            data = {
              'status': 'ready',
              'sources': wid == 'current'
                  ? [
                      {
                        'id': 'feishu',
                        'name': '飞书',
                        'type': 'feishu',
                        'status': 'active',
                        'total_items_synced': 12,
                      },
                      {
                        'id': 'notion',
                        'name': 'Notion',
                        'type': 'notion',
                        'status': 'syncing',
                      },
                      {
                        'id': 'gitlab',
                        'name': 'GitLab',
                        'type': 'gitlab',
                        'status': 'paused',
                      },
                    ]
                  : [],
            };
          case 'document':
            expectSync(payload['document_id'], 'roadmap');
            expectSync(wid, 'current');
            data = {'content': '第三季度产品规划与里程碑。'};
          case 'wiki':
            expectSync(wid, 'current');
            data = {
              'status': 'ready',
              'pages': [
                {
                  'id': 'concept/product',
                  'title': '产品概览',
                  'out_links': ['concept/research'],
                },
                {'id': 'concept/research', 'title': '用户研究', 'out_links': []},
              ],
            };
          case 'wiki_page':
            expectSync(wid, 'current');
            expectSync(payload['slug'], 'concept/product');
            data = {'content': '产品概览的 Wiki 正文。'};
          default:
            throw StateError(action);
        }
        return http.Response(
          jsonEncode({'success': true, 'data': data}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final cubit = KnowledgeBaseCubit(service);
    await cubit.load();
    addTearDown(cubit.close);
    final boundary = GlobalKey();
    const screenshot = String.fromEnvironment('KB_MIDDLE_SCREENSHOT');
    await tester.runAsync(() async {
      await rootBundle.loadString('assets/translations/zh-CN.json');
    });
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('zh', 'CN')],
        startLocale: const Locale('zh', 'CN'),
        fallbackLocale: const Locale('zh', 'CN'),
        path: 'assets/translations',
        child: Builder(
          builder: (context) => AppFlowyTheme(
            data: AppFlowyDefaultTheme().light(),
            child: MaterialApp(
              locale: const Locale('zh', 'CN'),
              supportedLocales: const [Locale('zh', 'CN')],
              localizationsDelegates: context.localizationDelegates,
              theme: ThemeData(
                fontFamily: screenshot.isEmpty ? null : 'Microsoft YaHei',
                colorSchemeSeed: const Color(0xFFEF633F),
                scaffoldBackgroundColor: Colors.white,
              ),
              home: RepaintBoundary(
                key: boundary,
                child: Scaffold(
                  body: BlocProvider.value(
                    value: cubit,
                    child: const KnowledgeBaseView(
                      category: KnowledgeBaseCategory.shared,
                      currentBaseId: 'current',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var attempt = 0;
        attempt < 50 && find.byType(KnowledgeBaseView).evaluate().isEmpty;
        attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pumpAndSettle();
    }

    expect(find.text('产品知识库'), findsOneWidget);
    expect(find.text('产品路线图.pdf'), findsOneWidget);
    expect(find.text('文件 (3)'), findsOneWidget);
    expect(find.text('知识库暂时无法连接，请稍后重试。'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(calls.where((call) => call.$1 == 'wiki'), isEmpty);
    sourceFails = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('数据源 (3)'), findsOneWidget);
    expect(find.text('飞书'), findsOneWidget);
    expect(find.text('Notion'), findsOneWidget);
    expect(find.text('GitLab'), findsOneWidget);

    await tester.tap(find.text('产品路线图.pdf'));
    await tester.pumpAndSettle();
    final middle = find.byKey(const ValueKey('knowledge-base-middle-pane'));
    expect(
      find.descendant(of: middle, matching: find.text('产品路线图.pdf')),
      findsOneWidget,
    );
    expect(
      tester.getRect(find.text('第三季度产品规划与里程碑。')).left,
      greaterThan(tester.getRect(middle).right),
    );
    if (screenshot.isNotEmpty) {
      await tester.runAsync(() async {
        final render = boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await render.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(screenshot).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.enterText(find.byType(TextField), '访谈');
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: middle, matching: find.text('产品路线图.pdf')),
      findsNothing,
    );
    expect(find.text('访谈记录.md'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    await tester.tap(find.text('飞书'));
    await tester.pumpAndSettle();
    expect(find.text('已同步条目：12'), findsOneWidget);

    await tester.tap(find.text('Wiki'));
    await tester.pumpAndSettle();
    expect(find.text('Wiki (2)'), findsOneWidget);
    expect(find.text('产品路线图.pdf'), findsNothing);
    await tester.tap(find.text('产品概览'));
    await tester.pumpAndSettle();
    expect(find.text('产品概览的 Wiki 正文。'), findsOneWidget);

    await tester.tap(find.text('图谱'));
    await tester.pumpAndSettle();
    final canvas =
        tester.widget<KnowledgeGraphCanvas>(find.byType(KnowledgeGraphCanvas));
    expect(
      canvas.data.nodes.map((node) => node.id),
      ['concept/product', 'concept/research'],
    );
    expect(canvas.data.edges, hasLength(1));
    canvas.onOpen(canvas.data.nodes.first);
    await tester.pumpAndSettle();
    expect(find.text('产品概览的 Wiki 正文。'), findsOneWidget);
    expect(calls.where((call) => call.$1 == 'wiki'), hasLength(1));

    await tester.tap(find.byTooltip('返回知识库列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('另一知识库'));
    await tester.pumpAndSettle();
    expect(find.text('另一库的文件'), findsOneWidget);
    expect(find.text('产品概览的 Wiki 正文。'), findsNothing);
    expect(find.text('产品路线图.pdf'), findsNothing);
    tester.view.physicalSize = const Size(700, 740);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    denied = true;
    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpAndSettle();
    expect(find.text('另一库的文件'), findsNothing);
    expect(find.text('知识库暂时无法连接，请稍后重试。'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    for (final label in ['文件', 'Wiki', '图谱']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('Wiki'));
    await tester.pumpAndSettle();
    expect(
      DefaultTabController.of(tester.element(find.byType(TabBar))).index,
      1,
    );
    denied = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    await selectCategory(tester, '私有知识库  1');
    final fileRequests = calls.where((call) => call.$1 == 'documents').length;
    await tester.tap(find.text('产品知识库'));
    await tester.pumpAndSettle();
    expect(find.text('Wiki (2)'), findsOneWidget);
    expect(
      DefaultTabController.of(tester.element(find.byType(TabBar))).index,
      1,
    );
    expect(
      calls.where((call) => call.$1 == 'documents'),
      hasLength(fileRequests),
    );
    await tester.tap(find.text('文件'));
    await tester.pumpAndSettle();
    expect(find.text('产品路线图.pdf'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('web import validates URLs, confirms parsing and handles retries',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const screenshot = String.fromEnvironment('KB_WEB_IMPORT_SCREENSHOT');
    if (screenshot.isNotEmpty) {
      for (final (name, path) in [
        ('Microsoft YaHei', 'C:/Windows/Fonts/msyh.ttc'),
        (
          'MaterialIcons',
          'E:/fly/FlyEnv-Data/env/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
        ),
      ]) {
        final font = FontLoader(name)
          ..addFont(
            Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
          );
        await font.load();
      }
    }
    final defaults = <String, dynamic>{
      'summary_enabled': true,
      'parser_engine_rules': [
        {
          'file_types': ['html'],
          'engine': '',
        }
      ],
      'chunking_config': {
        'chunk_size': 640,
        'chunk_overlap': 80,
        'strategy': 'auto',
        'enable_parent_child': false,
        'parent_chunk_size': 4096,
        'child_chunk_size': 384,
      },
      'enable_multimodel': false,
      'vlm_config': {
        'enabled': false,
        'model_id': '',
        'description_language': '',
        'custom_instructions': '',
      },
      'asr_config': {'enabled': false, 'model_id': '', 'language': ''},
      'question_generation_config': {
        'enabled': false,
        'question_count': 3,
        'custom_instructions': '',
      },
    };
    final calls = <(String, Map<String, dynamic>)>[];
    var optionsFail = true;
    var pending = Completer<http.Response>();
    final service = KnowledgeBaseService(
      () async => ('https://notes.example', 'token'),
      client: MockClient((request) async {
        final action = request.url.path.split('/').last;
        calls.add((action, jsonDecode(request.body) as Map<String, dynamic>));
        if (action == 'import_url') return pending.future;
        expect(action, 'web_import_options');
        if (optionsFail) return http.Response('', 404);
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'version': 2,
              'process_config': defaults,
              'tags': [
                {'id': 'tag', 'name': '学习'},
              ],
              'models': [
                {'id': 'vision', 'name': '视觉模型', 'type': 'VLLM'},
              ],
              'engines': [
                {'id': 'builtin', 'name': '内置解析'},
              ],
              'summary_available': true,
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(service.close);
    final boundary = GlobalKey();
    bool? imported;
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: AppFlowyTheme(
          data: AppFlowyDefaultTheme().light(),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: ThemeData(
              fontFamily: screenshot.isEmpty ? null : 'Microsoft YaHei',
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    imported = await showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => KnowledgeBaseWebImportDialog(
                        service: service,
                        base: KnowledgeBase.fromJson({
                          'id': 'base',
                          'workspace_id': 'workspace',
                          'name': '我的知识库',
                          'visibility': 'shared',
                        }),
                      ),
                    );
                  },
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Future<void> capture(String suffix) async {
      if (screenshot.isEmpty) return;
      await tester.runAsync(() async {
        final render = boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await render.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$screenshot-$suffix.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await capture('url');
    final confirm = find.byType(FilledButton);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text('请输入有效的 HTTP 或 HTTPS 网页地址'), findsOneWidget);
    for (final url in [
      'ftp://example.com',
      'https://',
      'https://example.com/a b',
    ]) {
      await tester.enterText(find.byType(TextFormField), url);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.text('请输入有效的 HTTP 或 HTTPS 网页地址'), findsOneWidget);
    }
    expect(calls, isEmpty);
    await tester.enterText(
      find.byType(TextFormField),
      '  https://example.com/article  ',
    );
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text('当前知识库服务尚不支持网页导入，请联系管理员更新。'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    optionsFail = false;
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text('上传文档确认'), findsOneWidget);
    expect(find.text('https://example.com/article'), findsOneWidget);
    expect(
      calls.map((call) => call.$1),
      ['web_import_options', 'web_import_options'],
    );
    await tester.tap(find.text('学习'));
    var previousSection = 0;
    Future<void> section(String label) async {
      final index = ['文档标签', '解析引擎', '分块设置', '图像处理', '音频处理', '文档摘要', 'AI 问题生成']
          .indexOf(label);
      final tile = find.widgetWithText(ListTile, label);
      await tester.scrollUntilVisible(
        tile,
        index >= previousSection ? 80 : -80,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      previousSection = index;
      await tester.tap(tile);
      await tester.pumpAndSettle();
    }

    await section('分块设置');
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller!
          .text,
      '640',
    );
    await capture('parse');
    await tester.enterText(find.byKey(const ValueKey('chunk_size')), '100');
    await tester.enterText(find.byKey(const ValueKey('chunk_overlap')), '100');
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(calls, hasLength(2));
    await tester.enterText(find.byKey(const ValueKey('chunk_size')), '800');
    await tester.enterText(find.byKey(const ValueKey('chunk_overlap')), '0');
    await section('解析引擎');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('内置解析').last);
    await tester.pumpAndSettle();
    await section('图像处理');
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vlm_config-model')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('视觉模型').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('vlm_config-custom_instructions')),
      '保留图片里的文字',
    );
    await section('音频处理');
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
    await section('文档摘要');
    await tester.tap(find.byType(SwitchListTile));
    await section('AI 问题生成');
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('question_count')), '5');
    await section('分块设置');
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('chunk_size')))
          .controller!
          .text,
      '800',
    );
    for (final status in [503, 409, 200]) {
      await tester.tap(confirm);
      await tester.pump();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '取消'))
            .onPressed,
        isNull,
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      pending.complete(
        http.Response(
          status == 200
              ? jsonEncode({
                  'success': true,
                  'data': {'document_id': 'document'},
                })
              : '',
          status,
        ),
      );
      await tester.pumpAndSettle();
      if (status != 200) {
        expect(find.text('https://example.com/article'), findsOneWidget);
        expect(
          find.text(status == 409 ? '该网页已存在于知识库中。' : '知识库暂时无法连接，请稍后重试。'),
          findsOneWidget,
        );
      }
      pending = Completer<http.Response>();
    }
    expect(imported, isTrue);
    expect(find.byType(KnowledgeBaseWebImportDialog), findsNothing);
    expect(calls, hasLength(5));
    expect(calls.last.$2, {
      'workspace_id': 'workspace',
      'base_id': 'base',
      'url': 'https://example.com/article',
      'tag_ids': ['tag'],
      'process_config': {
        ...defaults,
        'summary_enabled': false,
        'parser_engine_rules': [
          {
            'file_types': ['html'],
            'engine': 'builtin',
          }
        ],
        'chunking_config': {
          ...defaults['chunking_config'] as Map,
          'chunk_size': 800,
          'chunk_overlap': 0,
        },
        'enable_multimodel': true,
        'vlm_config': {
          'enabled': true,
          'model_id': 'vision',
          'description_language': '',
          'custom_instructions': '保留图片里的文字',
        },
        'question_generation_config': {
          'enabled': true,
          'question_count': 5,
          'custom_instructions': '',
        },
      },
    });
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'https://example.com');
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    await section('分块设置');
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('chunk_size')))
          .controller!
          .text,
      '640',
    );
    // Settings remain usable on a narrow window, including validation navigation.
    tester.view.physicalSize = const Size(390, 740);
    await tester.pumpAndSettle();
    expect(find.text('拆分策略'), findsOneWidget);
    await capture('narrow');
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('上一步'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('清空'));
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      isEmpty,
    );
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(KnowledgeBaseWebImportDialog), findsNothing);
    expect(calls, hasLength(6));
    expect(tester.takeException(), isNull);
  });

  test(
      'failed refresh clears inaccessible libraries and late requests cannot restore them',
      () async {
    final pending = Completer<http.Response>();
    var requests = 0;
    final service = KnowledgeBaseService(
      () async => ('https://notes.example', 'token'),
      client: MockClient((_) async {
        if (++requests == 1) return pending.future;
        return http.Response('', 403);
      }),
    );
    final cubit = KnowledgeBaseCubit(service);
    final first = cubit.load();
    await Future<void>.delayed(Duration.zero);
    await cubit.load();
    expect((cubit.state.error! as KnowledgeBaseException).status, 403);
    pending.complete(
      http.Response(
        jsonEncode({
          'success': true,
          'data': {'bases': []},
        }),
        200,
      ),
    );
    await first;
    expect(cubit.state.hasError, isTrue);
    expect(cubit.state.data, isNull);
    await cubit.close();
  });
}
