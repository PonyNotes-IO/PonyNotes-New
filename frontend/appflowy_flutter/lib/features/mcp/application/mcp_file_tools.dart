part of 'mcp_tools.dart';

class _McpGrant {
  _McpGrant(this.identity, this.value, this.kind)
      : expires = DateTime.now().add(const Duration(minutes: 15));
  final String identity, value, kind;
  final DateTime expires;
}

final _mcpGrants = <String, _McpGrant>{};

extension _McpFileTools on McpTools {
  Future<String> _grantIdentity() async {
    final profile = await _currentProfile(),
        workspace = await _currentWorkspace();
    if (profile == null || workspace == null) throw StateError('请先登录并打开工作区');
    return '${profile.id}|${profile.workspaceType}|${workspace.id}';
  }

  Future<String> _grant(String value, String kind) async {
    if (!_executionIsActive()) throw StateError('工具调用已结束或授权已撤销');
    _mcpGrants
        .removeWhere((_, grant) => grant.expires.isBefore(DateTime.now()));
    final id = const Uuid().v4();
    if (_mcpGrants.length >= 128) throw StateError('授权句柄数量已达上限，请稍后重试');
    _mcpGrants[id] = _McpGrant(await _grantIdentity(), value, kind);
    Timer(const Duration(minutes: 15), () => _mcpGrants.remove(id));
    return id;
  }

  Future<String> _resolveGrant(String id, String kind) async {
    if (!_executionIsActive()) throw StateError('工具调用已结束或授权已撤销');
    final grant = _mcpGrants[id];
    if (grant == null ||
        grant.kind != kind ||
        grant.expires.isBefore(DateTime.now()) ||
        grant.identity != await _grantIdentity()) {
      throw StateError('授权句柄已失效，请重新由用户选择');
    }
    return grant.value;
  }

  Future<String?> _askSecret(String label) async {
    final context = AppGlobals.rootNavKey.currentContext;
    if (context == null || !context.mounted) return null;
    final identity = await _grantIdentity();
    if (!context.mounted) return null;
    final controller = TextEditingController();
    try {
      final value = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(label),
          content: TextField(
            controller: controller,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: '仅用于当前授权操作'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('授权'),
            ),
          ],
        ),
      );
      if (value == null ||
          value.isEmpty ||
          identity != await _grantIdentity()) {
        return null;
      }
      return _grant(value, 'secret');
    } finally {
      controller.dispose();
    }
  }

  List<McpToolSpec> get _fileSpecs => [
        _actionTool(
          'system_action',
          '由用户选择文件/输出目录或输入凭据，返回15分钟有效的不透明句柄；也可经确认打开HTTP(S)网址。',
          {
            'operation': const JsonString(
              enumValues: [
                'pick_file',
                'pick_directory',
                'secret',
                'open_url',
              ],
            ),
            'url': const JsonString(),
            'label': const JsonString(),
          },
          [],
          _systemAction,
          required: const ['workspace_id', 'operation'],
        ),
        _actionTool(
          'clipboard_action',
          '读写文本剪贴板、复制/剪切/粘贴文档选区或打开系统分享。访问剪贴板前均由客户端确认；选区操作须提供expected_text。',
          {
            'operation': const JsonString(
              enumValues: [
                'read',
                'write',
                'clear',
                'copy',
                'cut',
                'paste',
                'share',
              ],
            ),
            'text': const JsonString(),
            'page_id': const JsonString(),
            'block_id': const JsonString(),
            'range': const JsonObject(),
            'expected_text': const JsonString(),
          },
          [],
          _clipboardAction,
          required: const ['workspace_id', 'operation'],
        ),
        _actionTool(
          'library_files',
          '列出、读取、导入、打开、删除或重命名本机文件库项目。本地输入/输出使用system_action授权句柄。',
          {
            'file_id': const JsonString(),
            'source_handle': const JsonString(),
            'name': const JsonString(),
            'query': const JsonString(),
            'offset': const JsonInteger(minimum: 0),
            'limit': const JsonInteger(minimum: 1, maximum: 500),
            'operation': const JsonString(enumValues: ['rename', 'export','move','share']),
            'destination_handle': const JsonString(),
          },
          [
            'list_library_files',
            'get_library_file',
            'import_library_file',
            'open_library_file',
            'delete_library_file',
            'manage_library_file',
          ],
          _libraryFiles,
        ),
      ];

  Future<CallToolResult> _systemAction(Map<String, dynamic> args) async {
    final check =
        await _validateWorkspace(_requiredString(args, 'workspace_id'));
    if (check != null) return check;
    final identity = await _grantIdentity();
    switch (args['operation']) {
      case 'secret':
        final id = await _askSecret(args['label'] as String? ?? '授权工具使用凭据');
        return id == null
            ? _error('cancelled', '用户未提供凭据。')
            : _ok({'credential_ref': id});
      case 'pick_file':
        final picked = await FilePicker.platform.pickFiles();
        final path = picked?.files.single.path;
        if (path == null || identity != await _grantIdentity()) {
          return _error('cancelled', '文件选择已取消。');
        }
        return _ok({
          'source_handle': await _grant(path, 'file'),
          'name': paths.basename(path),
        });
      case 'pick_directory':
        final path = await FilePicker.platform.getDirectoryPath();
        if (path == null || identity != await _grantIdentity()) {
          return _error('cancelled', '目录选择已取消。');
        }
        return _ok({'destination_handle': await _grant(path, 'directory')});
      case 'open_url':
        final url = Uri.parse(_requiredString(args, 'url'));
        if (!const ['http', 'https'].contains(url.scheme) ||
            url.userInfo.isNotEmpty) {
          throw const FormatException('只允许无内嵌凭据的HTTP(S)网址');
        }
        if (!await _confirm('system_action', args)) {
          return _error('permission_denied', '用户未批准打开网址。');
        }
        return _ok({'opened': await afLaunchUri(url)});
      default:
        throw const FormatException('未知系统操作');
    }
  }

  Future<CallToolResult> _clipboardAction(Map<String, dynamic> args) async {
    final check =
        await _validateWorkspace(_requiredString(args, 'workspace_id'));
    if (check != null) return check;
    if (!await _confirm('clipboard_action', args)) {
      return _error('permission_denied', '用户未批准访问剪贴板。');
    }
    final operation = args['operation'];
    if (operation == 'share') {
      await Share.share(_requiredString(args, 'text'));
      return _ok({'status': 'handed_to_system_share_sheet'});
    }
    if (['copy', 'cut', 'paste'].contains(operation)) {
      final page = _requiredString(args, 'page_id'),
          block = _requiredString(args, 'block_id');
      final read = await _documentText({
        'workspace_id': args['workspace_id'],
        'action': 'get_block',
        'page_id': page,
        'block_id': block,
      });
      if (read.isError) return read;
      final payload =
          jsonDecode((read.content.single as TextContent).text) as Map;
      final text = payload['text'] as String;
      if (payload['next_offset'] != null) {
        throw const FormatException('请将剪贴板操作限制在20000字符以内的块');
      }
      if (args['expected_text'] != text) {
        return _error('content_changed', '请重新读取正文后提供expected_text');
      }
      final range = _object(args, 'range'),
          start = range['start'],
          length = range['length'];
      if (start is! int ||
          length is! int ||
          start < 0 ||
          length < 0 ||
          start + length > text.length) {
        throw const FormatException('选区越界');
      }
      if (operation != 'paste') {
        await Clipboard.setData(
          ClipboardData(text: text.substring(start, start + length)),
        );
      }
      if (operation == 'copy') return _ok({'copied_characters': length});
      final replacement = operation == 'cut'
          ? ''
          : (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
      return _documentText({
        'workspace_id': args['workspace_id'],
        'action': 'edit_text',
        'page_id': page,
        'block_id': block,
        'expected_text': text,
        'range': range,
        'replacement_delta': replacement.isEmpty
            ? []
            : [
                {'insert': replacement},
              ],
      });
    }
    if (args['operation'] == 'read') {
      return _ok({
        'text': (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '',
      });
    }
    await Clipboard.setData(
      ClipboardData(
        text: args['operation'] == 'clear' ? '' : _requiredString(args, 'text'),
      ),
    );
    return _ok({'completed': true});
  }

  Future<CallToolResult> _libraryFiles(Map<String, dynamic> args) async {
    final check =
        await _validateWorkspace(_requiredString(args, 'workspace_id'));
    if (check != null) return check;
    final service = FileLibraryService();
    final files = await service.getAllFiles();
    final action = args['action'];
    Map<String, dynamic> summary(FileLibraryItem item) =>
        {'file_id': item.id, 'name': item.name, 'size': item.size};
    if (action == 'list_library_files') {
      final query = args['query'] as String? ?? '';
      final items = files.where((file) => file.name.contains(query)).toList();
      return _ok({
        'files': items
            .skip(_intArg(args, 'offset', 0, 0, 0x7fffffff))
            .take(_intArg(args, 'limit', 100, 1, 500))
            .map(summary)
            .toList(),
        'total': items.length,
      });
    }
    if (action == 'import_library_file') {
      final source = File(
        await _resolveGrant(_requiredString(args, 'source_handle'), 'file'),
      );
      if (!FileLibraryService.isExtensionAllowed(
        paths.extension(source.path),
      )) {
        throw const FormatException('不支持的文件类型');
      }
      final root = paths.join(
        await getIt<ApplicationDataStorage>().getPath(),
        'file_library',
      );
      await Directory(root).create(recursive: true);
      final id = const Uuid().v4();
      final name = args['name'] as String? ?? paths.basename(source.path);
      if (paths.basename(name) != name) {
        throw const FormatException('文件名不能包含路径');
      }
      final target = paths.join(
        root,
        '${paths.basenameWithoutExtension(name)}_$id${paths.extension(name)}',
      );
      await source.copy(target);
      return _ok({'imported': true, 'file_id': id, 'name': name});
    }
    final id = _requiredString(args, 'file_id');
    final item = files.where((file) => file.id == id).firstOrNull;
    if (item == null) return _error('not_found', '文件库项目不存在。');
    if (action == 'get_library_file') {
      return _ok(
        {...summary(item), 'source_handle': await _grant(item.url, 'file')},
      );
    }
    if (action == 'open_library_file') {
      if (!await _confirm('library_files', args)) {
        return _error('permission_denied', '用户未批准打开文件。');
      }
      await service.openPdfFile(item);
      return _ok({'opened': id});
    }
    if (action == 'delete_library_file') {
      if (!await _confirm('library_files', args)) {
        return _error('permission_denied', '用户未批准删除文件。');
      }
      await File(item.url).delete();
      return _ok({'deleted': id});
    }
    if(args['operation']=='share') {
      if(!await _confirm('library_files',args))return _error('permission_denied','未批准分享文件');
      await Share.shareXFiles([XFile(item.url)]);
      return _ok({'status':'handed_to_system_share_sheet'});
    }
    if (args['operation'] == 'export' || args['operation']=='move') {
      final directory = await _resolveGrant(
        _requiredString(args, 'destination_handle'),
        'directory',
      );
      final target = File(paths.join(directory, paths.basename(item.name)));
      if (await target.exists()) return _error('conflict', '输出文件已存在。');
      if(args['operation']=='move' && !await _confirm('library_files',args))return _error('permission_denied','未批准移出文件库');
      await File(item.url).copy(target.path);
      if(args['operation']=='move')await File(item.url).delete();
      return _ok({'exported': item.name,'removed_from_library':args['operation']=='move'});
    }
    final name = _requiredString(args, 'name');
    if (paths.basename(name) != name) throw const FormatException('文件名不能包含路径');
    if (!FileLibraryService.isExtensionAllowed(paths.extension(name))) {
      throw const FormatException('文件扩展名不受支持');
    }
    final target = paths.join(
      paths.dirname(item.url),
      '${paths.basenameWithoutExtension(name)}_$id${paths.extension(name)}',
    );
    if (await File(target).exists()) return _error('conflict', '目标文件已存在。');
    await File(item.url).rename(target);
    return _ok({'renamed': id, 'name': name});
  }
}
