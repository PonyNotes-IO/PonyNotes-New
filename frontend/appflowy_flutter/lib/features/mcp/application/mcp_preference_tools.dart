part of 'mcp_tools.dart';

extension _McpPreferenceTools on McpTools {
  McpToolSpec _preferencesTool(
    String name,
    String description,
    Map<String, _NativeAction> actions,
  ) {
    final base = _nativeTool(name, description, actions);
    final json = base.inputSchema.toJson();
    final properties = Map<String, dynamic>.from(json['properties'] as Map);
    properties['action'] = {
      'type': 'string',
      'enum': [
        ...actions.keys.map((a) => a.split('.').first).toSet(),
        'manage_shortcuts',
        'manage_themes',
      ],
    };
    properties.addAll({
      'bindings': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'key': {'type': 'string'},
            'command': {'type': 'string'},
          },
          'required': ['key', 'command'],
          'additionalProperties': false,
        },
      },
      'theme_id': {'type': 'string'},
      'source_handle': {'type': 'string'},
    });
    json['properties'] = properties;
    json['required'] = ['workspace_id', 'action'];
    json['oneOf'] = [
      ...json['oneOf'] as List,
      {
        'properties': {
          'action': {'const': 'manage_shortcuts'},
          'operation': {
            'enum': ['list', 'update', 'reset'],
          },
        },
        'required': ['operation'],
      },
      {
        'properties': {
          'action': {'const': 'manage_themes'},
          'operation': {
            'enum': ['list', 'import', 'apply', 'remove'],
          },
        },
        'required': ['operation'],
      },
    ];
    return McpToolSpec(
      name: name,
      description: description,
      inputSchema: JsonObject.fromJson(json),
      destructive: true,
      handler: (args) async {
        if (!const ['manage_shortcuts', 'manage_themes']
            .contains(args['action'])) {
          return base.handler(args);
        }
        final check =
            await _validateWorkspace(_requiredString(args, 'workspace_id'));
        if (check != null) return check;
        if (args['action'] == 'manage_shortcuts') {
          final service = SettingsShortcutService();
          if (args['operation'] == 'list') {
            return _ok({
              'bindings': allShortcutEvents
                  .map((e) => {'key': e.key, 'command': e.command})
                  .toList(),
            });
          }
          if (args['operation'] == 'reset') {
            await service.resetToDefaultShortcuts();
            return _ok({'reset': true});
          }
          final bindings = (args['bindings'] as List)
              .cast<Map>()
              .map(
                (e) =>
                    CommandShortcutModel.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList();
          for (final binding in bindings) {
            final event = allShortcutEvents
                .where((e) => e.key == binding.key)
                .firstOrNull;
            if (event == null ||
                !isSupportedShortcutCommand(event, binding.command)) {
              throw FormatException('快捷键无效：${binding.key}');
            }
          }
          await service.updateCommandShortcuts(allShortcutEvents, bindings);
          await service.saveAllShortcuts(allShortcutEvents);
          notifyShortcutChanges();
          return _ok({'updated': bindings.map((b) => b.key).toList()});
        }
        final plugins = FlowyPluginService.instance;
        if (args['operation'] == 'list') {
          return _ok({
            'themes':
                (await plugins.plugins).map((p) => {'id': p.name}).toList(),
          });
        }
        if (!await _confirm('user_preferences', args)) {
          return _error('permission_denied', '用户未批准主题变更。');
        }
        if (args['operation'] == 'import') {
          final directory = Directory(
            await _resolveGrant(
              _requiredString(args, 'source_handle'),
              'directory',
            ),
          );
          final plugin = await FlowyDynamicPlugin.decode(src: directory);
          await plugins.addPlugin(plugin);
          return _ok({'imported': plugin.name});
        }
        final id = _requiredString(args, 'theme_id');
        if (args['operation'] == 'remove') {
          final plugin = await plugins.lookup(name: id);
          if (plugin == null) return _error('not_found', '主题不存在。');
          await FlowyPluginService.removePlugin(plugin);
          return _ok({'removed': id});
        }
        if (!getIt.isRegistered<AppearanceSettingsCubit>()) {
          return _error('ui_unavailable', '当前外观设置不可用。');
        }
        await getIt<AppearanceSettingsCubit>().setTheme(id);
        return _ok({'applied': id});
      },
    );
  }
}
