import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:text_counter/text_counter.dart';

/// A word count service that uses text_counter for accurate multi-language word counting.
///
/// This replaces the default WordCountService from appflowy_editor which uses
/// a simple regex that doesn't properly handle CJK characters.
class CustomWordCountService {
  CustomWordCountService({
    required EditorState editorState,
    this.debounceDuration = const Duration(milliseconds: 300),
    void Function()? onWordCountChanged,
  }) : _editorState = editorState,
       _onWordCountChanged = onWordCountChanged {
    _initialize();
  }

  final EditorState _editorState;
  final Duration debounceDuration;
  final void Function()? _onWordCountChanged;
  Timer? _debounceTimer;
  StreamSubscription<EditorTransactionValue>? _transactionSubscription;

  Counters? _documentCounters;
  Counters? _selectionCounters;

  Counters? get documentCounters => _documentCounters;
  Counters? get selectionCounters => _selectionCounters;

  void _initialize() {
    _transactionSubscription = _editorState.transactionStream.listen(_onTransaction);
    _updateDocumentCount();
  }

  void _onTransaction(EditorTransactionValue event) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDuration, _updateDocumentCount);
  }

  void _updateDocumentCount() {
    final text = _getDocumentText();
    _documentCounters = Counters(
      wordCount: TextCounter.count(text),
      charCount: text.runes.length,
    );
    _onWordCountChanged?.call();
  }

  String _getDocumentText() {
    final buffer = StringBuffer();
    final root = _editorState.document.root;
    _appendNodeText(buffer, root);
    return buffer.toString();
  }

  void _appendNodeText(StringBuffer buffer, Node node) {
    final delta = node.delta;
    if (delta != null) {
      buffer.write(delta.toPlainText());
    }
    for (final child in node.children) {
      _appendNodeText(buffer, child);
    }
  }

  void updateSelectionCount(Selection? selection) {
    if (selection == null || selection.isCollapsed) {
      _selectionCounters = null;
      return;
    }

    final text = _getSelectionText(selection);
    _selectionCounters = Counters(
      wordCount: TextCounter.count(text),
      charCount: text.runes.length,
    );
    _onWordCountChanged?.call();
  }

  String _getSelectionText(Selection selection) {
    final buffer = StringBuffer();
    final start = selection.normalized.start;
    final end = selection.normalized.end;

    if (start.path.length == 1 && end.path.length == 1 &&
        start.path.first == end.path.first) {
      // Same node - simple case
      final node = _editorState.getNodeAtPath(start.path);
      if (node?.delta != null) {
        final startIdx = start.offset;
        final endIdx = end.offset;
        if (startIdx < endIdx) {
          return node!.delta!.slice(startIdx, endIdx).toPlainText();
        }
      }
      return '';
    }

    // Multi-node selection
    final startNode = _editorState.getNodeAtPath(start.path);
    final endNode = _editorState.getNodeAtPath(end.path);

    if (startNode?.delta != null) {
      buffer.write(startNode!.delta!.slice(start.offset).toPlainText());
    }

    // Collect nodes between start and end
    if (start.path.length == end.path.length) {
      Node? current = startNode?.next;
      while (current != null && current.key != endNode?.key) {
        buffer.write(current.delta?.toPlainText() ?? '');
        current = current.next;
      }
    }

    if (endNode?.delta != null) {
      buffer.write(endNode!.delta!.slice(0, end.offset).toPlainText());
    }

    return buffer.toString();
  }

  void dispose() {
    _debounceTimer?.cancel();
    _transactionSubscription?.cancel();
  }
}
