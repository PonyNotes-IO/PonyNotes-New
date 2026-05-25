import 'package:appflowy/plugins/document/presentation/editor_plugins/mention/mention_date_block.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/mention/mention_page_block.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/mention/mention_user_block.dart';
import 'package:appflowy/workspace/presentation/widgets/date_picker/widgets/reminder_selector.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'mention_link_block.dart';

enum MentionType {
  page,
  date,
  externalLink,
  childPage,
  user;

  static MentionType fromString(String value) => switch (value) {
        'page' => page,
        'date' => date,
        'externalLink' => externalLink,
        'childPage' => childPage,
        'user' => user,
        // Backwards compatibility
        'reminder' => date,
        _ => throw UnimplementedError(),
      };
}

Node dateMentionNode() {
  return paragraphNode(
    delta: Delta(
      operations: [
        TextInsert(
          MentionBlockKeys.mentionChar,
          attributes: MentionBlockKeys.buildMentionDateAttributes(
            date: DateTime.now().toIso8601String(),
            reminderId: null,
            reminderOption: null,
            includeTime: false,
          ),
        ),
      ],
    ),
  );
}

class MentionBlockKeys {
  const MentionBlockKeys._();

  static const mention = 'mention';
  static const type = 'type'; // MentionType, String

  static const pageId = 'page_id';
  static const blockId = 'block_id';
  static const url = 'url';
  static const originalText = 'original_text'; // 原始文字，用于移除链接后恢复

  // Related to Reminder and Date blocks
  static const date = 'date'; // Start Date
  static const includeTime = 'include_time';
  static const reminderId = 'reminder_id'; // ReminderID
  static const reminderOption = 'reminder_option';

  // Related to User mention blocks
  static const userId = 'user_id'; // User email as identifier
  static const userName = 'user_name';
  static const avatarUrl = 'avatar_url';

  static const mentionChar = '\$';

  static Map<String, dynamic> buildMentionPageAttributes({
    required MentionType mentionType,
    required String pageId,
    required String? blockId,
  }) {
    return {
      MentionBlockKeys.mention: {
        MentionBlockKeys.type: mentionType.name,
        MentionBlockKeys.pageId: pageId,
        if (blockId != null) MentionBlockKeys.blockId: blockId,
      },
    };
  }

  static Map<String, dynamic> buildMentionDateAttributes({
    required String date,
    required String? reminderId,
    required String? reminderOption,
    required bool includeTime,
  }) {
    return {
      MentionBlockKeys.mention: {
        MentionBlockKeys.type: MentionType.date.name,
        MentionBlockKeys.date: date,
        MentionBlockKeys.includeTime: includeTime,
        if (reminderId != null) MentionBlockKeys.reminderId: reminderId,
        if (reminderOption != null)
          MentionBlockKeys.reminderOption: reminderOption,
      },
    };
  }

  /// Build attributes for @user mention
  static Map<String, dynamic> buildMentionUserAttributes({
    required String userId,
    required String userName,
    String? avatarUrl,
  }) {
    return {
      MentionBlockKeys.mention: {
        MentionBlockKeys.type: MentionType.user.name,
        MentionBlockKeys.userId: userId,
        MentionBlockKeys.userName: userName,
        if (avatarUrl != null && avatarUrl.isNotEmpty)
          MentionBlockKeys.avatarUrl: avatarUrl,
      },
    };
  }
}

class MentionBlock extends StatelessWidget {
  const MentionBlock({
    super.key,
    required this.mention,
    required this.node,
    required this.index,
    required this.textStyle,
  });

  final Map<String, dynamic> mention;
  final Node node;
  final int index;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final type = MentionType.fromString(mention[MentionBlockKeys.type]);
    final editorState = context.read<EditorState>();

    switch (type) {
      case MentionType.page:
        final String? pageId = mention[MentionBlockKeys.pageId] as String?;
        if (pageId == null) {
          return const SizedBox.shrink();
        }
        final String? blockId = mention[MentionBlockKeys.blockId] as String?;

        return MentionPageBlock(
          key: ValueKey(pageId),
          editorState: editorState,
          pageId: pageId,
          blockId: blockId,
          node: node,
          textStyle: textStyle,
          index: index,
        );
      case MentionType.childPage:
        final String? pageId = mention[MentionBlockKeys.pageId] as String?;
        if (pageId == null) {
          return const SizedBox.shrink();
        }

        return MentionSubPageBlock(
          key: ValueKey(pageId),
          editorState: editorState,
          pageId: pageId,
          node: node,
          textStyle: textStyle,
          index: index,
        );

      case MentionType.date:
        final String date = mention[MentionBlockKeys.date];
        final reminderOption = ReminderOption.values.firstWhereOrNull(
          (o) => o.name == mention[MentionBlockKeys.reminderOption],
        );

        return MentionDateBlock(
          key: ValueKey('${node.id}_${index}'),
          editorState: editorState,
          date: date,
          node: node,
          textStyle: textStyle,
          index: index,
          reminderId: mention[MentionBlockKeys.reminderId],
          reminderOption: reminderOption ?? ReminderOption.none,
          includeTime: mention[MentionBlockKeys.includeTime] ?? false,
        );
      case MentionType.externalLink:
        final String? url = mention[MentionBlockKeys.url] as String?;
        if (url == null) {
          return const SizedBox.shrink();
        }
        return MentionLinkBlock(
          url: url,
          editorState: editorState,
          node: node,
          index: index,
        );
      case MentionType.user:
        final String? userId = mention[MentionBlockKeys.userId] as String?;
        final String? userName = mention[MentionBlockKeys.userName] as String?;
        if (userId == null || userName == null) {
          return const SizedBox.shrink();
        }
        final String? avatarUrl =
            mention[MentionBlockKeys.avatarUrl] as String?;

        return MentionUserBlock(
          key: ValueKey(userId),
          editorState: editorState,
          userId: userId,
          userName: userName,
          avatarUrl: avatarUrl,
          node: node,
          index: index,
          textStyle: textStyle,
        );
    }
  }
}
