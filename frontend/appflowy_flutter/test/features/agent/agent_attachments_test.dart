import 'dart:typed_data';
import 'package:appflowy/features/agent/application/agent_attachments.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all advertised document, image and source formats can be selected', () {
    for (final ext in agentAttachmentExtensions) {
      final file = PlatformFile(
        name: '附件.$ext',
        size: 3,
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      expect(
        () => validateAgentAttachments([file]),
        returnsNormally,
        reason: ext,
      );
    }
    expect(
      () => validateAgentAttachments([
        PlatformFile(name: 'PHOTO.JPEG', size: 1, bytes: Uint8List(1)),
      ]),
      returnsNormally,
    );
  });
  test(
      'unsupported, missing, empty, mismatched and oversized files fail before sending',
      () {
    for (final file in [
      PlatformFile(name: 'program.exe', size: 1, bytes: Uint8List(1)),
      PlatformFile(name: 'empty.pdf', size: 0, bytes: Uint8List(0)),
      PlatformFile(name: 'missing.docx', size: 1),
      PlatformFile(name: 'incomplete.xlsx', size: 2, bytes: Uint8List(1)),
      PlatformFile(
        name: 'large.pptx',
        size: 5 * 1024 * 1024 + 1,
        bytes: Uint8List(1),
      ),
    ]) {
      expect(
        () => validateAgentAttachments([file]),
        throwsStateError,
        reason: file.name,
      );
    }
    final file = PlatformFile(name: 'sample.txt', size: 1, bytes: Uint8List(1));
    expect(
      () => validateAgentAttachments(List.filled(5, file)),
      throwsStateError,
    );
  });
}
