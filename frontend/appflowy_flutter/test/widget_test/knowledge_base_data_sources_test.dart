import 'dart:convert';

import 'package:appflowy/plugins/knowledge_base/knowledge_base_data_source_editor.dart';
import 'package:appflowy/plugins/knowledge_base/knowledge_base_data_sources.dart';
import 'package:appflowy/plugins/knowledge_base/knowledge_base_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final base = KnowledgeBase.fromJson({
    'id': 'base',
    'workspace_id': 'workspace',
    'name': 'Library',
    'visibility': 'private',
    'can_manage': true,
    'ready': true,
  });
  const definition = {
    'type': 'notion',
    'name': 'Notion',
    'description': 'Notion',
    'fields': [
      {
        'key': 'api_key',
        'label': 'Integration Token',
        'required': true,
        'secret': true,
      },
    ],
  };

  Widget app(Widget child) => MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: child),
      );

  testWidgets(
      'WeKnora connection, explicit scope, retries, sync, credentials and removal',
      (tester) async {
    tester.view.physicalSize = const Size(680, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = <Map<String, dynamic>>[];
    Map<String, dynamic>? source;
    var failTest = true;
    var lostCreate = true;
    var failResources = true;
    var changes = 0;
    var backs = 0;
    var selectedIds = ['page'];
    final service = KnowledgeBaseService(
      () async => ('https://notes.example', 'user-token'),
      client: MockClient((request) async {
        expect(request.url.path, '/api/knowledge/data_source');
        expect(request.headers['Authorization'], 'Bearer user-token');
        final data = jsonDecode(request.body) as Map<String, dynamic>;
        expect(data['workspace_id'], 'workspace');
        expect(data['base_id'], 'base');
        calls.add(data);
        final operation = data['operation'];
        Map<String, dynamic> result = {};
        if (operation == 'test') {
          expect(data['type'], 'notion');
          expect(data['credentials'], {'api_key': 'secret'});
          if (failTest) return http.Response('', 400);
          result = {'connected': true};
        } else if (operation == 'create') {
          source ??= {
            'id': 'source',
            'name': 'Notion',
            'type': 'notion',
            'status': 'paused',
            'config': {'resource_ids': <String>[], 'settings': {}},
            'sync_schedule': '',
            'sync_mode': 'incremental',
            'conflict_strategy': 'overwrite',
            'sync_deletions': false,
          };
          if (lostCreate) {
            lostCreate = false;
            return http.Response('', 503);
          }
          result = {'source': source};
        } else {
          expect(data['source_id'], 'source');
          switch (operation) {
            case 'resources':
              if (failResources) {
                failResources = false;
                return http.Response('', 503);
              }
              result = {
                'resources': data['parent_id'] == ''
                    ? [
                        {
                          'external_id': 'space',
                          'name': '项目空间',
                          'has_children': true,
                        },
                      ]
                    : [
                        {
                          'external_id': 'page',
                          'parent_id': 'space',
                          'name': '项目计划',
                          'has_children': false,
                        },
                      ],
              };
            case 'save':
              expect(data['resource_ids'], selectedIds);
              expect(data['sync_schedule'], '0 0 * * * *');
              expect(data['sync_deletions'], false);
              source!['config'] = {
                'resource_ids': data['resource_ids'],
                'settings': {},
              };
              source!['sync_schedule'] = data['sync_schedule'];
              result = {'source': source};
            case 'sync':
              result = {
                'log': {'id': 'log', 'status': 'running'},
              };
              source!['latest_sync_log'] = {'id': 'log', 'status': 'success'};
            case 'list':
              result = {
                'sources': [source],
              };
            case 'logs':
              result = {
                'logs': [
                  {
                    'id': 'log',
                    'status': 'success',
                    'items_created': 1,
                    'items_updated': 0,
                    'items_deleted': 0,
                    'items_failed': 0,
                  }
                ],
              };
            case 'resume':
              source!['status'] = 'active';
            case 'pause':
              source!['status'] = 'paused';
            case 'credentials':
              expect(data['credentials'], {'api_key': 'replacement'});
            case 'delete':
              source = null;
            default:
              fail('Unexpected operation: $operation');
          }
        }
        return http.Response(
          jsonEncode({'success': true, 'data': result}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(service.close);
    await tester.pumpWidget(
      app(
        KnowledgeBaseDataSourceEditor(
          base: base,
          service: service,
          definition: definition,
          onBack: () => backs++,
          onChanged: () => changes++,
        ),
      ),
    );
    Future<void> tap(String label) async {
      if (find.text(label).evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          find.text(label),
          400,
          scrollable: find.byType(Scrollable).first,
        );
      }
      final finder = find.text(label).last;
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    await tap('保存连接');
    expect(calls, isEmpty);
    await tester.enterText(
      find.byKey(const ValueKey('source-api_key')),
      'secret',
    );
    await tap('测试连接');
    expect(find.text('数据源操作失败，请检查凭据、资源范围及同步配置。'), findsOneWidget);
    failTest = false;
    await tap('测试连接');
    expect(find.text('连接测试成功。'), findsOneWidget);
    await tap('保存连接');
    expect(find.text('知识库暂时无法连接，请稍后重试。'), findsOneWidget);
    await tap('保存连接');
    final creates = calls.where((c) => c['operation'] == 'create').toList();
    expect(creates, hasLength(2));
    expect(creates[0]['request_id'], creates[1]['request_id']);
    expect(find.byKey(const ValueKey('source-api_key')), findsNothing);
    await tap('加载资源');
    expect(find.text('知识库暂时无法连接，请稍后重试。'), findsOneWidget);
    await tap('加载资源');
    expect(find.text('项目空间'), findsOneWidget);
    await tester.tap(find.byTooltip('展开或收起'));
    await tester.pumpAndSettle();
    expect(calls.last['parent_id'], 'space');
    await tap('加载资源');
    await tester.tap(find.byTooltip('展开或收起'));
    await tester.pumpAndSettle();
    expect(
      calls.where(
        (c) => c['operation'] == 'resources' && c['parent_id'] == 'space',
      ),
      hasLength(2),
    );
    await tester.tap(find.byType(Checkbox).last);
    await tester.pumpAndSettle();
    await tap('刷新状态与日志');
    await tap('立即同步');
    expect(calls.where((c) => c['operation'] == 'sync'), isEmpty);
    final schedule = find.byType(DropdownButtonFormField<String>).first;
    await tester.ensureVisible(schedule);
    await tester.tap(schedule);
    await tester.pumpAndSettle();
    await tester.tap(find.text('每小时').last);
    await tester.pumpAndSettle();
    await tap('保存同步配置');
    expect(find.text('同步配置已保存。'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('项目空间'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    selectedIds = ['space'];
    await tap('保存同步配置');
    await tap('立即同步');
    expect(find.text('同步任务已提交。'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, '立即同步'),
          )
          .onPressed,
      isNull,
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c['operation'] == 'logs'), isNotEmpty);
    expect(find.text('同步完成'), findsWidgets);
    await tap('启用计划同步');
    expect(source!['status'], 'active');
    await tap('暂停计划同步');
    expect(source!['status'], 'paused');
    await tap('更新凭据');
    final token = find.byKey(const ValueKey('source-api_key'));
    expect(tester.widget<TextFormField>(token).controller!.text, isEmpty);
    expect(
      tester
          .widget<TextField>(
            find.descendant(of: token, matching: find.byType(TextField)),
          )
          .obscureText,
      isTrue,
    );
    await tester.enterText(token, 'replacement');
    await tap('保存新凭据');
    expect(token, findsNothing);
    tester.view.physicalSize = const Size(330, 740);
    await tester.pumpAndSettle();
    await tap('删除连接');
    await tap('取消');
    expect(calls.where((c) => c['operation'] == 'delete'), isEmpty);
    await tap('删除连接');
    await tap('删除');
    expect(source, isNull);
    expect(backs, 1);
    expect(changes, greaterThan(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('RSS replacement tests keep saved feeds and multiline headers',
      (tester) async {
    final calls = <Map<String, dynamic>>[];
    final service = KnowledgeBaseService(
      () async => ('https://notes.example', 'user-token'),
      client: MockClient((request) async {
        calls.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {'connected': true},
          }),
          200,
        );
      }),
    );
    addTearDown(service.close);
    await tester.pumpWidget(
      app(
        KnowledgeBaseDataSourceEditor(
          base: base,
          service: service,
          definition: const {
            'type': 'rss',
            'name': 'RSS',
            'fields': [
              {'key': 'auth_headers', 'label': 'Headers', 'secret': true},
            ],
          },
          source: const {
            'id': 'rss',
            'name': 'RSS',
            'status': 'paused',
            'config': {
              'resource_ids': ['https://example.invalid/feed'],
              'settings': {'feed_urls': 'https://example.invalid/feed'},
            },
          },
          onBack: () {},
          onChanged: () {},
        ),
      ),
    );
    await tester.tap(find.text('更新凭据'));
    await tester.pumpAndSettle();
    final headers = find.byKey(const ValueKey('source-auth_headers'));
    const value = 'Authorization: Bearer secret\nX-Api-Key: other';
    await tester.enterText(headers, value);
    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();
    expect(calls.single['operation'], 'test');
    expect(calls.single['credentials'], {'auth_headers': value});
    expect(
      calls.single['settings']['feed_urls'],
      'https://example.invalid/feed',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('non-managers cannot load source credentials or management APIs',
      (tester) async {
    var calls = 0;
    final service = KnowledgeBaseService(
      () async => ('https://notes.example', 'member-token'),
      client: MockClient((request) async {
        calls++;
        return http.Response('', 403);
      }),
    );
    addTearDown(service.close);
    await tester.pumpWidget(
      app(
        KnowledgeBaseDataSources(
          base: KnowledgeBase.fromJson({
            'id': 'base',
            'workspace_id': 'workspace',
            'name': 'Library',
            'visibility': 'shared',
          }),
          service: service,
          onClose: () {},
          onChanged: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('你没有此知识库的访问或管理权限，请刷新列表。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
