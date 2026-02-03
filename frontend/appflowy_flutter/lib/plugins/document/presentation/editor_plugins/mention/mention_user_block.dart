import 'package:appflowy/plugins/document/presentation/editor_plugins/mention/mention_block.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// 用于显示@用户提及的内联组件
/// Widget that displays a user mention in a document
class MentionUserBlock extends StatelessWidget {
  const MentionUserBlock({
    super.key,
    required this.editorState,
    required this.userId,
    required this.userName,
    this.avatarUrl,
    required this.node,
    required this.index,
    this.textStyle,
  });

  final EditorState editorState;
  final String userId;
  final String userName;
  final String? avatarUrl;
  final Node node;
  final int index;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => _onTap(context),
        child: _buildUserMention(context),
      ),
    );
  }

  Widget _buildUserMention(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.blue.withOpacity(0.2)
            : Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildAvatar(),
          const SizedBox(width: 4),
          Text(
            '@$userName',
            style: textStyle?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ) ??
                TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    final initial = userName.isNotEmpty ? userName[0].toUpperCase() : '?';

    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 8,
        backgroundImage: NetworkImage(avatarUrl!),
        backgroundColor: Colors.grey[300],
      );
    }

    return CircleAvatar(
      radius: 8,
      backgroundColor: Colors.blue[400],
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 8,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _onTap(BuildContext context) {
    // TODO: Show user profile popover or navigate to user page
    // For now, just select the mention block
    final selection = Selection.single(
      path: node.path,
      startOffset: index,
      endOffset: index + 1,
    );
    editorState.updateSelectionWithReason(selection);
  }
}
