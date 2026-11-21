part of 'mcp_tools.dart';

extension _McpDatabaseTools on McpTools {
  Uint8List? _fieldOptionBytes(FieldType type, Map<String, dynamic> args) {
    if (args['type_options'] != null && args['type_options_base64'] != null) {
      throw const FormatException('字段选项只可指定一种格式');
    }
    if (args['type_options_base64'] is String) {
      return Uint8List.fromList(
        base64Decode(args['type_options_base64'] as String),
      );
    }
    if (args['type_options'] == null) return null;
    final GeneratedMessage option = switch (type) {
      FieldType.Number => NumberTypeOptionPB(),
      FieldType.DateTime => DateTypeOptionPB(),
      FieldType.SingleSelect => SingleSelectTypeOptionPB(),
      FieldType.MultiSelect => MultiSelectTypeOptionPB(),
      FieldType.Checkbox => CheckboxTypeOptionPB(),
      FieldType.Checklist => ChecklistTypeOptionPB(),
      FieldType.Relation => RelationTypeOptionPB(),
      FieldType.Media => MediaTypeOptionPB(),
      FieldType.CreatedTime ||
      FieldType.LastEditedTime =>
        TimestampTypeOptionPB(),
      FieldType.Summary => SummarizationTypeOptionPB(),
      FieldType.Translate => TranslateTypeOptionPB(),
      FieldType.Time => TimeTypeOptionPB(),
      FieldType.URL => URLTypeOptionPB(),
      _ => RichTextTypeOptionPB(),
    };
    option.mergeFromProto3Json(_object(args, 'type_options'));
    return option.writeToBuffer();
  }

  Future<CallToolResult> _databaseViewActions(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id');
    final error = await _validateWorkspace(workspace);
    if (error != null) return error;
    if (args['action'] == 'list_database_views') {
      final catalog = await DatabaseEventGetDatabases().send().getOrThrow();
      final views = <Map<String, dynamic>>[];
      for (final entry in catalog.items) {
        final view = await _view(entry.viewId);
        if (view != null &&
            (view.workspaceId.isEmpty || view.workspaceId == workspace)) {
          views.add(
            {'database_id': entry.databaseId, 'view': _viewToJson(view)},
          );
        }
      }
      return _ok({'databases': views});
    }
    final parent = _requiredString(args, 'parent_id');
    await _scopedView(workspace, parent, write: true);
    String? database = args['database_id'] as String?;
    if (database != null) {
      final catalog = await DatabaseEventGetDatabases().send().getOrThrow();
      final entry = catalog.items
          .where((entry) => entry.databaseId == database)
          .firstOrNull;
      if (entry == null) return _error('not_found', '关联数据库不存在。');
      await _scopedView(workspace, entry.viewId);
    }
    final layout = switch (args['layout']) {
      'board' => ViewLayoutPB.Board,
      'calendar' => ViewLayoutPB.Calendar,
      _ => ViewLayoutPB.Grid
    };
    final view = await ViewBackendService.createView(
      parentViewId: parent,
      name: _requiredString(args, 'name'),
      layoutType: layout,
      openAfterCreate: false,
      ext: {if (database != null) 'database_id': database},
    ).getOrThrow();
    return _ok({'view': _viewToJson(view)});
  }

  Future<CallToolResult> _unscheduledCalendar(
    CalendarEventRequestPB request,
  ) async {
    final workspace = await _currentWorkspace();
    if (workspace == null) return _error('not_logged_in', '当前没有工作区。');
    final layout = await DatabaseEventGetLayoutSetting(
      DatabaseLayoutMetaPB(
        viewId: request.viewId,
        layout: DatabaseLayoutPB.Calendar,
      ),
    ).send().getOrThrow();
    return _queryDatabase({
      'workspace_id': workspace.id,
      'view_id': request.viewId,
      'limit': 100,
      'filters': [
        {'field_id': layout.calendar.fieldId, 'operator': 'is_empty'},
      ],
    });
  }

  Future<CallToolResult?> _requireDatabaseView(
    String workspace,
    String id, {
    bool write = false,
  }) async {
    final check = write
        ? await _requireWriteAccess(workspace)
        : await _validateWorkspace(workspace);
    if (check != null) return check;
    final view = await _view(id);
    if (view == null) return _error('not_found', '数据库视图不存在或无权访问。');
    if (view.workspaceId.isNotEmpty && view.workspaceId != workspace) {
      return _error('workspace_mismatch', '数据库不属于当前工作区。');
    }
    if (!const [ViewLayoutPB.Grid, ViewLayoutPB.Board, ViewLayoutPB.Calendar]
        .contains(view.layout)) {
      return _error('invalid_params', '目标不是数据库视图。');
    }
    if (write && view.isLocked) return _error('page_locked', '数据库页面已锁定。');
    return null;
  }

  Future<String?> _writeCellOperation(
    String view,
    String row,
    FieldPB field,
    Map<String, dynamic> args,
  ) async {
    final operation = args['operation'];
    if (!const ['set', 'clear', 'add', 'remove'].contains(operation)) {
      return '未知的单元格操作。';
    }
    final id = CellIdPB(viewId: view, rowId: row, fieldId: field.id);
    if (field.fieldType == FieldType.SingleSelect ||
        field.fieldType == FieldType.MultiSelect) {
      final current = await DatabaseEventGetCell(id).send().getOrThrow();
      final selected = SelectOptionCellDataPB.fromBuffer(current.data)
          .selectOptions
          .map((o) => o.id)
          .toSet();
      final requested =
          (args['option_ids'] as List? ?? []).cast<String>().toSet();
      final options = McpTools._selectOptions(field);
      if (requested.any((id) => !options.any((o) => o.id == id))) {
        return '选项ID不存在。';
      }
      if (operation != 'clear' && args['option_ids'] == null) {
        return '选择操作需要option_ids。';
      }
      if (field.fieldType == FieldType.SingleSelect && requested.length > 1) {
        return '单选字段只能有一个选项。';
      }
      final desired = switch (operation) {
        'clear' => <String>{},
        'set' => requested,
        'add' => field.fieldType == FieldType.SingleSelect
            ? requested
            : {...selected, ...requested},
        _ => selected.difference(requested),
      };
      await DatabaseEventUpdateSelectOptionCell(
        SelectOptionCellChangesetPB(
          cellIdentifier: id,
          insertOptionIds: desired.difference(selected),
          deleteOptionIds: selected.difference(desired),
        ),
      ).send().getOrThrow();
      return null;
    }
    if (operation == 'clear') {
      if (field.fieldType == FieldType.DateTime) {
        await DateCellBackendService(
          viewId: view,
          fieldId: field.id,
          rowId: row,
        ).clear().getOrThrow();
      } else if (field.fieldType == FieldType.Checklist) {
        final cell = await DatabaseEventGetCell(id).send().getOrThrow();
        final tasks = ChecklistCellDataPB.fromBuffer(cell.data);
        await ChecklistCellBackendService(
          viewId: view,
          fieldId: field.id,
          rowId: row,
        )
            .delete(optionIds: tasks.options.map((o) => o.id).toList())
            .getOrThrow();
      } else if (const [
        FieldType.RichText,
        FieldType.Number,
        FieldType.URL,
        FieldType.Time,
        FieldType.Checkbox,
      ].contains(field.fieldType)) {
        await CellBackendService.updateCell(
          viewId: view,
          cellContext: CellContext(fieldId: field.id, rowId: row),
          data: '',
        ).getOrThrow();
      } else {
        return '此字段需要使用对应的类型化单元格工具清空。';
      }
      return null;
    }
    if (operation != 'set') return '此字段仅支持set/clear；add/remove用于选项字段。';
    if (args['value'] is! String) return 'set需要value字符串。';
    return _writeCell(
      viewId: view,
      rowId: row,
      field: field,
      value: args['value'] as String,
      includeTime: args['include_time'] == true,
    );
  }
}

/// Pure query projection shared by the database tool and its regression tests.
@visibleForTesting
List<Map<String, dynamic>> filterDatabaseRows(
  List<Map<String, dynamic>> rows,
  List<Map> filters,
  List<Map> sorts,
) {
  String text(Map row, Object? field) =>
      ((row['cells_by_id'] as Map)[field] as Map?)?['text'] as String? ?? '';
  int compare(String left, String right) {
    final a = num.tryParse(left), b = num.tryParse(right);
    return a != null && b != null ? a.compareTo(b) : left.compareTo(right);
  }

  final selected = rows
      .where(
        (row) => filters.every((filter) {
          final value = text(row, filter['field_id']);
          final expected = filter['value'] as String? ?? '';
          return switch (filter['operator']) {
            'eq' => value == expected,
            'neq' => value != expected,
            'contains' => value.contains(expected),
            'gt' => compare(value, expected) > 0,
            'gte' => compare(value, expected) >= 0,
            'lt' => compare(value, expected) < 0,
            'lte' => compare(value, expected) <= 0,
            'is_empty' => value.isEmpty,
            _ => throw const FormatException('未知筛选操作'),
          };
        }),
      )
      .toList();
  if (sorts.isNotEmpty) {
    final order = {for (var i = 0; i < rows.length; i++) rows[i]['row_id']: i};
    selected.sort((a, b) {
      for (final sort in sorts) {
        final result =
            compare(text(a, sort['field_id']), text(b, sort['field_id']));
        if (result != 0) return sort['direction'] == 'desc' ? -result : result;
      }
      return order[a['row_id']]!.compareTo(order[b['row_id']]!);
    });
  }
  return selected;
}
