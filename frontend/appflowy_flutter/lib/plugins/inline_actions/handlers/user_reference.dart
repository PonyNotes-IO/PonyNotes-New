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
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/user/user_workspace_bloc.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../env/cloud_env.dart';

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
  DateTime? _lastCacheTime;
  static const Duration _cacheExpiration = Duration(minutes: 1); // 缓存过期时间

  Future<List<WorkspaceMemberPB>> _getWorkspaceMembers() async {
    // 检查缓存是否过期
    final now = DateTime.now();
    final isCacheExpired = _lastCacheTime == null || 
        now.difference(_lastCacheTime!).compareTo(_cacheExpiration) > 0;
    
    if (_cachedMembers != null && _currentWorkspaceId != null && !isCacheExpired) {
      return _cachedMembers!;
    }
    
    // 缓存过期，重新获取成员列表
    Log.info('[InlineUserReference] Cache expired, refreshing workspace members');
    _cachedMembers = null;

    try {
      // 方法1：使用与人员管理相同的方式获取当前工作区ID
      final currentWorkspaceResult = await FolderEventReadCurrentWorkspace().send();
      String? workspaceId;
      currentWorkspaceResult.fold(
        (workspace) {
          workspaceId = workspace.id;
          Log.info('[InlineUserReference] Got current workspace ID: $workspaceId');
        },
        (failure) {
          Log.warn('[InlineUserReference] Failed to get current workspace: $failure');
        },
      );
      
      // 方法2：如果方法1失败，使用缓存的工作区ID
      if (workspaceId == null || workspaceId?.isEmpty == true) {
        workspaceId = _currentWorkspaceId;
        if (workspaceId != null && workspaceId?.isNotEmpty == true) {
          Log.info('[InlineUserReference] Using cached workspace ID: $workspaceId');
        }
      }
      
      if (workspaceId == null || workspaceId?.isEmpty == true) {
        Log.warn('[InlineUserReference] No workspace ID available');
        return [];
      }
      _currentWorkspaceId = workspaceId;

      // 获取当前用户信息
      final currentUserResult = await UserBackendService.getCurrentUserProfile();
      final currentUser = currentUserResult.fold(
        (user) => user,
        (_) => null,
      );
      if (currentUser == null) {
        Log.warn('[InlineUserReference] No current user');
        return [];
      }

      // Get current user to exclude from list
      final currentUserId = currentUser.id;

      // Get workspace members - 使用与人员管理相同的方式
      final membersRequest = QueryWorkspacePB()..workspaceId = _currentWorkspaceId!;
      final result = await UserEventGetWorkspaceMembers(membersRequest).send();

      return result.fold(
        (members) {
          // Get current user email
          final currentUserEmail = currentUser.name;
          
          // Always filter out current user if email is available
          if (currentUserEmail.isNotEmpty) {
            _cachedMembers = members.items
                .where((m) => m.name != currentUserEmail)
                .toList();
          } else {
            // If current user email is not available, use all members
            _cachedMembers = members.items;
          }
          Log.info('[InlineUserReference] Found ${_cachedMembers!.length} workspace members');
          _lastCacheTime = DateTime.now(); // 更新缓存时间
          return _cachedMembers!;
        },
        (error) {
          Log.error('[InlineUserReference] Failed to get workspace members: $error');
          return [];
        },
      );
    } catch (e) {
      Log.error('[InlineUserReference] Error getting workspace members: $e');
      return [];
    }
  }

  @override
  Future<void> dispose() async {
    _cachedMembers = null;
    _currentWorkspaceId = null;
    _lastCacheTime = null;
    await super.dispose();
  }
  
  /// 手动清除缓存，用于在邀请新成员后立即更新成员列表
  void clearCache() {
    _cachedMembers = null;
    _lastCacheTime = null;
    Log.info('[InlineUserReference] Cache cleared manually');
  }

  @override
  Future<InlineActionsResult> search([String? search, bool forceRefresh = false]) async {
    // 如果需要强制刷新，清除缓存
    if (forceRefresh) {
      clearCache();
    }
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

    // If no members found, add a placeholder item to ensure the @user section appears
    if (items.isEmpty) {
      items.add(InlineActionsMenuItem(
        keywords: [],
        label: LocaleKeys.inlineActions_noUsers.tr(),
        iconBuilder: (onSelected) => const SizedBox.shrink(),
        onSelected: (context, editorState, menu, replace) async {

        },
      ));
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
          userId: member.name, // Use email as unique identifier
          userName: member.name.isNotEmpty ? member.name : member.email,
          avatarUrl: member.avatarUrl,
        ),
      );

    await editorState.apply(transaction);

    // Trigger notification creation for the mentioned user
    await _triggerPageMentionNotification(
      workspaceId: _currentWorkspaceId ?? '',
      viewId: currentViewId,
      personId: member.name.toString(),
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

      // Get access token and normalize it
      final userResult = await UserBackendService.getCurrentUserProfile();
      final rawToken = userResult.fold(
        (user) => user.token,
        (error) {
          Log.error('[InlineUserReference] Failed to get user profile: $error');
          return '';
        },
      );

      // Normalize token: if it's a JSON string, extract access_token
      String token = rawToken;
      if (token.isNotEmpty && token.trim().startsWith('{')) {
        try {
          final map = jsonDecode(token);
          if (map is Map && map['access_token'] is String) {
            token = map['access_token'] as String;
          }
        } catch (e) {
          Log.warn('[InlineUserReference] Failed to normalize token: $e');
        }
      }

      if (token.isEmpty) {
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
          'Authorization': 'Bearer $token',
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

  String? _extractAccessToken(String? rawToken) {
    if (rawToken == null || rawToken.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(rawToken);
      if (decoded is Map<String, dynamic>) {
        final accessToken = decoded['access_token'] as String?;
        if (accessToken != null && accessToken.isNotEmpty) {
          return accessToken;
        }
      }
    } catch (_) {
      // 非 JSON，直接使用原始 token
      return rawToken;
    }
    return null;
  }
}
