import 'dart:async';
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
import 'package:flutter/gestures.dart';
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
    creatorName: '马同学',
  );
  const second = AiProviderConfig(
    baseUrl: 'https://second.example/v1',
    modelName: 'reasoner-two',
    apiKey: 'second-key',
    supportsReasoning: true,
    creatorName: '谷谷爸爸',
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

  testWidgets('a new user can select project models without a custom key',
      (tester) async {
    AiProviderConfig? selected;
    String? effort;
    final service = AgentInternalService(
      account: () async => const AgentCloudAccount(
        baseUrl: 'https://cloud.test',
        accessToken: 'login',
        userId: '1',
      ),
      client: MockClient(
        (_) async => http.Response(
          '{"data":{"models":[{"id":"deepseek-chat","name":"DeepSeek"},{"id":"qwen3-vl-plus","name":"通义千问"},{"id":"doubao","name":"豆包"}]}}',
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    await tester.pumpWidget(
      WidgetTestWrapper(
        child: AgentModelSettingsButton(
          internalService: service,
          onChanged: (config, level) async {
            selected = config;
            effort = level;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('DeepSeek'), findsOneWidget);
    await tester.tap(find.byTooltip('选择模型'));
    await tester.pumpAndSettle();
    expect(find.text('平台模型'), findsOneWidget);
    expect(find.text('配置自定义模型'), findsOneWidget);
    expect(find.text('豆包'), findsOneWidget);
    await tester.tap(find.text('通义千问'));
    await tester.pumpAndSettle();
    expect(selected?.isInternal, true);
    expect(selected?.apiKey, isEmpty);
    expect((await service.preferred()).modelName, 'qwen3-vl-plus');
    expect(await storage.loadProfiles(), isEmpty);
    expect(selected?.supportsReasoning, true);
    await tester.tap(find.byTooltip('思考强度'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agent-thinking-max')));
    await tester.pumpAndSettle();
    expect(selected?.modelName, 'qwen3-vl-plus');
    expect(effort, 'max');
    expect(await AgentModelPreferences.loadThinking(), 'max');
  });

  testWidgets('opening the model menu keeps its anchor stable during a refresh',
      (tester) async {
    final refresh = Completer<http.Response>();
    final response = http.Response(
      '{"data":{"models":[{"id":"doubao","name":"豆包"}]}}',
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
    var requests = 0;
    final service = AgentInternalService(
      account: () async => const AgentCloudAccount(
        baseUrl: 'https://cloud.test',
        accessToken: 'login',
        userId: '1',
      ),
      client: MockClient(
        (_) async => ++requests == 1 ? response : await refresh.future,
      ),
    );
    await tester.pumpWidget(
      WidgetTestWrapper(
        child: Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AgentModelSettingsButton(internalService: service),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final trigger = find.byTooltip('选择模型');
    final anchor = tester.getRect(trigger);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    final anchorDuringRefresh = tester.getRect(trigger);
    final thinkingDuringRefresh = find.byTooltip('思考强度').evaluate().length;
    final menuItem = find.widgetWithText(MenuItemButton, '配置自定义模型');
    final menuRect = tester.getRect(menuItem);
    refresh.complete(response);
    await tester.pumpAndSettle();
    expect(requests, 2);
    expect(thinkingDuringRefresh, 1);
    expect(anchorDuringRefresh, anchor);
    expect(tester.getRect(trigger), anchor);
    expect(tester.getRect(menuItem), menuRect);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
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
    await tester.tap(find.byTooltip('思考强度'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agent-thinking-max')));
    await tester.pumpAndSettle();
    expect(effort, 'max');
    expect(await AgentModelPreferences.loadThinking(), 'max');
    expect(
      find.descendant(
        of: find.byTooltip('思考强度'),
        matching: find.text('最大'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('agent-thinking-max')), findsNothing);
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

  testWidgets('custom model hover shows its creator without selecting it',
      (tester) async {
    await storage.save(first);
    await storage.save(second);
    AiProviderConfig? selected;
    await tester.pumpWidget(
      WidgetTestWrapper(
        child: AgentModelSettingsButton(
          onChanged: (config, _) async => selected = config,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('选择模型'));
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 1));
    await mouse.moveTo(
      tester.getCenter(find.widgetWithText(MenuItemButton, first.modelName)),
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.text('创建人：马同学'), findsOneWidget);
    expect(find.text(first.modelName), findsNWidgets(2));
    expect(selected, isNull);
    expect((await storage.load()).modelName, second.modelName);
    expect(find.textContaining(first.baseUrl), findsNothing);
    await mouse.moveTo(
      tester.getCenter(find.widgetWithText(MenuItemButton, second.modelName)),
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.text('创建人：马同学'), findsNothing);
    expect(find.text('创建人：谷谷爸爸'), findsOneWidget);
    await tester.tap(find.widgetWithText(MenuItemButton, second.modelName));
    await tester.pumpAndSettle();
    expect(selected?.modelName, second.modelName);
    expect(find.byKey(const ValueKey('agent-model-details')), findsNothing);
    await mouse.removePointer();
  });

  testWidgets('legacy model details dismiss on exit and menu cancellation',
      (tester) async {
    await storage.save(first.copyWith(creatorName: ''));
    await tester.pumpWidget(
      const WidgetTestWrapper(child: AgentModelSettingsButton()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('选择模型'));
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 1));
    final target =
        tester.getCenter(find.widgetWithText(MenuItemButton, first.modelName));
    await mouse.moveTo(target);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.text('创建人：未知'), findsOneWidget);
    await mouse.moveTo(const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('agent-model-details')), findsNothing);
    await mouse.moveTo(target);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('agent-model-details')), findsNothing);
    // Closing before the hover delay expires must cancel the pending card too.
    await tester.tap(find.byTooltip('选择模型'));
    await tester.pumpAndSettle();
    await mouse.moveTo(const Offset(1, 1));
    await mouse.moveTo(target);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('agent-model-details')), findsNothing);
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
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
    expect(find.text('低'), findsOneWidget);
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

  testWidgets('thinking choices support keyboard selection and Escape',
      (tester) async {
    String? effort;
    await tester.pumpWidget(
      WidgetTestWrapper(
        child: AgentModelSettingsButton(
          currentConfig: first,
          currentThinking: 'medium',
          onChanged: (_, level) async => effort = level,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('思考强度'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(effort, 'high');
    expect(await AgentModelPreferences.loadThinking(), 'high');
    expect(find.byKey(const ValueKey('agent-thinking-high')), findsNothing);
    await tester.tap(find.byTooltip('思考强度'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('agent-thinking-high')), findsNothing);
    expect(effort, 'high');
  });

  testWidgets('custom model settings record the creator and retain it on edit',
      (tester) async {
    Future<void> openSettings(String creator) async {
      await tester.pumpWidget(
        WidgetTestWrapper(
          child: AiProviderSettingsView(
            key: ValueKey(creator),
            creatorName: creator,
            onSaved: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await openSettings('马同学');
    await tester.enterText(find.byType(TextField).at(0), first.baseUrl);
    await tester.enterText(find.byType(TextField).at(1), first.modelName);
    await tester.enterText(find.byType(TextField).at(2), first.apiKey);
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect((await storage.load()).creatorName, '马同学');
    await openSettings('修改人');
    await tester.enterText(find.byType(TextField).at(2), 'updated-key');
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect((await storage.load()).creatorName, '马同学');
    expect((await storage.load()).apiKey, 'updated-key');
  });

  testWidgets('failed thinking changes restore the previous level',
      (tester) async {
    await storage.save(first);
    await AgentModelPreferences.saveThinking('low');
    await tester.pumpWidget(
      WidgetTestWrapper(
        child: AgentModelSettingsButton(
          currentConfig: first,
          currentThinking: 'low',
          onChanged: (_, __) async => throw StateError('思考强度切换失败'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('思考强度'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agent-thinking-max')));
    await tester.pumpAndSettle();
    expect(await AgentModelPreferences.loadThinking(), 'low');
    expect(find.text('低'), findsOneWidget);
    expect(find.textContaining('思考强度切换失败'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  for (final variant in [
    (name: 'desktop-light', size: const Size(1360, 900), dark: false),
    (name: 'reference-dark', size: const Size(1215, 828), dark: true),
    (name: 'screenshot-dark', size: const Size(890, 606), dark: true),
    (name: 'phone-dark', size: const Size(390, 844), dark: true),
    (name: 'compact-light', size: const Size(320, 480), dark: false),
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
      final reference =
          variant.name == 'reference-dark' || variant.name == 'screenshot-dark';
      final firstProfile =
          reference ? first.copyWith(modelName: 'DeepSeek-V4.1-Flash') : first;
      final secondProfile = reference
          ? second.copyWith(modelName: 'DeepSeek-V4.1-Flash')
          : second;
      await storage.save(firstProfile);
      await storage.save(secondProfile);
      if (reference) {
        await storage
            .save(firstProfile.copyWith(baseUrl: 'https://third.example/v1'));
      }
      await AgentInternalService(
        account: () async => const AgentCloudAccount(
          baseUrl: 'https://cloud.test',
          accessToken: 'login',
          userId: '1',
        ),
      ).select(reference ? firstProfile : secondProfile);
      await AgentModelPreferences.saveThinking(reference ? 'medium' : 'high');
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
                          Align(
                            alignment: Alignment.centerRight,
                            child: AgentModelSettingsButton(
                              internalService: AgentInternalService(
                                account: () async => const AgentCloudAccount(
                                  baseUrl: 'https://cloud.test',
                                  accessToken: 'login',
                                  userId: '1',
                                ),
                                client: MockClient(
                                  (_) async => http.Response(
                                    '{"data":{"models":[{"id":"deepseek-chat","name":"DeepSeek"},{"id":"qwen3-vl-plus","name":"通义千问"},{"id":"doubao","name":"豆包"}]}}',
                                    200,
                                    headers: {
                                      'content-type':
                                          'application/json; charset=utf-8',
                                    },
                                  ),
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
          menu == 'model' ? find.byTooltip('选择模型') : find.byTooltip('思考强度'),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (menu == 'model') {
          expect(find.text('平台模型'), findsOneWidget);
          expect(find.text('自定义模型'), findsOneWidget);
          expect(find.byIcon(Icons.check), findsOneWidget);
          final lastItem =
              tester.getRect(find.widgetWithText(MenuItemButton, '配置自定义模型'));
          expect(lastItem.left, greaterThanOrEqualTo(0));
          expect(lastItem.right, lessThanOrEqualTo(variant.size.width));
          final triggerRight = tester.getTopRight(find.byTooltip('选择模型')).dx;
          if (triggerRight >= 224) {
            expect(lastItem.right, closeTo(triggerRight - 6, 1));
          }
          expect(
            tester
                .getBottomRight(find.widgetWithText(MenuItemButton, '配置自定义模型'))
                .dy,
            lessThan(tester.getTopLeft(find.byTooltip('选择模型')).dy),
          );
        } else {
          final firstItem = tester.getRect(
            find.byKey(const ValueKey('agent-thinking-off')),
          );
          final lastItem = tester.getRect(
            find.byKey(const ValueKey('agent-thinking-max')),
          );
          expect(firstItem.left, greaterThanOrEqualTo(0));
          expect(firstItem.top, greaterThanOrEqualTo(0));
          expect(lastItem.right, lessThanOrEqualTo(variant.size.width));
          expect(lastItem.bottom, lessThanOrEqualTo(variant.size.height));
          expect(find.text('思考强度'), findsOneWidget);
          expect(find.text('默认'), findsNothing);
          expect(find.text('按任务难度选择思考深度'), findsNothing);
          expect(find.text('思考越深入，通常耗时越长'), findsNothing);
          expect(find.byIcon(Icons.check), findsOneWidget);
          expect(lastItem.width, closeTo(78, 1));
          expect(lastItem.bottom - firstItem.top, lessThanOrEqualTo(186));
          final trigger = tester.getRect(find.byTooltip('思考强度'));
          expect(lastItem.bottom, lessThan(trigger.top));
          expect(lastItem.right, closeTo(trigger.right - 6, 1));
        }
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
        if (menu == 'model') {
          final mouse =
              await tester.createGesture(kind: PointerDeviceKind.mouse);
          await mouse.addPointer(location: const Offset(1, 1));
          await mouse.moveTo(
            tester.getCenter(
              find.descendant(
                of: find.byKey(
                  ValueKey('${firstProfile.baseUrl}|${firstProfile.modelName}'),
                ),
                matching: find.byType(MenuItemButton),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 250));
          await tester.pumpAndSettle();
          final card = tester.getRect(
            find.byKey(const ValueKey('agent-model-details')),
          );
          expect(card.left, greaterThanOrEqualTo(8));
          expect(card.top, greaterThanOrEqualTo(8));
          expect(card.right, lessThanOrEqualTo(variant.size.width - 8));
          expect(card.bottom, lessThanOrEqualTo(variant.size.height - 8));
          expect(find.text('创建人：马同学'), findsOneWidget);
          expect(tester.takeException(), isNull);
          if (variant.size.width >= 890) {
            final menuItem = tester.getRect(
              find.widgetWithText(MenuItemButton, '配置自定义模型'),
            );
            expect(card.right, lessThan(menuItem.left));
            expect(card.top, lessThan(tester.getTopLeft(find.text('平台模型')).dy));
          } else {
            expect(
              card.bottom,
              lessThan(tester.getTopLeft(find.text('平台模型')).dy),
            );
          }
          if (output != null) {
            await tester.runAsync(() async {
              final rendered = await (boundary.currentContext!
                      .findRenderObject()! as RenderRepaintBoundary)
                  .toImage();
              final bytes =
                  await rendered.toByteData(format: ui.ImageByteFormat.png);
              await File('$output/model-details-${variant.name}.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              rendered.dispose();
            });
          }
          await mouse.removePointer();
          await tester.pumpAndSettle();
        }
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
      }
      debugDisableShadows = shadowsDisabled;
    });
  }
}
