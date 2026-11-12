import 'dart:io';
import 'dart:convert';
import 'package:appflowy/features/agent/application/agent_artifacts.dart';
import 'package:appflowy/features/agent/application/agent_service.dart';
import 'package:appflowy/features/agent/application/agent_internal_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporary;
  late AgentArtifacts artifacts;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('agent-artifact-test-');
    artifacts = AgentArtifacts(directory: () async => temporary);
  });
  tearDown(() async => temporary.delete(recursive: true));

  test(
      'generated names cannot escape storage and accounts keep separate copies',
      () async {
    Future<File> save(String identity) => artifacts.save(
          identity: identity,
          document: '../document',
          message: '../message',
          artifact: {
            'index': 2,
            'file_name': '../../report.pdf',
            'file_size': 3,
          },
          independent: true,
          download: (file) async {
            await file.writeAsBytes([1, 2, 3]);
          },
        );
    final own = await save('account-one');
    expect((await artifacts.list('account-one')).single.independent, true);
    final other = await save('account-two');
    expect(p.isWithin(temporary.path, own.path), true);
    expect(p.extension(own.path), '.pdf');
    expect(own.path, isNot(other.path));
    var downloaded = false;
    await artifacts.save(
      identity: 'account-one',
      document: '../document',
      message: '../message',
      artifact: {'index': 2, 'file_name': '../../report.pdf', 'file_size': 3},
      download: (_) async {
        downloaded = true;
      },
    );
    expect(downloaded, false);
  });

  test('an incomplete download never becomes an output file', () async {
    await expectLater(
      artifacts.save(
        identity: 'one',
        document: 'doc',
        message: 'message',
        artifact: {'index': 0, 'file_name': 'report.txt', 'file_size': 10},
        download: (file) async {
          await file.writeAsString('partial');
        },
      ),
      throwsStateError,
    );
    expect(
      await temporary
          .list(recursive: true)
          .where((entry) => entry is File)
          .toList(),
      isEmpty,
    );
  });

  test('all artifacts survive restart without mixing accounts or workspaces',
      () async {
    for (final identity in [
      'cloud|one|workspace',
      'cloud|two|workspace',
      'cloud|one|other-workspace',
    ]) {
      await artifacts.save(
        identity: identity,
        document: 'document',
        message: 'answer',
        documentName: '会议记录',
        artifact: {'index': 0, 'file_name': '行动清单.txt', 'file_size': 4},
        download: (file) async {
          await file.writeAsString('done');
        },
      );
    }
    final restarted = AgentArtifacts(directory: () async => temporary);
    final entries = await restarted.list('cloud|one|workspace');
    expect(entries.length, 1);
    expect(entries.single.name, '行动清单.txt');
    expect(entries.single.documentName, '会议记录');
    expect(await entries.single.file.readAsString(), 'done');
    final folder = await restarted.folder('cloud|one|workspace', 'document');
    await File(p.join(folder.path, 'corrupt.artifact.json'))
        .writeAsString('broken');
    await File(p.join(folder.path, 'escape.artifact.json')).writeAsString(
      jsonEncode({
        'file': '../outside.txt',
        'document': 'document',
        'message': 'answer',
        'index': 4,
      }),
    );
    expect((await restarted.list('cloud|one|workspace')).length, 1);
    expect(await restarted.list('no-such-account'), isEmpty);
    await entries.single.file.delete();
    expect(await restarted.list('cloud|one|workspace'), isEmpty);
  });

  const account = AgentCloudAccount(
    baseUrl: 'https://cloud.test',
    accessToken: 'login',
    userId: 'one',
  );
  test('cloud sync streams the original bytes and reports server quota errors',
      () async {
    final file = File(p.join(temporary.path, 'output.pdf'));
    await file.writeAsBytes([0, 1, 2, 255]);
    var calls = 0;
    final service = AgentService(
      account: () async => account,
      client: MockClient.streaming((request, body) async {
        expect(request.headers['Authorization'], 'Bearer login');
        expect(
          request.url.path,
          '/api/file_storage/workspace/blob/report.pdf',
        );
        expect(await body.toBytes(), [0, 1, 2, 255]);
        return http.StreamedResponse(
          Stream.value(
            calls++ == 0
                ? '{"code":0}'.codeUnits
                : '{"code":1028,"message":"quota exceeded"}'.codeUnits,
          ),
          200,
        );
      }),
    );
    expect(
      await service.uploadArtifact(
        'https://cloud.test|one|workspace',
        'workspace',
        file,
        'report.pdf',
      ),
      'https://cloud.test/api/file_storage/workspace/blob/report.pdf',
    );
    await expectLater(
      service.uploadArtifact(
        'https://cloud.test|one|workspace',
        'workspace',
        file,
        'report.pdf',
      ),
      throwsStateError,
    );
    await expectLater(
      service.uploadArtifact(
        'https://cloud.test|other|workspace',
        'workspace',
        file,
        'report.pdf',
      ),
      throwsStateError,
    );
    expect(calls, 2);
  });

  test('a forged cloud link cannot receive the login token', () async {
    final service = AgentService(
      account: () async => account,
      client: MockClient((_) async => throw StateError('must not connect')),
    );
    final file = File(p.join(temporary.path, 'output'));
    for (final url in [
      'https://attacker.test/api/file_storage/workspace/blob/a',
      'https://cloud.test/api/file_storage/other/blob/a',
    ]) {
      await expectLater(
        service.downloadCloudArtifact(
          'https://cloud.test|one|workspace',
          'workspace',
          url,
          file,
        ),
        throwsStateError,
      );
    }
    expect(await file.exists(), false);
  });
}
