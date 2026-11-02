import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/plugins/import_page/file_upload_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('counts consumed body bytes and resets with a fresh retry request',
      () async {
    final bytes = Uint8List.fromList(List.generate(150000, (i) => i % 256));
    final progress = <(int, int)>[];
    for (var attempt = 0; attempt < 2; attempt++) {
      final request = FileUploadRequest(
        'PUT',
        Uri.parse('https://cloud/pdf'),
        bytes,
        onProgress: (sent, total) => progress.add((sent, total)),
      );
      final body = request.finalize();
      expect(progress.length, attempt * 4);
      expect(request.contentLength, bytes.length);
      expect(await body.toBytes(), bytes);
      expect(request.finalize, throwsStateError);
    }
    expect(
      progress.map((p) => p.$1),
      [0, 65536, 131072, 150000, 0, 65536, 131072, 150000],
    );
    expect(progress.every((p) => p.$2 == bytes.length), isTrue);
  });

  test('cancelled request never reports unsent bytes as complete', () async {
    final progress = <int>[];
    final request = FileUploadRequest(
      'PUT',
      Uri.parse('https://cloud/pdf'),
      Uint8List(150000),
      onProgress: (sent, _) => progress.add(sent),
    );
    await request.finalize().take(1).drain<void>();
    expect(progress, [0]);
  });

  test('100 percent sent still waits for the server response', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final received = Completer<int>();
    final respond = Completer<void>();
    final serving = server.first.then((request) async {
      received.complete(
        await request.fold<int>(0, (total, chunk) => total + chunk.length),
      );
      await respond.future;
      request.response.write('{"code":0}');
      await request.response.close();
    });
    final sent = <int>[];
    var confirmed = false;
    final bytes = Uint8List(150000);
    final upload = FileUploadRequest(
      'PUT',
      Uri.parse('http://127.0.0.1:${server.port}/pdf'),
      bytes,
      onProgress: (count, _) => sent.add(count),
    ).send().then((response) async {
      confirmed = true;
      return response.stream.transform(utf8.decoder).join();
    });
    expect(await received.future, bytes.length);
    expect(sent.last, bytes.length);
    expect(confirmed, isFalse);
    respond.complete();
    expect(await upload, '{"code":0}');
    await serving;
  });
}
