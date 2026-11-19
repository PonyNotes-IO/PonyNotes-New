part of 'mcp_tools.dart';

extension _McpStorageTools on McpTools {
  List<McpToolSpec> get _storageSpecs => [
        _actionTool(
          'storage_authorization',
          '发起百度网盘授权、查询状态、用安全句柄提交授权码或撤销授权。',
          {
            'operation': const JsonString(
              enumValues: ['start', 'status', 'complete', 'revoke'],
            ),
            'credential_ref': const JsonString(),
          },
          [],
          _storageAuthorization,
          required: const ['workspace_id', 'operation'],
        ),
        _actionTool(
          'remote_storage_files',
          '浏览已授权百度网盘或把指定文件导入本地文件库。',
          {
            'path': const JsonString(),
            'remote_file_id': const JsonString(),
            'name': const JsonString(),
            'offset': const JsonInteger(minimum: 0),
            'limit': const JsonInteger(minimum: 1, maximum: 100),
          },
          ['list_remote_storage_files', 'import_remote_storage_file'],
          _remoteStorageFiles,
        ),
        _actionTool(
          'assets',
          '上传/下载/删除当前工作区附件，输入输出须使用用户选择文件后的授权句柄。',
          {
            'source_handle': const JsonString(),
            'asset_url': const JsonString(),
            'destination_handle': const JsonString(),
            'name': const JsonString(),
          },
          ['upload_asset', 'download_asset', 'delete_asset'],
          _assets,
        ),
        _actionTool(
          'document_transfer',
          '直接导入Markdown/HTML/文本。PDF和Word打开客户端导入对话框。Notion ZIP创建新云工作区并返回任务ID。支持导出Markdown/HTML/PDF和数据库数据。',
          {
            'page_id': const JsonString(),
            'view_id': const JsonString(),
            'parent_id': const JsonString(),
            'source_handle': const JsonString(),
            'destination_handle': const JsonString(),
            'format': const JsonString(
              enumValues: [
                'markdown',
                'html',
                'text',
                'pdf',
                'word',
                'csv',
                'raw',
                'zip'
              ],
            ),
            'name': const JsonString(),
            'operation': const JsonString(
              enumValues: ['start', 'status', 'inspect', 'restore'],
            ),
            'backup_handle': const JsonString(),
            'task_id': const JsonString(),
          },
          [
            'export_database',
            'import_document',
            'import_workspace_data',
            'export_document',
            'export_workspace',
            'restore_workspace_data',
          ],
          _documentTransfer,
        ),
      ];

  Future<CallToolResult> _storageAuthorization(
    Map<String, dynamic> args,
  ) async {
    final error =
        await _validateWorkspace(_requiredString(args, 'workspace_id'));
    if (error != null) return error;
    final service = BaiduCloudService();
    switch (args['operation']) {
      case 'status':
        return _ok({'authorized': await service.isAuthorized()});
      case 'start':
        return _ok({
          'authorization_url': await service.getAuthorizationUrl(),
          'status': 'requires_human',
        });
      case 'complete':
        final code = await _resolveGrant(
          _requiredString(args, 'credential_ref'),
          'secret',
        );
        if (!await _confirm('storage_authorization', args)) {
          return _error('permission_denied', '用户未批准网盘授权。');
        }
        final success = await service.exchangeCodeForToken(code);
        return success
            ? _ok({'authorized': true})
            : _error('authorization_failed', '授权码交换失败。');
      case 'revoke':
        if (!await _confirm('storage_authorization', args)) {
          return _error('permission_denied', '用户未批准撤销网盘授权。');
        }
        await service.logout();
        return _ok({'authorized': false});
      default:
        throw const FormatException('未知网盘授权动作');
    }
  }

  Future<CallToolResult> _remoteStorageFiles(Map<String, dynamic> args) async {
    final error =
        await _validateWorkspace(_requiredString(args, 'workspace_id'));
    if (error != null) return error;
    final service = BaiduCloudService();
    if (!await service.isAuthorized()) {
      return _error('not_authorized', '请先授权百度网盘。');
    }
    if (args['action'] == 'list_remote_storage_files') {
      final files = await service.getFileList(
        dir: args['path'] as String? ?? '/',
        start: _intArg(args, 'offset', 0, 0, 0x7fffffff),
        limit: _intArg(args, 'limit', 100, 1, 100),
      );
      return _ok({
        'files': files
            .map(
              (f) => {
                'id': f.fsId,
                'path': f.path,
                'name': f.serverFilename,
                'size': f.size,
                'directory': f.isDirectory,
              },
            )
            .toList(),
      });
    }
    if (!await _confirm('remote_storage_files', args)) {
      return _error('permission_denied', '未批准网盘导入。');
    }
    final url = await service
        .getFileDownloadUrl(_requiredString(args, 'remote_file_id'));
    if (url == null) return _error('download_unavailable', '无法取得下载地址。');
    final name = _requiredString(args, 'name');
    if (paths.basename(name) != name ||
        !FileLibraryService.isExtensionAllowed(paths.extension(name))) {
      throw const FormatException('文件名或格式不支持');
    }
    final id = const Uuid().v4();
    final root = Directory(
      paths.join(
        await getIt<ApplicationDataStorage>().getPath(),
        'file_library',
      ),
    );
    await root.create(recursive: true);
    final target = paths.join(
      root.path,
      '${paths.basenameWithoutExtension(name)}_$id${paths.extension(name)}',
    );
    final result = await service.downloadFile(url, target);
    return result == null
        ? _error('download_failed', '网盘下载失败。')
        : _ok({'imported': id, 'name': name});
  }

  Future<CallToolResult> _assets(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id');
    final error = await _requireWriteAccess(workspace);
    if (error != null) return error;
    if (args['action'] == 'upload_asset') {
      final source = File(
        await _resolveGrant(_requiredString(args, 'source_handle'), 'file'),
      );
      final url = await FileUploadService.uploadFile(
        await source.readAsBytes(),
        paths.basename(source.path),
        workspaceId: workspace,
      );
      return _ok({'asset_url': url});
    }
    final url = Uri.parse(_requiredString(args, 'asset_url'));
    final account = await AgentCloudAccount.current();
    final base = Uri.parse(account.baseUrl);
    final prefix =
        '${base.path}/api/file_storage/${Uri.encodeComponent(workspace)}/blob/';
    if (url.origin != base.origin ||
        !url.path.startsWith(prefix) ||
        url.userInfo.isNotEmpty ||
        url.hasQuery ||
        url.hasFragment) {
      throw const FormatException('附件不属于当前工作区文件存储');
    }
    if (args['action'] == 'delete_asset') {
      if (!await _confirm('assets', args)) {
        return _error('permission_denied', '用户未批准删除附件。');
      }
      return _ok(await _cloudRequest('DELETE', url.path));
    }
    final target = await _outputFile(args, paths.basename(url.path));
    await AgentService().downloadCloudArtifact(
      await AgentService().identity(workspace),
      workspace,
      url.toString(),
      target,
    );
    return _ok({'saved': paths.basename(target.path)});
  }

  Future<CallToolResult> _documentTransfer(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id');
    final check = await _validateWorkspace(workspace);
    if (check != null) return check;
    final action = args['action'], format = args['format'] ?? 'markdown';
    if (action == 'export_document' &&
        !['markdown', 'html', 'pdf'].contains(format)) {
      throw const FormatException('文档导出支持markdown/html/pdf');
    }
    if (action == 'export_database' && !['csv', 'raw'].contains(format)) {
      throw const FormatException('数据库导出需指定csv或raw');
    }
    if (action == 'import_document' &&
        !['markdown', 'html', 'text', 'pdf', 'word'].contains(format)) {
      throw const FormatException('文档导入支持markdown/html/text/pdf/word');
    }
    if (action == 'export_workspace') return _exportWorkspaceData(args);
    if (action == 'restore_workspace_data') {
      final operation = args['operation'] ?? 'restore';
      if (operation != 'inspect' && operation != 'restore') {
        throw const FormatException('备份操作支持inspect/restore');
      }
      final directory = await _resolveGrant(
        _requiredString(
            args,
            args.containsKey('backup_handle')
                ? 'backup_handle'
                : 'source_handle'),
        'directory',
      );
      final kind = await _detectWorkspaceBackup(directory);
      if (operation == 'inspect') return _ok({'format': kind});
      if (kind == 'page_export_directory') {
        return _error('unsupported_backup', '请选择原生数据目录备份。页面导出包需逐页导入。');
      }
      final parent = _requiredString(args, 'parent_id');
      await _scopedView(workspace, parent, write: true);
      if (!await _confirm('document_transfer', args)) {
        return _error('permission_denied', '未批准导入工作区数据备份。');
      }
      await UserEventImportAppFlowyDataFolder(
        ImportAppFlowyDataPB(
          path: directory,
          parentViewId: parent,
          importContainerName: args['name'] as String? ?? '恢复的数据',
        ),
      ).send().getOrThrow();
      return _ok({'imported_backup': true, 'mode': 'non_destructive_import'});
    }
    if (action == 'import_workspace_data') return _importWorkspaceArchive(args);
    if (action == 'import_document') {
      final parent = _requiredString(args, 'parent_id');
      final target = await _scopedView(workspace, parent, write: true);
      if (!target.isSpace && target.layout != ViewLayoutPB.Document) {
        return _error('invalid_parent', '导入目标须为文档或空间。');
      }
      final file = File(
        await _resolveGrant(_requiredString(args, 'source_handle'), 'file'),
      );
      if (format == 'pdf' || format == 'word') {
        final extension = paths.extension(file.path).toLowerCase();
        final validExtensions = format == 'pdf' ? ['.pdf'] : ['.doc', '.docx'];
        final size = await file.length();
        if (!validExtensions.contains(extension) ||
            size == 0 ||
            !AliyunDocParseProcessor.isFileSizeValid(size)) {
          throw const FormatException('文件类型或大小不符合导入要求');
        }
        final context = AppGlobals.rootNavKey.currentContext;
        if (context == null || !context.mounted || !_executionIsActive()) {
          return _error('ui_unavailable', '该操作需要已打开并授权的客户端窗口。');
        }
        unawaited(showDialog<void>(
          context: context,
          builder: (_) => format == 'pdf'
              ? EnhancedPdfImportDialog(parentViewId: parent, initialFile: file)
              : EnhancedWordImportDialog(
                  parentViewId: parent, initialFile: file),
        ));
        return _ok({
          'status': 'requires_human',
          'format': format,
          'parent_id': parent
        });
      }
      if (format == 'text') {
        final text = systemEncoding.decode(await file.readAsBytes());
        return _createPage({
          'workspace_id': workspace,
          'parent_id': parent,
          'title': args['name'] ?? paths.basenameWithoutExtension(file.path),
        },
            initialDocument: Document(
                root: pageNode(children: [
              for (final line in text.split(RegExp(r'\r?\n')))
                paragraphNode(text: line),
            ])));
      }
      String markdown;
      if (format == 'html') {
        final bytes = await file.readAsBytes();
        String html;
        try {
          html = utf8.decode(bytes);
        } on FormatException {
          html = latin1.decode(bytes);
        }
        markdown = ProfessionalHtmlParser.convertHtmlToMarkdown(
          html,
          paths.basename(file.path),
        );
      } else {
        markdown = await file.readAsString();
      }
      return _createPage({
        'workspace_id': workspace,
        'parent_id': parent,
        'title': args['name'] ?? paths.basenameWithoutExtension(file.path),
        'markdown': markdown,
      });
    }
    if (action == 'export_database') {
      final view = _requiredString(args, 'view_id');
      final error = await _requireDatabaseView(workspace, view);
      if (error != null) return error;
      final payload = DatabaseViewIdPB(value: view);
      final data = format == 'raw'
          ? await DatabaseEventExportRawDatabaseData(payload)
              .send()
              .getOrThrow()
          : await DatabaseEventExportCSV(payload).send().getOrThrow();
      final file =
          await _outputFile(args, '$view.${format == 'raw' ? 'json' : 'csv'}');
      await file.writeAsString(data.data, flush: true);
      return _ok({'exported': paths.basename(file.path)});
    }
    final page = _requiredString(args, 'page_id');
    final view = await _scopedView(workspace, page);
    if (format == 'pdf') {
      if (view.layout != ViewLayoutPB.Document) {
        throw const FormatException('PDF导出需要文档页面');
      }
      final file = await _outputFile(args, '$page.pdf');
      if (!await _confirm('document_transfer', {
        ...args,
        'page_title': view.name,
        'behavior': '会加载此文档引用的本地图片和网络图片',
      })) {
        return _error('permission_denied', '未批准文档导出为PDF。');
      }
      final document = (await _readDocument(page, workspace))?.toDocument();
      if (document == null) {
        return _error('document_unavailable', '无法读取页面正文。');
      }
      final bytes =
          await DocumentPdfExporter.render(document, title: view.name);
      if (!_executionIsActive()) {
        return _error('permission_denied', '调用已超时或授权已撤销，未写入PDF。');
      }
      await file.create(exclusive: true);
      await file.writeAsBytes(bytes, flush: true);
      return _ok({'exported': paths.basename(file.path)});
    }
    final content = await DocumentExporter(view)
        .export(
          format == 'html'
              ? DocumentExportType.html
              : DocumentExportType.markdown,
        )
        .getOrThrow();
    final file =
        await _outputFile(args, '$page.${format == 'html' ? 'html' : 'md'}');
    await file.writeAsString(content, flush: true);
    return _ok({'exported': paths.basename(file.path)});
  }

  Future<String> _detectWorkspaceBackup(String directory) async {
    // Inspect only the directory structure. The native importer validates its database.
    if (await FileSystemEntity.type(paths.join(directory, 'cache.db'),
            followLinks: false) ==
        FileSystemEntityType.file) {
      await for (final child in Directory(directory).list(followLinks: false)) {
        if (child is Directory &&
            int.tryParse(paths.basename(child.path)) != null &&
            await FileSystemEntity.type(paths.join(child.path, 'collab_db'),
                    followLinks: false) ==
                FileSystemEntityType.directory) {
          return 'appflowy_data_directory';
        }
      }
    }
    final manifest = paths.join(directory, 'manifest.json');
    if (await FileSystemEntity.type(manifest, followLinks: false) ==
        FileSystemEntityType.file) {
      final prefix = await File(manifest)
          .openRead(0, 256)
          .transform(const Utf8Decoder(allowMalformed: true))
          .join();
      if (RegExp(r'"format"\s*:\s*"ponynotes-page-export-v1"')
          .hasMatch(prefix)) {
        return 'page_export_directory';
      }
    }
    return 'unknown';
  }

  Future<CallToolResult> _importWorkspaceArchive(
    Map<String, dynamic> args,
  ) async {
    final operation = args['operation'] ?? 'start';
    if (operation != 'start' && operation != 'status') {
      throw const FormatException('ZIP导入操作支持start/status');
    }
    if (operation == 'status') {
      final id = _requiredString(args, 'task_id');
      final response = await _cloudRequest('GET', '/api/import');
      final tasks = _object(response, 'data')['tasks'] as List;
      final task =
          tasks.cast<Map>().where((task) => task['task_id'] == id).firstOrNull;
      if (task == null) return _error('not_found', '当前账号没有这条导入任务。');
      final status = switch (task['status']) {
        0 => 'pending',
        1 => 'completed',
        2 => 'failed',
        3 => 'expired',
        4 => 'canceled',
        _ => 'unknown',
      };
      return _ok({'status': status, 'task': task});
    }

    if (args['parent_id'] != null || ![null, 'zip'].contains(args['format'])) {
      throw const FormatException('Notion ZIP导入创建新云工作区，不接受目标父页或其他格式');
    }
    final file = File(await _resolveGrant(
      _requiredString(args, 'source_handle'),
      'file',
    ));
    final size = await file.length();
    if (paths.extension(file.path).toLowerCase() != '.zip' || size == 0) {
      throw const FormatException('请选择非空的Notion ZIP文件');
    }
    if (!_executionIsActive()) {
      return _error('permission_denied', '授权已结束，未创建导入任务。');
    }
    final response = await _cloudRequest('POST', '/api/import/create', body: {
      'workspace_name':
          args['name'] ?? paths.basenameWithoutExtension(file.path),
      'content_length': size,
    });
    final data = _object(response, 'data');
    final id = _requiredString(data, 'task_id');
    final uri = Uri.tryParse(_requiredString(data, 'presigned_url'));
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return _error('upload_failed', '导入服务未返回可用的上传地址。',
          details: {'task_id': id});
    }
    final client = HttpClient();
    try {
      await (() async {
        final upload = await client.putUrl(uri);
        if (!_executionIsActive()) {
          throw StateError('MCP tool authorization ended');
        }
        upload.followRedirects = false;
        upload.contentLength = size;
        upload.headers.contentType = ContentType('application', 'zip');
        await upload.addStream(file.openRead());
        final result = await upload.close();
        if (result.statusCode < 200 || result.statusCode >= 300) {
          throw HttpException('Archive upload rejected (${result.statusCode})');
        }
        await result.drain<void>();
      })()
          .timeout(const Duration(seconds: 55));
    } catch (_) {
      return _error('upload_unconfirmed', '无法确认ZIP已上传，请先查询原任务状态。',
          details: {'task_id': id});
    } finally {
      client.close(force: true);
    }
    return _ok({'task_id': id, 'status': 'submitted'});
  }

  Future<CallToolResult> _exportWorkspaceData(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id');
    if (!await _confirm('document_transfer', args)) {
      return _error('permission_denied', '未批准导出工作区数据');
    }
    final target = await _outputFile(
      args,
      'workspace-$workspace-${DateTime.now().millisecondsSinceEpoch}',
    );
    final directory = await Directory(target.path).create();
    final views = (await ViewBackendService.getAllViews().getOrThrow()).items;
    final records = <Map<String, dynamic>>[];
    var skipped = 0;
    for (final view in views) {
      if (!_executionIsActive()) {
        skipped = views.length - records.length;
        break;
      }
      try {
        await _scopedView(workspace, view.id);
      } catch (_) {
        skipped++;
        continue;
      }
      final metadata = view.toProto3Json() as Map;
      metadata.remove('childViews');
      final entry = <String, dynamic>{'view': metadata};
      records.add(entry);
      try {
        if (view.isSpace) {
          entry['status'] = 'metadata_only';
          continue;
        }
        String content, extension;
        if (view.layout == ViewLayoutPB.Document) {
          final extra = view.extra.isEmpty
              ? <String, dynamic>{}
              : jsonDecode(view.extra) as Map;
          if (extra['view_type'] == 'handwriting_saber') {
            final snapshot = await HandwritingSaberDataService()
                .captureSnapshotForDuplicate(view.id);
            content = snapshot.localData.isEmpty
                ? EditorCoreInfo.empty(pageId: view.id).toJsonString()
                : utf8.decode(snapshot.localData);
            extension = 'ponynhw';
          } else {
            content = await DocumentExporter(view)
                .export(DocumentExportType.json)
                .getOrThrow();
            extension = 'afdocument';
          }
        } else if ([
          ViewLayoutPB.Grid,
          ViewLayoutPB.Board,
          ViewLayoutPB.Calendar,
        ].contains(view.layout)) {
          content = (await DatabaseEventExportRawDatabaseData(
            DatabaseViewIdPB(value: view.id),
          ).send().getOrThrow())
              .data;
          extension = 'database.json';
        } else if (view.layout == ViewLayoutPB.Whiteboard) {
          final scene = await WhiteboardToolBridge.execute(
            view.id,
            {'action': 'export', 'format': 'ponynotes'},
          );
          content = scene['json'] as String;
          extension = 'ponynotes';
        } else {
          throw UnsupportedError('该页面类型没有数据导出接口');
        }
        final name = '${view.id}.$extension';
        await File(paths.join(directory.path, name))
            .writeAsString(content, flush: true);
        entry.addAll({'status': 'exported', 'file': name});
      } catch (error) {
        entry.addAll({'status': 'failed', 'error': '$error'});
      }
    }
    final failed =
        records.where((record) => record['status'] == 'failed').length;
    await File(paths.join(directory.path, 'manifest.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'format': 'ponynotes-page-export-v1',
        'workspace_id': workspace,
        'complete': failed == 0 && skipped == 0,
        'skipped': skipped,
        'snapshot_backup': false,
        'includes_asset_bytes': false,
        'views': records,
      }),
      flush: true,
    );
    return _ok({
      'status': failed == 0 && skipped == 0 ? 'exported' : 'partial',
      'directory': paths.basename(directory.path),
      'exported':
          records.where((record) => record['status'] == 'exported').length,
      'failed': failed,
      'skipped': skipped,
      'snapshot_backup': false,
      'message': '包含页面数据和目录清单；附件保留引用，账号、权限和完整快照需由各自备份流程处理。',
    });
  }
}
