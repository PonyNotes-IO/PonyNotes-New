import 'dart:async';

import 'package:appflowy/plugins/document/presentation/note_block_navigation.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_block/custom_page_block_component.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _DocumentFixture {
  _DocumentFixture({
    required this.pageId,
    this.shrinkWrap = false,
    this.nested = false,
  }) {
    blocks = List.generate(
      70,
      (index) => paragraphNode(
        delta: Delta()
          ..insert(
            'Paragraph $index: content that takes up vertical space.',
          ),
      ),
    );
    root = pageNode(
      children: nested
          ? [
              paragraphNode(
                delta: Delta()..insert('Parent block'),
                children: blocks,
              ),
            ]
          : blocks,
    );
    editor = EditorState(document: Document(root: root));
    scroll =
        EditorScrollController(editorState: editor, shrinkWrap: shrinkWrap);
    navigation = NoteBlockNavigation(
      pageId: pageId,
      editor: editor,
      scrollController: scroll,
      hasHeader: () => true,
    );
  }

  final String pageId;
  final bool shrinkWrap;
  final bool nested;
  late final List<Node> blocks;
  late final Node root;
  late final EditorState editor;
  late final EditorScrollController scroll;
  late final NoteBlockNavigation navigation;

  Widget build() => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 500,
            child: AppFlowyEditor(
              editorState: editor,
              editorScrollController: scroll,
              shrinkWrap: shrinkWrap,
              editable: false,
              header:
                  const SizedBox(height: 400, child: Text('Document cover')),
              footer: const SizedBox(height: 500),
              blockComponentBuilders: {
                ...standardBlockComponentBuilderMap,
                PageBlockKeys.type: CustomPageBlockComponentBuilder(),
              },
            ),
          ),
        ),
      );

  Future<void> dispose(WidgetTester tester) async {
    navigation.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    scroll.dispose();
    editor.dispose();
  }
}

Future<bool> _finishJump(WidgetTester tester, Future<bool> result) async {
  bool? found;
  unawaited(result.then((value) {
    found = value;
  }));
  for (var frame = 0; frame < 90 && found == null; frame++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
  expect(
    found,
    isNotNull,
    reason: 'Block navigation should complete after layout',
  );
  await tester.pumpAndSettle();
  return found!;
}

void _expectVisible(WidgetTester tester, Node target) {
  final rectangle = tester.getRect(find.byKey(target.key));
  expect(rectangle.top, greaterThanOrEqualTo(0));
  expect(rectangle.bottom, lessThanOrEqualTo(500));
}

void main() {
  testWidgets('deep reference jumps past the cover to its actual block',
      (tester) async {
    final fixture = _DocumentFixture(pageId: 'deep-note');
    await tester.pumpWidget(fixture.build());
    fixture.navigation.attach();
    await tester.pumpAndSettle();
    final destination = fixture.blocks[55];
    final result = fixture.navigation.jumpToBlock(destination.id);
    expect(await _finishJump(tester, result), isTrue);
    _expectVisible(tester, destination);
    expect(fixture.editor.selection!.start.path, destination.path);
    await fixture.dispose(tester);
  });

  testWidgets(
      'nested reference reveals the child rather than the top of its parent',
      (tester) async {
    final fixture = _DocumentFixture(pageId: 'nested-note', nested: true);
    await tester.pumpWidget(fixture.build());
    fixture.navigation.attach();
    await tester.pumpAndSettle();
    final destination = fixture.blocks[45];
    final result = fixture.navigation.jumpToBlock(destination.id);
    expect(await _finishJump(tester, result), isTrue);
    _expectVisible(tester, destination);
    expect(destination.path, [0, 45]);
    await fixture.dispose(tester);
  });

  testWidgets(
      'embedded shrink-wrap editors scroll in pixels using target geometry',
      (tester) async {
    final fixture = _DocumentFixture(pageId: 'embedded-note', shrinkWrap: true);
    await tester.pumpWidget(fixture.build());
    fixture.navigation.attach();
    await tester.pumpAndSettle();
    final destination = fixture.blocks[50];
    final result = fixture.navigation.jumpToBlock(destination.id);
    expect(await _finishJump(tester, result), isTrue);
    _expectVisible(tester, destination);
    expect(fixture.scroll.scrollController.offset, greaterThan(500));
    await fixture.dispose(tester);
  });

  testWidgets(
      'reference destination survives a view-only open before the editor is mounted',
      (tester) async {
    final fixture = _DocumentFixture(pageId: 'pending-note');
    final destination = fixture.blocks[40];
    NoteBlockNavigation.request(fixture.pageId, destination.id);
    // SpaceHub may supply only a view; the editor consumes the pending block ID.
    fixture.navigation.attach();
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    _expectVisible(tester, destination);
    expect(fixture.editor.selection!.start.path, destination.path);
    await fixture.dispose(tester);
  });

  testWidgets(
      'an already open note accepts new and repeated reference destinations',
      (tester) async {
    final fixture = _DocumentFixture(pageId: 'open-note');
    await tester.pumpWidget(fixture.build());
    fixture.navigation.attach();
    await tester.pumpAndSettle();
    for (final index in [50, 10, 50, 50]) {
      final destination = fixture.blocks[index];
      NoteBlockNavigation.request(fixture.pageId, destination.id);
      await tester.pumpAndSettle();
      _expectVisible(tester, destination);
      expect(fixture.editor.selection!.start.path, destination.path);
    }
    await fixture.dispose(tester);
  });

  testWidgets(
      'leaving during a pending jump cancels work against a disposed editor',
      (tester) async {
    final fixture = _DocumentFixture(pageId: 'closing-note');
    fixture.navigation.attach();
    final result = fixture.navigation.jumpToBlock(fixture.blocks.last.id);
    fixture.navigation.dispose();
    await tester.pump();
    expect(await result, isFalse);
    await fixture.dispose(tester);
    expect(tester.takeException(), isNull);
  });
}
