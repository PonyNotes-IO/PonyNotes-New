import 'dart:convert';

import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/plugins/document/application/note_link_data.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/mention/mention_block.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

String referenceText(BuildContext context, String zh, String en) =>
    Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

class NoteReferenceTarget {
  const NoteReferenceTarget(this.pageId, this.blockId);
  final String pageId;
  final String? blockId;
}

/// Preserve the exact source range while a picker is open. Async UI never overwrites edits.
class NoteReferenceAnchor {
  NoteReferenceAnchor(this.nodeId, this.delta, this.start, this.length);
  final String nodeId;
  final String delta;
  final int start;
  final int length;

  static NoteReferenceAnchor? capture(
    EditorState editor, {
    int? start,
    int? length,
  }) {
    final selection = editor.selection;
    if (selection == null || !selection.isSingle) return null;
    final node = editor.getNodeAtPath(selection.start.path);
    if (node?.delta == null) return null;
    return NoteReferenceAnchor(
      node!.id,
      jsonEncode(node.delta!.toJson()),
      start ?? selection.start.offset,
      length ?? selection.end.offset - selection.start.offset,
    );
  }

  Future<bool> insert(EditorState editor, NoteReferenceTarget target) async {
    if (editor.isDisposed || !editor.editableNotifier.value) return false;
    Node? find(Node node) {
      if (node.id == nodeId) return node;
      for (final child in node.children) {
        final found = find(child);
        if (found != null) return found;
      }
      return null;
    }

    final node = find(editor.document.root);
    if (node?.delta == null || jsonEncode(node!.delta!.toJson()) != delta) {
      return false;
    }
    if (start < 0 || length < 0 || start + length > node.delta!.length) {
      return false;
    }
    await editor.apply(
      editor.transaction
        ..replaceText(
          node,
          start,
          length,
          MentionBlockKeys.mentionChar,
          attributes: MentionBlockKeys.buildMentionPageAttributes(
            mentionType: MentionType.page,
            pageId: target.pageId,
            blockId: target.blockId,
          ),
        ),
    );
    return true;
  }
}

Future<void> insertNoteReference(
  BuildContext context,
  EditorState editor, {
  ViewPB? initialView,
  NoteReferenceAnchor? anchor,
}) async {
  if (editor.isDisposed || !editor.editableNotifier.value) return;
  if (anchor == null && editor.selection == null) {
    Node? lastText;
    void walk(Node node) {
      if (node.delta != null) lastText = node;
      for (final child in node.children) {
        walk(child);
      }
    }

    walk(editor.document.root);
    if (lastText != null) {
      editor.selection = Selection.collapsed(
        Position(
          path: lastText!.path,
          offset: lastText!.delta!.length,
        ),
      );
    }
  }
  final source = anchor ?? NoteReferenceAnchor.capture(editor);
  if (source == null) return;
  final target = await showDialog<NoteReferenceTarget>(
    context: context,
    builder: (_) => NoteReferencePicker(initialView: initialView),
  );
  if (target == null || !context.mounted) return;
  if (!await source.insert(editor, target) && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          referenceText(
            context,
            '原段落已变化，请重新选择引用位置',
            'The source paragraph changed. Choose the insertion point again.',
          ),
        ),
      ),
    );
  }
}

class NoteReferencePicker extends StatefulWidget {
  const NoteReferencePicker({
    super.key,
    this.initialView,
    this.loadViews,
    this.loadBlocks,
  });
  final ViewPB? initialView;
  final Future<List<ViewPB>> Function()? loadViews;
  final Future<List<Node>> Function(ViewPB view)? loadBlocks;
  @override
  State<NoteReferencePicker> createState() => _NoteReferencePickerState();
}

class _NoteReferencePickerState extends State<NoteReferencePicker> {
  final _search = TextEditingController();
  List<ViewPB> _views = [];
  List<Node> _blocks = [];
  ViewPB? _view;
  bool _loading = true;
  bool _error = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _view = widget.initialView;
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      if (_view == null && widget.loadViews != null) {
        _views = await widget.loadViews!();
      } else if (_view != null && widget.loadBlocks != null) {
        final blocks = await widget.loadBlocks!(_view!);
        if (!mounted || generation != _generation) return;
        _blocks = blocks;
      } else if (_view == null) {
        final result = await ViewBackendService.getAllViews();
        _views = result.fold(
          (value) => value.items
              .where((view) => view.layout == ViewLayoutPB.Document)
              .toList(),
          (error) => throw StateError(error.msg),
        );
      } else {
        final result =
            await DocumentService().getDocument(documentId: _view!.id);
        if (!mounted || generation != _generation) return;
        final data = result.fold(
          (value) => value,
          (error) => throw StateError(error.msg),
        );
        final root = data.buildNode(data.pageId);
        final blocks = <Node>[];
        void walk(Node node) {
          if (node != root && noteBlockText(node).isNotEmpty) blocks.add(node);
          for (final child in node.children) {
            walk(child);
          }
        }

        if (root != null) walk(root);
        _blocks = blocks;
      }
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    String text(String zh, String en) => referenceText(context, zh, en);
    final query = _search.text.trim().toLowerCase();
    final views = _views
        .where((view) => view.name.toLowerCase().contains(query))
        .toList();
    final blocks = _blocks
        .where((node) => noteBlockText(node).toLowerCase().contains(query))
        .toList();
    return Dialog(
      child: SizedBox(
        width: 560,
        height: MediaQuery.sizeOf(context).height * .65,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: _view == null
                  ? const Icon(Icons.format_quote)
                  : IconButton(
                      tooltip: text('选择其他笔记', 'Choose another note'),
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () {
                        setState(() {
                          _view = null;
                          _search.clear();
                        });
                        _load();
                      },
                    ),
              title: Text(
                _view == null
                    ? text('引用段落', 'Reference a paragraph')
                    : _view!.name,
              ),
              subtitle: Text(
                text(
                  '选择内容片段，引用来源会自动关联',
                  'Choose a passage. Backlinks appear automatically.',
                ),
              ),
              trailing: IconButton(
                tooltip: text('关闭', 'Close'),
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _search,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: _view == null
                      ? text('搜索笔记', 'Search notes')
                      : text('搜索此笔记的段落', 'Search passages in this note'),
                ),
              ),
            ),
            if (_view != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => Navigator.pop(
                    context,
                    NoteReferenceTarget(_view!.id, null),
                  ),
                  icon: const Icon(Icons.article_outlined, size: 18),
                  label: Text(text('引用整篇笔记', 'Link to the whole note')),
                ),
              ),
            if (_loading) const LinearProgressIndicator(),
            Expanded(
              child: _error
                  ? Center(
                      child: TextButton(
                        onPressed: _load,
                        child: Text(
                          text(
                            '内容读取失败，点击重试',
                            'Could not load content. Retry',
                          ),
                        ),
                      ),
                    )
                  : _loading
                      ? const SizedBox.shrink()
                      : (_view == null ? views.isEmpty : blocks.isEmpty)
                          ? Center(
                              child: Text(
                                text('没有找到可引用的内容', 'No matching content'),
                              ),
                            )
                          : ListView.builder(
                              itemCount:
                                  _view == null ? views.length : blocks.length,
                              itemBuilder: (context, index) => _view == null
                                  ? ListTile(
                                      leading:
                                          const Icon(Icons.article_outlined),
                                      title: Text(
                                        views[index].name.isEmpty
                                            ? text('未命名', 'Untitled')
                                            : views[index].name,
                                      ),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () {
                                        setState(() {
                                          _view = views[index];
                                          _search.clear();
                                        });
                                        _load();
                                      },
                                    )
                                  : ListTile(
                                      leading: const Icon(Icons.format_quote),
                                      title: Text(
                                        noteBlockText(blocks[index]),
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      onTap: () => Navigator.pop(
                                        context,
                                        NoteReferenceTarget(
                                          _view!.id,
                                          blocks[index].id,
                                        ),
                                      ),
                                    ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
