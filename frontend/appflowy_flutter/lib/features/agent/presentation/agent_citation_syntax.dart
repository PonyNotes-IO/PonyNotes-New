import 'package:html/parser.dart' as html;
import 'package:markdown/markdown.dart' as md;

/// Resolve native citations through retrieved IDs and Cloud-authorized sources.
class AgentCitationSyntax extends md.InlineSyntax {
  AgentCitationSyntax(this.sources, Iterable<Map> evidence)
      : super(
          r'''<kb\b(?:"[^"]*"|'[^']*'|[^'">])*>|<kb\b[^>\r\n]*$''',
          startCharacter: 60,
        ) {
    for (final data in evidence) {
      for (final item in [
        data,
        ...(data['results'] as List? ?? []).whereType<Map>(),
      ]) {
        for (final chunk in [
          item['chunk_id'] ?? item['id'],
          ...(item['chunk_ids'] as List? ?? []),
        ].whereType<String>()) {
          chunks[chunk] = item;
        }
      }
    }
  }

  final Map<String, Map<String, dynamic>> sources;
  final chunks = <String, Map>{};

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final tag = match[0]!;
    // Wait for a complete citation while the answer is streaming.
    if (!tag.endsWith('>')) return true;
    final attributes = html.parseFragment(tag).children.first.attributes;
    final result = chunks[attributes['chunk_id']];
    final source = sources[result?['knowledge_id']];
    final base = result?['knowledge_base_id'];
    final url = source?['url'] as String?;
    final title = source?['title'] ?? attributes['doc'] ?? '引用资料';
    if (source == null ||
        url == null ||
        url.isEmpty ||
        (base != null && attributes['kb_id'] != base)) {
      parser.addNode(md.Text('（来源：$title，暂不可用）'));
    } else {
      parser.addNode(
        md.Element.text('a', '〔来源：$title〕')..attributes['href'] = url,
      );
    }
    return true;
  }
}

/// A citation on its own line would otherwise be parsed as a raw HTML block.
class AgentCitationBlockSyntax extends md.BlockSyntax {
  @override
  RegExp get pattern => RegExp(r'^ {0,3}<kb\b');

  @override
  md.Node parse(md.BlockParser parser) {
    final lines = [parser.current.content];
    parser.advance();
    while (!lines.last.contains('>') &&
        !parser.isDone &&
        !parser.current.isBlankLine) {
      lines.add(parser.current.content);
      parser.advance();
    }
    return md.Element(
      'p',
      md.InlineParser(lines.join('\n'), parser.document).parse(),
    );
  }
}
