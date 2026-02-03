import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/mention/mention_block.dart';
import 'package:appflowy/plugins/inline_actions/inline_actions_menu.dart';
import 'package:appflowy/plugins/inline_actions/inline_actions_result.dart';
import 'package:appflowy/plugins/inline_actions/service_handler.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/user/user_workspace_bloc.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// 用于在文档中@用户的内联操作服务
/// InlineUserReferenceService allows users to mention other workspace members
/// in documents using the @ symbol.
class InlineUserReferenceService extends InlineActionsDelegate {
  InlineUserReferenceService({
    required this.currentViewId,
    this.limitResults = 10,
  }) : assert(limitResults > 0, 'limitResults must be greater than 0');

  final String currentViewId;
  final int limitResults;

  List<WorkspaceMemberPB>? _cachedMembers;
  String? _currentWorkspaceId;

  Future<List<WorkspaceMemberPB>> _getWorkspaceMembers() async {
    if (_cachedMembers != null && _currentWorkspaceId != null) {
      return _cachedMembers!;
    }

    try {
      // Get current workspace ID
      final workspaceBloc = getIt<UserWorkspaceBloc>();
      final currentWorkspace = workspaceBloc.state.currentWorkspace;
      if (currentWorkspace == null) {
        return [];
      }
      _currentWorkspaceId = currentWorkspace.workspaceId;

      // Get current user to exclude from list
      final currentUserResult =
          await UserBackendService.getCurrentUserProfile();
      final currentUserId = currentUserResult.fold(
        (user) => user.id,
        (_) => null,
      );

      // Get workspace members
      final userService = UserBackendService(userId: currentUserId ?? Int64(0));
      final result =
          await userService.getWorkspaceMembers(_currentWorkspaceId!);

      return result.fold(
        (members) {
          // Filter out current user
          _cachedMembers = members.items
              .where((m) =>
                  currentUserId == null ||
                  m.email != currentUserResult.fold((u) => u.email, (_) => ''))
              .toList();
          return _cachedMembers!;
        },
        (_) => [],
      );
    } catch (e) {
      return [];
    }
  }

  @override
  Future<void> dispose() async {
    _cachedMembers = null;
    _currentWorkspaceId = null;
    await super.dispose();
  }

  @override
  Future<InlineActionsResult> search([String? search]) async {
    final members = await _getWorkspaceMembers();

    List<InlineActionsMenuItem> items;
    if (search != null && search.isNotEmpty) {
      final searchLower = search.toLowerCase();
      items = members
          .where((member) =>
              member.name.toLowerCase().contains(searchLower) ||
              member.email.toLowerCase().contains(searchLower))
          .take(limitResults)
          .map(_fromMember)
          .toList();
    } else {
      items = members.take(limitResults).map(_fromMember).toList();
    }

    return InlineActionsResult(
      title: LocaleKeys.inlineActions_mentionUser.tr(),
      results: items,
    );
  }

  InlineActionsMenuItem _fromMember(WorkspaceMemberPB member) {
    return InlineActionsMenuItem(
      keywords: [
        member.name.toLowerCase(),
        member.email.toLowerCase(),
      ],
      label: member.name.isNotEmpty ? member.name : member.email,
      iconBuilder: (onSelected) {
        // Build avatar icon
        return _buildAvatarWidget(member);
      },
      onSelected: (context, editorState, menu, replace) =>
          _onInsertUserMention(member, context, editorState, menu, replace),
    );
  }

  Widget _buildAvatarWidget(WorkspaceMemberPB member) {
    final name = member.name.isNotEmpty ? member.name : member.email;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    // If has avatar URL, show network image
    if (member.avatarUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 10,
        backgroundImage: NetworkImage(member.avatarUrl),
        backgroundColor: Colors.grey[300],
      );
    }

    // Otherwise show initial letter
    return CircleAvatar(
      radius: 10,
      backgroundColor: Colors.blue[400],
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 10,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Future<void> _onInsertUserMention(
    WorkspaceMemberPB member,
    BuildContext context,
    EditorState editorState,
    InlineActionsMenuService menuService,
    (int, int) replace,
  ) async {
    final selection = editorState.selection;
    if (selection == null || !selection.isCollapsed) {
      return;
    }

    final node = editorState.getNodeAtPath(selection.start.path);
    final delta = node?.delta;
    if (node == null || delta == null) {
      return;
    }

    // Get block ID for the mention
    final blockId = node.id;

    // Insert @user mention block
    final transaction = editorState.transaction
      ..replaceText(
        node,
        replace.$1,
        replace.$2,
        MentionBlockKeys.mentionChar,
        attributes: MentionBlockKeys.buildMentionUserAttributes(
          userId: member.email, // Use email as unique identifier
          userName: member.name.isNotEmpty ? member.name : member.email,
          avatarUrl: member.avatarUrl,
        ),
      );

    await editorState.apply(transaction);

    // Trigger notification creation for the mentioned user
    await _triggerPageMentionNotification(
      workspaceId: _currentWorkspaceId ?? '',
      viewId: currentViewId,
      personId: member.id.toString(),
      blockId: blockId,
      viewName: node.attributes['name'] ?? 'Untitled',
    );
  }

  /// 调用 update_page_mention API 创建提及通知
  /// Calls the update_page_mention API to create a mention notification
  Future<void> _triggerPageMentionNotification({
    required String workspaceId,
    required String viewId,
    required String personId,
    required String blockId,
    required String viewName,
  }) async {
    if (workspaceId.isEmpty || personId.isEmpty) {
      Log.warn('[InlineUserReference] Cannot trigger mention notification: missing workspaceId or personId');
      return;
    }

    try {
      // Get server URL from configuration
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;

      if (baseUrl.isEmpty) {
        Log.warn('[InlineUserReference] Cannot trigger mention notification: baseUrl is empty');
        return;
      }

      // Get access token
      final userResult = await UserBackendService.getCurrentUserProfile();
      final rawToken = userResult.fold(
        (user) => user.token,
        (error) {
          Log.error('[InlineUserReference] Failed to get user profile: $error');
          return '';
        },
      );

      if (rawToken.isEmpty) {
        Log.warn('[InlineUserReference] Cannot trigger mention notification: token is empty');
        return;
      }

      // Make API call
      final uri = Uri.parse('$baseUrl/api/workspace/$workspaceId/page-view/$viewId/page-mention');
      
      final body = jsonEncode({
        'person_id': personId,
        'block_id': blockId,
        'view_name': viewName,
        'require_notification': true,
      });

      final response = await http.put(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $rawToken',
        },
        body: body,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        Log.info('[InlineUserReference] Successfully triggered mention notification for person: $personId');
      } else {
        Log.error('[InlineUserReference] Failed to trigger mention notification: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      Log.error('[InlineUserReference] Error triggering mention notification: $e');
    }
  }
}
