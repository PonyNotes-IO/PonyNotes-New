import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/plugins/import_page/import_page_widgets.dart';
import 'package:appflowy/plugins/import_page/import_sync_section.dart';
import 'package:appflowy/plugins/knowledge_base/knowledge_base_data_source_editor.dart';
import 'package:appflowy/plugins/knowledge_base/knowledge_base_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EmptyTranslations extends AssetLoader {
  const _EmptyTranslations();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => {};
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    final iconFont =
        FontLoader('packages/font_awesome_flutter/FontAwesomeRegular');
    iconFont.addFont(
      rootBundle.load(
        'packages/font_awesome_flutter/lib/fonts/fa-regular-400.ttf',
      ),
    );
    await iconFont.load();
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (await font.exists()) {
      await (FontLoader('ImportTestFont')
            ..addFont(font.readAsBytes().then(ByteData.sublistView)))
          .load();
    }
  });

  for (final variant in [
    (name: 'reference', size: const Size(820, 662), dark: false, scale: 1.0),
    (name: 'desktop', size: const Size(1360, 900), dark: false, scale: 1.0),
    (name: 'tablet', size: const Size(600, 700), dark: false, scale: 1.0),
    (name: 'phone', size: const Size(390, 844), dark: false, scale: 1.0),
    (name: 'compact', size: const Size(320, 640), dark: false, scale: 1.6),
    (name: 'dark', size: const Size(820, 662), dark: true, scale: 1.0),
  ]) {
    testWidgets('import actions and sync work on ${variant.name}',
        (tester) async {
      tester.view.physicalSize = variant.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final capture = GlobalKey();
      final imports = <String>[];
      final operations = <String>[];
      final openedPages = <String>[];
      var connected = true;
      var noteStatus = <String, dynamic>{'status': 'idle'};
      Map<String, dynamic> source() => {
            'id': 'feishu',
            'type': 'feishu',
            'name': 'feishu',
            'status': 'paused',
            'note_sync': noteStatus,
            'config': {
              'resource_ids': ['test-id'],
            },
          };
      final service = KnowledgeBaseService(
        () async => ('https://knowledge.example', 'test'),
        client: MockClient((request) async {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          final operation = payload['operation'];
          final sourceId = payload['source_id'] as String?;
          expect(request.url.path, '/api/knowledge/workspace_sync');
          expect(payload.containsKey('base_id'), isFalse);
          expect(payload['workspace_id'], 'workspace');
          operations.add('$operation:$sourceId');
          final Map<String, dynamic> data;
          switch (operation) {
            case 'list':
              data = {
                'sources': [if (connected) source()],
              };
            case 'types':
              data = {
                'types': [
                  for (final kind in ['feishu', 'notion', 'yuque', 'gitlab'])
                    {'type': kind, 'name': kind, 'fields': <Object>[]},
                ],
              };
            case 'note_sync':
              noteStatus = {'status': 'running'};
              data = noteStatus;
            case 'delete':
              connected = false;
              data = {'deleted': true};
            default:
              fail('Unexpected operation $operation');
          }
          return http.Response(
            jsonEncode({'success': true, 'data': data}),
            200,
          );
        }),
      );
      addTearDown(service.close);
      final theme = variant.dark ? ThemeData.dark() : ThemeData.light();
      final previousShadows = debugDisableShadows;
      try {
        if (Platform.environment['PONYNOTES_IMPORT_SCREENSHOTS'] != null) {
          debugDisableShadows = false;
        }
        await tester.pumpWidget(
          EasyLocalization(
            supportedLocales: const [Locale('zh', 'CN')],
            startLocale: const Locale('zh', 'CN'),
            path: 'assets/translations',
            assetLoader: const _EmptyTranslations(),
            saveLocale: false,
            child: Builder(
              builder: (context) => MaterialApp(
                debugShowCheckedModeBanner: false,
                locale: context.locale,
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                theme: theme.copyWith(
                  textTheme:
                      theme.textTheme.apply(fontFamily: 'ImportTestFont'),
                  colorScheme: theme.colorScheme.copyWith(
                    surface:
                        variant.dark ? const Color(0xFF1E1E1E) : Colors.white,
                    onSurface:
                        variant.dark ? Colors.white : const Color(0xFF37352F),
                  ),
                ),
                home: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(variant.scale),
                  ),
                  child: RepaintBoundary(
                    key: capture,
                    child: Scaffold(
                      body: ImportPageContent(
                        onFileImport: imports.add,
                        onNotionImport: () => imports.add('notion'),
                        onObsidianImport: () => imports.add('obsidian'),
                        syncContent: ImportSyncSection(
                          workspaceId: 'workspace',
                          service: service,
                          onOpenSyncedPage: openedPages.add,
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
        expect(tester.takeException(), isNull);

        Future<void> screenshot(String state) async {
          final output = Platform.environment['PONYNOTES_IMPORT_SCREENSHOTS'];
          if (output == null) return;
          final previous = debugDisableShadows;
          final boundary = capture.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          try {
            debugDisableShadows = false;
            boundary.markNeedsPaint();
            await tester.pump();
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              await Directory(output).create(recursive: true);
              await File('$output/import-${variant.name}-$state.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          } finally {
            debugDisableShadows = previous;
          }
        }

        await screenshot('files');
        if (variant.name == 'reference') {
          final csv =
              tester.getTopLeft(find.byKey(const ValueKey('import-file-csv')));
          final html =
              tester.getTopLeft(find.byKey(const ValueKey('import-file-html')));
          expect(csv.dy, html.dy);
          // Keyboard users can reach and activate a file card.
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(imports, ['csv']);
          imports.clear();
        }

        for (final type in ['csv', 'pdf', 'markdown', 'html']) {
          final card = find.byKey(ValueKey('import-file-$type'));
          await tester.ensureVisible(card);
          await tester.tap(card);
          await tester.pumpAndSettle();
        }
        for (final service in ['Notion', 'Obsidian']) {
          await tester.ensureVisible(find.text(service));
          await tester.tap(find.text(service));
          await tester.pumpAndSettle();
        }
        expect(
          imports,
          ['csv', 'pdf', 'markdown', 'html', 'notion', 'obsidian'],
        );
        await tester.ensureVisible(find.widgetWithText(TextButton, '同步'));
        await tester.tap(find.widgetWithText(TextButton, '同步'));
        await tester.pumpAndSettle();
        expect(find.text('CSV'), findsNothing);
        expect(find.text('连接外部应用'), findsOneWidget);
        expect(find.text('已连接'), findsOneWidget);
        expect(find.text('手动同步 · 未同步', findRichText: true), findsOneWidget);
        await tester.runAsync(() async {
          final imageContext = tester.element(find.byType(ImportSyncSection));
          await Future.wait([
            for (final provider in ['feishu', 'notion', 'yuque', 'gitlab'])
              precacheImage(
                AssetImage('assets/images/icons/sync_$provider.png'),
                imageContext,
              ),
          ]);
        });
        await tester.pumpAndSettle();
        await screenshot('sync');
        if (variant.name == 'reference') {
          final feishu = find.byKey(const ValueKey('sync-feishu'));
          expect(
            tester.getTopLeft(feishu).dy,
            tester.getTopLeft(find.byKey(const ValueKey('sync-notion'))).dy,
          );
          Finder action(String tooltip) => find.descendant(
                of: feishu,
                matching: find.byWidgetPredicate(
                  (widget) => widget is IconButton && widget.tooltip == tooltip,
                ),
              );
          expect(find.text('暂未支持'), findsNothing);
          await tester.tap(action('编辑连接'));
          await tester.pumpAndSettle();
          final editor = tester.widget<KnowledgeBaseDataSourceEditor>(
            find.byType(KnowledgeBaseDataSourceEditor),
          );
          expect(editor.source?['id'], 'feishu');
          expect(editor.workspaceId, 'workspace');
          expect(editor.base, isNull);
          expect(find.text('同步计划'), findsNothing);
          await tester.tap(find.text('返回数据源'));
          await tester.pumpAndSettle();
          await tester.tap(action('立即同步'));
          await tester.pumpAndSettle();
          expect(operations, contains('note_sync:feishu'));
          expect(tester.widget<IconButton>(action('立即同步')).onPressed, isNull);
          noteStatus = {
            'status': 'success',
            'saved': 2,
            'view_id': 'private-page',
          };
          await tester.pump(const Duration(seconds: 5));
          await tester.pumpAndSettle();
          expect(
            tester.widget<IconButton>(action('立即同步')).onPressed,
            isNotNull,
          );
          expect(find.text('已保存 2 篇'), findsOneWidget);
          await tester.tap(find.text('打开同步笔记'));
          expect(openedPages, ['private-page']);
          await tester.tap(action('断开连接'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(TextButton, '取消'));
          await tester.pumpAndSettle();
          expect(operations, isNot(contains('delete:feishu')));
          await tester.tap(action('断开连接'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(TextButton, '断开连接'));
          await tester.pumpAndSettle();
          expect(operations, contains('delete:feishu'));
          expect(find.text('未连接'), findsNWidgets(4));
          for (final kind in ['feishu', 'notion', 'yuque', 'gitlab']) {
            final card = find.byKey(ValueKey('sync-$kind'));
            await tester.ensureVisible(card);
            await tester.tap(card);
            await tester.pumpAndSettle();
            final editorFinder = find.byType(KnowledgeBaseDataSourceEditor);
            expect(
              tester
                  .widget<KnowledgeBaseDataSourceEditor>(editorFinder)
                  .definition['type'],
              kind,
            );
            expect(find.text('选择目标知识库'), findsNothing);
            await tester.tap(find.text('返回数据源'));
            await tester.pumpAndSettle();
          }
        }
        await tester.tap(find.widgetWithText(TextButton, '导入'));
        await tester.pumpAndSettle();
        expect(find.text('CSV'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        debugDisableShadows = previousShadows;
      }
    });
  }
}
