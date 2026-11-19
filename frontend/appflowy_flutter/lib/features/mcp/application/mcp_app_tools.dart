part of 'mcp_tools.dart';

extension _McpAppTools on McpTools {
  List<McpToolSpec> get _appSpecs => [
        _actionTool(
          'manage_spaces',
          '创建/修改空间，调整根级顺序或移到回收站；可见性和删除由客户端确认。',
          {
            'space_id': const JsonString(),
            'name': const JsonString(),
            'icon': const JsonString(),
            'icon_color': const JsonString(),
            'visibility':
                const JsonString(enumValues: ['public', 'private', 'closed']),
            'after_id': const JsonString(),
          },
          ['create_space', 'update_space', 'move_space', 'delete_space'],
          _manageSpaces,
        ),
        _actionTool(
          'app_update',
          '读取版本、检查更新或启动当前平台的更新交互。安装由系统更新器确认。',
          {
            'operation': const JsonString(
              enumValues: ['version', 'check', 'download', 'install'],
            ),
          },
          [],
          _appUpdate,
          required: const ['workspace_id', 'operation'],
        ),
        _actionTool(
          'local_data',
          '查询本机数据与缓存，清理缓存，或计划下次重启迁移数据目录。',
          {
            'operation': const JsonString(
              enumValues: ['get', 'usage', 'migrate', 'clear_cache'],
            ),
            'destination_handle': const JsonString(),
          },
          ['manage_data_location', 'manage_local_data'],
          _localData,
        ),
        _actionTool(
          'device_capability_request',
          '查询/请求系统相机、相册、麦克风、通知权限；仅在调用时请求。',
          {
            'capability': const JsonString(
              enumValues: [
                'camera',
                'photos',
                'microphone',
                'notifications',
              ],
            ),
            'operation': const JsonString(enumValues: ['status', 'start']),
          },
          [],
          _deviceCapability,
          required: const ['workspace_id', 'capability', 'operation'],
        ),
        _actionTool(
          'app_navigation',
          '导航到页面或设置页，读取/切换/关闭标签。',
          {
            'destination': const JsonString(),
            'view_id': const JsonString(),
            'tab_id': const JsonString(),
            'operation': const JsonString(
              enumValues: [
                'list',
                'open',
                'activate',
                'close',
                'split',
                'select',
                'find',
                'replace',
              ],
            ),
            'index': const JsonInteger(minimum: 0),
            'page_id': const JsonString(),
            'block_id': const JsonString(),
            'expected_text': const JsonString(),
            'range': const JsonObject(),
            'query': const JsonString(),
            'replacement': const JsonString(),
            'sidebar_visible': const JsonBoolean(),
            'fullscreen': const JsonBoolean(),
            'zoom': const JsonNumber(minimum: 0.5, maximum: 2),
          },
          [
            'navigate_app',
            'manage_tabs',
            'editor_selection_action',
            'update_app_view',
          ],
          _appNavigation,
        ),
        _actionTool(
          'document_sync',
          '观察文档同步状态，或重新打开文档触发已有同步流程。未知状态不会被当作同步完成。',
          {
            'page_id': const JsonString(),
            'operation': const JsonString(enumValues: ['status', 'retry']),
          },
          [],
          _documentSync,
          required: const ['workspace_id', 'page_id', 'operation'],
        ),
      ];

  Future<CallToolResult> _manageSpaces(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id');
    final check = await _requireWriteAccess(workspace);
    if (check != null) return check;
    int permission() =>
        switch (args['visibility']) { 'private' => 1, 'closed' => 2, _ => 0 };
    if (args['action'] == 'create_space') {
      final view = await ViewBackendService.createView(
        parentViewId: workspace,
        name: _requiredString(args, 'name'),
        layoutType: ViewLayoutPB.Document,
        openAfterCreate: false,
        section:
            permission() == 1 ? ViewSectionPB.Private : ViewSectionPB.Public,
        extra: jsonEncode({
          'is_space': true,
          'space_icon': args['icon'] ?? '📁',
          'space_icon_color': args['icon_color'] ?? '',
          'space_permission': permission(),
          'space_created_at': DateTime.now().millisecondsSinceEpoch,
        }),
      ).getOrThrow();
      return _ok({'space': _viewToJson(view)});
    }
    final view = await _scopedView(
      workspace,
      _requiredString(args, 'space_id'),
      write: true,
    );
    if (!view.isSpace) throw const FormatException('目标不是空间');
    if (args['action'] == 'delete_space') {
      if (!await _confirm('manage_spaces', args)) {
        return _error('permission_denied', '用户未批准删除空间。');
      }
      await ViewBackendService.deleteView(viewId: view.id).getOrThrow();
      return _ok({'trashed': view.id});
    }
    if (args['action'] == 'move_space') {
      final after = args['after_id'] as String?;
      if (after != null && after.isNotEmpty) {
        final sibling = await _scopedView(workspace, after);
        if (!sibling.isSpace || sibling.id == view.id) {
          throw const FormatException('after_id须为其他空间');
        }
      }
      await ViewBackendService.moveViewV2(
        viewId: view.id,
        newParentId: workspace,
        prevViewId: after,
      ).getOrThrow();
    } else {
      if (args.containsKey('visibility') &&
          !await _confirm('manage_spaces', args)) {
        return _error('permission_denied', '用户未批准空间可见性变更。');
      }
      await SpaceUpdateExecutor(
        updateView: ViewBackendService.updateView,
        updateVisibility: ViewBackendService.updateViewsVisibility,
      )
          .execute(
            space: view,
            name: args['name'] as String?,
            icon: args['icon'] as String?,
            iconColor: args['icon_color'] as String?,
            permissionIndex:
                args.containsKey('visibility') ? permission() : null,
            isPublic: args.containsKey('visibility')
                ? args['visibility'] == 'public'
                : null,
          )
          .getOrThrow();
    }
    return _ok({'space': _viewToJson((await _view(view.id))!)});
  }

  Future<CallToolResult> _appUpdate(Map<String, dynamic> args) async {
    final error =
        await _validateWorkspace(_requiredString(args, 'workspace_id'));
    if (error != null) return error;
    final operation = args['operation'];
    if (operation == 'version') {
      return _ok({
        'version': ApplicationInfo.applicationVersion,
        'build': ApplicationInfo.buildNumber,
        'platform': Platform.operatingSystem,
      });
    }
    if (operation == 'check') {
      final item = await versionChecker.checkForUpdateInformation();
      return _ok({
        'update': item == null
            ? null
            : {
                'version': item.versionString,
                'title': item.title,
                'url': item.fileURL,
              },
        'check_completed': item != null,
      });
    }
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      return _error('unsupported_platform', '此平台通过应用商店更新。');
    }
    if (!await _confirm('app_update', args)) {
      return _error('permission_denied', '未批准启动更新器。');
    }
    await versionChecker.checkForUpdate();
    return _ok(
      {'status': 'requires_human', 'message': '已启动当前平台的更新流程，请在更新器中确认下载和安装。'},
    );
  }

  Future<CallToolResult> _localData(Map<String, dynamic> args) async {
    final error =
        await _validateWorkspace(_requiredString(args, 'workspace_id'));
    if (error != null) return error;
    final storage = getIt<ApplicationDataStorage>();
    if (args['operation'] == 'get' || args['operation'] == 'usage') {
      return _ok({
        'data_path': await storage.getPath(),
        'cache_bytes': getIt.isRegistered<FlowyCacheManager>()
            ? await getIt<FlowyCacheManager>().getCacheSize()
            : null,
      });
    }
    if (!await _confirm('local_data', args)) {
      return _error('permission_denied', '未批准数据管理操作。');
    }
    if (args['operation'] == 'clear_cache') {
      await getIt<FlowyCacheManager>().clearAllCache();
      return _ok({'cache_clear_requested': true});
    }
    final destination = await _resolveGrant(
      _requiredString(args, 'destination_handle'),
      'directory',
    );
    final settings =
        await const UserSettingsBackendService().getUserSetting().getOrThrow();
    final target = await storage.scheduleCustomPathMigration(
      path: destination,
      activeDataPath: paths.dirname(settings.userFolder),
    );
    return _ok(
      {'scheduled': true, 'destination': target, 'requires_restart': true},
    );
  }

  Future<CallToolResult> _deviceCapability(Map<String, dynamic> args) async {
    final error =
        await _validateWorkspace(_requiredString(args, 'workspace_id'));
    if (error != null) return error;
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
      return _error('unsupported_platform', '当前平台不通过此接口管理设备授权。');
    }
    final permission = switch (args['capability']) {
      'camera' => permissions.Permission.camera,
      'photos' => permissions.Permission.photos,
      'microphone' => permissions.Permission.microphone,
      _ => permissions.Permission.notification
    };
    final status = args['operation'] == 'start'
        ? !await _confirm('device_capability_request', args)
            ? null
            : await permission.request()
        : await permission.status;
    return status == null
        ? _error('permission_denied', '用户未批准系统权限请求。')
        : _ok({'capability': args['capability'], 'status': status.name});
  }

  Future<CallToolResult> _appNavigation(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id');
    final error = await _validateWorkspace(workspace);
    if (error != null) return error;
    final context = AppGlobals.rootNavKey.currentContext;
    if (context == null || !context.mounted) {
      return _error('ui_unavailable', '当前窗口不可用。');
    }
    if (args['action'] == 'update_app_view') {
      if (args['zoom'] != null) {
        return _error('unsupported_platform', '当前版本全局缩放已暂停以避免白板偏移，未修改缩放。');
      }
      if (args['fullscreen'] == true) FullWindowController.enter();
      if (args['fullscreen'] == false) FullWindowController.exit();
      if (args['sidebar_visible'] is bool) {
        final bloc = context.read<HomeSettingBloc>();
        bloc.add(
          HomeSettingEvent.changeMenuStatus(
            args['sidebar_visible'] == true
                ? MenuStatus.expanded
                : MenuStatus.hidden,
          ),
        );
      }
      return _ok({
        'fullscreen': FullWindowController.isFullWindow.value,
        'sidebar_requested': args['sidebar_visible'],
      });
    }
    if (args['action'] == 'editor_selection_action') {
      final page = _requiredString(args, 'page_id');
      await _scopedView(workspace, page);
      final editor = DocumentBloc.findOpen(page)?.state.editorState;
      if (editor == null) return _error('ui_unavailable', '请先打开目标文档。');
      final block = args['block_id'] as String?;
      if (args['operation'] == 'find') {
        final query = _requiredString(args, 'query');
        return _ok({
          'matches': _flattenDocument(editor.document.root)
              .where((b) => b.text.contains(query))
              .map(
                (b) => {'block_id': b.node.id, 'offset': b.text.indexOf(query)},
              )
              .toList(),
        });
      }
      if (block == null) throw const FormatException('需要block_id');
      final node = _findNode(editor.document, block);
      if (node?.delta == null) return _error('not_found', '文本块不存在。');
      final range = _object(args, 'range'),
          start = range['start'],
          length = range['length'];
      if (start is! int ||
          length is! int ||
          start < 0 ||
          length < 0 ||
          start + length > node!.delta!.length) {
        throw const FormatException('选区越界');
      }
      if (args['operation'] == 'replace') {
        return _documentText({
          'workspace_id': workspace,
          'page_id': page,
          'block_id': block,
          'action': 'edit_text',
          'range': range,
          'expected_text': args['expected_text'],
          'replacement_delta': [
            {'insert': args['replacement'] ?? ''},
          ],
        });
      }
      await editor.updateSelectionWithReason(
        Selection(
          start: Position(path: node.path, offset: start),
          end: Position(path: node.path, offset: start + length),
        ),
      );
      return _ok({'selection_set': true});
    }
    if (args['action'] == 'navigate_app' && args['destination'] != null) {
      final page = SettingsPage.values
          .where((p) => p.name == args['destination'])
          .firstOrNull;
      if (page == null) {
        throw const FormatException('destination须为设置页名称，打开页面请提供view_id');
      }
      final profile = (await _currentProfile())!;
      if (!context.mounted) return _error('ui_unavailable', '当前窗口已关闭。');
      unawaited(showSettingsDialog(context, profile, null, page));
      return _ok({'opened_settings': page.name});
    }
    final tabs = getIt<TabsBloc>();
    if (args['operation'] == 'close') {
      tabs.add(TabsEvent.closeTab(_requiredString(args, 'tab_id')));
    } else if (args['operation'] == 'activate')
      tabs.add(TabsEvent.selectTab(args['index'] as int));
    else if (args['operation'] == 'list')
      return _ok({
        'current_index': tabs.state.currentIndex,
        'tabs': [
          for (var i = 0; i < tabs.state.pageManagers.length; i++)
            {'index': i, 'tab_id': tabs.state.pageManagers[i].plugin.id},
        ],
      });
    else {
      final view =
          await _scopedView(workspace, _requiredString(args, 'view_id'));
      if (args['operation'] == 'split') {
        tabs.add(
          TabsEvent.openSecondaryPlugin(plugin: view.plugin(), view: view),
        );
      } else {
        tabs.add(TabsEvent.openPlugin(plugin: view.plugin(), view: view));
      }
    }
    return _ok({'requested': true});
  }

  Future<CallToolResult> _documentSync(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id'),
        page = _requiredString(args, 'page_id');
    await _scopedView(workspace, page);
    final state = Completer<DocumentSyncStatePB>();
    final listener = DocumentSyncStateListener(id: page)
      ..start(
        didReceiveSyncState: (value) {
          if (!state.isCompleted) state.complete(value);
        },
      );
    try {
      if (args['operation'] == 'retry') {
        await _documentService
            .openDocument(documentId: page, workspaceId: workspace)
            .getOrThrow();
      }
      final result = await state.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => DocumentSyncStatePB(),
      );
      return _ok({
        'page_id': page,
        'state': state.isCompleted ? result.toProto3Json() : null,
        'observed': state.isCompleted,
        'retry_requested': args['operation'] == 'retry',
      });
    } finally {
      await listener.stop();
    }
  }
}
