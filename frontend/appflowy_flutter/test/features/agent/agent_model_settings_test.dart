import 'dart:io';
import 'dart:ui' as ui;
import 'package:appflowy/features/agent/application/agent_model_preferences.dart';
import 'package:appflowy/features/agent/application/agent_internal_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:appflowy/features/agent/presentation/agent_model_settings.dart';
import 'package:appflowy/features/ai_internal/application/ai_provider_config.dart';
import 'package:appflowy/features/ai_internal/presentation/ai_provider_settings_view.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widget_test/widget_test_wrapper.dart';

void main() {
  const first = AiProviderConfig(
    baseUrl: 'https://first.example/v1',
    modelName: 'reasoner-one',
    apiKey: 'first-key',
    supportsReasoning: true,
  );
  const second = AiProviderConfig(
    baseUrl: 'https://second.example/v1',
    modelName: 'reasoner-two',
    apiKey: 'second-key',
    supportsReasoning: true,
  );
  const storage = AiProviderConfigStorage();
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

  testWidgets('a new user can select sub2api models without a custom key',
      (tester) async {
    AiProviderConfig? selected;
    final service = AgentInternalService(
      account: () async => const AgentCloudAccount(
        baseUrl: 'https://cloud.test',
        accessToken: 'login',
        userId: '1',
      ),
      client: MockClient(
        (_) async => http.Response(
          '{"data":[{"id":"managed-first"},{"id":"managed-second"}]}',
          200,
        ),
      ),
    );
    await tester.pumpWidget(
      WidgetTestWrapper(
        child: AgentModelSettingsButton(
          internalService: service,
          onChanged: (config, _) async => selected = config,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('managed-first'), findsOneWidget);
    await tester.tap(find.byTooltip('选择模型'));
    await tester.pumpAndSettle();
    expect(find.text('内部模型'), findsOneWidget);
    expect(find.text('配置自定义模型'), findsOneWidget);
    await tester.tap(find.text('managed-second'));
    await tester.pumpAndSettle();
    expect(selected?.isInternal, true);
    expect(selected?.apiKey, isEmpty);
    expect((await service.preferred()).modelName, 'managed-second');
    expect(await storage.loadProfiles(), isEmpty);
  });

  testWidgets(
      'model menu switches secure profiles and applies the selected thinking level',
      (tester) async {
    await storage.save(first);
    await storage.save(second);
    AiProviderConfig? selected;
    String? effort;
    await tester.pumpWidget(
      WidgetTestWrapper(
        child: AgentModelSettingsButton(
          onChanged: (config, level) async {
            selected = config;
            effort = level;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('选择模型'));
    await tester.pumpAndSettle();
    expect(find.text('配置自定义模型'), findsOneWidget);
    await tester.tap(find.text('reasoner-one').last);
    await tester.pumpAndSettle();
    expect(selected?.modelName, first.modelName);
    expect(selected?.apiKey, first.apiKey);
    await tester.tap(find.text('思考 · 关闭'));
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(4);
    slider.onChangeEnd!(4);
    await tester.pumpAndSettle();
    expect(effort, 'high');
    expect(await AgentModelPreferences.loadThinking(), 'high');
    expect(find.text('思考 · 高'), findsOneWidget);
  });

  testWidgets('failed model changes keep the previous active model',
      (tester) async {
    await storage.save(first);
    await storage.save(second);
    await tester.pumpWidget(
      WidgetTestWrapper(
        child: AgentModelSettingsButton(
          onChanged: (_, __) async {
            throw StateError('模型切换失败');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('选择模型'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(first.modelName).last);
    await tester.pumpAndSettle();
    expect((await storage.load()).modelName, second.modelName);
    expect(find.textContaining('模型切换失败'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'an open document shows its actual model when another document changes the default',
      (tester) async {
    await storage.save(second);
    await tester.pumpWidget(
      const WidgetTestWrapper(
        child: AgentModelSettingsButton(
          currentConfig: first,
          currentThinking: 'low',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(first.modelName), findsOneWidget);
    expect(find.text('思考 · 低'), findsOneWidget);
    await tester.tap(find.byTooltip('选择模型'));
    await tester.pumpAndSettle();
    expect(find.text(first.modelName), findsWidgets);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text(first.modelName), findsOneWidget);
    expect(find.text(second.modelName), findsNothing);
  });

  testWidgets('custom configuration is available directly from the model menu',
      (tester) async {
    AiProviderConfig? selected;
    await tester.pumpWidget(
      WidgetTestWrapper(
        child: AgentModelSettingsButton(
          currentConfig: first,
          onChanged: (config, _) async {
            selected = config;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('选择模型'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('配置自定义模型'));
    await tester.pumpAndSettle();
    expect(find.byType(AiProviderSettingsView), findsOneWidget);
    expect(find.text('模型地址'), findsOneWidget);
    expect(find.text('支持推理 / 思考程度'), findsOneWidget);
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('请填写模型地址、模型名称和 API Key。'), findsOneWidget);
    expect(find.byType(AiProviderSettingsView), findsOneWidget);
    await tester.enterText(
      find.byType(TextField).at(0),
      'https://custom.example/v1',
    );
    await tester.enterText(find.byType(TextField).at(1), 'my-custom-model');
    await tester.enterText(find.byType(TextField).at(2), 'custom-key');
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.byType(AiProviderSettingsView), findsNothing);
    expect(selected?.modelName, 'my-custom-model');
    expect(selected?.apiKey, 'custom-key');
    expect(find.text('my-custom-model'), findsOneWidget);
  });

  for (final variant in [
    (name: 'desktop-light', size: const Size(1360, 900), dark: false),
    (name: 'phone-dark', size: const Size(390, 844), dark: true),
  ]) {
    testWidgets('model and thinking popovers fit ${variant.name}',
        (tester) async {
      final shadowsDisabled = debugDisableShadows;
      debugDisableShadows = false;
      addTearDown(() => debugDisableShadows = shadowsDisabled);
      tester.view.physicalSize = variant.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await storage.save(first);
      await storage.save(second);
      await AgentModelPreferences.saveThinking('high');
      final theme = AppFlowyDefaultTheme();
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: variant.dark ? Brightness.dark : Brightness.light,
              fontFamily: 'AgentTestFont',
            ),
            home: AppFlowyTheme(
              data: variant.dark ? theme.dark() : theme.light(),
              child: Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 792),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: variant.dark ? Colors.white24 : Colors.black26,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const TextField(
                            decoration: InputDecoration(
                              hintText: '输入问题，或告诉我需要做什么',
                              border: InputBorder.none,
                            ),
                          ),
                          const SizedBox(height: 8),
                          AgentModelSettingsButton(
                            internalService: AgentInternalService(
                              account: () async => const AgentCloudAccount(
                                baseUrl: 'https://cloud.test',
                                accessToken: 'login',
                                userId: '1',
                              ),
                              client: MockClient(
                                (_) async => http.Response(
                                  '{"data":[{"id":"sub2api-chat"},{"id":"sub2api-reasoner-long-model-name"}]}',
                                  200,
                                ),
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
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final menu in ['model', 'thinking']) {
        await tester.tap(
          menu == 'model' ? find.byTooltip('选择模型') : find.text('思考 · 高'),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final output = Platform.environment['PONYNOTES_AGENT_SCREENSHOTS'];
        if (output != null) {
          await tester.runAsync(() async {
            final rendered = await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
            final bytes =
                await rendered.toByteData(format: ui.ImageByteFormat.png);
            await Directory(output).create(recursive: true);
            await File('$output/$menu-${variant.name}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            rendered.dispose();
          });
        }
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
      }
      debugDisableShadows = shadowsDisabled;
    });
  }
}
