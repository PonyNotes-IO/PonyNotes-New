import 'dart:async';
import 'dart:io';

import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_block.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_upload_menu.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/file_storage_task.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-storage/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:cross_file/cross_file.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_material_app.dart';

const _url = 'https://example.test/api/file_storage/w/v1/blob/d/file.mp4';
const _quota =
    'The workspace owner doesn’t have enough cloud storage. The file wasn’t uploaded.';

class _TestStorage extends FileStorageService {
  FlowyError? failure;
  bool finished = false;
  bool uploadFailed = false;
  late AutoRemoveNotifier<FileProgress> notifier;

  @override
  AutoRemoveNotifier<FileProgress> onFileProgress({required String fileUrl}) =>
      notifier = super.onFileProgress(fileUrl: fileUrl);

  @override
  Future<FlowyResult<FileStatePB, FlowyError>> getFileState(String url) async {
    final error = failure;
    return FlowyResult.success(
      FileStatePB(
        isFinish: finished,
        errorCode: error?.code.value,
        errorMessage: error?.msg,
        uploadFailed: uploadFailed,
      ),
    );
  }
}

class _LocalDocumentBloc extends Mock implements DocumentBloc {
  @override
  bool get isLocalMode => true;

  @override
  DocumentState get state => DocumentState.initial();
}

class _PreparingStorage extends ApplicationDataStorage {
  final path = Completer<String>();

  @override
  Future<String> getPath() => path.future;
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  for (final errorCode in [
    null,
    ErrorCode.FileStorageLimitExceeded,
    ErrorCode.RecordNotFound,
  ]) {
    testWidgets(
        'selects a file in place for ${errorCode?.name ?? 'an empty block'}',
        (tester) async {
      final directory =
          Directory.systemTemp.createTempSync('document-attachment');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File(p.join(directory.path, 'large-video.mp4'))
        ..writeAsStringSync('video');
      final storage = _PreparingStorage();
      getIt.registerSingleton<ApplicationDataStorage>(storage);
      addTearDown(() => getIt.unregister<ApplicationDataStorage>());
      final previousUrl = errorCode == null ? '' : _url;
      if (errorCode != null) {
        final cloudStorage = _TestStorage()
          ..failure = FlowyError(code: errorCode, msg: 'Upload failed');
        getIt.registerSingleton<FileStorageService>(cloudStorage);
        addTearDown(() async {
          await cloudStorage.dispose();
          await getIt.unregister<FileStorageService>();
        });
      }
      final node = errorCode == null
          ? fileNode(url: '')
          : fileNode(
              url: previousUrl,
              type: FileUrlType.cloud,
              name: 'old-video.mp4',
            );
      final editor = EditorState.blank()
        ..editorStyle = const EditorStyle.desktop();
      await editor.apply(editor.transaction..insertNode([0], node));
      final originalBlock = editor.getNodeAtPath([0])!;
      addTearDown(editor.dispose);
      final key = GlobalKey<FileBlockComponentState>();
      await tester.pumpWidget(
        WidgetTestApp(
          child: MultiProvider(
            providers: [
              Provider<EditorState>.value(value: editor),
              Provider<DocumentBloc>.value(value: _LocalDocumentBloc()),
            ],
            child: SizedBox(
              width: 390,
              child: FileBlockComponent(
                key: key,
                node: editor.getNodeAtPath([0])!,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      if (errorCode != null) {
        await tester.tap(find.text('old-video.mp4'));
        await tester.pumpAndSettle();
        expect(find.byType(FileUploadMenu), findsOneWidget);
        key.currentState!.controller.close();
        await tester.pumpAndSettle();
        expect(originalBlock.attributes[FileBlockKeys.url], previousUrl);
      }

      late Future<void> upload;
      await tester.runAsync(() async {
        upload = key.currentState!.insertFileFromLocal([XFile(file.path)]);
      });
      await tester.pump();

      final ring = find.byType(CircularProgressIndicator);
      expect(find.text('large-video.mp4'), findsOneWidget);
      expect(find.text('Preparing file…'), findsOneWidget);
      expect(tester.widget<CircularProgressIndicator>(ring).value, isNull);
      expect(originalBlock.attributes[FileBlockKeys.url], previousUrl);

      await tester.runAsync(() async {
        storage.path.complete(directory.path);
        await upload;
      });
      await tester.pumpAndSettle();
      expect(ring, findsNothing);
      expect(find.text('large-video.mp4'), findsOneWidget);
      expect(find.text('Preparing file…'), findsNothing);
      final updated = editor.getNodeAtPath([0])!;
      expect(updated.id, originalBlock.id);
      expect(
        File(updated.attributes[FileBlockKeys.url] as String).existsSync(),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final succeeded in [false, true]) {
    testWidgets(
        'settles new pending attachment on ${succeeded ? 'success' : 'terminal failure'}',
        (tester) async {
      final storage = _TestStorage();
      getIt.registerSingleton<FileStorageService>(storage);
      addTearDown(() async {
        await storage.dispose();
        await getIt.unregister<FileStorageService>();
      });
      final editor = EditorState.blank()
        ..editorStyle = const EditorStyle.desktop();
      addTearDown(editor.dispose);
      await editor.apply(
        editor.transaction
          ..insertNode(
            [0],
            fileNode(
              url: _url,
              type: FileUrlType.cloud,
              name: 'pending.mp4',
              pendingUpload: true,
            ),
          ),
      );
      final pending = editor.getNodeAtPath([0])!;
      await tester.pumpWidget(
        WidgetTestApp(
          child: Provider<EditorState>.value(
            value: editor,
            child: FileBlockComponent(node: pending),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('pending.mp4'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // A different device seeing an unavailable cloud object is not evidence
      // that this upload failed; it may still be transferring elsewhere.
      storage.failure = FlowyError(
        code: ErrorCode.RecordNotFound,
        msg: 'Missing cloud object',
      );
      await storage.refreshFileProgress(storage.notifier);
      await tester.pumpAndSettle();
      expect(editor.getNodeAtPath([0])?.id, pending.id);
      expect(find.text('Pending sync'), findsOneWidget);

      storage.failure = succeeded
          ? null
          : FlowyError(
              code: ErrorCode.FileStorageLimitExceeded,
              msg: 'Total storage limit exceeded',
            );
      storage.uploadFailed = !succeeded;
      storage.finished = succeeded;
      await storage.refreshFileProgress(storage.notifier);
      await tester.pumpAndSettle();
      final current = editor.getNodeAtPath([0]);
      if (succeeded) {
        expect(current?.id, pending.id);
        expect(current?.attributes[FileBlockKeys.pendingUpload], isNot(true));
        expect(find.byType(CircularProgressIndicator), findsNothing);
      } else {
        expect(current?.id, isNot(pending.id));
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('shows upload progress and keeps quota failure after reopening',
      (tester) async {
    final storage = getIt.registerSingleton<FileStorageService>(_TestStorage())
        as _TestStorage;
    addTearDown(() async {
      await storage.dispose();
      await getIt.unregister<FileStorageService>();
    });
    final node =
        fileNode(url: _url, type: FileUrlType.cloud, name: 'video.mp4');
    final editor = EditorState.blank()
      ..editorStyle = const EditorStyle.desktop();
    addTearDown(editor.dispose);

    Future<void> open() async {
      await tester.pumpWidget(
        WidgetTestApp(
          child: Provider<EditorState>.value(
            value: editor,
            child: SizedBox(
              width: 390,
              child: FileBlockComponent(node: node),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await open();
    final ring = find.byType(CircularProgressIndicator);
    expect(find.text('Pending sync'), findsOneWidget);
    expect(tester.widget<CircularProgressIndicator>(ring).value, 0);

    storage.notifier.value = FileProgress(fileUrl: _url, progress: 0.4);
    await tester.pump();
    expect(tester.widget<CircularProgressIndicator>(ring).value, 0.4);
    expect(find.text('Uploading'), findsOneWidget);

    storage.notifier.value = FileProgress(
      fileUrl: _url,
      progress: 0,
      errorCode: ErrorCode.NetworkError.value,
    );
    await tester.pump();
    expect(find.text('Pending sync'), findsOneWidget);
    expect(ring, findsNothing);

    storage.notifier.value = FileProgress(fileUrl: _url, progress: 0.6);
    await tester.pump();
    expect(tester.widget<CircularProgressIndicator>(ring).value, 0.6);

    storage.failure = FlowyError(
      code: ErrorCode.FileStorageLimitExceeded,
      msg: 'Total storage limit exceeded',
    );
    storage.uploadFailed = true;
    await storage.refreshFileProgress(storage.notifier);
    await tester.pumpAndSettle();
    expect(find.text('video.mp4'), findsOneWidget);
    expect(find.textContaining(_quota), findsOneWidget);
    expect(find.text('Pending sync'), findsNothing);
    expect(ring, findsNothing);
    await tester.pumpWidget(const SizedBox());
    await open();
    expect(find.textContaining(_quota), findsOneWidget);
    expect(find.textContaining('3 GB'), findsNothing);

    expect(
      uploadFailureMessage(
        ErrorCode.SingleUploadLimitExceeded.value,
        'File size 314572801 bytes exceeds single upload limit 314572800 bytes.',
      ),
      contains('300 MB'),
    );
    expect(
      uploadFailureMessage(
        ErrorCode.PlanLimitExceeded.value,
        'File size 301.0MB exceeds single upload limit 300MB for mfb plan.',
      ),
      contains('300 MB'),
    );
    expect(
      uploadFailureMessage(
        ErrorCode.NotEnoughPermissions.value,
        'Storage error',
      ),
      contains('permission'),
    );

    await tester.pumpWidget(const SizedBox());
    storage.failure = null;
    storage.uploadFailed = false;
    storage.finished = true;
    await open();
    expect(find.text('video.mp4'), findsOneWidget);
    expect(find.textContaining(_quota), findsNothing);
    expect(ring, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
