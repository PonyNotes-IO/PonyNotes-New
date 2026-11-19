part of 'mcp_tools.dart';

extension _McpPersonalTools on McpTools {
  List<McpToolSpec> get _personalSpecs => [
        _actionTool(
          'reminders',
          '读取、创建、改期、完成和删除提醒。scheduled_at使用含时区的ISO8601。',
          {
            'reminder_id': const JsonString(),
            'page_id': const JsonString(),
            'block_id': const JsonString(),
            'scheduled_at': const JsonString(),
            'title': const JsonString(),
            'message': const JsonString(),
            'completed': const JsonBoolean(),
            'offset': const JsonInteger(minimum: 0),
            'limit': const JsonInteger(minimum: 1, maximum: 500),
          },
          [
            'list_reminders',
            'get_reminder',
            'create_reminder',
            'update_reminder',
            'set_reminder_completed',
            'delete_reminder',
          ],
          _reminders,
        ),
        _actionTool(
          'notifications',
          '读取通知并标记已读/归档/取消归档，支持all批量处理。',
          {
            'notification_id': const JsonString(),
            'operation': const JsonString(
              enumValues: ['read', 'archive', 'unarchive'],
            ),
            'all': const JsonBoolean(),
            'unread_only': const JsonBoolean(),
          },
          ['list_notifications', 'update_notification'],
          _notifications,
        ),
        _preferencesTool('user_preferences', '读取与修改外观、日期时间、通知、快捷键和主题。', {
          'get_user_preferences.appearance': _NativeAction<UserWorkspaceIdPB>(
            UserWorkspaceIdPB.create,
            (p) async => UserEventGetAppearanceSetting().send().getOrThrow(),
            readOnly: true,
          ),
          'get_user_preferences.date_time': _NativeAction<UserWorkspaceIdPB>(
            UserWorkspaceIdPB.create,
            (p) async => UserEventGetDateTimeSettings().send().getOrThrow(),
            readOnly: true,
          ),
          'get_user_preferences.notifications':
              _NativeAction<UserWorkspaceIdPB>(
            UserWorkspaceIdPB.create,
            (p) async => UserEventGetNotificationSettings().send().getOrThrow(),
            readOnly: true,
          ),
          'update_user_preferences.appearance':
              _NativeAction<AppearanceSettingsPB>(
            AppearanceSettingsPB.create,
            (p) async => UserEventSetAppearanceSetting(p).send().getOrThrow(),
          ),
          'update_user_preferences.date_time':
              _NativeAction<DateTimeSettingsPB>(
            DateTimeSettingsPB.create,
            (p) async => UserEventSetDateTimeSettings(p).send().getOrThrow(),
          ),
          'update_user_preferences.notifications':
              _NativeAction<NotificationSettingsPB>(
            NotificationSettingsPB.create,
            (p) async =>
                UserEventSetNotificationSettings(p).send().getOrThrow(),
          ),
        }),
        _actionTool(
          'view_history',
          '查询收藏与最近记录，移除最近记录。',
          {
            'operation': const JsonString(
              enumValues: ['list', 'remove', 'clear', 'reorder'],
            ),
            'page_ids': const JsonArray(items: JsonString()),
            'offset': const JsonInteger(minimum: 0),
            'limit': const JsonInteger(minimum: 1, maximum: 500),
          },
          ['manage_favorites', 'manage_recent_views'],
          _viewHistory,
        ),
      ];

  Future<CallToolResult> _reminders(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id');
    final check = await _validateWorkspace(workspace);
    if (check != null) return check;
    const service = ReminderService();
    final entries = await service.fetchReminders().getOrThrow();
    final views = await ViewBackendService.getAllViews().getOrThrow();
    final ids = views.items.map((view) => view.id).toSet();
    final available = entries.where((r) => ids.contains(r.objectId)).toList();
    final action = args['action'];
    if (action == 'list_reminders') {
      final offset = _intArg(args, 'offset', 0, 0, 0x7fffffff),
          limit = _intArg(args, 'limit', 100, 1, 500);
      return _ok({
        'reminders': available
            .skip(offset)
            .take(limit)
            .map((r) => r.toProto3Json())
            .toList(),
        'total': available.length,
      });
    }
    if (action == 'create_reminder') {
      final page = _requiredString(args, 'page_id');
      await _scopedView(workspace, page);
      final time = DateTime.tryParse(_requiredString(args, 'scheduled_at'));
      if (time == null) throw const FormatException('scheduled_at无效');
      final reminder = ReminderPB(
        id: const Uuid().v4(),
        objectId: page,
        scheduledAt: Int64(time.millisecondsSinceEpoch ~/ 1000),
        title: _requiredString(args, 'title'),
        message: args['message'] as String? ?? '',
        meta: {
          if (args['block_id'] != null) 'block_id': args['block_id'] as String,
        },
      );
      await service.addReminder(reminder: reminder).getOrThrow();
      return _message(reminder);
    }
    final reminder =
        available.where((r) => r.id == args['reminder_id']).firstOrNull;
    if (reminder == null) return _error('not_found', '提醒不存在或不属于当前工作区。');
    if (action == 'get_reminder') return _message(reminder);
    if (action == 'delete_reminder') {
      if (!await _confirm('reminders', args)) {
        return _error('permission_denied', '未批准删除提醒。');
      }
      await service.removeReminder(reminderId: reminder.id).getOrThrow();
      return _ok({'deleted': reminder.id});
    }
    final updated = ReminderPB()..mergeFromMessage(reminder);
    if (action == 'set_reminder_completed') {
      if (args['completed'] is! bool) {
        throw const FormatException('需要completed');
      }
      updated.isAck = args['completed'] as bool;
    } else {
      if (args['scheduled_at'] != null) {
        final time = DateTime.tryParse(args['scheduled_at'] as String);
        if (time == null) throw const FormatException('scheduled_at无效');
        updated.scheduledAt = Int64(time.millisecondsSinceEpoch ~/ 1000);
      }
      if (args['title'] != null) updated.title = args['title'] as String;
      if (args['message'] != null) updated.message = args['message'] as String;
    }
    await service.updateReminder(reminder: updated).getOrThrow();
    return _message(updated);
  }

  Future<CallToolResult> _notifications(Map<String, dynamic> args) async {
    final check =
        await _validateWorkspace(_requiredString(args, 'workspace_id'));
    if (check != null) return check;
    if (args['action'] == 'list_notifications') {
      final response = await _cloudRequest('GET', '/api/user/notifications');
      final items = (response['notifications'] as List? ?? [])
          .where(
            (r) => args['unread_only'] != true || (r as Map)['is_read'] != true,
          )
          .toList();
      return _ok({'notifications': items});
    }
    final operation = _requiredString(args, 'operation');
    if (!const ['read', 'archive', 'unarchive'].contains(operation)) {
      throw const FormatException('未知通知操作');
    }
    final suffix = args['all'] == true
        ? '$operation-all'
        : '${Uri.encodeComponent(_requiredString(args, 'notification_id'))}/$operation';
    return _ok(await _cloudRequest('POST', '/api/user/notifications/$suffix'));
  }

  Future<CallToolResult> _viewHistory(Map<String, dynamic> args) async {
    final check =
        await _validateWorkspace(_requiredString(args, 'workspace_id'));
    if (check != null) return check;
    final operation = args['operation'] ?? 'list';
    if (args['action'] == 'manage_favorites') {
      if (operation == 'reorder') return _reorderFavorites(args);
      return _message(await FolderEventReadFavorites().send().getOrThrow());
    }
    final recent = await FolderEventReadRecentViews(
      ReadRecentViewsPB(
        start: Int64(_intArg(args, 'offset', 0, 0, 0x7fffffff)),
        limit: Int64(_intArg(args, 'limit', 500, 1, 500)),
      ),
    ).send().getOrThrow();
    if (operation == 'list') return _message(recent);
    final ids = operation == 'clear'
        ? recent.items.map((r) => r.item.id).toList()
        : (args['page_ids'] as List? ?? []).cast<String>();
    if (ids.isEmpty) throw const FormatException('需要page_ids');
    await FolderEventUpdateRecentViews(
      UpdateRecentViewPayloadPB(viewIds: ids, addInRecent: false),
    ).send().getOrThrow();
    return _ok({'removed': ids});
  }

  Future<CallToolResult> _reorderFavorites(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id');
    final ids = (args['page_ids'] as List? ?? []).cast<String>();
    for (var i = 0; i < ids.length; i++) {
      await _scopedView(workspace, ids[i]);
      await _cloudRequest(
        'POST',
        '/api/workspace/${Uri.encodeComponent(workspace)}/page-view/${Uri.encodeComponent(ids[i])}/reorder-favorite',
        body: {'prev_view_id': i == 0 ? null : ids[i - 1]},
      );
    }
    return _ok({'reordered': ids});
  }
}
