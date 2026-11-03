import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

/// Read outgoing links from the editor so an insertion appears immediately.
List<NoteLinkPB> editorOutgoingLinks(String pageId, EditorState editor) {
  final links = <String, NoteLinkPB>{};
  void add(Node node, String target, String? blockId, String kind, int offset) {
    if (target.isEmpty) return;
    final key = '${node.id}/$target/${blockId ?? ''}/$kind';
    final existing = links[key];
    if (existing != null) {
      existing.occurrence++;
    } else {
      links[key] = NoteLinkPB(
        srcPageId: pageId,
        srcBlockId: node.id,
        dstPageId: target,
        dstBlockId: blockId,
        kind: kind,
        charOffset: offset,
        occurrence: 1,
      );
    }
  }

  void url(Node node, Object? raw, int offset) {
    if (raw is! String) return;
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    final internal = const {'ponynotes', 'appflowy', 'appflowy-flutter'}
        .contains(uri.scheme);
    final share = uri.scheme == 'https' &&
        uri.path == '/share' &&
        const {
          'xiaomabiji.com',
          'www.xiaomabiji.com',
          'ponynotes.io',
          'www.ponynotes.io',
        }.contains(uri.host);
    if (!internal && !share) return;
    final target =
        uri.queryParameters['viewId'] ?? uri.queryParameters['page_id'];
    final block =
        uri.queryParameters['blockId'] ?? uri.queryParameters['block_id'];
    if (target != null) {
      add(
        node,
        target,
        block,
        block == null ? 'reference' : 'block_ref',
        offset,
      );
    }
  }

  void walk(Node node) {
    if (const {'sub_page', 'mention', 'link_to_page', 'embed'}
        .contains(node.type)) {
      final target = node.attributes['view_id'];
      if (target is String) add(node, target, null, 'embed', 0);
    }
    if (const {'link_preview', 'link_embed'}.contains(node.type)) {
      url(node, node.attributes['url'], 0);
    }
    var offset = 0;
    for (final op in node.delta?.toJson() ?? <Map<String, dynamic>>[]) {
      final attributes = op['attributes'];
      final mention = attributes is Map ? attributes['mention'] : null;
      if (attributes is Map) url(node, attributes['href'], offset);
      if (op['insert'] == r'$' &&
          mention is Map &&
          const {'page', 'childPage'}.contains(mention['type'] ?? 'page') &&
          mention['page_id'] is String) {
        final blockId = mention['block_id'] as String?;
        add(
          node,
          mention['page_id'] as String,
          blockId,
          blockId != null
              ? 'block_ref'
              : mention['type'] == 'childPage'
                  ? 'embed'
                  : 'reference',
          offset,
        );
      }
      final insert = op['insert'];
      offset += insert is String ? insert.runes.length : 1;
    }
    for (final child in node.children) {
      walk(child);
    }
  }

  walk(editor.document.root);
  return links.values.toList();
}

/// A source note can cite several blocks; note counts and occurrence counts differ.
Map<String, List<NoteLinkPB>> groupNoteLinks(
  Iterable<NoteLinkPB> links, {
  required bool incoming,
}) {
  final groups = <String, List<NoteLinkPB>>{};
  for (final link in links) {
    final id = incoming ? link.srcPageId : link.dstPageId;
    (groups[id] ??= []).add(link);
  }
  return groups;
}

int noteLinkOccurrences(Iterable<NoteLinkPB> links) => links.fold(
      0,
      (count, link) => count + (link.occurrence > 0 ? link.occurrence : 1),
    );

String noteLinkContext(String text, int offset) {
  final runes = text.runes.toList();
  final start = (offset - 60).clamp(0, runes.length);
  final end = (offset + 100).clamp(start, runes.length);
  return '${start > 0 ? '…' : ''}${String.fromCharCodes(runes.sublist(start, end))}${end < runes.length ? '…' : ''}';
}

/// Structural mentions occupy one editor character; never expose their '$' placeholder.
String noteBlockText(Node node, {Map<String, String> titles = const {}}) {
  final text = StringBuffer();
  for (final op in node.delta?.toJson() ?? <Map<String, dynamic>>[]) {
    final mention = (op['attributes'] as Map?)?['mention'];
    if (op['insert'] == r'$' && mention is Map) {
      text.write(titles[mention['page_id']] ?? '↗');
    } else if (op['insert'] is String) {
      text.write(op['insert']);
    }
  }
  return text.toString().trim();
}
