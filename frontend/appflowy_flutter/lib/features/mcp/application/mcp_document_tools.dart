part of 'mcp_tools.dart';

extension _McpDocumentTools on McpTools {
  List<McpToolSpec> get _documentSpecs => [
        _actionTool(
          'document_text',
          '读取完整富文本delta，局部替换或格式化文本。range使用UTF-16偏移，与编辑器一致；编辑须提交expected_text。',
          {
            'page_id': const JsonString(),
            'block_id': const JsonString(),
            'range': const JsonObject(
              properties: {
                'start': JsonInteger(minimum: 0),
                'length': JsonInteger(minimum: 0),
              },
              required: [
                'start',
                'length',
              ],
              additionalProperties: false,
            ),
            'expected_text': const JsonString(),
            'replacement_delta': const JsonArray(items: JsonObject()),
            'attributes': const JsonObject(),
            'offset': const JsonInteger(minimum: 0),
            'limit': const JsonInteger(minimum: 1, maximum: 20000),
          },
          ['get_block', 'edit_text', 'format_text'],
          _documentText,
          required: const ['workspace_id', 'action', 'page_id', 'block_id'],
        ),
        _actionTool(
          'document_versions',
          '列出/读取/比较/保存/恢复历史版本，执行撤销或重做。恢复需要客户端确认。',
          {
            'page_id': const JsonString(),
            'snapshot_id': const JsonString(),
            'from_snapshot_id': const JsonString(),
            'to_snapshot_id': const JsonString(),
            'operation': const JsonString(enumValues: ['undo', 'redo']),
            'offset': const JsonInteger(minimum: 0),
          },
          [
            'document_history_action',
            'list_document_versions',
            'get_document_version',
            'diff_document_versions',
            'save_document_version',
            'restore_document_version',
          ],
          _documentVersions,
          required: const ['workspace_id', 'action', 'page_id'],
        ),
        _actionTool(
          'document_blocks',
          '复制/转换块、修改样式/媒体/公式，编辑简单表格与分栏。',
          {
            'page_id': const JsonString(),
            'block_id': const JsonString(),
            'target_type': const JsonString(),
            'attributes': const JsonObject(),
            'target_parent_id': const JsonString(),
            'after_block_id': const JsonString(),
            'formula': const JsonString(),
            'url': const JsonString(),
            'width': const JsonNumber(),
            'caption': const JsonString(),
            'align': const JsonString(),
            'indent': const JsonInteger(minimum: 0),
            'operation': const JsonString(),
            'row': const JsonInteger(minimum: 0),
            'column': const JsonInteger(minimum: 0),
            'values': const JsonArray(items: JsonString()),
            'widths': const JsonArray(items: JsonNumber()),
            'column_count': const JsonInteger(minimum: 2, maximum: 4),
            'block_ids': const JsonArray(items: JsonString()),
            'offset': const JsonInteger(minimum: 0),
            'expected_text': const JsonString(),
            'user_id': const JsonString(),
          },
          [
            'convert_block',
            'update_block_style',
            'duplicate_block',
            'update_media_block',
            'update_equation',
            'edit_simple_table',
            'update_columns',
            'transform_blocks',
            'insert_person_mention',
          ],
          _documentBlocks,
          required: const ['workspace_id', 'action', 'page_id', 'block_id'],
        ),
      ];

  Future<CallToolResult> _documentText(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id'),
        page = _requiredString(args, 'page_id');
    final id = _requiredString(args, 'block_id'),
        action = _requiredString(args, 'action');
    final view =
        await _scopedView(workspace, page, write: action != 'get_block');
    if (view.layout != ViewLayoutPB.Document || view.isSpace) {
      return _error('unsupported_layout', '目标不是文档页面。');
    }
    final state = await _loadEditorState(page, workspace);
    if (state == null) return _error('document_unavailable', '无法读取文档。');
    try {
      final node = _findNode(state.document, id);
      if (node == null) return _error('not_found', '内容块不存在。');
      final delta = node.delta;
      if (delta == null) return _error('unsupported_block', '此块不包含富文本。');
      if (action == 'get_block') {
        final offset = _intArg(args, 'offset', 0, 0, delta.length);
        final limit = _intArg(args, 'limit', 20000, 1, 20000);
        final end = min(offset + limit, delta.length);
        return _ok({
          'block_id': id,
          'type': node.type,
          'attributes': McpTools.blockAttributes(node),
          'delta': delta.slice(offset, end).toJson(),
          'text': delta.slice(offset, end).toPlainText(),
          'length': delta.length,
          'next_offset': end < delta.length ? end : null,
        });
      }
      final range = _object(args, 'range');
      final start = range['start'], length = range['length'];
      if (start is! int ||
          length is! int ||
          start < 0 ||
          length < 0 ||
          start + length > delta.length) {
        throw const FormatException('文本范围越界');
      }
      if (args['expected_text'] is! String ||
          delta.toPlainText() != args['expected_text']) {
        return _error('content_changed', '正文已变化，请重新读取后提交expected_text。');
      }
      final transaction = state.transaction;
      final selection = Selection(
        start: Position(path: node.path, offset: start),
        end: Position(path: node.path, offset: start + length),
      );
      if (action == 'format_text') {
        final attributes = _object(args, 'attributes');
        const allowed = {
          'bold',
          'italic',
          'underline',
          'strikethrough',
          'code',
          'href',
          'font_color',
          'background_color',
          'highlight',
        };
        if (attributes.keys.any((key) => !allowed.contains(key))) {
          throw const FormatException('不支持的文本格式属性');
        }
        transaction.formatText(node, start, length, attributes);
      } else {
        final replacement = args['replacement_delta'];
        if (replacement is! List) {
          throw const FormatException('需要replacement_delta');
        }
        final inserted = Delta.fromJson(replacement);
        if (inserted.toJson().any((op) => !op.containsKey('insert'))) {
          throw const FormatException('replacement_delta只接受insert操作');
        }
        final change = Delta()
          ..retain(start)
          ..delete(length);
        for (final op in inserted.toJson()) {
          change.insert(
            op['insert'] as String,
            attributes: op['attributes'] as Map<String, dynamic>?,
          );
        }
        final updated = delta.compose(change);
        transaction.updateNode(node, {blockComponentDelta: updated.toJson()});
      }
      transaction.afterSelection = selection;
      final failure = await persistDocument(
        pageId: page,
        workspaceId: workspace,
        state: state,
        transaction: transaction,
        verify: (data) => const DeepCollectionEquality()
            .equals(data.toDocument()?.toJson(), state.document.toJson()),
      );
      if (failure != null) return failure;
      return _ok({'block_id': id, 'updated': true});
    } finally {
      await _closeEditorState(page, state);
    }
  }

  Future<CallToolResult> _documentVersions(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id'),
        page = _requiredString(args, 'page_id'),
        action = _requiredString(args, 'action');
    final read = const [
      'list_document_versions',
      'get_document_version',
      'diff_document_versions',
    ].contains(action);
    await _scopedView(workspace, page, write: !read);
    final service = VersionHistoryService();
    switch (action) {
      case 'list_document_versions':
        return _message(
          await service.list(
            page,
            offset: _intArg(args, 'offset', 0, 0, 0x7fffffff),
          ),
        );
      case 'get_document_version':
        return _message(
          await service.get(page, _requiredString(args, 'snapshot_id')),
        );
      case 'save_document_version':
        return _message(await service.save(page));
      case 'restore_document_version':
        final before = await service.readCurrent(page);
        if (!await _confirm('document_versions', args)) {
          return _error('permission_denied', '未批准恢复历史版本。');
        }
        if (!const DeepCollectionEquality().equals(
          before.toProto3Json(),
          (await service.readCurrent(page)).toProto3Json(),
        )) {
          return _error('content_changed', '确认期间文档已改变，未恢复历史版本。');
        }
        return _message(
          await service.restore(page, _requiredString(args, 'snapshot_id')),
        );
      case 'diff_document_versions':
        Future<DocumentDataPB> version(String? id) =>
            id == null || id == 'current'
                ? service.readCurrent(page)
                : service.get(page, id);
        final from = await version(args['from_snapshot_id'] as String?);
        final to = await version(args['to_snapshot_id'] as String?);
        final diff = compareHistory((from, to));
        return _ok({
          'lines': diff.lines
              .map((line) => {'change': line.change.name, 'text': line.text})
              .toList(),
        });
      case 'document_history_action':
        await _documentService
            .openDocument(documentId: page, workspaceId: workspace)
            .getOrThrow();
        final payload = DocumentRedoUndoPayloadPB(documentId: page);
        if (args['operation'] == 'undo') {
          await DocumentEventUndo(payload).send().getOrThrow();
        } else if (args['operation'] == 'redo') {
          await DocumentEventRedo(payload).send().getOrThrow();
        } else {
          throw const FormatException('需要undo或redo');
        }
        return _ok({
          'completed': true,
          'document': (await service.readCurrent(page)).toProto3Json(),
        });
      default:
        throw const FormatException('未知历史操作');
    }
  }

  Future<CallToolResult> _documentBlocks(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id'),
        page = _requiredString(args, 'page_id'),
        id = _requiredString(args, 'block_id');
    final check = await _requireWritableDocument(workspace, page);
    if (check != null) return check;
    final state = await _loadEditorState(page, workspace);
    if (state == null) return _error('document_unavailable', '无法读取文档。');
    try {
      final node = _findNode(state.document, id);
      if (node == null || node == state.document.root) {
        return _error('not_found', '目标块不存在。');
      }
      final transaction = state.transaction;
      final action = args['action'];
      switch (action) {
        case 'convert_block':
          final type = _requiredString(args, 'target_type');
          final replacement = McpTools.createBlockNode(
            type,
            {'text': node.delta?.toPlainText() ?? ''},
          );
          if (replacement == null) throw const FormatException('目标块类型不可转换');
          final converted = node.copyWith(
            type: replacement.type,
            attributes: {
              ...node.attributes,
              ...replacement.attributes,
              if (node.delta != null) blockComponentDelta: node.delta!.toJson(),
            },
          );
          transaction.deleteNode(node);
          transaction.insertNode(node.path, converted);
        case 'duplicate_block':
          final parent = args['target_parent_id'] == null
              ? node.parent
              : _findNode(state.document, args['target_parent_id'] as String);
          if (parent == null) throw const FormatException('父块不存在');
          final after = args['after_block_id'] == null
              ? null
              : _findNode(state.document, args['after_block_id'] as String);
          if (after != null && after.parent != parent) {
            throw const FormatException('定位块不属于目标父级');
          }
          transaction.insertNode(
            after?.path.next ?? parent.path.child(parent.children.length),
            node.copyWith(),
          );
        case 'update_equation':
          transaction
              .updateNode(node, {'formula': _requiredString(args, 'formula')});
        case 'update_media_block':
          if (!const ['image', 'video', 'file', 'link_preview']
              .contains(node.type)) {
            throw const FormatException('目标不是媒体块');
          }
          transaction.updateNode(node, {
            if (args['url'] != null) 'url': args['url'],
            if (args['width'] != null) 'width': args['width'],
            if (args['caption'] != null) 'caption': args['caption'],
          });
        case 'update_block_style':
          transaction.updateNode(node, {
            if (args['align'] != null) 'align': args['align'],
            if (args['indent'] != null) 'indent': args['indent'],
          });
        case 'update_columns':
          if (node.type != SimpleColumnsBlockKeys.type) {
            throw const FormatException('目标不是分栏块');
          }
          final count = args['column_count'] as int? ?? node.children.length;
          if (count < node.children.length) {
            final removed = node.children.skip(count);
            if (removed.any((column) => column.children.any((child) =>
                child.type != ParagraphBlockKeys.type ||
                child.children.isNotEmpty ||
                (child.delta?.toPlainText() ?? '').isNotEmpty,),)) {
              return _error('requires_content_move', '减少分栏前请先移动末尾列内容，避免丢失已有块。');
            }
            for (final column in removed.toList().reversed) {
              transaction.deleteNode(column);
            }
          }
          final widths = (args['widths'] as List).cast<num>();
          if (widths.length != count || widths.any((w) => w <= 0)) {
            throw const FormatException('列宽数量不匹配或宽度无效');
          }
          for (var i = 0; i < min(count, node.children.length); i++) {
            transaction.updateNode(
              node.children[i],
              {
                SimpleColumnBlockKeys.ratio:
                    widths[i] / widths.reduce((a, b) => a + b),
              },
            );
          }
          for (var i = node.children.length; i < count; i++) {
            transaction.insertNode(
                node.path.child(i),
                simpleColumnNode(
                    ratio: widths[i] / widths.reduce((a, b) => a + b),),);
          }
        case 'edit_simple_table':
          return await _editSimpleTable(args, state, node);
        case 'transform_blocks':
          if (node.delta == null) throw const FormatException('目标不是文本块');
          if (args['expected_text'] != node.delta!.toPlainText()) {
            return _error('content_changed', '请先读取最新文本并提交expected_text。');
          }
          if (args['operation'] == 'split') {
            final offset = args['offset'];
            if (offset is! int || offset < 0 || offset > node.delta!.length) {
              throw const FormatException('拆分位置越界');
            }
            transaction.updateNode(
              node,
              {blockComponentDelta: node.delta!.slice(0, offset).toJson()},
            );
            final tail = paragraphNode()
              ..updateAttributes(
                {blockComponentDelta: node.delta!.slice(offset).toJson()},
              );
            transaction.insertNode(node.path.next, tail);
          } else if (args['operation'] == 'merge') {
            final ids = (args['block_ids'] as List? ?? []).cast<String>();
            final merge =
                ids.map((id) => _findNode(state.document, id)).toList();
            if (ids.isEmpty ||
                ids.toSet().length != ids.length ||
                ids.first != node.id ||
                merge.any(
                  (n) =>
                      n == null ||
                      n.delta == null ||
                      n.parent != node.parent ||
                      n.children.isNotEmpty,
                )) {
              throw const FormatException('只可合并同级无子树的文本块，block_ids以当前块开头');
            }
            for (var i = 1; i < merge.length; i++) {
              if (merge[i]!.path.last != merge[i - 1]!.path.last + 1) {
                throw const FormatException('合并块必须按顺序相邻');
              }
            }
            final merged =
                Delta.fromJson([for (final n in merge) ...n!.delta!.toJson()]);
            transaction
                .updateNode(node, {blockComponentDelta: merged.toJson()});
            for (final n in merge.skip(1).toList().reversed) {
              transaction.deleteNode(n!);
            }
          } else {
            throw const FormatException('operation须为split/merge');
          }
        case 'insert_person_mention':
          if (node.delta == null ||
              args['offset'] is! int ||
              (args['offset'] as int) > node.delta!.length) {
            throw const FormatException('目标文本或插入位置无效');
          }
          if (args['expected_text'] != node.delta!.toPlainText()) {
            return _error('content_changed', '请先读取最新文本并提交expected_text。');
          }
          final userId = _requiredString(args, 'user_id');
          final members =
              await UserBackendService(userId: (await _currentProfile())!.id)
                  .getWorkspaceMembers(workspace)
                  .getOrThrow();
          final member = members.items
              .where((member) => member.uid.toString() == userId)
              .firstOrNull;
          if (member == null) return _error('not_found', '工作区成员不存在。');
          transaction.insertText(
            node,
            args['offset'] as int,
            MentionBlockKeys.mentionChar,
            attributes: MentionBlockKeys.buildMentionUserAttributes(
              userId: userId,
              userName: member.name,
            ),
          );
      }
      final failure = await persistDocument(
        pageId: page,
        workspaceId: workspace,
        state: state,
        transaction: transaction,
        verify: (data) => const DeepCollectionEquality()
            .equals(data.toDocument()?.toJson(), state.document.toJson()),
      );
      return failure ?? _ok({'updated': true});
    } finally {
      await _closeEditorState(page, state);
    }
  }

  Future<CallToolResult> _editSimpleTable(
    Map<String, dynamic> args,
    EditorState state,
    Node node,
  ) async {
    if (node.type != SimpleTableBlockKeys.type || node.children.isEmpty) {
      throw const FormatException('目标不是简单表格');
    }
    final operation = _requiredString(args, 'operation');
    final row = args['row'] as int?;
    final column = args['column'] as int?;
    final rows = node.children.length,
        columns = node.children.first.children.length;
    final transaction = state.transaction;
    final index = row ?? column;
    if (index == null || index < 0 || index > (row != null ? rows : columns)) {
      throw const FormatException('行列位置越界');
    }
    final insertion = operation == 'insert';
    if (!insertion && index == (row != null ? rows : columns)) {
      throw const FormatException('目标行列不存在');
    }
    final values = (args['values'] as List? ?? []).cast<String>();
    Node cell(int i) => simpleTableCellBlockNode(
          children: [paragraphNode(text: i < values.length ? values[i] : '')],
        );
    if (insertion || operation == 'duplicate') {
      final at = insertion ? index : index + 1;
      if (row != null) {
        final inserted = operation == 'duplicate'
            ? node.children[index].copyWith()
            : simpleTableRowBlockNode(
                children: [for (var i = 0; i < columns; i++) cell(i)],
              );
        transaction.insertNode(node.path.child(at), inserted);
      } else {
        for (var i = 0; i < rows; i++) {
          final parent = node.children[i];
          transaction.insertNode(
            parent.path.child(at),
            operation == 'duplicate'
                ? parent.children[index].copyWith()
                : cell(i),
          );
        }
      }
      final attributes = node.mapTableAttributes(
        node,
        type: row != null
            ? TableMapOperationType.insertRow
            : TableMapOperationType.insertColumn,
        index: at,
      );
      if (attributes != null) transaction.updateNode(node, attributes);
    } else if (operation == 'delete') {
      if ((row != null ? rows : columns) <= 1) {
        throw const FormatException('不能删除最后一行或列');
      }
      if (row != null) {
        transaction.deleteNode(node.children[index]);
      } else {
        for (final parent in node.children) {
          transaction.deleteNode(parent.children[index]);
        }
      }
      final attributes = node.mapTableAttributes(
        node,
        type: row != null
            ? TableMapOperationType.deleteRow
            : TableMapOperationType.deleteColumn,
        index: index,
      );
      if (attributes != null) transaction.updateNode(node, attributes);
    } else if (operation == 'clear' || operation == 'set') {
      final cells = row != null
          ? node.children[index].children
          : node.children.map((r) => r.children[index]).toList();
      for (var i = 0; i < cells.length; i++) {
        transaction.deleteNode(cells[i]);
        transaction.insertNode(
          cells[i].path,
          simpleTableCellBlockNode(
            children: [
              paragraphNode(
                text: operation == 'clear'
                    ? ''
                    : i < values.length
                        ? values[i]
                        : '',
              ),
            ],
          ),
        );
      }
    } else if (operation == 'width') {
      final width = args['width'];
      if (column == null || width is! num || width <= 0) {
        throw const FormatException('需要column和正数width');
      }
      final widths = Map<String, dynamic>.from(
        node.attributes[SimpleTableBlockKeys.columnWidths] as Map? ?? {},
      );
      widths['$index'] = width;
      transaction.updateNode(node, {SimpleTableBlockKeys.columnWidths: widths});
    } else {
      throw const FormatException(
        'operation须为insert/duplicate/delete/clear/set/width',
      );
    }
    final error = await persistDocument(
      pageId: _requiredString(args, 'page_id'),
      workspaceId: _requiredString(args, 'workspace_id'),
      state: state,
      transaction: transaction,
      verify: (data) => const DeepCollectionEquality()
          .equals(data.toDocument()?.toJson(), state.document.toJson()),
    );
    return error ?? _ok({'table_id': node.id, 'updated': true});
  }
}
