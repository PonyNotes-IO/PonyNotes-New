import 'dart:io';

import 'package:appflowy/plugins/import_page/notion_import_dialog.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory fixtureDir;
  late File zip;

  setUp(() {
    fixtureDir = Directory.systemTemp.createTempSync('notion-import-test-');
    zip = File('${fixtureDir.path}/export.ZIP')..createSync();
  });
  tearDown(() => fixtureDir.deleteSync(recursive: true));

  Future<void> openDialog(
    WidgetTester tester, {
    required Future<String?> Function() pickZipPath,
    required ValueChanged<String?> onResult,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(platform: TargetPlatform.windows),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final result = await showDialog<String>(
                  context: context,
                  builder: (_) => NotionImportDialog(pickZipPath: pickZipPath),
                );
                onResult(result);
              },
              child: const Text('Open import'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open import'));
    await tester.pumpAndSettle();
  }

  Future<void> finishFileCheck(WidgetTester tester) async {
    // Let dart:io finish its file check outside the test's fake clock.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('a canceled picker keeps the dialog open and can be retried', (
    tester,
  ) async {
    var picks = 0;
    String? result;
    await openDialog(
      tester,
      pickZipPath: () async => ++picks == 1 ? null : zip.path,
      onResult: (path) => result = path,
    );
    final choose = find.textContaining('Choose a file', findRichText: true);
    await tester.tap(choose);
    await tester.pumpAndSettle();
    expect(find.byType(NotionImportDialog), findsOneWidget);

    await tester.runAsync(() => tester.tap(choose));
    await finishFileCheck(tester);
    expect(result, zip.path);
    expect(find.byType(NotionImportDialog), findsNothing);
  });

  testWidgets(
      'invalid drops stay in the dialog and a valid ZIP returns its path', (
    tester,
  ) async {
    String? result;
    await openDialog(
      tester,
      pickZipPath: () async => null,
      onResult: (path) => result = path,
    );
    final target = tester.widget<DropTarget>(find.byType(DropTarget));
    void drop(List<String> files) => target.onDragDone!(
          DropDoneDetails(
            files: files.map(DropItemFile.new).toList(),
            globalPosition: Offset.zero,
            localPosition: Offset.zero,
          ),
        );

    drop(['readme.md']);
    await tester.pumpAndSettle();
    expect(find.text('Choose a valid ZIP file.'), findsOneWidget);
    expect(result, isNull);

    drop([zip.path, zip.path]);
    await tester.pumpAndSettle();
    expect(find.text('Drop one ZIP file at a time.'), findsOneWidget);

    await tester.runAsync(() async => drop([zip.path]));
    await finishFileCheck(tester);
    expect(result, zip.path);
    expect(find.byType(NotionImportDialog), findsNothing);
  });
}
