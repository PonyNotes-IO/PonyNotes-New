import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/plugins/handwriting_saber/application/handwriting_saber_data_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-handwriting-saber/entities.pb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Log.shared.disableLog = true;
  const session = (userId: '1', workspaceId: 'workspace');
  List<int> doc(int width) => utf8.encode(jsonEncode({
        'pages': [
          {'id': 'page', 'width': width}
        ]
      }));

  test('a queued reversal compares against the preceding successful local save',
      () async {
    final dir = Directory.systemTemp.createTempSync('handwriting-save-');
    final started = Completer<void>();
    final release = Completer<void>();
    final submitted = <SaveHandwritingSaberPayloadPB>[];
    final base = doc(100);
    final service = HandwritingSaberDataService.forTesting(
      readRemote: (_) async => base,
      pathFor: (_) async => '${dir.path}/note.sbn2',
      readSession: () async => session,
      writeRemote: (p) async {
        submitted.add(p);
        if (submitted.length == 1) {
          started.complete();
          await release.future;
        }
        return SaveHandwritingSaberResponsePB()..localSnapshot = p.sbn2Bytes;
      },
    );
    try {
      service.acceptSnapshot('note', base);
      final first = service.saveHandwritingSaberData('note', doc(200));
      await started.future;
      final reverse = service.saveHandwritingSaberData('note', base);
      release.complete();
      expect(await first, isTrue);
      expect(await reverse, isTrue);
      expect(submitted[1].baseSbn2Bytes, doc(200));
      expect(submitted[1].sbn2Bytes, base);
      expect(await File('${dir.path}/note.sbn2').readAsBytes(), base);
      expect(File('${dir.path}/note.sbn2.pending').existsSync(), isFalse);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('failed save and offline reopen preserve the original pending base',
      () async {
    final dir = Directory.systemTemp.createTempSync('handwriting-retry-');
    final base = doc(100);
    var online = false;
    final submitted = <SaveHandwritingSaberPayloadPB>[];
    HandwritingSaberDataService create() =>
        HandwritingSaberDataService.forTesting(
          readRemote: (_) async {
            if (!online) throw StateError('offline');
            return base;
          },
          pathFor: (_) async => '${dir.path}/note.sbn2',
          readSession: () async => session,
          writeRemote: (p) async {
            submitted.add(p);
            if (!online) throw StateError('offline');
            return SaveHandwritingSaberResponsePB()
              ..localSnapshot = p.sbn2Bytes;
          },
        );
    try {
      final service = create()..acceptSnapshot('note', base);
      expect(await service.saveHandwritingSaberData('note', doc(200)), isFalse);
      final reopened = create();
      final local = await reopened.loadHandwritingSaberData('note');
      expect(jsonDecode(utf8.decode(local))['pages'][0]['width'], 200);
      online = true;
      expect(await reopened.saveHandwritingSaberData('note', doc(300)), isTrue);
      expect(submitted.last.baseSbn2Bytes, base);
      expect(submitted.last.sbn2Bytes, doc(300));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('an account or workspace switch rejects a pending save before dispatch',
      () async {
    final dir = Directory.systemTemp.createTempSync('handwriting-account-');
    var current = session;
    var submitted = false;
    final service = HandwritingSaberDataService.forTesting(
      readRemote: (_) async => doc(100),
      pathFor: (_) async => '${dir.path}/note.sbn2',
      readSession: () async => current,
      writeRemote: (p) async {
        submitted = true;
        return SaveHandwritingSaberResponsePB();
      },
    );
    try {
      await service.loadHandwritingSaberData('note');
      current = (userId: '1', workspaceId: 'another-workspace');
      expect(await service.saveHandwritingSaberData('note', doc(200)), isFalse);
      expect(submitted, isFalse);
      expect(dir.listSync(), isEmpty);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
  test('corrupt primary backup falls back without erasing the original files',
      () async {
    final dir = Directory.systemTemp.createTempSync('handwriting-corrupt-');
    final path = '${dir.path}/note.sbn2';
    File(path).writeAsStringSync('truncated json');
    File('$path.previous').writeAsBytesSync(doc(100));
    final service = HandwritingSaberDataService.forTesting(
      readRemote: (_) async => throw StateError('offline'),
      pathFor: (_) async => path,
      readSession: () async => session,
      writeRemote: (_) async => SaveHandwritingSaberResponsePB(),
    );
    try {
      final loaded = await service.loadHandwritingSaberData('note');
      expect(jsonDecode(utf8.decode(loaded))['pages'][0]['width'], 100);
      expect(File(path).readAsStringSync(), 'truncated json');
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
