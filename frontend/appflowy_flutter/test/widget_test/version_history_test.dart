import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/features/version_history/version_history_page.dart';
import 'package:appflowy/features/version_history/version_history_service.dart';
import 'package:appflowy/features/version_history/version_history_diff_view.dart';
import 'package:appflowy/features/version_history/version_history_diff.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_backend/protobuf/flowy-document/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:protobuf/protobuf.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

class _Appearance extends Mock implements AppearanceSettingsCubit {}

class _History extends VersionHistoryService {
  int saves = 0;
  int restores = 0;
  bool fail = false;
  bool failRestore = false;
  Object? listFailure;
  Completer<DocumentSnapshotMetaPB>? pending;
  Completer<void>? pendingRestore;
  final versions = <DocumentSnapshotMetaPB>[];
  final contents = <String, DocumentDataPB>{};
  late DocumentDataPB current = document.deepCopy();
  final document = DocumentDataPBFromTo.fromDocument(
    Document(
      root: pageNode(
        children: [
          headingNode(level: 1, text: 'Project notes'),
          paragraphNode(
            text: 'The content saved before the next major change.',
          ),
          bulletedListNode(text: 'A saved version stays read only.'),
          paragraphNode(
            text: 'The original document remains open and editable.',
          ),
        ],
      ),
    ),
  )!;

  @override
  Future<DocumentHistoryListPB> list(
    String documentId, {
    int offset = 0,
  }) async {
    if (listFailure != null) throw listFailure!;
    return DocumentHistoryListPB(
      items: versions.skip(offset),
      retentionDays: 7,
    );
  }

  @override
  Future<DocumentSnapshotMetaPB> save(String documentId) async {
    saves++;
    if (fail) throw FlowyError(msg: 'offline');
    final version = pending != null
        ? await pending!.future
        : DocumentSnapshotMetaPB(
            snapshotId: 'saved-$saves',
            objectId: documentId,
            createdAt: Int64(1793840400000),
          );
    return store(version);
  }

  DocumentSnapshotMetaPB store(DocumentSnapshotMetaPB version) {
    for (final existing in versions) {
      if (!compareHistory((current, contents[existing.snapshotId]!))
          .hasChanges) {
        return existing.deepCopy()..reused = true;
      }
    }
    versions.insert(0, version);
    contents[version.snapshotId] = current.deepCopy();
    return version;
  }

  @override
  Future<DocumentDataPB> get(String documentId, String snapshotId) async =>
      contents[snapshotId]!.deepCopy();

  @override
  Future<DocumentDataPB> readCurrent(String documentId) async =>
      current.deepCopy();

  @override
  Future<DocumentSnapshotMetaPB> restore(
    String documentId,
    String snapshotId,
  ) async {
    expect(documentId, 'document');
    restores++;
    if (failRestore) throw FlowyError(msg: 'cloud_storage_full');
    await pendingRestore?.future;
    final backup = store(
      DocumentSnapshotMetaPB(
        snapshotId: 'backup-$restores',
        objectId: documentId,
        createdAt: Int64(1793840400000 + restores * 1000),
      ),
    );
    current = contents[snapshotId]!.deepCopy();
    return backup;
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            await File('build/unit_test_assets/fonts/MaterialIcons-Regular.otf')
                .readAsBytes(),
          ),
        ),
      );
    await icons.load();
    if (Platform.isWindows) {
      for (final family in ['Arial', 'Roboto', 'Ahem', 'Microsoft YaHei UI']) {
        final font = FontLoader(family)
          ..addFont(
            Future.value(
              ByteData.sublistView(
                await File('C:/Windows/Fonts/arial.ttf').readAsBytes(),
              ),
            ),
          )
          ..addFont(
            Future.value(
              ByteData.sublistView(
                await File('C:/Windows/Fonts/arialbd.ttf').readAsBytes(),
              ),
            ),
          );
        await font.load();
      }
    }
  });

  Future<void> mount(
    WidgetTester tester,
    _History service, {
    Size size = const Size(1100, 760),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final appearance = _Appearance();
    final state = AppearanceSettingsState.initial(
      AppTheme.fallback,
      ThemeModePB.Light,
      'Arial',
      LayoutDirectionPB.LTRLayout,
      null,
      false,
      LocaleSettingsPB(languageCode: 'en', countryCode: 'US'),
      false,
      0,
      UserDateFormatPB.Friendly,
      UserTimeFormatPB.TwentyFourHour,
      '',
      null,
      null,
      1,
    );
    when(() => appearance.state).thenReturn(state);
    when(() => appearance.stream).thenAnswer((_) => const Stream.empty());
    final theme = DesktopAppearance().getThemeData(
      AppTheme.fallback,
      Brightness.light,
      'Arial',
      builtInCodeFontFamily,
    );
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        saveLocale: false,
        assetLoader: const TestBundleAssetLoader(),
        child: Builder(
          builder: (context) => BlocProvider<AppearanceSettingsCubit>.value(
            value: appearance,
            child: MaterialApp(
              theme: theme,
              locale: context.locale,
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              home: RepaintBoundary(
                key: const ValueKey('history-capture'),
                child: VersionHistoryPage(
                  view: ViewPB(id: 'document', name: 'Project notes'),
                  service: service,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> finishComparison(WidgetTester tester) async {
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      do {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      } while (find.byType(CircularProgressIndicator).evaluate().isNotEmpty &&
          DateTime.now().isBefore(deadline));
    });
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  }

  DocumentDataPB changedDocument() => DocumentDataPBFromTo.fromDocument(
        Document(
          root: pageNode(
            children: [
              paragraphNode(text: 'Current changes to preserve'),
            ],
          ),
        ),
      )!;

  testWidgets(
      'manual save, diff, preview and repeated restores preserve both versions',
      (tester) async {
    final service = _History()..pending = Completer<DocumentSnapshotMetaPB>();
    await mount(tester, service);
    expect(service.saves, 0);
    expect(
      find.text(
        'No saved versions yet. Save a version before making a major change.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('save-document-version')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-document-version')));
    expect(service.saves, 1);
    service.pending!.complete(
      DocumentSnapshotMetaPB(
        snapshotId: 'one',
        objectId: 'document',
        createdAt: Int64(1793840400000),
      ),
    );
    await tester.pumpAndSettle();
    final historical = service.current.writeToBuffer();
    service.current = changedDocument();
    final newer = service.current.writeToBuffer();
    await tester.tap(find.byType(ListTile).first);
    await finishComparison(tester);
    expect(find.byType(HistoryDiffView), findsOneWidget);
    expect(find.textContaining('Current changes to preserve'), findsOneWidget);
    expect(find.text('Create a copy'), findsNothing);
    ScaffoldMessenger.of(tester.element(find.byType(HistoryDiffView)))
        .clearSnackBars();
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('history-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/history-verification').create(recursive: true);
      await File('build/history-verification/desktop.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await tester.tap(find.text('Version preview'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AppFlowyEditor>(find.byType(AppFlowyEditor)).editable,
      isFalse,
    );
    expect(
      find.textContaining('Project notes', findRichText: true),
      findsWidgets,
    );
    service.pendingRestore = Completer<void>();
    await tester.tap(find.text('Restore this version'));
    await tester.pump();
    await tester.tap(find.text('Restoring…'));
    expect(service.restores, 1);
    service.pendingRestore!.complete();
    await finishComparison(tester);
    expect(service.current.writeToBuffer(), historical);
    expect(service.versions.length, 2);
    expect(service.contents['backup-1']!.writeToBuffer(), newer);
    service.pendingRestore = null;
    await tester.tap(find.byType(ListTile).first);
    await finishComparison(tester);
    await tester.tap(find.text('Restore this version'));
    await finishComparison(tester);
    expect(service.current.writeToBuffer(), newer);
    expect(service.contents['one']!.writeToBuffer(), historical);
    expect(service.versions.length, 2);
    expect(service.restores, 2);
    expect(service.saves, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeated manual save reuses version and reports already saved',
      (tester) async {
    final service = _History();
    await mount(tester, service);
    await tester.tap(find.byKey(const ValueKey('save-document-version')));
    await tester.pumpAndSettle();
    final first = service.versions.single.deepCopy();
    await tester.tap(find.byKey(const ValueKey('save-document-version')));
    await tester.pumpAndSettle();
    expect(service.saves, 2);
    expect(service.versions.single.writeToBuffer(), first.writeToBuffer());
    expect(find.text('Current content is already saved'), findsOneWidget);
  });

  testWidgets(
      'restoring between two manually saved versions adds no duplicates',
      (tester) async {
    final service = _History();
    final first = await service.save('document');
    final older = service.current.writeToBuffer();
    service.current = changedDocument();
    final second = await service.save('document');
    final newer = service.current.writeToBuffer();
    await mount(tester, service);
    await tester.tap(find.byType(ListTile).last);
    await finishComparison(tester);
    await tester.tap(find.text('Restore this version'));
    await finishComparison(tester);
    expect(service.current.writeToBuffer(), older);
    expect(service.versions.length, 2);
    await tester.tap(find.byType(ListTile).first);
    await finishComparison(tester);
    await tester.tap(find.text('Restore this version'));
    await finishComparison(tester);
    expect(service.current.writeToBuffer(), newer);
    expect(service.versions.length, 2);
    expect(
      service.versions.map((v) => v.snapshotId),
      [second.snapshotId, first.snapshotId],
    );
    expect(service.saves, 2);
  });

  testWidgets('incompatible native response explains restart and permits retry',
      (tester) async {
    final service = _History()
      ..listFailure = InvalidProtocolBufferException.invalidTag();
    await mount(tester, service);
    expect(
      find.text(
        'The version history component returned an incompatible response. Fully quit and reopen the app. If this persists, update the app.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('save-document-version')),
          )
          .onPressed,
      isNull,
    );
    service.listFailure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('save-document-version')),
          )
          .onPressed,
      isNotNull,
    );
    expect(service.saves, 0);
  });

  testWidgets('mobile save failure adds no version and permits retry',
      (tester) async {
    final service = _History()..fail = true;
    await mount(tester, service, size: const Size(390, 844));
    await tester.tap(find.byKey(const ValueKey('save-document-version')));
    await tester.pumpAndSettle();
    expect(service.versions, isEmpty);
    service.fail = false;
    await tester.tap(find.byKey(const ValueKey('save-document-version')));
    await tester.pumpAndSettle();
    expect(service.saves, 2);
    expect(service.versions.length, 1);
    service.current = changedDocument();
    final before = service.current.writeToBuffer();
    await tester.tap(find.byType(ListTile).first);
    await finishComparison(tester);
    expect(find.byType(HistoryDiffView), findsOneWidget);
    service.failRestore = true;
    await tester.tap(find.text('Restore this version'));
    await tester.pumpAndSettle();
    expect(service.current.writeToBuffer(), before);
    expect(service.versions.length, 1);
    expect(find.textContaining('Cloud storage is full.'), findsOneWidget);
    ScaffoldMessenger.of(tester.element(find.byType(HistoryDiffView)))
        .clearSnackBars();
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('history-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/history-verification').create(recursive: true);
      await File('build/history-verification/mobile.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    expect(tester.takeException(), isNull);
  });
}
