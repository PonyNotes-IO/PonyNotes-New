import 'dart:async';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/plugins/document/application/note_link_data.dart';
import 'package:appflowy/plugins/document/application/note_link_service.dart';
import 'package:appflowy/plugins/document/application/note_relations_controller.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/mention/mention_block.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/mention/mention_page_block.dart';
import 'package:appflowy/plugins/knowledge_graph/knowledge_graph_plugin.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';

import 'note_reference_list.dart';
import 'note_reference_picker.dart';

export 'package:appflowy/plugins/document/application/note_link_data.dart'
    show editorOutgoingLinks;

class BacklinkPanel extends StatefulWidget {
  const BacklinkPanel({
    super.key,
    required this.pageId,
    required this.editorState,
    required this.editable,
  });
  final String pageId;
  final EditorState editorState;
  final bool editable;
  @override
  State<BacklinkPanel> createState() => _BacklinkPanelState();
}

class _BacklinkPanelState extends State<BacklinkPanel> {
  bool _outgoing = false;
  bool _showAll = false;
  bool _showUnresolved = false;
  List<NoteLinkPB>? _unlinked;
  final _unlinkedContexts = <String, String>{};
  bool _searchingUnlinked = false;
  bool _unlinkedError = false;
  NoteRelationsController? get _controller =>
      context.read<NoteRelationsController?>();
  Map<String, ViewPB> get _views => _controller?.views ?? {};
  DocumentLinksPB? get _links => _controller?.links;
  String text(String zh, String en) => referenceText(context, zh, en);
  Future<void> _load() async => _controller?.refresh();

  Future<void> _searchUnlinked() async {
    if (_searchingUnlinked) return;
    final title = _views[widget.pageId]?.name.trim();
    if (title == null || title.isEmpty) return;
    setState(() {
      _searchingUnlinked = true;
      _unlinkedError = false;
    });
    final excluded = {
      widget.pageId,
      ...?_links?.incoming.map((link) => link.srcPageId),
    };
    try {
      final candidates = await NoteLinkService.findLocalCandidates(title)
          .timeout(const Duration(seconds: 10));
      final matches = <NoteLinkPB>[];
      for (final id in candidates
          .where((id) => !excluded.contains(id) && _views.containsKey(id))) {
        if (!mounted) return;
        final document = await DocumentService().getDocument(documentId: id);
        final data = document.fold((data) => data, (_) => null);
        if (data == null) continue;
        final root = data.buildNode(data.pageId);
        Node? find(Node node) {
          if ((node.delta?.toPlainText().toLowerCase() ?? '')
              .contains(title.toLowerCase())) {
            return node;
          }
          for (final child in node.children) {
            final match = find(child);
            if (match != null) return match;
          }
          return null;
        }

        final node = root == null ? null : find(root);
        if (node == null) continue;
        matches.add(
          NoteLinkPB(
            srcPageId: id,
            srcBlockId: node.id,
            dstPageId: widget.pageId,
          ),
        );
        _unlinkedContexts['$id/${node.id}'] = String.fromCharCodes(
          (node.delta?.toPlainText() ?? '').runes.take(160),
        );
      }
      if (mounted) setState(() => _unlinked = matches);
    } catch (_) {
      if (mounted) setState(() => _unlinkedError = true);
    } finally {
      if (mounted) setState(() => _searchingUnlinked = false);
    }
  }

  Future<void> _resolve(UnresolvedNoteLinkPB link) async {
    final title = link.rawTitle.trim();
    final candidates = _views.values
        .where((view) => view.name.trim().toLowerCase() == title.toLowerCase())
        .toList();
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(text('链接到「$title」', 'Link to “$title”')),
        children: [
          for (final view in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, view.id),
              child: Text(
                '${view.name} · ${_views[view.parentViewId]?.name ?? text('笔记', 'Note')}',
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'create'),
            child: Text(text('创建笔记并链接', 'Create note and link')),
          ),
        ],
      ),
    );
    if (choice == null || !mounted || !widget.editable) return;
    // Re-read the live block; an asynchronous dialog must not overwrite intervening edits.
    Node? find(Node current) {
      if (current.id == link.srcBlockId) return current;
      for (final child in current.children) {
        final found = find(child);
        if (found != null) return found;
      }
      return null;
    }

    final node = find(widget.editorState.document.root);
    final plain = node?.delta?.toPlainText();
    if (node == null || plain == null) return;
    final pattern = RegExp(r'\[\[([^\]\n]+)\]\]');
    final matches = pattern
        .allMatches(plain)
        .where((match) => match.group(1)!.split('|').first.trim() == title)
        .toList();
    if (matches.isEmpty) return;
    final match = matches.first;
    try {
      var id = choice;
      if (choice == 'create') {
        final workspace = context.read<UserWorkspaceBloc>().state;
        final workspaceId = workspace.currentWorkspace?.workspaceId;
        if (workspaceId == null) return;
        final result = await ViewBackendService.createViewWithPermissionCheck(
          userId: workspace.userProfile.id.toInt(),
          workspaceId: workspaceId,
          layoutType: ViewLayoutPB.Document,
          parentViewId: widget.pageId,
          name: title,
          openAfterCreate: false,
        );
        id = result.fold(
          (view) => view.id,
          (error) => throw StateError(error.msg),
        );
      }
      if (!mounted) return;
      // The block can change while the new page is being created too.
      if (node.delta?.toPlainText() != plain) {
        unawaited(_load());
        return;
      }
      final transaction = widget.editorState.transaction
        ..replaceText(
          node,
          match.start,
          match.end - match.start,
          MentionBlockKeys.mentionChar,
          attributes: MentionBlockKeys.buildMentionPageAttributes(
            mentionType: MentionType.page,
            pageId: id,
            blockId: null,
          ),
        );
      await widget.editorState.apply(transaction);
      unawaited(_load());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              text('建立链接失败，请重试', 'Could not create link. Please retry.'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _discover() async {
    await _searchUnlinked();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: SizedBox(
          width: 560,
          height: MediaQuery.sizeOf(context).height * .6,
          child: Column(
            children: [
              ListTile(
                title: Text(
                  text('可能提到本文的笔记', 'Possible mentions of this note'),
                ),
                subtitle: Text(
                  text(
                    '以下是文字匹配，尚未建立引用关系',
                    'Text matches; these are not linked references',
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(dialogContext),
                ),
              ),
              Expanded(
                child: _unlinkedError
                    ? Center(
                        child: Text(
                          text(
                            '搜索失败，请稍后重试',
                            'Search failed. Please try again.',
                          ),
                        ),
                      )
                    : _unlinked?.isEmpty != false
                        ? Center(
                            child: Text(
                              text(
                                '未发现其他提及',
                                'No other mentions found',
                              ),
                            ),
                          )
                        : ListView(
                            children: [
                              for (final link in _unlinked!)
                                ListTile(
                                  title: Text(
                                    _views[link.srcPageId]?.name ?? '',
                                  ),
                                  subtitle: Text(
                                    _unlinkedContexts[
                                            '${link.srcPageId}/${link.srcBlockId}'] ??
                                        '',
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () {
                                    final view = _views[link.srcPageId];
                                    if (view == null) return;
                                    Navigator.pop(dialogContext);
                                    handleMentionBlockTap(
                                      context,
                                      widget.editorState,
                                      view,
                                      blockId: link.srcBlockId,
                                    );
                                  },
                                ),
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<NoteRelationsController?>();
    if (controller == null) return const SizedBox.shrink();
    final incoming = controller.incoming;
    final outgoing = controller.outgoing;
    final links = _outgoing ? outgoing : incoming;
    final groups = groupNoteLinks(links, incoming: !_outgoing);
    final visibleIds = groups.keys.take(_showAll ? groups.length : 5).toSet();
    final visible = links
        .where(
          (link) =>
              visibleIds.contains(_outgoing ? link.dstPageId : link.srcPageId),
        )
        .toList();
    final unresolved = controller.links?.unresolved ?? <UnresolvedNoteLinkPB>[];
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => setState(() {
                  _outgoing = false;
                  _showAll = false;
                }),
                style: TextButton.styleFrom(
                  foregroundColor:
                      _outgoing ? Theme.of(context).hintColor : null,
                ),
                child: Text(
                  text(
                    '引用此笔记 · ${groupNoteLinks(incoming, incoming: true).length} 篇',
                    'Backlinks · ${groupNoteLinks(incoming, incoming: true).length} notes',
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _outgoing = true;
                  _showAll = false;
                }),
                style: TextButton.styleFrom(
                  foregroundColor:
                      !_outgoing ? Theme.of(context).hintColor : null,
                ),
                child: Text(
                  text(
                    '本文引用 · ${groupNoteLinks(outgoing, incoming: false).length} 篇',
                    'Outgoing · ${groupNoteLinks(outgoing, incoming: false).length} notes',
                  ),
                ),
              ),
              if (context.read<TabsBloc?>() != null &&
                  controller.views.containsKey(widget.pageId))
                IconButton(
                  tooltip: text('查看局部图谱', 'Open local graph'),
                  icon: const Icon(Icons.hub_outlined, size: 18),
                  onPressed: () => context.read<TabsBloc>().add(
                        TabsEvent.openPlugin(
                          plugin: KnowledgeGraphPlugin(
                            focusView: controller.views[widget.pageId],
                          ),
                          view: controller.views[widget.pageId],
                        ),
                      ),
                ),
              PopupMenuButton<String>(
                tooltip: text('更多引用操作', 'More reference actions'),
                onSelected: (action) {
                  if (action == 'discover') {
                    _discover();
                  } else {
                    controller.refreshReferences();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'refresh',
                    child: Text(text('刷新引用', 'Refresh references')),
                  ),
                  PopupMenuItem(
                    value: 'discover',
                    enabled: !_searchingUnlinked,
                    child: Text(text('查找其他提及', 'Find other mentions')),
                  ),
                ],
              ),
            ],
          ),
          if (controller.loading) const LinearProgressIndicator(),
          if (controller.error)
            TextButton(
              onPressed: _load,
              child:
                  Text(text('引用读取失败，点击重试', 'Could not load references. Retry')),
            )
          else if (!controller.loading && links.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _outgoing
                    ? text(
                        '输入 [[ 或使用“引用段落”关联其他笔记',
                        'Type [[ or use “Reference a paragraph” to connect notes',
                      )
                    : text(
                        '其他笔记引用本文后，会自动出现在这里',
                        'References from other notes appear here automatically',
                      ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            NoteReferenceList(
              controller: controller,
              links: visible,
              incoming: !_outgoing,
            ),
          if (!_showAll && groups.length > 5)
            TextButton(
              onPressed: () => setState(() => _showAll = true),
              child: Text(
                text(
                  '查看全部 ${groups.length} 篇笔记',
                  'Show all ${groups.length} notes',
                ),
              ),
            ),
          if (controller.incomplete)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                text(
                  '部分笔记尚未同步，引用列表可能不完整',
                  'Some notes are not synced yet; references may be incomplete',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (controller.links?.truncated ?? false)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                text('引用较多，当前仅显示部分结果', 'Only some references are shown'),
              ),
            ),
          if (unresolved.isNotEmpty) ...[
            TextButton.icon(
              onPressed: () =>
                  setState(() => _showUnresolved = !_showUnresolved),
              icon: const Icon(Icons.add_link, size: 18),
              label: Text(
                text(
                  '完善 ${unresolved.length} 个待建立链接',
                  'Resolve ${unresolved.length} pending links',
                ),
              ),
            ),
            if (_showUnresolved)
              for (final link in unresolved)
                ListTile(
                  title: Text(link.rawTitle),
                  trailing: const Icon(Icons.add_link),
                  onTap: widget.editable ? () => _resolve(link) : null,
                ),
          ],
          if (widget.editable)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () =>
                    insertNoteReference(context, widget.editorState),
                icon: const Icon(Icons.format_quote, size: 18),
                label: Text(text('引用段落', 'Reference a paragraph')),
              ),
            ),
        ],
      ),
    );
  }
}
