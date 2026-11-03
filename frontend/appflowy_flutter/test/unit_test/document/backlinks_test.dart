import 'package:appflowy/plugins/document/presentation/editor_plugins/backlinks/backlink_panel.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'outgoing links follow live editor insertions and removals without an index read',
      () async {
    final node = paragraphNode(delta: Delta()..insert('中文 😀 '));
    final editor =
        EditorState(document: Document(root: pageNode(children: [node])));
    expect(editorOutgoingLinks('source', editor), isEmpty);
    await editor.apply(editor.transaction
      ..insertText(node, node.delta!.length, r'$', attributes: {
        'mention': {
          'type': 'page',
          'page_id': 'target',
          'block_id': 'target-block'
        },
      }));
    final links = editorOutgoingLinks('source', editor);
    expect(links, hasLength(1));
    expect(links.single.srcPageId, 'source');
    expect(links.single.srcBlockId, node.id);
    expect(links.single.dstPageId, 'target');
    expect(links.single.dstBlockId, 'target-block');
    expect(links.single.kind, 'block_ref');
    expect(links.single.charOffset, '中文 😀 '.runes.length);
    await editor
        .apply(editor.transaction..deleteText(node, '中文 😀 '.length, 1));
    expect(editorOutgoingLinks('source', editor), isEmpty);
    editor.dispose();
  });

  test('non-page mentions and arbitrary page_id attributes do not create links',
      () {
    final node = paragraphNode(
        delta: Delta()
          ..insert(r'$', attributes: {
            'mention': {'type': 'user', 'page_id': 'fake'}
          })
          ..insert('text', attributes: {'page_id': 'fake'})
          ..insert(r'$', attributes: {
            'mention': {'type': 'page', 'page_id': 'real'}
          }));
    final editor =
        EditorState(document: Document(root: pageNode(children: [node])));
    expect(editorOutgoingLinks('source', editor).map((link) => link.dstPageId),
        ['real']);
    editor.dispose();
  });
}
