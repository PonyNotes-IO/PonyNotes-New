import 'dart:async';

import 'package:appflowy/plugins/import_page/obsidian_import_dialog.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FolderPicker extends FilePickerService {
  final result = Completer<String?>();

  @override
  Future<String?> getDirectoryPath({String? title}) => result.future;
}

void main() {
  testWidgets('folder picker keeps the dialog open until selection ends', (
    tester,
  ) async {
    final picker = _FolderPicker();
    getIt.pushNewScope();
    addTearDown(getIt.popScope);
    getIt.registerSingleton<FilePickerService>(picker);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<int>(
                context: context,
                barrierDismissible: false,
                builder: (_) => const ObsidianImportDialog(),
              ),
              child: const Text('Open import'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open import'));
    await tester.pumpAndSettle();

    final choose = find.widgetWithText(TextButton, 'Choose a vault folder');
    final cancel = find.widgetWithText(OutlinedButton, 'Cancel');
    await tester.tap(choose);
    await tester.pump();

    expect(tester.widget<TextButton>(choose).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(cancel).onPressed, isNull);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(ObsidianImportDialog), findsOneWidget);

    picker.result.complete(null);
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(choose).onPressed, isNotNull);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(find.byType(ObsidianImportDialog), findsNothing);
  });
}
