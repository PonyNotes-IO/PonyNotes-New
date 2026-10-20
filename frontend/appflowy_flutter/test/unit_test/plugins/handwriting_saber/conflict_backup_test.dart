import 'package:appflowy/plugins/handwriting_saber/application/handwriting_saber_data_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const filePath = '/tmp/notes/abc.sbn2';

  test('conflictFilePath returns null when remote matches local', () {
    final path = HandwritingSaberDataService.conflictFilePath(
      filePath: filePath,
      remoteBytes: const [1, 2, 3],
      localBytes: const [1, 2, 3],
      timestampMs: 1000,
    );
    expect(path, isNull);
  });

  test('conflictFilePath returns null when remote is empty', () {
    final path = HandwritingSaberDataService.conflictFilePath(
      filePath: filePath,
      remoteBytes: const [],
      localBytes: const [1, 2, 3],
      timestampMs: 1000,
    );
    expect(path, isNull);
  });

  test('conflictFilePath keeps the remote copy when content differs', () {
    final path = HandwritingSaberDataService.conflictFilePath(
      filePath: filePath,
      remoteBytes: const [9, 9],
      localBytes: const [1, 2, 3],
      timestampMs: 1000,
    );
    expect(path, '/tmp/notes/abc.conflict.1000.sbn2');
  });
}
