import 'package:appflowy/plugins/document/presentation/editor_plugins/base/format_arrow_character.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/format_mark_character.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('format shortcut:', () {
    setUpAll(() {
      Log.shared.disableLog = true;
    });

    tearDownAll(() {
      Log.shared.disableLog = false;
    });

    test('turn = + > into ⇒', () async {
      final document = Document.blank()
        ..insert([
          0,
        ], [
          paragraphNode(text: '='),
        ]);

      final editorState = EditorState(document: document);
      editorState.selection = Selection.collapsed(
        Position(path: [0], offset: 1),
      );

      final result = await customFormatGreaterEqual.execute(editorState);
      expect(result, true);

      expect(editorState.document.root.children.length, 1);
      final node = editorState.document.root.children[0];
      expect(node.delta!.toPlainText(), '⇒');

      // use undo to revert the change
      undoCommand.execute(editorState);
      expect(editorState.document.root.children.length, 1);
      final nodeAfterUndo = editorState.document.root.children[0];
      expect(nodeAfterUndo.delta!.toPlainText(), '=>');

      editorState.dispose();
    });

    test('turn - + > into →', () async {
      final document = Document.blank()
        ..insert([
          0,
        ], [
          paragraphNode(text: '-'),
        ]);

      final editorState = EditorState(document: document);
      editorState.selection = Selection.collapsed(
        Position(path: [0], offset: 1),
      );

      final result = await customFormatDashGreater.execute(editorState);
      expect(result, true);

      expect(editorState.document.root.children.length, 1);
      final node = editorState.document.root.children[0];
      expect(node.delta!.toPlainText(), '→');

      // use undo to revert the change
      undoCommand.execute(editorState);
      expect(editorState.document.root.children.length, 1);
      final nodeAfterUndo = editorState.document.root.children[0];
      expect(nodeAfterUndo.delta!.toPlainText(), '->');

      editorState.dispose();
    });

    test('turn -- into —', () async {
      final document = Document.blank()
        ..insert([
          0,
        ], [
          paragraphNode(text: '-'),
        ]);

      final editorState = EditorState(document: document);
      editorState.selection = Selection.collapsed(
        Position(path: [0], offset: 1),
      );

      final result = await customFormatDoubleHyphenEmDash.execute(editorState);
      expect(result, true);

      expect(editorState.document.root.children.length, 1);
      final node = editorState.document.root.children[0];
      expect(node.delta!.toPlainText(), '—');

      // use undo to revert the change
      undoCommand.execute(editorState);
      expect(editorState.document.root.children.length, 1);
      final nodeAfterUndo = editorState.document.root.children[0];
      expect(nodeAfterUndo.delta!.toPlainText(), '--');

      editorState.dispose();
    });

    test('turn ==mark== into highlighted text', () async {
      final document = Document.blank()
        ..insert([
          0,
        ], [
          paragraphNode(text: '==mark='),
        ]);

      final editorState = EditorState(document: document);
      editorState.selection = Selection.collapsed(
        Position(path: [0], offset: 7),
      );

      final result = await formatDoubleEqualsToMark.execute(editorState);
      expect(result, true);

      final delta = editorState.document.root.children.first.delta!;
      expect(delta.toPlainText(), 'mark');
      final textInsert = delta.whereType<TextInsert>().single;
      expect(
        textInsert.attributes?[AppFlowyRichTextKeys.backgroundColor],
        Colors.yellow.withValues(alpha: 0.3).toHex(),
      );

      undoCommand.execute(editorState);
      expect(
        editorState.document.root.children.first.delta!.toPlainText(),
        '==mark==',
      );

      editorState.dispose();
    });

    test('does not format empty == delimiters', () async {
      final document = Document.blank()
        ..insert([
          0,
        ], [
          paragraphNode(text: '==='),
        ]);

      final editorState = EditorState(document: document);
      editorState.selection = Selection.collapsed(
        Position(path: [0], offset: 3),
      );

      expect(await formatDoubleEqualsToMark.execute(editorState), false);
      expect(
        editorState.document.root.children.first.delta!.toPlainText(),
        '===',
      );

      editorState.dispose();
    });
  });
}
