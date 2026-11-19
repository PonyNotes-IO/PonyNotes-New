part of 'mcp_tools.dart';

extension _McpCanvasTools on McpTools {
  List<McpToolSpec> get _canvasSpecs => [
        _actionTool(
          'whiteboards',
          '读取和编辑已打开白板的实时场景，元素写入使用版本检查。可导入原始场景并查询平台支持的导出格式。',
          {
            'view_id': const JsonString(),
            'operations': const JsonArray(
              items: JsonObject(
                properties: {
                  'action': JsonString(
                      enumValues: ['add', 'update', 'delete', 'reorder']),
                  'element': JsonObject(description: 'add时提供完整元素和唯一id'),
                  'element_id': JsonString(description: 'update/delete时指定元素ID'),
                  'expected_version': JsonInteger(
                      minimum: 0,
                      description:
                          'update/delete时使用get_whiteboard返回的元素version'),
                  'properties': JsonObject(description: 'update时提供要更新的属性'),
                  'element_ids': JsonArray(
                      items: JsonString(), description: 'reorder时提供所有元素ID的新顺序'),
                  'expected_versions': JsonObject(
                      additionalProperties: JsonInteger(minimum: 0),
                      description: 'reorder时提供各元素ID到最新version的映射'),
                },
                required: ['action'],
                additionalProperties: false,
                extra: {
                  'oneOf': [
                    {
                      'properties': {
                        'action': {'const': 'add'}
                      },
                      'required': ['element']
                    },
                    {
                      'properties': {
                        'action': {'const': 'update'}
                      },
                      'required': [
                        'element_id',
                        'expected_version',
                        'properties'
                      ]
                    },
                    {
                      'properties': {
                        'action': {'const': 'delete'}
                      },
                      'required': ['element_id', 'expected_version']
                    },
                    {
                      'properties': {
                        'action': {'const': 'reorder'}
                      },
                      'required': ['element_ids', 'expected_versions']
                    },
                  ],
                },
              ),
            ),
            'view_state': const JsonObject(properties: {
              'scrollX': JsonNumber(),
              'scrollY': JsonNumber(),
              'zoom': JsonNumber(minimum: 0.1, maximum: 10)
            }, additionalProperties: false),
            'destination_handle': const JsonString(),
            'name': const JsonString(),
            'source_handle': const JsonString(),
            'format': const JsonString(enumValues: ['ponynotes', 'svg', 'png']),
          },
          [
            'get_whiteboard',
            'edit_whiteboard',
            'import_whiteboard',
            'export_whiteboard',
            'save_whiteboard',
            'whiteboard_capabilities',
          ],
          _whiteboards,
          required: const ['workspace_id', 'view_id', 'action'],
        ),
        _actionTool(
          'handwriting_documents',
          '读取手写结构、修改指定页对象、管理页面，导入或导出源文件/PDF。写入要求expected_document与读取结果完全一致。',
          {
            'view_id': const JsonString(),
            'page_index': const JsonInteger(minimum: 0),
            'expected_document': const JsonObject(),
            'document': const JsonObject(),
            'operations': const JsonArray(items: JsonObject()),
            'operation': const JsonString(
              enumValues: ['add', 'delete', 'reorder', 'background'],
            ),
            'page': const JsonObject(),
            'order': const JsonArray(items: JsonString()),
            'source_handle': const JsonString(),
            'destination_handle': const JsonString(),
            'asset_kind':
                const JsonString(enumValues: ['source', 'pdf', 'image', 'web']),
            'url': const JsonString(),
            'name': const JsonString(),
            'format': const JsonString(enumValues: ['ponynhw', 'pdf']),
            'tool': const JsonString(),
            'color': const JsonInteger(),
            'width': const JsonNumber(minimum: 0, maximum: 100),
          },
          [
            'get_handwriting',
            'edit_handwriting',
            'set_handwriting_tool',
            'extract_pdf_text',
            'manage_handwriting_pages',
            'import_handwriting_asset',
            'export_handwriting',
            'save_handwriting',
            'handwriting_capabilities',
          ],
          _handwriting,
          required: const ['workspace_id', 'view_id', 'action'],
        ),
      ];

  Future<File> _outputFile(
    Map<String, dynamic> args,
    String defaultName,
  ) async {
    final directory = await _resolveGrant(
      _requiredString(args, 'destination_handle'),
      'directory',
    );
    final name = args['name'] as String? ?? defaultName;
    if (paths.basename(name) != name || name == '.' || name == '..') {
      throw const FormatException('文件名无效');
    }
    final file = File(paths.join(directory, name));
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('输出路径已存在，请指定新名称');
    }
    return file;
  }

  Future<CallToolResult> _whiteboards(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id'),
        view = _requiredString(args, 'view_id');
    await _scopedView(
      workspace,
      view,
      write: const ['edit_whiteboard', 'import_whiteboard', 'save_whiteboard']
          .contains(args['action']),
    );
    if (args['action'] == 'whiteboard_capabilities') {
      final live = WhiteboardToolBridge.isOpen(view)
          ? await WhiteboardToolBridge.execute(view, {'action': 'capabilities'})
          : <String, dynamic>{};
      return _ok({
        'requires_open_editor': true,
        'open': WhiteboardToolBridge.isOpen(view),
        'actions': [
          'get_whiteboard',
          'edit_whiteboard',
          'import_whiteboard',
          'export_whiteboard',
          'save_whiteboard',
        ],
        'export_formats': live['formats'] ?? ['ponynotes'],
        'save_available': live['save_available'] ?? false,
        'element_operations': ['add', 'update', 'delete', 'reorder'],
        'version_required_for_update': true,
      });
    }
    final action = switch (args['action']) {
      'get_whiteboard' => 'read',
      'edit_whiteboard' => 'edit',
      'import_whiteboard' => 'import',
      'export_whiteboard' => 'export',
      _ => 'save'
    };
    Map<String, dynamic>? scene;
    if (action == 'import') {
      final file = File(
        await _resolveGrant(_requiredString(args, 'source_handle'), 'file'),
      );
      scene = Map<String, dynamic>.from(
        jsonDecode(await file.readAsString()) as Map,
      );
    }
    final result = await WhiteboardToolBridge.execute(view, {
      'action': action,
      'format': args['format'] ?? 'ponynotes',
      if (scene != null) 'scene': scene,
      'operations': args['operations'] ?? [],
      if (args['view_state'] != null) 'view_state': args['view_state'],
    });
    if (action == 'export') {
      final file =
          await _outputFile(args, '$view.${args['format'] ?? 'ponynotes'}');
      if (result['base64'] is String) {
        await file.writeAsBytes(
          base64Decode(result['base64'] as String),
          flush: true,
        );
      } else {
        await file.writeAsString(
          (result['text'] ?? result['json']) as String,
          flush: true,
        );
      }
      return _ok({'exported': paths.basename(file.path)});
    }
    return _ok(result);
  }

  Future<CallToolResult> _handwriting(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id'),
        view = _requiredString(args, 'view_id'),
        action = _requiredString(args, 'action');
    final read = const [
      'get_handwriting',
      'handwriting_capabilities',
      'export_handwriting',
    ].contains(action);
    final pageView = await _scopedView(workspace, view, write: !read);
    if (pageView.extra.isEmpty ||
        (jsonDecode(pageView.extra) as Map)['view_type'] !=
            'handwriting_saber') {
      throw const FormatException('目标不是手写文档');
    }
    if (action == 'set_handwriting_tool') {
      return _ok(HandwritingSaberDataService.controlTool(view, args));
    }
    if (action == 'extract_pdf_text') {
      final file =
          await _resolveGrant(_requiredString(args, 'source_handle'), 'file');
      return _ok({
        'pages': (args['page_index'] is int
                ? {
                    args['page_index'] as int:
                        await PdfTextExtractionService.extractPageTextFromFile(
                      file,
                      args['page_index'] as int,
                    ),
                  }
                : await PdfTextExtractionService.extractAllPagesTextFromFile(
                    file,
                  ))
            .map((page, text) => MapEntry('$page', text)),
      });
    }
    if (action == 'handwriting_capabilities') {
      return _ok({
        'coordinate_space': 'document logical pixels',
        'object_kinds': [
          'strokes',
          'images',
          'webViews',
          'textBoxes',
          'listBoxes',
          'taskListBoxes',
        ],
        'export_formats': ['ponynhw', 'pdf'],
        'import_formats': ['ponynhw', 'pdf', 'image', 'web'],
        'write_precondition': 'expected_document必须等于当前文档',
      });
    }
    final service = HandwritingSaberDataService();
    final snapshot = await service.captureSnapshotForDuplicate(view);
    final current = snapshot.localData.isEmpty
        ? EditorCoreInfo.empty(pageId: view).toJson()
        : Map<String, dynamic>.from(
            jsonDecode(utf8.decode(snapshot.localData)) as Map,
          );
    if (action == 'get_handwriting') {
      return _ok({'view_id': view, 'document': current});
    }
    if (action == 'export_handwriting') {
      final file =
          await _outputFile(args, '$view.${args['format'] ?? 'ponynhw'}');
      if (args['format'] == 'pdf') {
        final context = AppGlobals.rootNavKey.currentContext;
        if (context == null || !context.mounted) throw StateError('当前窗口不可用');
        final document = await EditorExporter.generatePdf(
          EditorCoreInfo.fromJson(current),
          context,
        );
        await file.writeAsBytes(await document.save(), flush: true);
      } else {
        await file.writeAsString(jsonEncode(current), flush: true);
      }
      return _ok({'exported': paths.basename(file.path)});
    }
    if (!const DeepCollectionEquality()
        .equals(current, args['expected_document'])) {
      return _error('content_changed', '手写内容已变化，请重新读取后编辑。');
    }
    final updated =
        Map<String, dynamic>.from(jsonDecode(jsonEncode(current)) as Map);
    final pages = (updated['pages'] as List).cast<Map>();
    final importedPaths = <String>{};
    if (action == 'import_handwriting_asset') {
      await _importHandwritingAsset(args, pages, importedPaths);
      updated['pages'] = pages;
    } else if (action == 'manage_handwriting_pages') {
      final operation = args['operation'];
      if (args['page_index'] is int &&
          (args['page_index'] as int) >= pages.length) {
        throw const FormatException('页索引越界');
      }
      if (operation == 'add') {
        pages.add({..._object(args, 'page'), 'id': const Uuid().v4()});
      } else if (operation == 'delete') {
        if (pages.length <= 1) throw const FormatException('不能删除最后一页');
        if (!await _confirm('handwriting_documents', args)) {
          return _error('permission_denied', '未批准删除手写页。');
        }
        pages.removeAt(args['page_index'] as int);
      } else if (operation == 'reorder') {
        final order = (args['order'] as List).cast<String>();
        if (order.length != pages.length ||
            order.toSet().length != pages.length ||
            order.any((id) => !pages.any((p) => p['id'] == id))) {
          throw const FormatException('页顺序必须包含全部唯一页ID');
        }
        final sorted =
            order.map((id) => pages.firstWhere((p) => p['id'] == id)).toList();
        pages
          ..clear()
          ..addAll(sorted);
      } else {
        final patch = _object(args, 'page');
        const allowed = {
          'backgroundImage',
          'backgroundColor',
          'backgroundPattern',
          'lineHeight',
          'lineThickness',
          'width',
          'height',
        };
        if (patch.keys.any((key) => !allowed.contains(key))) {
          throw const FormatException('背景操作不接受页面对象/ID；修改对象请使用edit_handwriting');
        }
        for (final key in [
          'backgroundColor',
          'backgroundPattern',
          'lineHeight',
          'lineThickness',
        ]) {
          if (patch.containsKey(key)) updated[key] = patch[key];
        }
        pages[args['page_index'] as int].addAll(
          {...patch}..removeWhere(
              (key, _) => [
                'backgroundColor',
                'backgroundPattern',
                'lineHeight',
                'lineThickness',
              ].contains(key),
            ),
        );
      }
      updated['pages'] = pages;
    } else if (action == 'edit_handwriting') {
      final index = args['page_index'] as int? ?? 0;
      if (index >= pages.length) throw const FormatException('页面索引越界');
      for (final op in (args['operations'] as List).cast<Map>()) {
        if (!['add', 'update', 'delete'].contains(op['action'])) {
          throw const FormatException('对象操作须为add/update/delete');
        }
        final kind = op['kind'];
        if (!const [
          'strokes',
          'images',
          'webViews',
          'textBoxes',
          'listBoxes',
          'taskListBoxes',
        ].contains(kind)) {
          throw const FormatException('未知手写对象类型');
        }
        final items = (pages[index][kind] as List? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        final target = items.indexWhere((item) => item['id'] == op['id']);
        if (op['action'] == 'add') {
          if (target >= 0) throw const FormatException('对象ID重复');
          items.add({
            ...Map<String, dynamic>.from(op['value'] as Map),
            'id': op['id'] ??
                (kind == 'webViews'
                    ? DateTime.now().microsecondsSinceEpoch
                    : const Uuid().v4()),
          });
        } else {
          if (target < 0) throw const FormatException('对象不存在');
          if (op['action'] == 'delete') {
            items.removeAt(target);
          } else {
            items[target] = {
              ...items[target],
              ...Map<String, dynamic>.from(op['value'] as Map),
              'id': items[target]['id'],
            };
          }
        }
        pages[index][kind] = items;
      }
      updated['pages'] = pages;
    }
    final existingPaths = <String>{...importedPaths};
    void gather(Object? value) {
      if (value is String &&
          (paths.isAbsolute(value) || value.startsWith('file:'))) {
        existingPaths.add(value);
      }
      if (value is Map)
        for (final child in value.values) {
          gather(child);
        }
      if (value is List)
        for (final child in value) {
          gather(child);
        }
    }

    gather(current);
    if (args['source_handle'] is String) {
      existingPaths
          .add(await _resolveGrant(args['source_handle'] as String, 'file'));
    }
    void validatePaths(Object? value) {
      if (value is String &&
          (paths.isAbsolute(value) || value.startsWith('file:')) &&
          !existingPaths.contains(value)) {
        throw const FormatException('新增本地资源路径必须先通过文件选择授权；不能在画布数据中注入任意文件路径');
      }
      if (value is Map)
        for (final child in value.values) {
          validatePaths(child);
        }
      if (value is List)
        for (final child in value) {
          validatePaths(child);
        }
    }

    validatePaths(updated);
    final normalized = EditorCoreInfo.fromJson(updated);
    if (!_executionIsActive()) {
      return _error('permission_denied', '调用已超时或授权已撤销，未保存本次修改。');
    }
    final latest = await service.captureSnapshotForDuplicate(view);
    if (!listEquals(snapshot.localData, latest.localData)) {
      return _error('content_changed', '提交前手写内容已改变，未保存本次修改。');
    }
    final saved = await service.saveHandwritingSaberData(
      view,
      utf8.encode(normalized.toJsonStringForCollab()),
      localData: utf8.encode(normalized.toJsonString()),
    );
    if (!saved) return _error('write_unconfirmed', '手写保存未确认，请重新读取。');
    HandwritingSaberDataService.triggerReload(view);
    return _ok({'saved': true, 'view_id': view});
  }

  Future<void> _importHandwritingAsset(
    Map<String, dynamic> args,
    List<Map> pages,
    Set<String> importedPaths,
  ) async {
    final index = args['page_index'] as int? ?? 0;
    if (index >= pages.length) throw const FormatException('目标页索引越界');
    final kind = args['asset_kind'] as String? ?? 'source';
    final target = handwriting.EditorPage.fromJson(
      Map<String, dynamic>.from(pages[index]),
    );
    if (kind == 'web') {
      final url = Uri.parse(_requiredString(args, 'url'));
      if (!['https', 'http'].contains(url.scheme) || url.userInfo.isNotEmpty) {
        throw const FormatException('只允许无内嵌凭据的HTTP(S)网页');
      }
      if (!await _confirm('handwriting_documents', args)) {
        throw StateError('用户未批准嵌入网页');
      }
      final elements = List<Map>.from(pages[index]['webViews'] as List? ?? []);
      final nextId = elements.fold<int>(
            0,
            (value, item) => max(value, (item['id'] as int?) ?? 0),
          ) +
          1;
      elements.add(
        WebViewEditorElement(
          id: nextId,
          url: url.toString(),
          pageIndex: index,
          pageSize: target.size,
        ).toJson(),
      );
      pages[index]['webViews'] = elements;
      return;
    }
    final source = File(
      await _resolveGrant(_requiredString(args, 'source_handle'), 'file'),
    );
    if (kind == 'source') {
      final decoded = jsonDecode(await source.readAsString());
      if (decoded is! Map<String, dynamic> ||
          decoded['pages'] is! List ||
          (decoded['pages'] as List).isEmpty) {
        throw const FormatException('手写源文件必须包含非空pages数组');
      }
      final incoming = EditorCoreInfo.fromJson(decoded).toJson();
      final ids = pages.map((page) => page['id']).toSet();
      for (final page in (incoming['pages'] as List).cast<Map>()) {
        if (!ids.add(page['id'])) throw const FormatException('导入页面ID冲突');
      }
      pages.addAll((incoming['pages'] as List).cast<Map>());
      return;
    }
    final bytes = await source.readAsBytes();
    final cloud =
        (await _currentProfile())!.workspaceType != WorkspaceTypePB.LocalW;
    if (kind == 'image') {
      if (!['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp']
          .contains(paths.extension(source.path).toLowerCase())) {
        throw const FormatException('不支持的图片格式');
      }
      final image = PngEditorImage(
        id: const Uuid().v4(),
        imageBytes: bytes,
        extension: paths.extension(source.path),
        pageIndex: index,
        pageSize: target.size,
        dstRect: const Rect.fromLTWH(50, 50, 200, 200),
      );
      if (cloud) {
        image.imageUrl = await FileUploadService.uploadFile(
          bytes,
          paths.basename(source.path),
          workspaceId: _requiredString(args, 'workspace_id'),
        );
      }
      pages[index]['images'] = [
        ...pages[index]['images'] as List? ?? [],
        image.toJson(),
      ];
      return;
    }
    final cached = await HandwritingPdfCacheService().cacheImportedPdf(bytes);
    importedPaths.add(cached);
    final document = await PdfDocumentCacheManager().load(cached);
    if (document.pages.isEmpty) throw const FormatException('PDF没有页面');
    final url = cloud
        ? await FileUploadService.uploadFile(
            bytes,
            paths.basename(source.path),
            workspaceId: _requiredString(args, 'workspace_id'),
          )
        : null;
    for (final page in document.pages) {
      final size = Size(
        handwriting.EditorPage.defaultWidth,
        handwriting.EditorPage.defaultWidth * page.height / page.width,
      );
      pages.add(
        handwriting.EditorPage(
          size: size,
          backgroundImage: PdfEditorImage(
            pdfFilePath: cached,
            pdfUrl: url,
            pdfPageIndex: page.pageNumber - 1,
            naturalSize: Size(page.width, page.height),
            dstRect: Offset.zero & size,
          ),
        ).toJson(),
      );
    }
  }
}
