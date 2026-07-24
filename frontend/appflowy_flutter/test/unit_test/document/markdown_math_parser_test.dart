import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy/shared/markdown_to_document.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Markdown math parser:', () {
    setUpAll(() {
      Log.shared.disableLog = true;
    });

    tearDownAll(() {
      Log.shared.disableLog = false;
    });

    test('convert inline dollar math to inline formula attribute', () {
      final document = customMarkdownToDocument(
        r'The formula is $a^2+b^2=c^2$ here.',
      );

      final paragraph = document.nodeAtPath([0])!;
      expect(paragraph.type, ParagraphBlockKeys.type);

      final inserts = paragraph.delta!.whereType<TextInsert>().toList();
      expect(inserts.length, 3);
      expect(inserts[1].text, MentionBlockKeys.mentionChar);
      expect(
        inserts[1].attributes?[InlineMathEquationKeys.formula],
        'a^2+b^2=c^2',
      );
    });

    test('convert double dollar block math to math equation node', () {
      final document = customMarkdownToDocument(r'$$\frac{1}{2}$$');

      final mathNode = document.nodeAtPath([0])!;
      expect(mathNode.type, MathEquationBlockKeys.type);
      expect(
        mathNode.attributes[MathEquationBlockKeys.formula],
        r'\frac{1}{2}',
      );
    });

    test('convert bracket display math delimiter to math equation node', () {
      final document = customMarkdownToDocument(
        r'''
Before

\[
\int_0^1 x^2 dx
\]

After
''',
      );

      final mathNode = document.nodeAtPath([1])!;
      expect(mathNode.type, MathEquationBlockKeys.type);
      expect(
        mathNode.attributes[MathEquationBlockKeys.formula],
        r'\int_0^1 x^2 dx',
      );
    });

    test('convert parenthesized inline math delimiter to inline formula', () {
      final document = customMarkdownToDocument(
        r'The formula is \(a_n=\frac{1}{n}\) here.',
      );

      final paragraph = document.nodeAtPath([0])!;
      final inserts = paragraph.delta!.whereType<TextInsert>().toList();
      expect(inserts.length, 3);
      expect(inserts[1].text, MentionBlockKeys.mentionChar);
      expect(
        inserts[1].attributes?[InlineMathEquationKeys.formula],
        r'a_n=\frac{1}{n}',
      );
    });

    test('convert ==text== to highlighted text', () {
      final document = customMarkdownToDocument('Before ==marked== after');

      final inserts =
          document.nodeAtPath([0])!.delta!.whereType<TextInsert>().toList();
      expect(
        inserts.map((insert) => insert.text).join(),
        'Before marked after',
      );
      expect(
        inserts[1].attributes?[AppFlowyRichTextKeys.backgroundColor],
        Colors.yellow.withValues(alpha: 0.3).toHex(),
      );
    });
  });
}
