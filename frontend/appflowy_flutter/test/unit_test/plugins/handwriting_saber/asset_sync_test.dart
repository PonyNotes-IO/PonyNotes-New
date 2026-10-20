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
    final original = utf8.encode(jsonEncode({
      'pages': [
        for (var i = 0; i < 2; i++)
          {
            'id': 'page$i',
            'backgroundImage': {'pdfFilePath': pdf.path, 'pdfPageIndex': i}
          },
      ]
    }));
    File(path).writeAsBytesSync(original);
    var uploads = 0;
    var failCommit = true;
    final commits = <SaveHandwritingSaberPayloadPB>[];
    final worker = HandwritingAssetSync.forTesting(
      session: () async => identity,
      upload: (bytes, name, workspace) async {
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
          userId: identity.userId);
      expect(await run(), isFalse);
      expect(uploads, 1);
      expect(File('$path.assets.pending').existsSync(), isTrue);
      failCommit = false;
      expect(await run(), isTrue);
      expect(uploads, 1);
      expect(File('$path.assets.pending').existsSync(), isFalse);
      expect(File(path).readAsBytesSync(), original);
      final result = jsonDecode(utf8.decode(commits.last.sbn2Bytes));
      expect(result['pages'][0]['backgroundImage']['pdfUrl'],
          result['pages'][1]['backgroundImage']['pdfUrl']);
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
    File(path).writeAsStringSync(jsonEncode({
      'pages': [
        {
          'images': [
            {
              'id': 'image',
              'imageBytes': [1, 2, 3]
            }
          ]
        }
      ]
    }));
    var session = identity;
    var committed = false;
    final worker = HandwritingAssetSync.forTesting(
      session: () async => session,
      upload: (_, __, ___) async {
        session = (userId: '1', workspaceId: 'other');
        return 'https://cloud/image';
      },
      commit: (_) async {
        committed = true;
      },
    );
    try {
      expect(
          await worker.sync(
              viewId: 'note',
              path: path,
              workspaceId: identity.workspaceId,
              userId: identity.userId),
          isFalse);
      expect(committed, isFalse);
      expect(File(path).existsSync(), isTrue);
      expect(File('$path.assets.pending').existsSync(), isTrue);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
