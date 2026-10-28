import 'dart:async';

import 'package:appflowy/plugins/handwriting_saber/application/handwriting_asset_sync.dart';
import 'package:appflowy/plugins/handwriting_saber/presentation/dialogs/pdf_upload_dialog.dart';
import 'package:appflowy_backend/log.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_material_app.dart';

void main() {
  setUpAll(() async {
    Log.shared.disableLog = true;
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });

  Future<void> openDialog(
    WidgetTester tester,
    Future<void> Function(ValueChanged<HandwritingUploadProgress>) upload,
  ) async {
    await tester.pumpWidget(
      WidgetTestApp(
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                PdfUploadDialog.show(context: context, upload: upload),
            child: const Text('Import PDF'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import PDF'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('blocks dismissal, reports real progress, and waits after 100%',
      (tester) async {
    final done = Completer<void>();
    late ValueChanged<HandwritingUploadProgress> report;
    var runs = 0;
    await openDialog(tester, (onProgress) {
      runs++;
      report = onProgress;
      return done.future;
    });
    expect(
      find.text('File is uploading. Please do not quit the app'),
      findsOneWidget,
    );
    report(
      const HandwritingUploadProgress(
        sentBytes: 524288,
        totalBytes: 1048576,
      ),
    );
    await tester.pump();
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .value,
      0.5,
    );
    expect(find.text('50% · 0.50 / 1.00 MiB'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .value,
      0.5,
    );

    await tester.tapAt(const Offset(5, 5));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PdfUploadDialog), findsOneWidget);
    expect(runs, 1);

    report(
      const HandwritingUploadProgress(
        sentBytes: 1048576,
        totalBytes: 1048576,
      ),
    );
    await tester.pump();
    expect(
      find.text('File sent. Waiting for server confirmation…'),
      findsOneWidget,
    );
    expect(find.byType(PdfUploadDialog), findsOneWidget);
    report(const HandwritingUploadProgress(isSaving: true));
    await tester.pump();
    expect(find.text('Saving the PDF sync information…'), findsOneWidget);
    expect(find.byType(PdfUploadDialog), findsOneWidget);
    done.complete();
    await tester.pumpAndSettle();
    expect(find.byType(PdfUploadDialog), findsNothing);
  });

  testWidgets('failure remains blocked, retry succeeds and closes the dialog',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final done = Completer<void>();
    var runs = 0;
    await openDialog(tester, (_) {
      runs++;
      if (runs == 1) throw StateError('offline');
      return done.future;
    });
    expect(find.text('Upload failed'), findsOneWidget);
    expect(find.textContaining('Your local PDF is retained.'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PdfUploadDialog), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(runs, 2);
    expect(find.text('Upload failed'), findsNothing);
    expect(find.byType(PdfUploadDialog), findsOneWidget);
    done.complete();
    await tester.pumpAndSettle();
    expect(find.byType(PdfUploadDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
