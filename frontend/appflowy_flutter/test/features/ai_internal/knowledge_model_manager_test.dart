import 'dart:convert';
import 'package:appflowy/features/ai_internal/application/knowledge_model_service.dart';
import 'package:appflowy/features/ai_internal/presentation/ai_provider_settings_view.dart';
import 'package:appflowy/features/ai_internal/presentation/knowledge_model_widgets.dart';
import 'package:appflowy/features/ai_internal/presentation/knowledge_model_form_controls.dart';
import 'package:appflowy/plugins/knowledge_base/knowledge_base_service.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ModelApiFixture {
  final requests = <(String, Map<String, dynamic>)>[];
  Map<String, dynamic>? saved;
  Map<String, dynamic>? bound;
  bool rejectSave = false;
  bool rejectDelete = false;
  bool canManage = true;
  final deleted = <String>[];
  Map<String, String> providerIcons = {};
  List<Map<String, dynamic>> additionalProviders = [];
  List<Map<String, dynamic>>? aliyunModels;
  static const workspace = '11111111-1111-4111-8111-111111111111';
  static const base = '22222222-2222-4222-8222-222222222222';
  List<Map<String, dynamic>> get models => [
        {
          'id': 'chat',
          'name': 'deepseek-chat',
          'display_name': 'DeepSeek',
          'type': 'KnowledgeQA',
          'is_builtin': true,
          'status': 'active',
          'parameters': {'provider': 'deepseek'},
        },
        {
          'id': 'embed',
          'name': 'text-embedding-v4',
          'type': 'Embedding',
          'is_builtin': true,
          'status': 'active',
          'parameters': {'provider': 'aliyun'},
        },
        {
          'id': 'rank',
          'name': 'gte-rerank-v2',
          'type': 'Rerank',
          'is_builtin': false,
          'status': 'active',
          'parameters': {
            'provider': 'aliyun',
            'base_url': 'https://example.com/v1',
          },
        },
        if (saved != null)
          {
            ...saved!,
            'id': 'new-model',
            'is_builtin': false,
            'status': 'active',
          },
      ].where((model) => !deleted.contains(model['id'])).toList();
  Map<String, dynamic> settings = {
    'embedding_model_id': 'embed',
    'summary_model_id': 'chat',
    'rerank_model_id': '',
    'vlm_model_id': '',
    'asr_model_id': '',
    'rerank_top_k': 10,
  };
  late final service = KnowledgeModelService(
    KnowledgeBaseService(
      () async => ('https://cloud.example', 'account-token'),
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer account-token');
        final data = jsonDecode(request.body) as Map<String, dynamic>;
        final action = request.url.pathSegments.last;
        requests.add((action, data));
        if (action != 'bases') expect(data['workspace_id'], workspace);
        final Map<String, dynamic> result;
        switch (action) {
          case 'models':
            result = {
              'models': models,
              'can_manage': canManage,
              'providers': [
                {
                  'value': 'deepseek',
                  'label': '深度求索',
                  'icon': providerIcons['deepseek'] ?? '',
                },
                {
                  'value': 'aliyun',
                  'label': '阿里云 DashScope',
                  'icon': providerIcons['aliyun'] ?? '',
                },
              ],
            };
          case 'model_providers':
            final type = data['type'] as String;
            final frontendType = KnowledgeModelType.fromApi(type).providerKey;
            result = {
              'providers': [
                {
                  'value': 'generic',
                  'label': '自定义',
                  'modelTypes': [frontendType],
                  'models': [],
                  'defaultUrls': {},
                },
                {
                  'value': 'aliyun',
                  'icon': providerIcons['aliyun'] ?? '',
                  'label': '阿里云 DashScope',
                  'requiresAuth': true,
                  'modelTypes': [frontendType],
                  'defaultUrls': {
                    frontendType:
                        'https://dashscope.aliyuncs.com/compatible-mode/v1',
                  },
                  'models': aliyunModels ??
                      [
                        {
                          'id': type == 'Embedding'
                              ? 'text-embedding-v4'
                              : 'gte-rerank-v2',
                          'name': type == 'Embedding' ? '通义向量' : '通义重排',
                          if (type == 'Embedding') 'dimension': 1024,
                          'type': frontendType,
                        },
                        {
                          'id': 'must-not-show-chat',
                          'name': '不应显示的对话模型',
                          'type': 'chat',
                        },
                      ],
                  'extraFields': [
                    {
                      'key': 'embedding_only',
                      'label': '向量专用字段',
                      'type': 'string',
                      'model_types': ['Embedding'],
                    },
                    {
                      'key': 'rerank_only',
                      'label': '重排专用字段',
                      'type': 'string',
                      'model_types': ['Rerank'],
                    },
                  ],
                },
                ...additionalProviders,
              ],
            };
          case 'model_save':
            if (rejectSave) return http.Response('{}', 409);
            saved = Map<String, dynamic>.from(data['model'] as Map);
            result = {'model': saved};
          case 'model_delete':
            if (rejectDelete) return http.Response('{}', 409);
            deleted.add(data['id'] as String);
            result = {'deleted': true};
          case 'bases':
            result = {
              'bases': [
                {
                  'id': base,
                  'workspace_id': workspace,
                  'name': '项目资料',
                  'visibility': 'private',
                  'can_manage': true,
                  'ready': true,
                }
              ],
            };
          case 'model_settings':
            result = {'settings': settings, 'embedding_locked': true};
          case 'model_bind':
            bound = Map<String, dynamic>.from(data['settings'] as Map);
            result = {'updated': true};
          default:
            throw StateError('Unexpected action: $action');
        }
        return http.Response.bytes(
          utf8.encode(jsonEncode({'success': true, 'data': result})),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    ),
    workspace,
  );
}

Future<void> pumpModelManager(
  WidgetTester tester,
  ModelApiFixture fixture, {
  double width = 640,
  bool dark = false,
  double scale = 1,
  ThemeData? materialTheme,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    AppFlowyTheme(
      data:
          dark ? AppFlowyDefaultTheme().dark() : AppFlowyDefaultTheme().light(),
      child: MaterialApp(
        theme: materialTheme ??
            ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(body: AiProviderSettingsView(service: fixture.service)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues(
      {'ai_internal.model': 'existing-chat'},
    ),
  );
  for (final dark in [false, true]) {
    testWidgets(
        'model controls use neutral focus and hover in ${dark ? 'dark' : 'light'} mode',
        (tester) async {
      final fixture = ModelApiFixture();
      addTearDown(fixture.service.close);
      final material =
          ThemeData(brightness: dark ? Brightness.dark : Brightness.light);
      await pumpModelManager(
        tester,
        fixture,
        dark: dark,
        materialTheme: material.copyWith(
          colorScheme: material.colorScheme.copyWith(primary: modelAccent),
          hoverColor: modelAccent,
          focusColor: modelAccent,
        ),
      );
      expect(tester.widget<Text>(find.text('DeepSeek')).style!.fontSize, 14);
      expect(
        Theme.of(tester.element(find.text('DeepSeek')))
            .textTheme
            .bodyLarge!
            .fontSize,
        14,
      );
      await tester.tap(find.text('添加模型'));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('model-provider'));
      final theme = Theme.of(tester.element(field));
      expect(theme.textTheme.bodyLarge!.fontSize, 14);
      expect(theme.colorScheme.primary, isNot(modelAccent));
      expect(theme.hoverColor.a, lessThan(.1));
      expect(theme.splashFactory, NoSplash.splashFactory);
      await tester.tap(field);
      await tester.pumpAndSettle();
      final option = find.text('阿里云 DashScope').last;
      expect(Theme.of(tester.element(option)).hoverColor, theme.hoverColor);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('阿里云 DashScope'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('model-url')));
      await tester.pumpAndSettle();
      final decoration = tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('model-url')),
              matching: find.byType(TextField),
            ),
          )
          .decoration!;
      expect(
        (decoration.focusedBorder! as OutlineInputBorder).borderSide.color,
        isNot(modelAccent),
      );
      expect(
        (decoration.focusedBorder! as OutlineInputBorder).borderSide.width,
        1,
      );
      await tester.ensureVisible(find.text('保存'));
      final button = tester.element(find.byType(FilledButton));
      final style = Theme.of(button).filledButtonTheme.style!;
      expect(style.backgroundColor!.resolve({}), modelAccent);
      expect(
        style.backgroundColor!.resolve({WidgetState.disabled})!.a,
        lessThan(1),
      );
      expect(style.foregroundColor!.resolve({}), Colors.white);
      expect(tester.takeException(), isNull);
    });
  }
  test('model service uses the authenticated workspace-scoped Cloud API',
      () async {
    final fixture = ModelApiFixture();
    addTearDown(fixture.service.close);
    final models = await fixture.service.list();
    expect(models.first.label, 'DeepSeek');
    expect(fixture.service.canManage, isTrue);
  });
  testWidgets(
      'provider panel stays below its field and supports keyboard selection',
      (tester) async {
    final fixture = ModelApiFixture();
    addTearDown(fixture.service.close);
    await pumpModelManager(tester, fixture);
    await tester.tap(find.text('添加模型'));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('model-provider'));
    final anchor = tester.getRect(field);
    await tester.tap(field);
    await tester.pumpAndSettle();
    final option = find.byKey(const ValueKey('model-option-aliyun'));
    final rect = tester.getRect(option);
    expect(rect.top, greaterThan(anchor.bottom));
    expect(rect.left, greaterThanOrEqualTo(anchor.left));
    expect(rect.right, lessThanOrEqualTo(anchor.right));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(option, findsNothing);
    expect(find.text('阿里云 DashScope'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('token sliders and exact inputs persist validated model limits',
      (tester) async {
    final fixture = ModelApiFixture();
    addTearDown(fixture.service.close);
    await pumpModelManager(tester, fixture);
    await tester.tap(find.text('添加模型'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('model-url')),
      'https://chat.example/v1',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('model-name')));
    await tester.enterText(
      find.byKey(const ValueKey('model-name')),
      'chat-model',
    );
    final contextSlider = find.byKey(const ValueKey('model-context-slider'));
    await tester.ensureVisible(contextSlider);
    tester.widget<Slider>(contextSlider).onChanged!(123456);
    await tester.pumpAndSettle();
    expect(find.text('123,456'), findsOneWidget);
    final output = find.byKey(const ValueKey('model-output-value'));
    await tester.ensureVisible(output);
    await tester.enterText(output, '123457');
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('不能超过上下文长度'), findsOneWidget);
    expect(fixture.saved, isNull);
    await tester.ensureVisible(output);
    await tester.enterText(output, '6543');
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(fixture.saved!['parameters']['context_window'], 123456);
    expect(fixture.saved!['parameters']['max_output_tokens'], 6543);
    expect(fixture.saved!['parameters'].containsKey('temperature'), isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'categories show only their models and type-specific provider fields',
      (tester) async {
    final fixture = ModelApiFixture();
    addTearDown(fixture.service.close);
    await pumpModelManager(tester, fixture, width: 396);
    expect(find.text('DeepSeek'), findsOneWidget);
    await tester.tap(find.text('Embedding (1)'));
    await tester.pumpAndSettle();
    expect(find.text('DeepSeek'), findsNothing);
    expect(find.text('gte-rerank-v2'), findsNothing);
    expect(find.text('text-embedding-v4'), findsOneWidget);
    await tester.tap(find.text('添加模型'));
    await tester.pumpAndSettle();
    expect(fixture.requests.last.$2['type'], 'Embedding');
    expect(find.text('向量维度'), findsOneWidget);
    expect(find.text('上下文长度'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('model-provider')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('阿里云 DashScope').last);
    await tester.pumpAndSettle();
    expect(find.text('向量专用字段'), findsOneWidget);
    expect(find.text('重排专用字段'), findsNothing);
    await tester.ensureVisible(find.text('厂商模型'));
    await tester.tap(find.byKey(const ValueKey('model-preset')));
    await tester.pumpAndSettle();
    expect(find.text('不应显示的对话模型'), findsNothing);
    await tester.tap(find.text('通义向量').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('model-key')));
    await tester.enterText(find.byKey(const ValueKey('model-key')), 'user-key');
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(fixture.saved?['type'], 'Embedding');
    expect(
      fixture.saved?['parameters']['embedding_parameters']['dimension'],
      1024,
    );
    expect(fixture.saved?['parameters'].containsKey('context_window'), isFalse);
    expect(
      (await SharedPreferences.getInstance()).getString('ai_internal.model'),
      'existing-chat',
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'rerank form hides vectors and chat fields, preserves a rejected draft',
      (tester) async {
    final fixture = ModelApiFixture()..rejectSave = true;
    addTearDown(fixture.service.close);
    await pumpModelManager(tester, fixture, width: 320, dark: true, scale: 1.3);
    await tester.ensureVisible(find.text('ReRank (1)'));
    await tester.tap(find.text('ReRank (1)'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('添加模型'));
    await tester.tap(find.text('添加模型'));
    await tester.pumpAndSettle();
    expect(find.text('向量维度'), findsNothing);
    expect(find.text('上下文长度'), findsNothing);
    expect(find.text('MAX tokens'), findsNothing);
    expect(find.text('接口协议'), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('model-url')));
    await tester.enterText(
      find.byKey(const ValueKey('model-url')),
      'https://rerank.example/v1',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('model-key')));
    await tester.enterText(
      find.byKey(const ValueKey('model-key')),
      'rerank-key',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('model-name')));
    await tester.enterText(
      find.byKey(const ValueKey('model-name')),
      'my-reranker',
    );
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.textContaining('配置冲突'), findsOneWidget);
    expect(find.text('my-reranker'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'knowledge base usage sends real model ids, never a conversation credential',
      (tester) async {
    final fixture = ModelApiFixture();
    addTearDown(fixture.service.close);
    await pumpModelManager(tester, fixture);
    await tester.ensureVisible(find.byTooltip('知识库使用设置').first);
    await tester.tap(find.byTooltip('知识库使用设置').first);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey('binding-embedding_model_id')),
          )
          .onChanged,
      isNull,
    );
    final rerank =
        find.widgetWithText(DropdownButtonFormField<String>, '不使用').first;
    await tester.ensureVisible(rerank);
    await tester.tap(rerank);
    await tester.pumpAndSettle();
    await tester.tap(find.text('gte-rerank-v2').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存使用设置'));
    await tester.tap(find.text('保存使用设置'));
    await tester.pumpAndSettle();
    expect(fixture.bound?['rerank_model_id'], 'rank');
    expect(fixture.bound?['embedding_model_id'], 'embed');
    expect(
      fixture.requests.lastWhere((r) => r.$1 == 'model_bind').$2['base_id'],
      ModelApiFixture.base,
    );
    expect(fixture.bound!.containsKey('api_key'), isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'chat limits reach WeKnora model facts without embedding parameters',
      (tester) async {
    final fixture = ModelApiFixture();
    addTearDown(fixture.service.close);
    await pumpModelManager(tester, fixture);
    await tester.tap(find.text('添加模型'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('model-url')),
      'https://chat.example/v1',
    );

    await tester.ensureVisible(find.byKey(const ValueKey('model-name')));
    await tester.enterText(find.byKey(const ValueKey('model-name')), 'my-chat');
    expect(find.text('向量维度'), findsNothing);
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final params = fixture.saved!['parameters'] as Map;
    expect(fixture.saved!['type'], 'KnowledgeQA');
    expect(params.containsKey('api_key'), isFalse);
    expect(params['context_window'], 128000);
    expect(params['max_output_tokens'], 8192);
    expect(params['spec']['api'], 'openai-completions');
    expect(params['spec']['reasoning'], isTrue);
    expect(params.containsKey('embedding_parameters'), isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'temperature card stays local and is never written to model parameters',
      (tester) async {
    final fixture = ModelApiFixture();
    addTearDown(fixture.service.close);
    await pumpModelManager(tester, fixture);
    await tester.tap(find.text('添加模型'));
    await tester.pumpAndSettle();
    final slider = find.byKey(const ValueKey('model-temperature-slider'));
    expect(find.text('1.3 温度'), findsOneWidget);
    await tester.ensureVisible(slider);
    tester.widget<Slider>(slider).onChanged!(1.8);
    await tester.pumpAndSettle();
    expect(find.text('1.8 温度'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('model-url')),
      'https://chat.example/v1',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('model-name')));
    await tester.enterText(find.byKey(const ValueKey('model-name')), 'my-chat');
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final params = fixture.saved!['parameters'] as Map;
    expect(params.containsKey('temperature'), isFalse);
    expect((params['spec'] as Map).containsKey('temperature'), isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'card actions edit, cancel deletion and delete after confirmation',
      (tester) async {
    final fixture = ModelApiFixture();
    addTearDown(fixture.service.close);
    await pumpModelManager(tester, fixture, width: 1254);
    final card = find.byKey(const ValueKey('model-card-rank'));
    expect(
      tester.getTopLeft(find.text('添加模型')).dy,
      lessThan(tester.getTopLeft(find.text('全部 (3)')).dy),
    );
    await tester
        .tap(find.descendant(of: card, matching: find.byTooltip('编辑模型')));
    await tester.pumpAndSettle();
    expect(find.text('编辑模型'), findsOneWidget);
    expect(find.text('gte-rerank-v2'), findsOneWidget);
    await tester.ensureVisible(find.text('取消'));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除模型'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(fixture.deleted, isEmpty);
    await tester.tap(find.byTooltip('删除模型'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(fixture.deleted, ['rank']);
    expect(
      fixture.requests.lastWhere((r) => r.$1 == 'model_delete').$2,
      {'workspace_id': ModelApiFixture.workspace, 'id': 'rank'},
    );
    expect(card, findsNothing);
    expect(find.text('全部 (2)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('rejected deletion keeps the model and read-only hides actions',
      (tester) async {
    final fixture = ModelApiFixture()..rejectDelete = true;
    addTearDown(fixture.service.close);
    await pumpModelManager(tester, fixture, width: 320, dark: true, scale: 1.3);
    await tester.ensureVisible(find.byTooltip('删除模型'));
    await tester.tap(find.byTooltip('删除模型'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(fixture.deleted, isEmpty);
    expect(find.byKey(const ValueKey('model-card-rank')), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    final readonly = ModelApiFixture()..canManage = false;
    addTearDown(readonly.service.close);
    await pumpModelManager(tester, readonly);
    expect(find.byTooltip('编辑模型'), findsNothing);
    expect(find.byTooltip('删除模型'), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(
            find
                .ancestor(
                  of: find.text('添加模型'),
                  matching: find.byWidgetPredicate(
                    (widget) => widget is OutlinedButton,
                  ),
                )
                .first,
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}
