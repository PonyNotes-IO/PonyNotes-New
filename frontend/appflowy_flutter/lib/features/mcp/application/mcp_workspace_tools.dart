part of 'mcp_tools.dart';

extension _McpWorkspaceTools on McpTools {
  List<McpToolSpec> get _workspaceSpecs => [
        _actionTool(
          'manage_workspace',
          '读取/修改工作区设置、名称与图标，退出或删除工作区。危险操作由客户端确认。',
          {
            'name': const JsonString(),
            'icon': const JsonString(),
            'settings': const JsonObject(),
          },
          [
            'update_workspace',
            'get_workspace_settings',
            'update_workspace_settings',
            'leave_workspace',
            'delete_workspace',
          ],
          _manageWorkspace,
        ),
        _actionTool(
          'workspace_members',
          '读取成员、邀请、修改角色、移除成员和团队ACL。管理操作需要所有者权限及客户端确认。',
          {
            'email': const JsonString(),
            'user_id': const JsonString(),
            'role': const JsonString(enumValues: ['owner', 'member', 'guest']),
            'team_id': const JsonString(),
            'acl': const JsonObject(),
          },
          [
            'list_workspace_members',
            'invite_workspace_member',
            'update_workspace_member',
            'remove_workspace_member',
            'get_team_permissions',
            'update_team_permissions',
          ],
          _workspaceMembers,
        ),
        _actionTool(
          'workspace_invitations',
          '读取邀请、接受邀请或用邀请码加入工作区。',
          {
            'invite_id': const JsonString(),
            'invite_code': const JsonString(),
          },
          [
            'list_workspace_invitations',
            'accept_workspace_invitation',
            'join_workspace',
          ],
          _workspaceInvitations,
        ),
        _actionTool(
          'create_view',
          '创建文档、数据库、白板或问AI页面。',
          {
            'parent_id': const JsonString(),
            'title': const JsonString(),
            'layout': const JsonString(
              enumValues: [
                'document',
                'grid',
                'board',
                'calendar',
                'whiteboard',
                'chat',
                'handwriting',
              ],
            ),
          },
          [],
          _createViewTool,
          required: const ['workspace_id', 'parent_id', 'title', 'layout'],
        ),
        _actionTool(
          'page_properties',
          '修改页面样式、图标、锁定、收藏或可见性。',
          {
            'page_id': const JsonString(),
            'name': const JsonString(),
            'icon': const JsonString(),
            'icon_type': const JsonString(enumValues: ['emoji', 'url', 'icon']),
            'cover': const JsonObject(
              properties: {
                'type': JsonString(
                  enumValues: [
                    'none',
                    'color',
                    'gradient',
                    'built_in',
                    'custom',
                    'unsplash',
                  ],
                ),
                'value': JsonString(),
              },
              required: ['type', 'value'],
              additionalProperties: false,
            ),
            'cover_position': const JsonNumber(),
            'style': const JsonObject(
              properties: {
                'font': JsonString(),
                'font_layout':
                    JsonString(enumValues: ['small', 'normal', 'large']),
                'line_height_layout':
                    JsonString(enumValues: ['small', 'normal', 'large']),
              },
              additionalProperties: false,
            ),
            'locked': const JsonBoolean(),
            'favorite': const JsonBoolean(),
            'visibility': const JsonString(enumValues: ['public', 'private']),
          },
          [
            'update_page_properties',
            'set_page_locked',
            'set_page_favorite',
            'set_page_visibility',
          ],
          _pageProperties,
          required: const ['workspace_id', 'action', 'page_id'],
        ),
        _actionTool(
          'trash_actions',
          '恢复全部/指定回收站项目或永久删除，永久删除由客户端确认。',
          {
            'page_ids': const JsonArray(items: JsonString()),
            'all': const JsonBoolean(),
          },
          ['restore_trash', 'purge_trash'],
          _trashActions,
        ),
        _actionTool(
          'view_navigation',
          '列出私有/共享视图、祖先路径，打开视图或生成内部链接。',
          {
            'view_id': const JsonString(),
            'page_id': const JsonString(),
            'block_id': const JsonString(),
            'section':
                const JsonString(enumValues: ['all', 'private', 'shared']),
            'ancestor_of': const JsonString(),
            'offset': const JsonInteger(minimum: 0),
            'limit': const JsonInteger(minimum: 1, maximum: 500),
          },
          ['open_view', 'list_views', 'get_view_link'],
          _viewNavigation,
        ),
      ];

  Future<CallToolResult> _manageWorkspace(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id');
    final action = _requiredString(args, 'action');
    final check = action == 'get_workspace_settings'
        ? await _validateWorkspace(workspace)
        : await _requireOwner(workspace);
    if (check != null) return check;
    final profile = (await _currentProfile())!;
    final service = UserBackendService(userId: profile.id);
    if (action == 'get_workspace_settings') {
      return _message(
        await UserEventGetWorkspaceSetting(
          UserWorkspaceIdPB(workspaceId: workspace),
        ).send().getOrThrow(),
      );
    }
    if (!await _confirm('manage_workspace', args)) {
      return _error('permission_denied', '用户未批准操作。');
    }
    switch (action) {
      case 'update_workspace':
        if (args['name'] == null && args['icon'] == null) {
          throw const FormatException('需要name或icon');
        }
        if (args['name'] != null) {
          await service
              .renameWorkspace(workspace, _requiredString(args, 'name'))
              .getOrThrow();
        }
        if (args['icon'] != null) {
          await service
              .updateWorkspaceIcon(workspace, args['icon'] as String)
              .getOrThrow();
        }
      case 'update_workspace_settings':
        final data = UpdateUserWorkspaceSettingPB()
          ..mergeFromProto3Json(_object(args, 'settings'));
        data.workspaceId = workspace;
        await UserEventUpdateWorkspaceSetting(data).send().getOrThrow();
      case 'leave_workspace':
        await service.leaveWorkspace(workspace).getOrThrow();
      case 'delete_workspace':
        await service.deleteWorkspaceById(workspace).getOrThrow();
    }
    return _ok(
      {'workspace_id': workspace, 'action': action, 'completed': true},
    );
  }

  Future<CallToolResult> _workspaceMembers(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id'),
        action = _requiredString(args, 'action');
    final read = const ['list_workspace_members', 'get_team_permissions']
        .contains(action);
    final check = read
        ? await _validateWorkspace(workspace)
        : await _requireOwner(workspace);
    if (check != null) return check;
    final service = UserBackendService(userId: (await _currentProfile())!.id);
    if (action == 'list_workspace_members') {
      return _message(
        await service.getWorkspaceMembers(workspace).getOrThrow(),
      );
    }
    if (action == 'get_team_permissions') {
      return _message(
        await service.getTeamACL(_requiredString(args, 'team_id')).getOrThrow(),
      );
    }
    if (!await _confirm('workspace_members', args)) {
      return _error('permission_denied', '用户未批准成员管理。');
    }
    final role = switch (args['role']) {
      'owner' => AFRolePB.Owner,
      'guest' => AFRolePB.Guest,
      _ => AFRolePB.Member
    };
    switch (action) {
      case 'invite_workspace_member':
        await service
            .inviteWorkspaceMember(
              workspace,
              _requiredString(args, 'email'),
              role: role,
            )
            .getOrThrow();
      case 'update_workspace_member':
        await service
            .updateWorkspaceMember(
              workspace,
              _requiredString(args, 'email'),
              role,
            )
            .getOrThrow();
      case 'remove_workspace_member':
        await service
            .removeWorkspaceMember(
              workspace,
              args['email'] as String? ?? _requiredString(args, 'user_id'),
            )
            .getOrThrow();
      case 'update_team_permissions':
        final acl = TeamACLPB()..mergeFromProto3Json(_object(args, 'acl'));
        acl.teamId = _requiredString(args, 'team_id');
        await service.updateTeamACL(acl).getOrThrow();
    }
    return _ok({'completed': true, 'action': action});
  }

  Future<CallToolResult> _workspaceInvitations(
    Map<String, dynamic> args,
  ) async {
    final workspace = _requiredString(args, 'workspace_id');
    final check = await _validateWorkspace(workspace);
    if (check != null) return check;
    final action = _requiredString(args, 'action');
    if (action == 'list_workspace_invitations') {
      return _message(
        await UserEventListWorkspaceInvitations().send().getOrThrow(),
      );
    }
    if (!await _confirm('workspace_invitations', args)) {
      return _error('permission_denied', '用户未批准加入工作区。');
    }
    if (action == 'accept_workspace_invitation') {
      await UserEventAcceptWorkspaceInvitation(
        AcceptWorkspaceInvitationPB(
          inviteId: _requiredString(args, 'invite_id'),
        ),
      ).send().getOrThrow();
    } else {
      return _joinWorkspaceByCode(args);
    }
    return _ok({'completed': true});
  }

  Future<CallToolResult> _createViewTool(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id');
    final parent = await _scopedView(
      workspace,
      _requiredString(args, 'parent_id'),
      write: true,
    );
    if (!parent.isSpace && parent.layout != ViewLayoutPB.Document) {
      throw const FormatException('父级须为空间或文档');
    }
    final layout = switch (args['layout']) {
      'grid' => ViewLayoutPB.Grid,
      'board' => ViewLayoutPB.Board,
      'calendar' => ViewLayoutPB.Calendar,
      'whiteboard' => ViewLayoutPB.Whiteboard,
      'chat' => ViewLayoutPB.Chat,
      _ => ViewLayoutPB.Document
    };
    final view = await ViewBackendService.createView(
      parentViewId: parent.id,
      name: _requiredString(args, 'title'),
      layoutType: layout,
      openAfterCreate: false,
      extra: args['layout'] == 'handwriting'
          ? jsonEncode({'view_type': 'handwriting_saber'})
          : null,
    ).getOrThrow();
    return _ok({'page': _viewToJson(view)});
  }

  Future<CallToolResult> _pageProperties(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id'),
        id = _requiredString(args, 'page_id');
    final action = _requiredString(args, 'action');
    final view = await _scopedView(
      workspace,
      id,
      write: action != 'set_page_locked' && action != 'set_page_favorite',
    );
    if (action == 'set_page_locked' || action == 'set_page_visibility') {
      final check = await _requireWriteAccess(workspace);
      if (check != null) return check;
    }
    switch (action) {
      case 'set_page_locked':
        if (args['locked'] is! bool) throw const FormatException('需要locked');
        if (args['locked'] == true) {
          await ViewBackendService.lockView(id).getOrThrow();
        } else {
          await ViewBackendService.unlockView(id).getOrThrow();
        }
      case 'set_page_favorite':
        if (args['favorite'] is! bool) {
          throw const FormatException('需要favorite');
        }
        await ViewBackendService.updateView(
          viewId: id,
          isFavorite: args['favorite'] as bool,
        ).getOrThrow();
      case 'set_page_visibility':
        if (!await _confirm('page_properties', args)) {
          return _error('permission_denied', '未批准可见性变更。');
        }
        await ViewBackendService.updateViewsVisibility(
          [view],
          args['visibility'] == 'public',
        ).getOrThrow();
      case 'update_page_properties':
        if (args.containsKey('cover_position')) {
          return _error('unsupported_capability', '当前页面封面协议未包含位置字段，未修改页面。');
        }
        final extra = view.extra.isEmpty
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(jsonDecode(view.extra) as Map);
        if (args['style'] != null) extra.addAll(_object(args, 'style'));
        if (args.containsKey('cover')) {
          extra[ViewExtKeys.coverKey] = args['cover'];
        }
        if (args['name'] != null || extra.isNotEmpty) {
          await ViewBackendService.updateView(
            viewId: id,
            name: args['name'] as String?,
            extra: jsonEncode(extra),
          ).getOrThrow();
        }
        if (args.containsKey('icon')) {
          await ViewBackendService.updateViewIcon(
            view: view,
            viewIcon: switch (args['icon_type']) {
              'url' => EmojiIconData.custom(args['icon'] as String),
              'icon' =>
                EmojiIconData(FlowyIconType.icon, args['icon'] as String),
              _ => EmojiIconData.emoji(args['icon'] as String),
            },
          ).getOrThrow();
        }
    }
    final fresh = await _view(id);
    return fresh == null
        ? _error('write_unconfirmed', '已提交，页面暂时无法读取。')
        : _ok({'page': _viewToJson(fresh)});
  }

  Future<CallToolResult> _trashActions(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id');
    final check = await _requireWriteAccess(workspace);
    if (check != null) return check;
    final trash = TrashService();
    final ids = (args['page_ids'] as List? ?? []).cast<String>();
    if (args['all'] != true && ids.isEmpty) {
      throw const FormatException('需要page_ids或all=true');
    }
    final known = (await trash.readTrash().getOrThrow())
        .items
        .map((item) => item.id)
        .toSet();
    if (ids.any((id) => !known.contains(id))) {
      return _error('not_found', '指定项目不在当前回收站。');
    }
    if (args['action'] == 'purge_trash') {
      if (!await _confirm('trash_actions', args)) {
        return _error('permission_denied', '未批准永久删除。');
      }
      if (args['all'] == true) {
        await trash.deleteAll().getOrThrow();
      } else {
        await trash.deleteViews(ids).getOrThrow();
      }
    } else {
      if (args['all'] == true) {
        await trash.restoreAll().getOrThrow();
      } else {
        for (final id in ids) {
          await TrashService.putback(id).getOrThrow();
        }
      }
    }
    return _ok({
      'completed': true,
      'remaining': (await trash.readTrash().getOrThrow()).items.length,
    });
  }

  Future<CallToolResult> _viewNavigation(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id');
    final check = await _validateWorkspace(workspace);
    if (check != null) return check;
    final action = _requiredString(args, 'action');
    if (action == 'list_views') {
      if (args['ancestor_of'] != null) {
        await _scopedView(workspace, args['ancestor_of'] as String);
        return _message(
          await ViewBackendService.getViewAncestors(
            args['ancestor_of'] as String,
          ).getOrThrow(),
        );
      }
      if (args['section'] == 'shared') {
        return _message(await FolderEventGetSharedViews().send().getOrThrow());
      }
      final views = args['section'] == 'private'
          ? await FolderEventReadPrivateViews(
              GetWorkspaceViewPB(value: workspace),
            ).send().getOrThrow()
          : await ViewBackendService.getAllViews().getOrThrow();
      final offset = _intArg(args, 'offset', 0, 0, 0x7fffffff),
          limit = _intArg(args, 'limit', 100, 1, 500);
      return _ok({
        'views': views.items.skip(offset).take(limit).map(_viewToJson).toList(),
        'total': views.items.length,
      });
    }
    final id = args['view_id'] as String? ?? _requiredString(args, 'page_id');
    final view = await _scopedView(workspace, id);
    if (action == 'get_view_link') {
      return _ok({
        'url': Uri(
          scheme: 'ponynotes',
          host: 'open',
          queryParameters: {
            'viewId': id,
            'workspaceId': workspace,
            if (args['block_id'] != null) 'blockId': args['block_id'] as String,
          },
        ).toString(),
      });
    }
    if (!getIt.isRegistered<TabsBloc>()) {
      return _error('ui_unavailable', '当前没有可用的工作区窗口。');
    }
    final block = args['block_id'] as String?;
    if (block != null) NoteBlockNavigation.request(id, block);
    getIt<TabsBloc>().openPlugin(
      view,
      arguments: {if (block != null) PluginArgumentKeys.blockId: block},
    );
    return _ok({'opened': id});
  }
}
