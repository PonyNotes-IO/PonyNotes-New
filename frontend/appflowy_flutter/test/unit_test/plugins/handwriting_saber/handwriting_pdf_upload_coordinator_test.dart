import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:appflowy/plugins/handwriting_saber/application/handwriting_pdf_upload_coordinator.dart';

class _FakeBackend implements HandwritingPdfUploadBackend {
  int uploadCount = 0;
  final Completer<String?> started = Completer<String?>();
  Completer<String?> result = Completer<String?>();

  @override
  Future<String?> uploadAndWait({
    required String localPdfPath,
    required String parentDir,
  }) {
    uploadCount += 1;
    if (!started.isCompleted) {
      started.complete(localPdfPath);
    }
    return result.future;
  }
}

void main() {
  test('concurrent calls for one PDF share one upload future', () async {
    final backend = _FakeBackend();
    final coordinator = HandwritingPdfUploadCoordinator(backend: backend);

    final first = coordinator.upload(
      workspaceId: 'workspace-a',
      parentDir: 'page-a',
      localPdfPath: 'C:/notes/book.pdf',
    );
    final second = coordinator.upload(
      workspaceId: 'workspace-a',
      parentDir: 'page-a',
      localPdfPath: 'C:/notes/book.pdf',
    );

    await backend.started.future;
    expect(backend.uploadCount, 1);

    backend.result.complete('https://cloud/book.pdf');
    expect(await first, 'https://cloud/book.pdf');
    expect(await second, 'https://cloud/book.pdf');
  });

  test('failed upload is shared and does not automatically retry', () async {
    final backend = _FakeBackend();
    final coordinator = HandwritingPdfUploadCoordinator(backend: backend);

    final first = coordinator.upload(
      workspaceId: 'workspace-a',
      parentDir: 'page-a',
      localPdfPath: 'book.pdf',
    );
    final second = coordinator.upload(
      workspaceId: 'workspace-a',
      parentDir: 'page-a',
      localPdfPath: 'book.pdf',
    );

    await backend.started.future;
    backend.result.complete(null);

    expect(await first, isNull);
    expect(await second, isNull);
    expect(backend.uploadCount, 1);
  });

  test(
      'in-flight state is removed after completion so explicit retry can start',
      () async {
    final backend = _FakeBackend();
    final coordinator = HandwritingPdfUploadCoordinator(backend: backend);

    final first = coordinator.upload(
      workspaceId: 'workspace-a',
      parentDir: 'page-a',
      localPdfPath: 'book.pdf',
    );
    await backend.started.future;
    backend.result.complete(null);
    expect(await first, isNull);

    backend.result = Completer<String?>();
    final retry = coordinator.upload(
      workspaceId: 'workspace-a',
      parentDir: 'page-a',
      localPdfPath: 'book.pdf',
    );
    backend.result.complete('https://cloud/book.pdf');
    expect(await retry, 'https://cloud/book.pdf');
    expect(backend.uploadCount, 2);
  });
}
