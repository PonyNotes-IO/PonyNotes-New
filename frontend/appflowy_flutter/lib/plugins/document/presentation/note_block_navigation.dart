import 'dart:async';

import 'package:appflowy/plugins/document/application/note_relations_controller.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

/// Carries a reference destination through tab reuse and SpaceHub's view-only opens.
/// Scrolling belongs to the target editor, after its viewport has been attached.
class NoteBlockNavigation {
  NoteBlockNavigation({
    required this.pageId,
    required this.editor,
    required this.scrollController,
    required this.hasHeader,
  });

  static final _editors = Expando<NoteBlockNavigation>();
  static final _pages = <String, Set<NoteBlockNavigation>>{};
  static final _pending = <String, _BlockDestination>{};

  final String pageId;
  final EditorState editor;
  final EditorScrollController scrollController;
  final bool Function() hasHeader;
  bool _disposed = false;
  int _generation = 0;

  static NoteBlockNavigation? forEditor(EditorState editor) => _editors[editor];

  static void request(String pageId, String blockId) {
    if (blockId.isEmpty) return;
    _pending.remove(pageId)?.expiry.cancel();
    final destination = _BlockDestination(blockId);
    _pending[pageId] = destination;
    destination.expiry = Timer(const Duration(seconds: 10), () {
      if (identical(_pending[pageId], destination)) _pending.remove(pageId);
    });
    for (final navigator
        in _pages[pageId]?.toList() ?? <NoteBlockNavigation>[]) {
      navigator._openDestination(destination);
    }
  }

  void attach() {
    _editors[editor] = this;
    (_pages[pageId] ??= {}).add(this);
    final destination = _pending[pageId];
    if (destination != null) _openDestination(destination);
  }

  void _openDestination(_BlockDestination destination) {
    unawaited(
      jumpToBlock(destination.blockId).then((found) {
        if (found && identical(_pending[pageId], destination)) {
          _pending.remove(pageId);
          destination.expiry.cancel();
        }
      }),
    );
  }

  Future<bool> jumpToBlock(String blockId) async {
    final generation = ++_generation;
    // Opening a note can take several frames, including restoring its scroll offset.
    for (var attempt = 0; attempt < 60; attempt++) {
      if (!_active(generation)) return false;
      await WidgetsBinding.instance.endOfFrame;
      if (!_active(generation)) return false;
      final node = _find(editor.document.root, blockId);
      if (node != null && await _reveal(node, generation)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    return false;
  }

  Future<bool> jumpToPath(Path path) async {
    final node = editor.getNodeAtPath(path);
    if (node == null) return false;
    return jumpToBlock(node.id);
  }

  bool _active(int generation) =>
      !_disposed && !editor.isDisposed && generation == _generation;

  Future<bool> _reveal(Node node, int generation) async {
    if (node.path.isEmpty) return false;
    if (scrollController.shrinkWrap) {
      if (!scrollController.scrollController.hasClients) return false;
    } else {
      final items = scrollController.itemScrollController;
      if (!items.isAttached) return false;
      // The cover/title is a real list item, while node.path is document-relative.
      items.jumpTo(
        index: node.path.first + (hasHeader() ? 1 : 0),
        alignment: .3,
      );
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!_active(generation)) return false;
    var targetContext = node.key.currentContext;
    if (targetContext == null || !targetContext.mounted) return false;
    final renderObject = targetContext.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return false;
    }

    // This editor version only completes the returned future for UI events.
    // Transaction selection updates are synchronous; wait for layout separately.
    unawaited(
      editor.updateSelectionWithReason(
        Selection.collapsed(Position(path: node.path)),
        customSelectionType: SelectionType.block,
        extraInfo: {
          selectionExtraInfoDoNotAttachTextService: true,
          selectionExtraInfoDisableMobileToolbarKey: true,
        },
      ),
    );
    await WidgetsBinding.instance.endOfFrame;
    if (!_active(generation)) return false;
    targetContext = node.key.currentContext;
    if (targetContext == null || !targetContext.mounted) return false;
    // First-level indexing only mounts the parent. Reveal the actual nested block.
    await Scrollable.ensureVisible(targetContext, alignment: .3);
    if (!_active(generation)) return false;
    NoteRelationsController.forEditor(editor)?.highlight(node.id);
    return true;
  }

  Node? _find(Node node, String id) {
    if (node.id == id) return node;
    for (final child in node.children) {
      final found = _find(child, id);
      if (found != null) return found;
    }
    return null;
  }

  void dispose() {
    _disposed = true;
    _generation++;
    if (_editors[editor] == this) _editors[editor] = null;
    final navigators = _pages[pageId];
    navigators?.remove(this);
    if (navigators?.isEmpty ?? false) _pages.remove(pageId);
  }
}

class _BlockDestination {
  _BlockDestination(this.blockId);
  final String blockId;
  late final Timer expiry;
}
