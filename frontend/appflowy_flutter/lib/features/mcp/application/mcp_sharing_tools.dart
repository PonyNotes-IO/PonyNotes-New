part of 'mcp_tools.dart';

extension _McpSharingTools on McpTools {
  Future<CallToolResult> _sharingCloud(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id'),
        action = _requiredString(args, 'action');
    final check = await _validateWorkspace(workspace);
    if (check != null) return check;
    final page = args['page_id'] as String?;
    final base = '/api/workspace/${Uri.encodeComponent(workspace)}';
    if (action == 'request_resource_access') {
      return _ok(
        await _cloudRequest(
          'POST',
          '/api/access-request',
          body: {
            'workspace_id': workspace,
            'view_id': _requiredString(args, 'page_id'),
          },
        ),
      );
    }
    if (action == 'manage_access_requests') {
      final operation = _requiredString(args, 'operation');
      final id = args['request_id'] as String?;
      if (page != null) {
        final endpoint =
            '$base/spaces/${Uri.encodeComponent(page)}/join-requests';
        if (operation == 'list') {
          return _ok(await _cloudRequest('GET', endpoint));
        }
        if (!await _confirm('page_sharing', args)) {
          return _error('permission_denied', '未批准处理空间访问申请。');
        }
        if (operation == 'cancel') {
          return _ok(await _cloudRequest('DELETE', endpoint));
        }
        return _ok(
          await _cloudRequest(
            'POST',
            '$endpoint/${Uri.encodeComponent(_requiredString(args, 'request_id'))}',
            body: {'approve': args['decision'] == true},
          ),
        );
      }
      if (id == null) throw const FormatException('需要request_id');
      if (operation == 'get') {
        return _ok(
          await _cloudRequest(
            'GET',
            '/api/access-request/${Uri.encodeComponent(id)}',
          ),
        );
      }
      if (!await _confirm('page_sharing', args)) {
        return _error('permission_denied', '未批准处理访问申请。');
      }
      return _ok(
        await _cloudRequest(
          'POST',
          '/api/access-request/${Uri.encodeComponent(id)}/approve',
          body: {'is_approved': args['decision'] == true},
        ),
      );
    }
    if (page == null) throw const FormatException('需要page_id');
    await _scopedView(workspace, page, write: true);
    if (!await _confirm('page_sharing', args)) {
      return _error('permission_denied', '未批准页面共享或权限变更。');
    }
    final endpoint = '$base/collab/${Uri.encodeComponent(page)}';
    if (action == 'create_page_share_link') {
      return _ok(
        await _cloudRequest(
          'POST',
          '$endpoint/invite-link',
          body: {'permission_id': args['access_level'] ?? 1},
        ),
      );
    }
    return _ok(
      await _cloudRequest(
        'PATCH',
        '$endpoint/members/${Uri.encodeComponent(_requiredString(args, 'user_id'))}',
        body: {'permission_id': args['access_level'] ?? 1},
      ),
    );
  }

  Future<CallToolResult> _publishingCloud(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id'),
        action = _requiredString(args, 'action');
    final check = await _validateWorkspace(workspace);
    if (check != null) return check;
    if (action == 'manage_site_domain') {
      // The current Sites UI edits a publish namespace; DNS domain binding is
      // not implemented by the product's server.
      return _error(
        'unsupported_capability',
        '当前站点功能提供发布命名空间，未提供DNS自定义域名绑定；请使用update_site_settings.namespace。',
      );
    }
    final publish = Uri.encodeComponent(_requiredString(args, 'publish_id'));
    if (action == 'import_published_page') {
      final parent = _requiredString(args, 'parent_id');
      await _scopedView(workspace, parent, write: true);
      if (!await _confirm('site_publishing', args)) {
        return _error('permission_denied', '未批准复制发布页。');
      }
      return _ok(
        await _cloudRequest(
          'POST',
          '/api/workspace/${Uri.encodeComponent(workspace)}/published-duplicate',
          body: {
            'published_view_id': Uri.decodeComponent(publish),
            'dest_view_id': parent,
          },
        ),
      );
    }
    final operation = _requiredString(args, 'operation');
    final base = '/api/workspace/published-info/$publish';
    if (operation == 'list_comments') {
      return _ok(await _cloudRequest('GET', '$base/comment'));
    }
    if (operation == 'list_reactions') {
      return _ok(
        await _cloudRequest(
          'GET',
          '$base/reaction?comment_id=${Uri.encodeComponent(_requiredString(args, 'comment_id'))}',
        ),
      );
    }
    if (!await _confirm('site_publishing', args)) {
      return _error('permission_denied', '未批准发布页互动。');
    }
    if (operation == 'comment' || operation == 'reply') {
      return _ok(
        await _cloudRequest(
          'POST',
          '$base/comment',
          body: {
            'content': _requiredString(args, 'text'),
            'reply_comment_id': args['reply_comment_id'],
          },
        ),
      );
    }
    if (operation == 'delete_comment') {
      return _ok(
        await _cloudRequest(
          'DELETE',
          '$base/comment',
          body: {'comment_id': _requiredString(args, 'comment_id')},
        ),
      );
    }
    if (!const ['react', 'remove_reaction'].contains(operation)) {
      throw const FormatException('未知发布页互动动作');
    }
    return _ok(
      await _cloudRequest(
        operation == 'react' ? 'POST' : 'DELETE',
        '$base/reaction',
        body: {
          'comment_id': _requiredString(args, 'comment_id'),
          'reaction_type': _requiredString(args, 'reaction'),
        },
      ),
    );
  }
}
