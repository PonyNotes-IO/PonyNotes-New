import 'dart:convert';
import 'dart:math';

import 'package:appflowy/features/version_history/version_history_diff.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy_backend/protobuf/flowy-document/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/protobuf.dart';

DocumentDataPB document(List<String> lines) =>
    DocumentDataPBFromTo.fromDocument(
      Document(
        root: pageNode(
          children: lines.map((text) => paragraphNode(text: text)).toList(),
        ),
      ),
    )!;

void main() {
  test('internal IDs do not make identical content appear changed', () {
    expect(
      compareHistory((document(['one']), document(['one']))).hasChanges,
      isFalse,
    );
  });

  test('equal-format text segmentation does not appear as a content change',
      () {
    final before = document(['hello']);
    final after = before.deepCopy();
    final block =
        after.blocks.values.firstWhere((block) => block.ty == 'paragraph');
    block.data =
        '{"delta":[{"insert":"he","attributes":{}},{"insert":"llo"},{"insert":""}]}';
    expect(compareHistory((before, after)).hasChanges, isFalse);
  });

  test('inline and external text match in the comparison', () {
    final inline = document(['hello']);
    final external = inline.deepCopy();
    final block =
        external.blocks.values.firstWhere((block) => block.ty == 'paragraph');
    block.externalId = 'external-id';
    block.externalType = 'text';
    block.data = '{}';
    external.meta.textMap['external-id'] = '[{"insert":"hello"}]';
    expect(compareHistory((inline, external)).hasChanges, isFalse);
  });

  test(
      'unified diff reconstructs both sides including repeated and moved lines',
      () {
    final random = Random(16);
    for (var attempt = 0; attempt < 100; attempt++) {
      final current =
          List.generate(1 + random.nextInt(10), (_) => '${random.nextInt(4)}');
      final version =
          List.generate(1 + random.nextInt(10), (_) => '${random.nextInt(4)}');
      final diff = compareHistory((document(current), document(version)));
      expect(
        diff.lines
            .where((line) => line.change != HistoryChange.added)
            .map((line) => line.text)
            .toList(),
        current,
      );
      expect(
        diff.lines
            .where((line) => line.change != HistoryChange.removed)
            .map((line) => line.text)
            .toList(),
        version,
      );
      expect(
        diff.lines
            .where((line) => line.currentLine != null)
            .map((line) => line.currentLine)
            .toList(),
        List.generate(current.length, (i) => i + 1),
      );
      expect(
        diff.lines
            .where((line) => line.versionLine != null)
            .map((line) => line.versionLine)
            .toList(),
        List.generate(version.length, (i) => i + 1),
      );
    }
  });

  test('format-only changes are visible even if the plain text matches', () {
    final before = document(['same text']);
    final after = before.deepCopy();
    final block =
        after.blocks.values.firstWhere((block) => block.ty == 'paragraph');
    block.data = jsonEncode({
      'delta': [
        {
          'insert': 'same text',
          'attributes': {'bold': true},
        }
      ],
    });
    final diff = compareHistory((before, after));
    expect(diff.added, 1);
    expect(diff.removed, 1);
    expect(diff.lines.every((line) => line.attributesChanged), isTrue);
  });

  test('external text and image changes are included', () {
    final before = document(['inline text']);
    final block =
        before.blocks.values.firstWhere((block) => block.ty == 'paragraph');
    block.externalId = 'text';
    block.externalType = 'text';
    before.meta.textMap['text'] = '[{"insert":"external content"}]';
    final after = before.deepCopy();
    after.meta.textMap['text'] = '[{"insert":"changed external content"}]';
    final diff = compareHistory((before, after));
    expect(diff.lines.first.text, 'external content');
    expect(diff.lines.last.text, 'changed external content');
    block.ty = 'image';
    block.clearExternalId();
    block.clearExternalType();
    block.data = '{"url":"old-image.png"}';
    final newer = before.deepCopy();
    newer.blocks[block.id]!.data = '{"url":"new-image.png"}';
    expect(compareHistory((before, newer)).hasChanges, isTrue);
  });
}
