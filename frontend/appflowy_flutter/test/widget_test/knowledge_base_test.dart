import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/plugins/knowledge_base/knowledge_base_cubit.dart';
import 'package:appflowy/plugins/knowledge_base/knowledge_base_page.dart';
import 'package:appflowy/plugins/knowledge_base/knowledge_base_plugin.dart';
import 'package:appflowy/plugins/knowledge_base/knowledge_base_service.dart';
import 'package:appflowy/plugins/knowledge_graph/presentation/knowledge_graph_canvas.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_knowledge_base_button.dart';
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
    final bases = [
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
      BlocProvider<TabsBloc>.value(
        value: tabs,
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
                      child: BlocProvider.value(
                        value: cubit,
                        child: const KnowledgeBaseView(
                          category: KnowledgeBaseCategory.shared,
                        ),
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
                      currentWorkspaceId: 'current',
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
