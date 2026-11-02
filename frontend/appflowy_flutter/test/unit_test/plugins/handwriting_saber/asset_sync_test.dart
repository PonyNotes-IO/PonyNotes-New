import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/plugins/handwriting_saber/application/handwriting_asset_sync.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-handwriting-saber/entities.pb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Log.shared.disableLog = true;
  const identity = (userId: '1', workspaceId: 'workspace');
  test(
      'upload results survive failed reference commit and shared PDFs upload once',
      () async {
    final dir = Directory.systemTemp.createTempSync('handwriting-assets-');
    final path = '${dir.path}/note.sbn2';
    final pdf = File('${dir.path}/original.pdf')..writeAsStringSync('%PDF-1.7');
    final original = utf8.encode(
      jsonEncode({
        'pages': [
          for (var i = 0; i < 2; i++)
            {
              'id': 'page$i',
              'backgroundImage': {'pdfFilePath': pdf.path, 'pdfPageIndex': i},
            },
        ],
      }),
    );
    File(path).writeAsBytesSync(original);
    var uploads = 0;
    var failCommit = true;
    final commits = <SaveHandwritingSaberPayloadPB>[];
    final worker = HandwritingAssetSync.forTesting(
      session: () async => identity,
      upload: (bytes, name, workspace, onProgress) async {
        uploads++;
        expect(workspace, identity.workspaceId);
        return 'https://cloud/$name';
      },
      commit: (p) async {
        commits.add(p);
        if (failCommit) throw StateError('offline');
      },
    );
    try {
      Future<bool> run() => worker.sync(
            viewId: 'note',
            path: path,
            workspaceId: identity.workspaceId,
            userId: identity.userId,
          );
      await expectLater(run(), throwsStateError);
      expect(uploads, 1);
      expect(File('$path.assets.pending').existsSync(), isTrue);
      failCommit = false;
      expect(await run(), isTrue);
      expect(uploads, 1);
      expect(File('$path.assets.pending').existsSync(), isFalse);
      expect(File(path).readAsBytesSync(), original);
      final result = jsonDecode(utf8.decode(commits.last.sbn2Bytes));
      expect(
        result['pages'][0]['backgroundImage']['pdfUrl'],
        result['pages'][1]['backgroundImage']['pdfUrl'],
      );
      expect(commits.last.userId, identity.userId);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test(
      'a workspace switch during upload retains originals and cannot commit references',
      () async {
    final dir = Directory.systemTemp.createTempSync('handwriting-switch-');
    final path = '${dir.path}/note.sbn2';
    File(path).writeAsStringSync(
      jsonEncode({
        'pages': [
          {
            'images': [
              {
                'id': 'image',
                'imageBytes': [1, 2, 3],
              }
            ],
          }
        ],
      }),
    );
    var session = identity;
    var committed = false;
    final worker = HandwritingAssetSync.forTesting(
      session: () async => session,
      upload: (_, __, ___, ____) async {
        session = (userId: '1', workspaceId: 'other');
        return 'https://cloud/image';
      },
      commit: (_) async {
        committed = true;
      },
    );
    try {
      await expectLater(
        worker.sync(
          viewId: 'note',
          path: path,
          workspaceId: identity.workspaceId,
          userId: identity.userId,
        ),
        throwsStateError,
      );
      expect(committed, isFalse);
      expect(File(path).existsSync(), isTrue);
      expect(File('$path.assets.pending').existsSync(), isTrue);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('late observers share byte progress and wait for reference commit',
      () async {
    final dir = Directory.systemTemp.createTempSync('handwriting-progress-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/note.sbn2';
    final pdf = File('${dir.path}/original.pdf')..writeAsStringSync('%PDF-1.7');
    File(path).writeAsStringSync(
      jsonEncode({
        'pages': [
          for (var i = 0; i < 300; i++)
            {
              'id': 'page$i',
              'backgroundImage': {'pdfFilePath': pdf.path, 'pdfPageIndex': i},
            },
        ],
      }),
    );
    final uploadStarted = Completer<void>();
    final uploadResponse = Completer<String>();
    final commitStarted = Completer<void>();
    final commitDone = Completer<void>();
    var uploads = 0;
    final worker = HandwritingAssetSync.forTesting(
      session: () async => identity,
      upload: (bytes, name, workspace, progress) async {
        uploads++;
        progress(4, bytes.length);
        uploadStarted.complete();
        final url = await uploadResponse.future;
        progress(bytes.length, bytes.length);
        return url;
      },
      commit: (_) async {
        if (!commitStarted.isCompleted) commitStarted.complete();
        await commitDone.future;
      },
    );
    final firstProgress = <HandwritingUploadProgress>[];
    var finished = false;
    final first = worker
        .sync(
          viewId: 'note',
          path: path,
          workspaceId: identity.workspaceId,
          userId: identity.userId,
          onProgress: firstProgress.add,
        )
        .then((_) => finished = true);
    await uploadStarted.future;
    final lateProgress = <HandwritingUploadProgress>[];
    final second = worker.sync(
      viewId: 'note',
      path: path,
      workspaceId: identity.workspaceId,
      userId: identity.userId,
      onProgress: lateProgress.add,
    );
    expect(lateProgress.single.sentBytes, 4);
    expect(lateProgress.single.totalBytes, pdf.lengthSync());
    expect(finished, isFalse);
    uploadResponse.complete('https://cloud/original.pdf');
    await commitStarted.future;
    expect(firstProgress.any((p) => p.fraction == 1), isTrue);
    expect(lateProgress.last.isSaving, isTrue);
    expect(finished, isFalse);
    expect(File('$path.assets.pending').existsSync(), isTrue);
    commitDone.complete();
    await Future.wait([first, second]);
    expect(finished, isTrue);
    expect(uploads, 1);
    expect(File('$path.assets.pending').existsSync(), isFalse);
  });

  test(
      'failed PDF upload reports failure once and retry preserves the original',
      () async {
    final dir = Directory.systemTemp.createTempSync('handwriting-retry-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/note.sbn2';
    final pdf = File('${dir.path}/original.pdf')..writeAsStringSync('%PDF-1.7');
    final original = jsonEncode({
      'pages': [
        for (var i = 0; i < 300; i++)
          {
            'id': 'page$i',
            'backgroundImage': {'pdfFilePath': pdf.path, 'pdfPageIndex': i},
          },
      ],
    });
    File(path).writeAsStringSync(original);
    var failUpload = true;
    var uploads = 0;
    var commits = 0;
    final worker = HandwritingAssetSync.forTesting(
      session: () async => identity,
      upload: (bytes, name, workspace, progress) async {
        uploads++;
        if (failUpload) throw StateError('offline');
        return 'https://cloud/original.pdf';
      },
      commit: (_) async {
        commits++;
      },
    );
    Future<bool> run() => worker.sync(
          viewId: 'note',
          path: path,
          workspaceId: identity.workspaceId,
          userId: identity.userId,
        );
    await expectLater(run(), throwsStateError);
    expect(uploads, 1);
    expect(commits, 0);
    expect(File('$path.assets.pending').existsSync(), isTrue);
    expect(File(path).readAsStringSync(), original);
    expect(pdf.readAsStringSync(), '%PDF-1.7');
    failUpload = false;
    expect(await run(), isTrue);
    expect(uploads, 2);
    expect(commits, 1);
    expect(File('$path.assets.pending').existsSync(), isFalse);
  });
  test('a missing PDF retains the journal without blocking other assets',
      () async {
    final dir = Directory.systemTemp.createTempSync('handwriting-partial-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/note.sbn2';
    final pdf = File('${dir.path}/original.pdf');
    File(path).writeAsStringSync(
      jsonEncode({
        'pages': [
          {
            'backgroundImage': {'pdfFilePath': pdf.path},
          },
          {
            'images': [
              {
                'imageBytes': [1, 2, 3],
              },
            ],
          },
        ],
      }),
    );
    var uploads = 0;
    final commits = <SaveHandwritingSaberPayloadPB>[];
    final worker = HandwritingAssetSync.forTesting(
      session: () async => identity,
      upload: (_, name, __, ___) async {
        uploads++;
        return 'https://cloud/$name';
      },
      commit: (payload) async {
        commits.add(payload);
      },
    );
    Future<bool> run() => worker.sync(
          viewId: 'note',
          path: path,
          workspaceId: identity.workspaceId,
          userId: identity.userId,
        );
    await expectLater(run(), throwsStateError);
    expect(uploads, 1);
    expect(commits.length, 1);
    final partial = jsonDecode(utf8.decode(commits.single.sbn2Bytes));
    expect(
      partial['pages'][1]['images'][0]['imageUrl'],
      startsWith('https://cloud/'),
    );
    expect(File('$path.assets.pending').existsSync(), isTrue);
    pdf.writeAsStringSync('%PDF-1.7');
    expect(await run(), isTrue);
    expect(uploads, 2);
    expect(File('$path.assets.pending').existsSync(), isFalse);
  });
}
