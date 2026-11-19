part of 'mcp_tools.dart';

class _NativeAction<T extends GeneratedMessage> {
  const _NativeAction(
    this.create,
    this.send, {
    this.readOnly = false,
    this.owner = false,
    this.confirm = false,
  });
  final T Function() create;
  final Future<Object?> Function(T) send;
  final bool readOnly;
  final bool owner;
  final bool confirm;

  Future<Object?> execute(GeneratedMessage payload) => send(payload as T);
}

extension _McpNativeTools on McpTools {
  McpToolSpec _nativeTool(
    String name,
    String description,
    Map<String, _NativeAction> actions, {
    bool database = false,
  }) {
    final branches = <Map<String, dynamic>>[];
    for (final entry in actions.entries) {
      final parts = entry.key.split('.');
      branches.add({
        'properties': {
          'action': {'const': parts.first},
          if (parts.length > 1) 'operation': {'const': parts.last},
          'request': mcpMessageSchema(entry.value.create()).toJson(),
        },
        'required': ['action', 'request', if (parts.length > 1) 'operation'],
      });
    }
    final schema = JsonObject(
      properties: {
        'workspace_id': const JsonString(),
        if (database) 'view_id': const JsonString(),
        'action': JsonString(
          enumValues:
              actions.keys.map((key) => key.split('.').first).toSet().toList(),
        ),
        'operation': const JsonString(),
        'request': const JsonObject(),
      },
      required: [
        'workspace_id',
        'action',
        'request',
        if (database) 'view_id',
      ],
      additionalProperties: false,
      extra: {'oneOf': branches},
    );
    return McpToolSpec(
      name: name,
      description:
          '$description request使用下方每个action对应的protobuf JSON结构；viewId/workspaceId由当前上下文约束。',
      inputSchema: schema,
      readOnly: actions.values.every((action) => action.readOnly),
      destructive: actions.values.any((action) => !action.readOnly),
      handler: (args) async {
        final key = actions.containsKey(args['action'])
            ? args['action'] as String
            : '${args['action']}.${args['operation']}';
        final action = actions[key];
        if (action == null) throw const FormatException('未知业务动作');
        final workspace = _requiredString(args, 'workspace_id');
        final check = action.owner
            ? await _requireOwner(workspace)
            : action.readOnly
                ? await _validateWorkspace(workspace)
                : await _requireWriteAccess(workspace);
        if (check != null) return check;
        if (database) {
          final error = await _requireDatabaseView(
            workspace,
            _requiredString(args, 'view_id'),
            write: !action.readOnly,
          );
          if (error != null) return error;
        }
        final request = _object(args, 'request');
        final declared = action.create();
        if (declared is ViewIdPB) {
          await _scopedView(
            workspace,
            _requiredString(request, 'value'),
            write: !action.readOnly,
          );
        }
        if (declared is UnpublishViewsPayloadPB) {
          for (final id in (request['viewIds'] as List? ?? []).cast<String>()) {
            await _scopedView(workspace, id, write: true);
          }
        }
        if (declared is PublishViewParamsPB) {
          final selected = request['selectedViewIds'];
          if (selected is Map)
            for (final id
                in (selected['items'] as List? ?? []).cast<String>()) {
              await _scopedView(workspace, id, write: true);
            }
        }
        if (database && declared is DatabaseViewIdPB) {
          if (request['value'] != null && request['value'] != args['view_id']) {
            throw const FormatException('请求数据库视图与授权上下文不一致');
          }
          request['value'] = args['view_id'];
        }
        if (declared is DatabaseIdPB) {
          final databases =
              await DatabaseEventGetDatabases().send().getOrThrow();
          final database = databases.items
              .where((item) => item.databaseId == request['value'])
              .firstOrNull;
          if (database == null) return _error('not_found', '关联目标数据库不存在。');
          await _scopedView(workspace, database.viewId);
        }
        void bindScope(Map data) {
          for (final entry in data.entries.toList()) {
            final key = entry.key;
            final expected = key == 'workspaceId' || key == 'workspace_id'
                ? workspace
                : key == 'viewId' || key == 'view_id'
                    ? args['view_id']
                    : null;
            if (expected != null && entry.value != expected) {
              throw const FormatException('业务请求目标与授权上下文不一致');
            }
            if (entry.value is Map) bindScope(entry.value as Map);
            if (entry.value is List)
              for (final child in entry.value as List) {
                if (child is Map) bindScope(child);
              }
          }
        }

        bindScope(request);
        Future<void> checkViews(Object? value) async {
          if (value is Map) {
            for (final entry in value.entries) {
              if (const [
                    'viewId',
                    'pageId',
                    'parentViewId',
                    'parentId',
                    'targetViewId',
                    'chatId',
                    'objectId',
                  ].contains(entry.key) &&
                  entry.value is String &&
                  (entry.value as String).isNotEmpty &&
                  entry.value != workspace) {
                await _scopedView(
                  workspace,
                  entry.value as String,
                  write: !action.readOnly,
                );
              }
              await checkViews(entry.value);
            }
          } else if (value is List) {
            for (final item in value) {
              await checkViews(item);
            }
          }
        }

        await checkViews(request);
        final payload = action.create();
        final names = payload.info_.byName.keys;
        if (names.contains('workspaceId')) request['workspaceId'] = workspace;
        if (database && names.contains('viewId')) {
          request['viewId'] = args['view_id'];
        }
        payload.mergeFromProto3Json(request);
        if (payload is ChatId) {
          final view = await _scopedView(workspace, payload.value);
          if (view.layout != ViewLayoutPB.Chat) {
            throw const FormatException('目标不是聊天页面');
          }
        }
        if (payload is MediaCellChangesetPB) {
          for (final file in payload.insertedFiles) {
            final uri = Uri.tryParse(file.url);
            if (uri == null ||
                !['http', 'https'].contains(uri.scheme) ||
                uri.userInfo.isNotEmpty) {
              throw const FormatException('附件单元格仅接受HTTP(S)资源；本地文件请先通过assets上传');
            }
          }
        }
        if (action.confirm && !await _confirm(name, args)) {
          return _error('permission_denied', '用户未批准操作。');
        }
        final result = await action.execute(payload);
        if (result is CallToolResult) return result;
        return result is GeneratedMessage
            ? _message(result)
            : _ok({'completed': true, if (result != null) 'data': result});
      },
    );
  }

  List<McpToolSpec> get _nativeSpecs => [
        _nativeTool(
          'database_fields',
          '数据库列复制、移动、清空、类型选项、选择项与字段展示设置。',
          {
            'duplicate_database_field': _NativeAction<DuplicateFieldPayloadPB>(
              DuplicateFieldPayloadPB.create,
              (p) async => DatabaseEventDuplicateField(p).send().getOrThrow(),
            ),
            'move_database_field': _NativeAction<MoveFieldPayloadPB>(
              MoveFieldPayloadPB.create,
              (p) async => DatabaseEventMoveField(p).send().getOrThrow(),
            ),
            'clear_database_field': _NativeAction<ClearFieldPayloadPB>(
              ClearFieldPayloadPB.create,
              (p) async => DatabaseEventClearField(p).send().getOrThrow(),
              confirm: true,
            ),
            'update_field_options': _NativeAction<TypeOptionChangesetPB>(
              TypeOptionChangesetPB.create,
              (p) async =>
                  DatabaseEventUpdateFieldTypeOption(p).send().getOrThrow(),
            ),
            'manage_select_options.create':
                _NativeAction<CreateSelectOptionPayloadPB>(
              CreateSelectOptionPayloadPB.create,
              (p) async =>
                  DatabaseEventCreateSelectOption(p).send().getOrThrow(),
            ),
            'manage_select_options.update':
                _NativeAction<RepeatedSelectOptionPayload>(
              RepeatedSelectOptionPayload.create,
              (p) async => DatabaseEventInsertOrUpdateSelectOption(p)
                  .send()
                  .getOrThrow(),
            ),
            'manage_select_options.delete':
                _NativeAction<RepeatedSelectOptionPayload>(
              RepeatedSelectOptionPayload.create,
              (p) async =>
                  DatabaseEventDeleteSelectOption(p).send().getOrThrow(),
              confirm: true,
            ),
            'update_field_settings': _NativeAction<FieldSettingsChangesetPB>(
              FieldSettingsChangesetPB.create,
              (p) async =>
                  DatabaseEventUpdateFieldSettings(p).send().getOrThrow(),
            ),
          },
          database: true,
        ),
        _nativeTool(
          'database_cells',
          '类型化清单、日期范围、关联行和媒体单元格操作。',
          {
            'update_checklist_cell':
                _NativeAction<ChecklistCellDataChangesetPB>(
              ChecklistCellDataChangesetPB.create,
              (p) async =>
                  DatabaseEventUpdateChecklistCell(p).send().getOrThrow(),
            ),
            'update_date_cell': _NativeAction<DateCellChangesetPB>(
              DateCellChangesetPB.create,
              (p) async => DatabaseEventUpdateDateCell(p).send().getOrThrow(),
            ),
            'update_relation_cell': _NativeAction<RelationCellChangesetPB>(
              RelationCellChangesetPB.create,
              (p) async =>
                  DatabaseEventUpdateRelationCell(p).send().getOrThrow(),
            ),
            'list_relation_targets': _NativeAction<DatabaseIdPB>(
              DatabaseIdPB.create,
              (p) async =>
                  DatabaseEventGetRelatedDatabaseRows(p).send().getOrThrow(),
              readOnly: true,
            ),
            'update_media_cell': _NativeAction<MediaCellChangesetPB>(
              MediaCellChangesetPB.create,
              (p) async => DatabaseEventUpdateMediaCell(p).send().getOrThrow(),
            ),
            'rename_database_media': _NativeAction<RenameMediaChangesetPB>(
              RenameMediaChangesetPB.create,
              (p) async => DatabaseEventRenameMediaFile(p).send().getOrThrow(),
            ),
          },
          database: true,
        ),
        _nativeTool(
          'database_rows',
          '读取行内容与元信息、复制、移动以及设置行详情文档。',
          {
            'get_database_row': _NativeAction<DatabaseViewRowIdPB>(
              DatabaseViewRowIdPB.create,
              (p) async => DatabaseEventGetRow(p).send().getOrThrow(),
              readOnly: true,
            ),
            'duplicate_database_row': _NativeAction<DatabaseViewRowIdPB>(
              DatabaseViewRowIdPB.create,
              (p) async => DatabaseEventDuplicateRow(p).send().getOrThrow(),
            ),
            'move_database_row': _NativeAction<MoveRowPayloadPB>(
              MoveRowPayloadPB.create,
              (p) async => DatabaseEventMoveRow(p).send().getOrThrow(),
            ),
            'database_row_meta.get': _NativeAction<DatabaseViewRowIdPB>(
              DatabaseViewRowIdPB.create,
              (p) async => DatabaseEventGetRowMeta(p).send().getOrThrow(),
              readOnly: true,
            ),
            'database_row_meta.update': _NativeAction<UpdateRowMetaChangesetPB>(
              UpdateRowMetaChangesetPB.create,
              (p) async => DatabaseEventUpdateRowMeta(p).send().getOrThrow(),
            ),
            'database_row_document': _NativeAction<DatabaseViewRowIdPB>(
              DatabaseViewRowIdPB.create,
              (p) async => DatabaseEventInitRow(p).send().getOrThrow(),
            ),
          },
          database: true,
        ),
        _nativeTool(
          'database_ai_action',
          '对数据库行执行AI摘要或翻译。',
          {
            'summarize': _NativeAction<SummaryRowPB>(
              SummaryRowPB.create,
              (p) async => DatabaseEventSummarizeRow(p).send().getOrThrow(),
            ),
            'translate': _NativeAction<TranslateRowPB>(
              TranslateRowPB.create,
              (p) async => DatabaseEventTranslateRow(p).send().getOrThrow(),
            ),
          },
          database: true,
        ),
        _withActions(
          _nativeTool(
            'database_views',
            '数据库视图配置、布局、筛选排序、分组、日历与统计。',
            {
              'get_database_view_settings': _NativeAction<DatabaseViewIdPB>(
                DatabaseViewIdPB.create,
                (p) async =>
                    DatabaseEventGetDatabaseSetting(p).send().getOrThrow(),
                readOnly: true,
              ),
              'update_database_view': _NativeAction<LayoutSettingChangesetPB>(
                LayoutSettingChangesetPB.create,
                (p) async =>
                    DatabaseEventSetLayoutSetting(p).send().getOrThrow(),
              ),
              'manage_database_filters.list': _NativeAction<DatabaseViewIdPB>(
                DatabaseViewIdPB.create,
                (p) async => DatabaseEventGetAllFilters(p).send().getOrThrow(),
                readOnly: true,
              ),
              'manage_database_filters.update':
                  _NativeAction<DatabaseSettingChangesetPB>(
                DatabaseSettingChangesetPB.create,
                (p) async =>
                    DatabaseEventUpdateDatabaseSetting(p).send().getOrThrow(),
              ),
              'manage_database_sorts.list': _NativeAction<DatabaseViewIdPB>(
                DatabaseViewIdPB.create,
                (p) async => DatabaseEventGetAllSorts(p).send().getOrThrow(),
                readOnly: true,
              ),
              'manage_database_sorts.update':
                  _NativeAction<DatabaseSettingChangesetPB>(
                DatabaseSettingChangesetPB.create,
                (p) async =>
                    DatabaseEventUpdateDatabaseSetting(p).send().getOrThrow(),
              ),
              'manage_database_sorts.clear': _NativeAction<DatabaseViewIdPB>(
                DatabaseViewIdPB.create,
                (p) async => DatabaseEventDeleteAllSorts(p).send().getOrThrow(),
              ),
              'set_database_grouping': _NativeAction<GroupByFieldPayloadPB>(
                GroupByFieldPayloadPB.create,
                (p) async =>
                    DatabaseEventSetGroupByField(p).send().getOrThrow(),
              ),
              'manage_database_groups.list': _NativeAction<DatabaseViewIdPB>(
                DatabaseViewIdPB.create,
                (p) async => DatabaseEventGetGroups(p).send().getOrThrow(),
                readOnly: true,
              ),
              'manage_database_groups.create':
                  _NativeAction<CreateGroupPayloadPB>(
                CreateGroupPayloadPB.create,
                (p) async => DatabaseEventCreateGroup(p).send().getOrThrow(),
              ),
              'manage_database_groups.update': _NativeAction<UpdateGroupPB>(
                UpdateGroupPB.create,
                (p) async => DatabaseEventUpdateGroup(p).send().getOrThrow(),
              ),
              'manage_database_groups.delete':
                  _NativeAction<DeleteGroupPayloadPB>(
                DeleteGroupPayloadPB.create,
                (p) async => DatabaseEventDeleteGroup(p).send().getOrThrow(),
                confirm: true,
              ),
              'move_database_group.group': _NativeAction<MoveGroupPayloadPB>(
                MoveGroupPayloadPB.create,
                (p) async => DatabaseEventMoveGroup(p).send().getOrThrow(),
              ),
              'move_database_group.row': _NativeAction<MoveGroupRowPayloadPB>(
                MoveGroupRowPayloadPB.create,
                (p) async => DatabaseEventMoveGroupRow(p).send().getOrThrow(),
              ),
              'database_calendar_events.list':
                  _NativeAction<CalendarEventRequestPB>(
                CalendarEventRequestPB.create,
                (p) async =>
                    DatabaseEventGetAllCalendarEvents(p).send().getOrThrow(),
                readOnly: true,
              ),
              'database_calendar_events.unscheduled':
                  _NativeAction<CalendarEventRequestPB>(
                CalendarEventRequestPB.create,
                (p) => _unscheduledCalendar(p),
                readOnly: true,
              ),
              'database_calendar_events.get':
                  _NativeAction<DatabaseViewRowIdPB>(
                DatabaseViewRowIdPB.create,
                (p) async =>
                    DatabaseEventGetCalendarEvent(p).send().getOrThrow(),
                readOnly: true,
              ),
              'database_calendar_events.move':
                  _NativeAction<MoveCalendarEventPB>(
                MoveCalendarEventPB.create,
                (p) async =>
                    DatabaseEventMoveCalendarEvent(p).send().getOrThrow(),
              ),
              'manage_database_calculations.list':
                  _NativeAction<DatabaseViewIdPB>(
                DatabaseViewIdPB.create,
                (p) async =>
                    DatabaseEventGetAllCalculations(p).send().getOrThrow(),
                readOnly: true,
              ),
              'manage_database_calculations.set':
                  _NativeAction<UpdateCalculationChangesetPB>(
                UpdateCalculationChangesetPB.create,
                (p) async =>
                    DatabaseEventUpdateCalculation(p).send().getOrThrow(),
              ),
              'manage_database_calculations.remove':
                  _NativeAction<RemoveCalculationChangesetPB>(
                RemoveCalculationChangesetPB.create,
                (p) async =>
                    DatabaseEventRemoveCalculation(p).send().getOrThrow(),
              ),
              'list_database_snapshots': _NativeAction<DatabaseViewIdPB>(
                DatabaseViewIdPB.create,
                (p) async =>
                    DatabaseEventGetDatabaseSnapshots(p).send().getOrThrow(),
                readOnly: true,
              ),
            },
            database: true,
          ),
          {
            'parent_id': const JsonString(),
            'database_id': const JsonString(),
            'name': const JsonString(),
            'layout':
                const JsonString(enumValues: ['grid', 'board', 'calendar']),
          },
          ['list_database_views', 'create_database_view'],
          _databaseViewActions,
        ),
      ];
}
