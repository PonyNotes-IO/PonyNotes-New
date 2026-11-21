part of 'mcp_tools.dart';

extension _McpExtendedTools on McpTools {
  McpToolSpec _withActions(
    McpToolSpec base,
    Map<String, JsonSchema> fields,
    List<String> actions,
    Future<CallToolResult> Function(Map<String, dynamic>) handler,
  ) {
    final json = base.inputSchema.toJson();
    final properties = Map<String, dynamic>.from(json['properties'] as Map);
    properties.addAll(
      {for (final entry in fields.entries) entry.key: entry.value.toJson()},
    );
    final previous = Map<String, dynamic>.from(properties['action'] as Map);
    previous['enum'] = [...previous['enum'] as List, ...actions];
    properties['action'] = previous;
    json['properties'] = properties;
    json['required'] = ['workspace_id', 'action'];
    final branches = json['oneOf'] as List?;
    if (branches != null) {
      json['oneOf'] = [
        ...branches,
        {
          'properties': {
            'action': {'enum': actions},
          },
        }
      ];
    }
    return McpToolSpec(
      name: base.name,
      description: base.description,
      inputSchema: JsonObject.fromJson(json),
      destructive: true,
      handler: (args) =>
          actions.contains(args['action']) ? handler(args) : base.handler(args),
    );
  }

  McpToolSpec _actionTool(
    String name,
    String description,
    Map<String, JsonSchema> fields,
    List<String> actions,
    Future<CallToolResult> Function(Map<String, dynamic>) handler, {
    List<String> required = const ['workspace_id', 'action'],
    bool readOnly = false,
  }) =>
      McpToolSpec(
        name: name,
        description: description,
        inputSchema: JsonObject(
          properties: {
            'workspace_id': const JsonString(description: '当前工作区ID'),
            if (actions.isNotEmpty) 'action': JsonString(enumValues: actions),
            ...fields,
          },
          required: required,
          additionalProperties: false,
        ),
        readOnly: readOnly,
        destructive: !readOnly,
        handler: handler,
      );

  String _requiredString(Map<String, dynamic> args, String key) {
    final value = args[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('缺少$key');
    }
    return value;
  }

  Map<String, dynamic> _object(Map<String, dynamic> args, String key) {
    final value = args[key];
    if (value is! Map) throw FormatException('$key必须是对象');
    return Map<String, dynamic>.from(value);
  }

  CallToolResult _message(GeneratedMessage message) =>
      _ok({'data': message.toProto3Json()});

  bool _executionIsActive() {
    final scope =
        Zone.current[_mcpExecutionScope] as ({String name, DateTime deadline})?;
    return !(isAuthorizationCurrent?.call() == false) &&
        (scope == null ||
            (DateTime.now().isBefore(scope.deadline) &&
                (!isAgentChannel || _allowed(scope.name))));
  }

  Future<bool> _confirm(String tool, Map<String, dynamic> args) async {
    if (!_executionIsActive()) return false;
    if (confirmOperation != null) {
      return await confirmOperation!(tool, args) && _executionIsActive();
    }
    final context = AppGlobals.rootNavKey.currentContext;
    if (context == null || !context.mounted) return false;
    final profile = await _currentProfile();
    final workspace = await _currentWorkspace();
    if (!context.mounted) return false;
    Object? redact(Object? value) {
      if (value is Map) {
        return {
          for (final entry in value.entries)
            entry.key: RegExp(
              'token|password|secret|credential|api.?key',
              caseSensitive: false,
            ).hasMatch('${entry.key}')
                ? '已隐藏'
                : redact(entry.value),
        };
      }
      if (value is List) return value.map(redact).toList();
      return value;
    }

    final preview = const JsonEncoder.withIndent('  ').convert(redact(args));
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('允许执行 ${args['action'] ?? tool}？'),
        content: SingleChildScrollView(
          child: Text('工具：$tool\n工作区：${workspace?.id ?? ''}\n$preview'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('拒绝'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('允许'),
          ),
        ],
      ),
    );
    return accepted == true &&
        _executionIsActive() &&
        (await _currentProfile())?.id == profile?.id &&
        (await _currentWorkspace())?.id == workspace?.id;
  }

  Future<CallToolResult?> _requireOwner(String workspace) async {
    final check = await _requireWriteAccess(workspace);
    if (check != null) return check;
    final profile = await _currentProfile();
    if (profile?.workspaceType == WorkspaceTypePB.LocalW) return null;
    final role = await WorkspacePermissionService.getCurrentUserRole(
      workspaceId: workspace,
      userId: profile!.id.toInt(),
    );
    return role == AFRolePB.Owner
        ? null
        : _error('permission_denied', '此操作需要工作区所有者权限。');
  }

  Future<ViewPB> _scopedView(
    String workspace,
    String id, {
    bool write = false,
  }) async {
    final check = write
        ? await _requireWriteAccess(workspace)
        : await _validateWorkspace(workspace);
    if (check != null) throw StateError('当前工作区无权执行此操作。');
    final view = await _view(id);
    if (view == null ||
        (view.workspaceId.isNotEmpty && view.workspaceId != workspace)) {
      throw StateError('页面不存在或不属于当前工作区。');
    }
    if (write && view.isLocked) throw StateError('页面已锁定。');
    return view;
  }
}

/// Derive parameter schemas from the installed business DTOs, preserving enum
/// names, Base64 bytes and nested message shapes used by protobuf JSON.
JsonSchema mcpMessageSchema(GeneratedMessage message) {
  JsonSchema fieldSchema(FieldInfo field) {
    if (field is MapFieldInfo) {
      return JsonObject(
        additionalProperties: field.valueCreator == null
            ? const JsonAny()
            : mcpMessageSchema(field.valueCreator!()),
      );
    }
    final base = PbFieldType.baseType(field.type);
    JsonSchema schema;
    if (field.enumValues != null) {
      schema =
          JsonString(enumValues: field.enumValues!.map((v) => v.name).toList());
    } else if (field.subBuilder != null) {
      schema = mcpMessageSchema(field.subBuilder!());
    } else if (base == PbFieldType.BOOL_BIT) {
      schema = const JsonBoolean();
    } else if (base == PbFieldType.STRING_BIT ||
        base == PbFieldType.BYTES_BIT) {
      schema = JsonString(
        description: base == PbFieldType.BYTES_BIT ? 'Base64编码的二进制' : null,
      );
    } else if (const [
      PbFieldType.INT64_BIT,
      PbFieldType.UINT64_BIT,
      PbFieldType.SINT64_BIT,
      PbFieldType.FIXED64_BIT,
      PbFieldType.SFIXED64_BIT,
    ].contains(base)) {
      schema = const JsonString(description: '64位十进制整数字符串');
    } else if (base == PbFieldType.DOUBLE_BIT ||
        base == PbFieldType.FLOAT_BIT) {
      schema = const JsonNumber();
    } else {
      schema = const JsonInteger();
    }
    return PbFieldType.isRepeated(field.type)
        ? JsonArray(items: schema)
        : schema;
  }

  return JsonObject(
    properties: {
      for (final field in message.info_.fieldInfo.values)
        field.name: fieldSchema(field),
    },
    additionalProperties: false,
  );
}
