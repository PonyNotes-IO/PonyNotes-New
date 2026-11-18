import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:appflowy/features/ai_internal/presentation/ai_provider_settings_view.dart';
import 'package:appflowy/features/ai_internal/presentation/knowledge_model_widgets.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'knowledge_model_manager_test.dart' as fixtures;

const output =
    'C:/Users/qq479/Desktop/PonyNotes/outputs/model-visual-polish-20261117';
const phase = String.fromEnvironment('CAPTURE_PHASE', defaultValue: 'after');

class VisualFixture extends fixtures.ModelApiFixture {
  @override
  List<Map<String, dynamic>> get models => [
        for (var i = 0; i < 9; i++)
          {
            'id': 'model-$i',
            'name': i == 0 || i == 3
                ? 'DeepSeek-V4.1-Flash'
                : 'Qwen3.7 Text Embedding',
            'type': i == 0 ? 'KnowledgeQA' : 'Embedding',
            'is_builtin': i < 3,
            if (i == 3) 'status': 'active',
            if (i == 4) 'status': 'inactive',
            'parameters': {
              'provider': i == 0 || i == 3 ? 'deepseek' : 'aliyun',
            },
          },
      ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in ['Ahem', 'Roboto', 'SimHei', 'RobotoMono']) {
      final loader = FontLoader(family);
      loader.addFont(
        Future.value(
          ByteData.sublistView(
            File('C:/Windows/Fonts/msyh.ttc').readAsBytesSync(),
          ),
        ),
      );
      await loader.load();
    }
    for (final entry in {
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
      'packages/material_symbols_icons/MaterialSymbolsOutlined':
          'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf',
    }.entries) {
      final loader = FontLoader(entry.key);
      loader.addFont(rootBundle.load(entry.value));
      await loader.load();
    }
  });
  for (final state in [
    'list-light',
    'list-dark',
    'list-compact',
    'list-narrow-dark',
    'form-light',
    'provider-light',
    'provider-dark',
    'form-dark',
    'compact-light',
    'narrow-dark',
    'form-bottom',
    'compact-bottom',
    'wide-bottom',
    'narrow-bottom',
    'bindings-light',
  ]) {
    testWidgets('render $state', (tester) async {
      debugDisableShadows = false;
      final fixture = VisualFixture();
      addTearDown(fixture.service.close);
      for (final id in [
        'generic',
        'deepseek',
        'aliyun',
        'zhipu',
        'volcengine',
        'hunyuan',
        'siliconflow',
      ]) {
        fixture.providerIcons[id] =
            'data:image/svg+xml;base64,${base64Encode(File('C:/Users/qq479/Desktop/PonyNotes/outputs/model-management-20261117/provider-assets/$id.svg').readAsBytesSync())}';
      }
      fixture.aliyunModels = [
        for (final id in ['qwen-plus', 'qwen3.8-max', 'deepseek-v4-pro'])
          {'id': id, 'name': id, 'type': 'chat'},
      ];
      fixture.additionalProviders = [
        for (final entry in {
          'zhipu': '智谱 BigModel',
          'volcengine': '火山引擎 Volcengine',
          'hunyuan': '腾讯混元 Hunyuan',
          'siliconflow': '硅基流动 SiliconFlow',
        }.entries)
          {
            'value': entry.key,
            'label': entry.value,
            'icon': fixture.providerIcons[entry.key],
            'description': {
              'zhipu': 'glm-5.3、glm-5.2、embedding-3、rerank',
              'volcengine': 'doubao-seed-2-1-pro、doubao-embedding-vision',
              'hunyuan':
                  'hunyuan-t1-latest、hunyuan-turbos-latest、hunyuan-embedding',
              'siliconflow':
                  'deepseek-ai/DeepSeek-V4-Pro、zai-org/GLM-5.2、Qwen/Qwen3.5',
            }[entry.key],
            'models': [],
            'defaultUrls': {},
          },
      ];
      final dark = state.contains('dark');
      final narrow = state.contains('narrow');
      final wide = state.contains('wide');
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(
        narrow
            ? 320
            : wide
                ? 1000
                : state.contains('compact')
                    ? 598
                    : 750,
        narrow
            ? 800
            : state.startsWith('list')
                ? 582
                : state.contains('compact')
                    ? 570
                    : 708,
      );
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final theme =
          dark ? AppFlowyDefaultTheme().dark() : AppFlowyDefaultTheme().light();
      final key = GlobalKey();
      final material = ThemeData(
        fontFamily: 'Roboto',
        brightness: dark ? Brightness.dark : Brightness.light,
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: AppFlowyTheme(
            data: theme,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: material.copyWith(
                colorScheme:
                    material.colorScheme.copyWith(primary: modelAccent),
                focusColor: modelAccent.withValues(alpha: .3),
                hoverColor: modelAccent.withValues(alpha: .2),
                highlightColor: modelAccent.withValues(alpha: .2),
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(narrow ? 1.3 : 1),
                ),
                child: child!,
              ),
              home: Scaffold(
                backgroundColor: theme.backgroundColorScheme.primary,
                body: AiProviderSettingsView(service: fixture.service),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (state.startsWith('list')) {
        // Capture the initial model inventory.
      } else if (state.startsWith('bindings')) {
        await tester.ensureVisible(find.byTooltip('知识库使用设置').first);
        await tester.tap(find.byTooltip('知识库使用设置').first);
        await tester.pumpAndSettle();
        final field = find.byKey(const ValueKey('binding-rerank_model_id'));
        await tester.ensureVisible(field);
        await tester.tap(field);
        await tester.pumpAndSettle();
      } else {
        await tester.tap(find.text('添加模型'));
        await tester.pumpAndSettle();
        if (state.startsWith('provider')) {
          await tester.tap(find.byKey(const ValueKey('model-provider')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('model-option-aliyun')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('model-provider')));
          await tester.pumpAndSettle();
        } else if (state.startsWith('protocol')) {
          await tester.tap(find.byKey(const ValueKey('model-protocol')));
          await tester.pumpAndSettle();
        } else {
          // Keep the initial, closed form visible for comparison.
        }
        if (state.endsWith('-bottom')) {
          await tester.ensureVisible(
            find.byKey(const ValueKey('model-temperature-value')),
          );
          await tester.pumpAndSettle();
        }
      }
      final pointer =
          await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      final hoverText = state.startsWith('provider')
          ? '阿里云 DashScope'
          : state.startsWith('bindings')
              ? 'gte-rerank-v2'
              : 'Ollama 本地服务';
      if ((state.startsWith('provider') ||
              state.startsWith('bindings') ||
              state.startsWith('protocol')) &&
          find.text(hoverText).evaluate().isNotEmpty) {
        await pointer.addPointer(
          location: tester.getCenter(find.text(hoverText).last),
        );
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image = await (key.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$output/$phase-$state.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
      debugDisableShadows = true;
    });
  }
}
