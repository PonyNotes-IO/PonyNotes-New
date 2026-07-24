import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor_plugins/appflowy_editor_plugins.dart';
import 'package:flutter/material.dart';

const _equals = '=';
final defaultMarkHighlightColor = Colors.yellow.withValues(alpha: 0.3).toHex();

/// Formats text wrapped in double equals signs as a highlight.
///
/// Typing `==mark==` removes the delimiters and applies the same default
/// yellow highlight offered by the editor's highlight toolbar.
final CharacterShortcutEvent formatDoubleEqualsToMark = CharacterShortcutEvent(
  key: 'format text surrounded by double equals as highlight',
  character: _equals,
  handler: _handleDoubleEqualsToMark,
);

Future<bool> _handleDoubleEqualsToMark(EditorState editorState) async {
  final selection = editorState.selection;
  if (selection == null || !selection.isCollapsed || selection.end.offset < 4) {
    return false;
  }

  final node = editorState.getNodeAtPath(selection.end.path);
  final delta = node?.delta;
  if (node == null || delta == null || node.type == CodeBlockKeys.type) {
    return false;
  }

  final plainText = delta.toPlainText();
  if (selection.end.offset > plainText.length) {
    return false;
  }

  // The shortcut is called before the newly typed '=' is inserted, so the
  // text must currently end with the first closing delimiter.
  final textBeforeCursor = plainText.substring(0, selection.end.offset);
  if (!textBeforeCursor.endsWith(_equals)) {
    return false;
  }

  final closingDelimiterStart = selection.end.offset - 1;
  final openingDelimiterStart =
      textBeforeCursor.substring(0, closingDelimiterStart).lastIndexOf('==');
  final highlightedTextStart = openingDelimiterStart + 2;
  if (openingDelimiterStart < 0 ||
      highlightedTextStart >= closingDelimiterStart) {
    return false;
  }

  // Insert the last '=' first so one undo operation restores the exact typed
  // markdown, matching the editor's other character-format shortcuts.
  final insertion = editorState.transaction
    ..insertText(node, selection.end.offset, _equals)
    ..afterSelection = Selection.collapsed(
      selection.end.copyWith(offset: selection.end.offset + 1),
    );
  await editorState.apply(insertion, skipHistoryDebounce: true);

  final deletion = editorState.transaction
    ..deleteText(node, closingDelimiterStart, 2)
    ..deleteText(node, openingDelimiterStart, 2);
  await editorState.apply(deletion);

  final highlightedTextLength = closingDelimiterStart - highlightedTextStart;
  final format = editorState.transaction
    ..formatText(
      node,
      openingDelimiterStart,
      highlightedTextLength,
      {AppFlowyRichTextKeys.backgroundColor: defaultMarkHighlightColor},
    )
    ..afterSelection = Selection.collapsed(
      Position(
        path: selection.end.path,
        offset: openingDelimiterStart + highlightedTextLength,
      ),
    );
  await editorState.apply(format);
  return true;
}
