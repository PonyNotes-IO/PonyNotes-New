import 'package:appflowy/plugins/document/application/note_link_data.dart';
import 'package:appflowy/plugins/document/application/note_relations_controller.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/backlinks/note_reference_list.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/backlinks/note_reference_picker.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Preserve the editor's own selectable widget/key and decorate every nesting level.
class ReferencedBlockBuilder extends BlockComponentBuilder {
  ReferencedBlockBuilder(this.delegate)
      : super(configuration: delegate.configuration);
  final BlockComponentBuilder delegate;
  @override
  BlockComponentValidate get validate => delegate.validate;
  @override
  Position start(Node node) => delegate.start(node);
  @override
  Position end(Node node) => delegate.end(node);
  @override
  BlockComponentWidget build(BlockComponentContext context) => ReferencedBlock(
        node: context.node,
        configuration: delegate.configuration,
        child: delegate.build(context) as Widget,
      );
}

class ReferencedBlock extends BlockComponentStatelessWidget {
  const ReferencedBlock({
    super.key,
    required super.node,
    required super.configuration,
    required this.child,
  });
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<NoteRelationsController?>();
    if (controller == null) return child;
    final references = controller.incomingTo(node.id);
    final count = groupNoteLinks(references, incoming: true).length;
    final highlighted = controller.highlightedBlockId == node.id;
    final color = Theme.of(context).colorScheme.primary;
    return AnimatedContainer(
      key: ValueKey('referenced-block-${node.id}'),
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: highlighted ? color.withValues(alpha: .13) : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: child),
          if (count > 0)
            Tooltip(
              message: referenceText(
                context,
                '$count 篇笔记引用此段落',
                '$count notes reference this passage',
              ),
              child: TextButton.icon(
                key: ValueKey('block-reference-sources-${node.id}'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(36, 28),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () =>
                    showBlockReferenceSources(context, controller, node.id),
                icon: const Icon(Icons.format_quote, size: 14),
                label: Text('$count'),
              ),
            ),
        ],
      ),
    );
  }
}
