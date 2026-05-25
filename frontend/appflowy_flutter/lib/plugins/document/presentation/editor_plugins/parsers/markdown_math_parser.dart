import 'dart:convert';

import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:markdown/markdown.dart' as md;

class MarkdownMathBlockParser extends CustomMarkdownParser {
  const MarkdownMathBlockParser();

  @override
  List<Node> transform(
    md.Node element,
    List<CustomMarkdownParser> parsers, {
    MarkdownListType listType = MarkdownListType.unknown,
    int? startNumber,
  }) {
    if (element is! md.Element || element.tag != 'p') {
      return [];
    }

    final formula = _extractBlockFormula(element.textContent);
    if (formula == null) {
      return [];
    }

    return [
      mathEquationNode(formula: formula),
    ];
  }

  String? _extractBlockFormula(String text) {
    final trimmed = text.trim();
    if (!trimmed.startsWith(r'$$') || !trimmed.endsWith(r'$$')) {
      return null;
    }

    final formula = trimmed.substring(2, trimmed.length - 2).trim();
    return formula.isEmpty ? null : formula;
  }
}

class MarkdownInlineMathSyntax extends md.InlineSyntax {
  MarkdownInlineMathSyntax()
      : super(
          r'\$(?!\$)([^$\n]+?)\$(?!\$)',
          startCharacter: r'$'.codeUnitAt(0),
        );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    if (_isEscaped(parser.source, match.start)) {
      return false;
    }

    final formula = match.group(1)?.trim();
    if (formula == null || formula.isEmpty || formula.contains(r'$$')) {
      return false;
    }

    final element = md.Element.text('span', MentionBlockKeys.mentionChar)
      ..attributes[InlineMathEquationKeys.formula] = jsonEncode(formula);
    parser.addNode(element);
    return true;
  }

  bool _isEscaped(String source, int dollarIndex) {
    var slashCount = 0;
    var index = dollarIndex - 1;
    while (index >= 0 && source.codeUnitAt(index) == r'\'.codeUnitAt(0)) {
      slashCount++;
      index--;
    }
    return slashCount.isOdd;
  }
}
