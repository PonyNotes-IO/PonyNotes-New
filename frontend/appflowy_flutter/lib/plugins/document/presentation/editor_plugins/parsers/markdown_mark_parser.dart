import 'dart:convert';

import 'package:appflowy/plugins/document/presentation/editor_plugins/base/format_mark_character.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:markdown/markdown.dart' as md;

/// Parses `==text==` into the editor's default highlight attribute.
class MarkdownInlineMarkSyntax extends md.InlineSyntax {
  MarkdownInlineMarkSyntax()
      : super(
          r'==(?=\S)(.+?\S)==',
          startCharacter: '='.codeUnitAt(0),
        );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    if (_isEscaped(parser.source, match.start)) {
      return false;
    }

    final text = match.group(1);
    if (text == null || text.trim().isEmpty) {
      return false;
    }

    final nestedNodes = md.InlineParser(text, parser.document).parse();
    final element = md.Element('mark', nestedNodes)
      ..attributes[AppFlowyRichTextKeys.backgroundColor] =
          jsonEncode(defaultMarkHighlightColor);
    parser.addNode(element);
    return true;
  }

  bool _isEscaped(String source, int index) {
    var slashCount = 0;
    for (var cursor = index - 1;
        cursor >= 0 && source.codeUnitAt(cursor) == r'\'.codeUnitAt(0);
        cursor--) {
      slashCount++;
    }
    return slashCount.isOdd;
  }
}
