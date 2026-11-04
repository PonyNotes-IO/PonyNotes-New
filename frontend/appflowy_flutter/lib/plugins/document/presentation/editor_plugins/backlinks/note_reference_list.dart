import 'package:appflowy/plugins/document/application/note_link_data.dart';
import 'package:appflowy/plugins/document/application/note_relations_controller.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/backlinks/note_reference_picker.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/mention/mention_page_block.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:flutter/material.dart';

/// Group by note, then expose each passage as a separate navigation destination.
class NoteReferenceList extends StatelessWidget {
  const NoteReferenceList({
    super.key,
    required this.controller,
    required this.links,
    this.incoming = true,
    this.navigationContext,
    this.beforeOpen,
  });
  final NoteRelationsController controller;
  final List<NoteLinkPB> links;
  final bool incoming;
  final BuildContext? navigationContext;
  final VoidCallback? beforeOpen;

  @override
  Widget build(BuildContext context) {
    final groups = groupNoteLinks(links, incoming: incoming);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in groups.entries)
          _NoteReferenceGroup(
            controller: controller,
            links: group.value,
            incoming: incoming,
            navigationContext: navigationContext,
            beforeOpen: beforeOpen,
          ),
      ],
    );
  }
}

class _NoteReferenceGroup extends StatelessWidget {
  const _NoteReferenceGroup({
    required this.controller,
    required this.links,
    required this.incoming,
    this.navigationContext,
    this.beforeOpen,
  });
  final NoteRelationsController controller;
  final List<NoteLinkPB> links;
  final bool incoming;
  final BuildContext? navigationContext;
  final VoidCallback? beforeOpen;

  @override
  Widget build(BuildContext context) {
    final link = links.first;
    final id = incoming ? link.srcPageId : link.dstPageId;
    final view = controller.views[id];
    final title = view == null
        ? referenceText(context, '笔记暂不可用', 'Note unavailable')
        : view.name.isEmpty
            ? referenceText(context, '未命名', 'Untitled')
            : view.name;
    final count = noteLinkOccurrences(links);
    final space = controller.spaceName(id);
    final subtitle = [
      if (space != null && space.isNotEmpty) space,
      referenceText(context, '$count 处引用', '$count references'),
    ].join(' · ');
    if (links.length == 1) {
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: const Icon(Icons.format_quote, size: 20),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle, style: Theme.of(context).textTheme.labelSmall),
            _excerpt(context, link),
          ],
        ),
        enabled: view != null,
        onTap: view == null ? null : () => _open(context, link),
      );
    }
    return ExpansionTile(
      key: PageStorageKey('references/$incoming/$id'),
      leading: const Icon(Icons.format_quote, size: 20),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle),
      children: [
        for (final reference in links)
          ListTile(
            contentPadding:
                const EdgeInsetsDirectional.only(start: 52, end: 16),
            title: _excerpt(context, reference),
            trailing: const Icon(Icons.north_east, size: 16),
            onTap: view == null ? null : () => _open(context, reference),
          ),
      ],
    );
  }

  Widget _excerpt(BuildContext context, NoteLinkPB link) {
    final id = incoming ? link.srcPageId : link.dstPageId;
    final block = incoming ? link.srcBlockId : link.dstBlockId;
    if (block.isEmpty) {
      return Text(referenceText(context, '整篇笔记', 'Whole note'));
    }
    return FutureBuilder<String>(
      future:
          controller.excerpt(id, block, offset: incoming ? link.charOffset : 0),
      builder: (context, snapshot) => Text(
        snapshot.data?.isNotEmpty == true
            ? snapshot.data!
            : referenceText(context, '查看引用段落', 'Open referenced passage'),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  void _open(BuildContext context, NoteLinkPB link) {
    final id = incoming ? link.srcPageId : link.dstPageId;
    final block = incoming ? link.srcBlockId : link.dstBlockId;
    final view = controller.views[id];
    if (view == null) return;
    final navigation = navigationContext ?? context;
    beforeOpen?.call();
    handleMentionBlockTap(
      navigation,
      controller.editorState,
      view,
      blockId: block.isEmpty ? null : block,
    );
  }
}

Future<void> showBlockReferenceSources(
  BuildContext context,
  NoteRelationsController controller,
  String blockId,
) =>
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: controller,
        builder: (dialogContext, _) {
          final links = controller.incomingTo(blockId);
          final count = groupNoteLinks(links, incoming: true).length;
          return Dialog(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 560,
                maxHeight: MediaQuery.sizeOf(context).height * .65,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text(
                      referenceText(
                        context,
                        '引用此段落 · $count 篇笔记',
                        'References to this passage · $count notes',
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: referenceText(context, '关闭', 'Close'),
                      onPressed: () => Navigator.pop(dialogContext),
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: SingleChildScrollView(
                      child: links.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                referenceText(
                                  context,
                                  '暂无引用',
                                  'No references',
                                ),
                              ),
                            )
                          : NoteReferenceList(
                              controller: controller,
                              links: links,
                              navigationContext: context,
                              beforeOpen: () => Navigator.pop(dialogContext),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
