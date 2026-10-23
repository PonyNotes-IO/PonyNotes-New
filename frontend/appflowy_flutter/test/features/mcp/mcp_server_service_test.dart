import 'dart:async';
import 'dart:convert';

import 'package:appflowy/features/mcp/application/mcp_server_service.dart';
import 'package:appflowy/features/mcp/application/mcp_permissions.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/features/mcp/application/mcp_tools.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/util/time.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart'
    hide quoteNode;
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor_plugins/appflowy_editor_plugins.dart';
import 'package:appflowy/workspace/presentation/widgets/date_picker/widgets/reminder_selector.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:protobuf/protobuf.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('revoking a tool blocks calls on an existing MCP session', () async {
    SharedPreferences.setMockInitialValues({});
    await McpPermissions.instance.load();
    addTearDown(McpPermissions.instance.allowAll);
    final tools =
        McpTools(endpoint: 'test', version: 'test', isAgentChannel: true);
    var calls = 0;
    final spec = McpToolSpec(
      name: 'permission_probe',
      description: 'No backend access',
      inputSchema: const JsonObject(additionalProperties: false),
      handler: (_) async {
        calls++;
        return CallToolResult(content: [TextContent(text: 'executed')]);
      },
    );
    tools.toolSpecs
      ..clear()
      ..add(spec);
    final toServer = StreamController<List<int>>();
    final toClient = StreamController<List<int>>();
    final server =
        McpServer(const Implementation(name: 'server', version: 'test'));
    tools.registerAll(server);
    final client =
        McpClient(const Implementation(name: 'client', version: 'test'));
    addTearDown(() async {
      await client.close();
      await server.close();
      await toServer.close();
      await toClient.close();
    });
    await server.connect(
      IOStreamTransport(stream: toServer.stream, sink: toClient.sink),
    );
    await client.connect(
      IOStreamTransport(stream: toClient.stream, sink: toServer.sink),
    );
    const request = CallToolRequest(name: 'permission_probe');
    expect((await client.callTool(request)).isError, isFalse);
    await McpPermissions.instance.setAllowed(spec.name, false);
    final blocked = await client.callTool(request);
    expect(blocked.isError, isTrue);
    expect(
      (jsonDecode((blocked.content.single as TextContent).text) as Map)['error']
          ['code'],
      'permission_denied',
    );
    expect(calls, 1);
    // Internal AI intentionally has its own authorization path.
    final internal = McpTools(endpoint: 'test', version: 'test');
    internal.toolSpecs
      ..clear()
      ..add(spec);
    expect((await internal.executeTool(spec.name, {})).isError, isFalse);
    await McpPermissions.instance.setAllowed(spec.name, true);
    expect((await client.callTool(request)).isError, isFalse);
    expect(calls, 3);
  });

  test('write confirmation uses backend data, never the submitted memory state',
      () async {
    final service = _WriteTestDocumentService();
    final tools =
        McpTools(endpoint: 'test', version: 'test', documentService: service);
    for (final save in [false, true]) {
      final state = EditorState.blank();
      addTearDown(state.dispose);
      service.saved = DocumentDataPBFromTo.fromDocument(state.document)!;
      service.saveWrites = save;
      service.failRead = false;
      final transaction = state.transaction
        ..insertNode([1], paragraphNode(text: 'new'));
      final inserted = transaction.operations
          .whereType<InsertOperation>()
          .single
          .nodes
          .single
          .id;
      final result = await tools.persistDocument(
        pageId: 'page',
        workspaceId: 'workspace',
        state: state,
        transaction: transaction,
        verify: (doc) => doc.blocks.containsKey(inserted),
      );
      if (save) {
        expect(result, isNull);
      } else {
        expect(result?.isError, isTrue);
        expect(
          (jsonDecode((result!.content.single as TextContent).text)
              as Map)['error']['code'],
          'write_unconfirmed',
        );
      }
    }
    final state = EditorState.blank();
    addTearDown(state.dispose);
    service.saved = DocumentDataPBFromTo.fromDocument(state.document)!;
    service.failRead = true;
    service.saveWrites = false;
    final result = await tools.persistDocument(
      pageId: 'page',
      workspaceId: 'workspace',
      state: state,
      transaction: state.transaction
        ..insertNode([1], paragraphNode(text: 'new')),
      verify: (_) => true,
    );
    expect(result?.isError, isTrue);
  });

  test('hashToken returns stable SHA-256 hex', () {
    expect(
      McpServerService.hashToken('abc'),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  test('constantTimeEquals matches only identical digests', () {
    const digest =
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
    expect(McpServerService.constantTimeEquals(digest, digest), isTrue);
    expect(
      McpServerService.constantTimeEquals(
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ae',
        digest,
      ),
      isFalse,
    );
    expect(McpServerService.constantTimeEquals('short', digest), isFalse);
  });

  test('server exposes the read tools', () async {
    final toServer = StreamController<List<int>>();
    final toClient = StreamController<List<int>>();
    final serverTransport = IOStreamTransport(
      stream: toServer.stream,
      sink: toClient.sink,
    );
    final clientTransport = IOStreamTransport(
      stream: toClient.stream,
      sink: toServer.sink,
    );
    final server = McpServerService.instance.buildServer();
    final client = McpClient(
      const Implementation(name: 'test-client', version: '1.0.0'),
    );
    addTearDown(() async {
      await client.close();
      await server.close();
      await toServer.close();
      await toClient.close();
    });

    await server.connect(serverTransport);
    await client.connect(clientTransport);

    final tools = await client.listTools();
    expect(
      tools.tools.map((tool) => tool.name),
      containsAll([
        'get_context',
        'list_workspaces',
        'list_pages',
        'get_page',
        'list_blocks',
        'search_notes',
        'create_workspace',
        'open_workspace',
        'create_page',
        'rename_page',
        'move_page',
        'delete_page',
        'restore_page',
        'append_content',
        'insert_block',
        'update_block',
        'delete_block',
      ]),
    );
  });

  // 回归：注册表一度只填了 3 个工具，内部 AI 因此看不到检索与写操作。
  test('工具注册表覆盖全部 27 个工具，只读/破坏性标记正确', () async {
    final tools = McpTools(endpoint: 'test', version: '1.0.0');
    final specs = tools.toolSpecs;

    expect(specs.length, 27);
    expect(
      specs.map((spec) => spec.name).toSet().length,
      27,
      reason: '工具名不应重复',
    );
    expect(
      specs.where((spec) => spec.readOnly).map((spec) => spec.name),
      unorderedEquals([
        'get_context',
        'list_workspaces',
        'list_pages',
        'get_page',
        'list_blocks',
        'query_database',
        'list_trash',
        'search_notes',
      ]),
    );
    expect(
      specs.where((spec) => spec.destructive).map((spec) => spec.name),
      unorderedEquals([
        'delete_page',
        'delete_block',
        'delete_database_row',
        'delete_database_field',
      ]),
    );
    expect(specs.where((spec) => !spec.readOnly).length, 19);

    final unknown = await tools.executeTool('no_such_tool', const {});
    expect(unknown.isError, isTrue);
  });

  test('createBlockNode maps supported block types', () {
    expect(
      McpTools.createBlockNode('paragraph', {'text': 'hello'})?.type,
      ParagraphBlockKeys.type,
    );
    expect(
      McpTools.createBlockNode('heading2', {'text': 'title'})?.type,
      HeadingBlockKeys.type,
    );
    expect(
      McpTools.createBlockNode(
        'todo_list',
        {'text': 'task', 'checked': true},
      )?.attributes[TodoListBlockKeys.checked],
      isTrue,
    );
    expect(
      McpTools.createBlockNode('divider', const {})?.type,
      DividerBlockKeys.type,
    );
    expect(
      McpTools.createBlockNode('toggle_list', {'text': 'toggle'})?.type,
      ToggleListBlockKeys.type,
    );
    expect(
      McpTools.createBlockNode('code', {'text': 'print(1)', 'language': 'dart'})
          ?.attributes[CodeBlockKeys.language],
      'dart',
    );
    expect(
      McpTools.createBlockNode('callout', {'text': 'note'})?.type,
      CalloutBlockKeys.type,
    );
    expect(
      McpTools.createBlockNode('math_equation', {'formula': 'a^2'})
          ?.attributes[MathEquationBlockKeys.formula],
      'a^2',
    );
    expect(
      McpTools.createBlockNode(
        'image',
        {'url': 'https://example.com/a.png'},
      )?.type,
      ImageBlockKeys.type,
    );
    expect(
      McpTools.createBlockNode('video', {'url': 'https://example.com/a.mp4'})
          ?.type,
      VideoBlockKeys.type,
    );
    expect(
      McpTools.createBlockNode(
        'file',
        {'url': 'https://example.com/a.pdf', 'file_name': 'a.pdf'},
      )?.type,
      FileBlockKeys.type,
    );
    expect(McpTools.createBlockNode('image', const {}), isNull);
    expect(McpTools.createBlockNode('unknown', const {}), isNull);
    expect(
      McpTools.createBlockNode(
        'gallery',
        {
          'image_urls': [
            'https://example.com/a.png',
            'https://example.com/b.png',
          ],
        },
      )?.type,
      MultiImageBlockKeys.type,
    );
    expect(
      McpTools.createBlockNode(
        'link_preview',
        {'url': 'https://example.com'},
      )?.type,
      LinkPreviewBlockKeys.type,
    );
    expect(
      McpTools.createBlockNode('sub_page', {'page_id_ref': 'abc'})?.type,
      SubPageBlockKeys.type,
    );
    final columns = McpTools.createBlockNode('columns', {'column_count': 3});
    expect(columns?.type, SimpleColumnsBlockKeys.type);
    expect(columns?.children.length, 3);
    final table = McpTools.createBlockNode(
      'table',
      {
        'rows': [
          ['名称', '数量'],
          ['苹果', '3'],
        ],
      },
    );
    expect(table?.type, SimpleTableBlockKeys.type);
    expect(table?.children.length, 2);
    expect(
      table?.children.first.children.first.children.first.delta?.toPlainText(),
      '名称',
    );
    // 首行默认作为表头
    expect(table?.attributes[SimpleTableBlockKeys.enableHeaderRow], isTrue);
    expect(table?.attributes[SimpleTableBlockKeys.enableHeaderColumn], isFalse);
    final tableNoHeader = McpTools.createBlockNode(
      'table',
      {
        'rows': [
          ['a', 'b'],
        ],
        'header_row': false,
        'header_column': true,
      },
    );
    expect(
      tableNoHeader?.attributes[SimpleTableBlockKeys.enableHeaderRow],
      isFalse,
    );
    expect(
      tableNoHeader?.attributes[SimpleTableBlockKeys.enableHeaderColumn],
      isTrue,
    );
    expect(
      McpTools.createBlockNode('outline', const {})?.type,
      OutlineBlockKeys.type,
    );
    expect(
      McpTools.createBlockNode('grid', {
        'view_id_ref': 'view-1',
        'parent_view_id': 'page-1',
      })?.type,
      DatabaseBlockKeys.gridType,
    );
    expect(
      McpTools.createBlockNode('calendar', {'view_id_ref': 'view-2'})?.type,
      DatabaseBlockKeys.calendarType,
    );
    expect(
      McpTools.createBlockNode('ai_writer', {'ai_command': 'explain'}),
      isNull,
    );
    final dateNode = McpTools.createBlockNode('date', {
      'host_block_id': 'block-1',
      'host_delta': [],
      'date': '2026-10-22T00:00:00Z',
    });
    expect(dateNode?.id, 'block-1');
    final mentionOps = dateNode!.delta!
        .toJson()
        .whereType<Map>()
        .where(
          (op) =>
              op['attributes'] is Map &&
              (op['attributes'] as Map)[MentionBlockKeys.mention] != null,
        )
        .toList();
    expect(mentionOps, hasLength(1));
    expect(
      mentionOps.single['attributes'][MentionBlockKeys.mention]
          [MentionBlockKeys.type],
      MentionType.date.name,
    );
    final reminderNode = McpTools.createBlockNode('date', {
      'host_block_id': 'block-2',
      'host_delta': [],
      'date': '2026-10-22T09:30:00+08:00',
      'reminder_id': 'reminder-1',
      'reminder_option': 'five_mins_before',
    });
    final reminderMention = reminderNode!.delta!
        .toJson()
        .whereType<Map>()
        .firstWhere((op) => op['insert'] == '​');
    final reminderAttrs =
        (reminderMention['attributes'] as Map)[MentionBlockKeys.mention] as Map;
    expect(reminderAttrs[MentionBlockKeys.reminderId], 'reminder-1');
    expect(
      reminderAttrs[MentionBlockKeys.reminderOption],
      'fiveMinsBefore',
    );
    expect(McpTools.createBlockNode('grid', const {}), isNull);
  });

  test('buildUpdateAttributes 只写入请求的字段并按块类型校验', () {
    final code = codeBlockNode(delta: Delta()..insert('print(1)'));
    final codeAttrs = McpTools.buildUpdateAttributes(
      code,
      {'language': 'python'},
    );
    expect(codeAttrs.error, isNull);
    expect(codeAttrs.attributes[CodeBlockKeys.language], 'python');
    // 没传 text 时不动正文
    expect(codeAttrs.attributes.containsKey(blockComponentDelta), isFalse);

    final callout = calloutNode();
    final calloutAttrs = McpTools.buildUpdateAttributes(
      callout,
      {'icon': '🔥'},
    );
    expect(calloutAttrs.attributes[CalloutBlockKeys.icon], '🔥');

    final table = simpleTableBlockNode(
      children: [
        simpleTableRowBlockNode(children: [simpleTableCellBlockNode()]),
      ],
    );
    final tableAttrs = McpTools.buildUpdateAttributes(
      table,
      {'header_row': false, 'header_column': true},
    );
    expect(
      tableAttrs.attributes[SimpleTableBlockKeys.enableHeaderRow],
      isFalse,
    );
    expect(
      tableAttrs.attributes[SimpleTableBlockKeys.enableHeaderColumn],
      isTrue,
    );

    final paragraph = paragraphNode(text: 'hi');
    expect(
      McpTools.buildUpdateAttributes(paragraph, {'language': 'dart'}).error,
      contains('code'),
    );
    expect(
      McpTools.buildUpdateAttributes(paragraph, {'header_row': true}).error,
      contains('table'),
    );
    expect(
      McpTools.buildUpdateAttributes(paragraph, const {}).attributes,
      isEmpty,
    );
  });

  test('formatCellValue 按字段类型输出文本', () {
    expect(
      McpTools.formatCellValue(FieldType.RichText, utf8.encode('你好')),
      '你好',
    );
    expect(McpTools.formatCellValue(FieldType.Number, utf8.encode('42')), '42');
    expect(
      McpTools.formatCellValue(
        FieldType.Checkbox,
        CheckboxCellDataPB(isChecked: true).writeToBuffer(),
      ),
      'true',
    );
    expect(
      McpTools.formatCellValue(
        FieldType.SingleSelect,
        SelectOptionCellDataPB(
          selectOptions: [
            SelectOptionPB(name: '高'),
            SelectOptionPB(name: '急'),
          ],
        ).writeToBuffer(),
      ),
      '高, 急',
    );
    expect(
      McpTools.formatCellValue(
        FieldType.Time,
        TimeCellDataPB(time: Int64(90)).writeToBuffer(),
      ),
      formatTime(90),
    );
    expect(
      McpTools.formatCellValue(
        FieldType.Relation,
        RelationCellDataPB(rowIds: ['r1', 'r2']).writeToBuffer(),
      ),
      'r1, r2',
    );
    // 空单元格不报错
    expect(McpTools.formatCellValue(FieldType.DateTime, const []), '');
  });

  test('数据库写入的值解析：勾选与多值', () {
    expect(McpTools.asBool('true'), isTrue);
    expect(McpTools.asBool(' YES '), isTrue);
    expect(McpTools.asBool('1'), isTrue);
    expect(McpTools.asBool('false'), isFalse);
    expect(McpTools.asBool(''), isFalse);

    expect(McpTools.splitValues('高, 急 ,,低'), ['高', '急', '低']);
    expect(McpTools.splitValues('  '), isEmpty);
  });

  test('blockAttributes exposes resource urls', () {
    final image = imageNode(url: 'https://example.com/a.png');
    final imageAttrs = McpTools.blockAttributes(image);
    expect(imageAttrs['url'], 'https://example.com/a.png');
    expect(imageAttrs.containsKey(blockComponentDelta), isFalse);

    final gallery = multiImageNode(
      images: [
        ImageBlockData(
          url: 'https://example.com/a.png',
          type: CustomImageType.external,
        ),
        ImageBlockData(
          url: 'https://example.com/b.png',
          type: CustomImageType.external,
        ),
      ],
    );
    final galleryAttrs = McpTools.blockAttributes(gallery);
    expect(galleryAttrs[MultiImageBlockKeys.images], isA<List>());
    expect(
      (galleryAttrs[MultiImageBlockKeys.images] as List).length,
      2,
    );

    final video = Node(
      type: VideoBlockKeys.type,
      attributes: {VideoBlockKeys.url: 'https://example.com/a.mp4'},
    );
    expect(McpTools.blockAttributes(video)['url'], 'https://example.com/a.mp4');
  });

  test('parseReminderOption maps MCP values', () {
    expect(
      McpTools.parseReminderOption('five_mins_before'),
      ReminderOption.fiveMinsBefore,
    );
    expect(
      McpTools.parseReminderOption('one_week_before'),
      ReminderOption.oneWeekBefore,
    );
    expect(McpTools.parseReminderOption('bogus'), isNull);
  });

  test('deltaText renders date mentions as readable dates', () {
    final delta = Delta()
      ..insert('截止 ')
      ..insert(
        '​',
        attributes: {
          MentionBlockKeys.mention: {
            MentionBlockKeys.type: MentionType.date.name,
            MentionBlockKeys.date: '2026-10-22T01:30:00Z',
            MentionBlockKeys.includeTime: true,
          },
        },
      );
    final local = DateTime.parse('2026-10-22T09:30:00+08:00').toLocal();
    final expected = '${local.year}/${local.month}/${local.day} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    final text = McpTools.deltaText(delta);
    expect(text, contains('截止 '));
    expect(text, contains(expected));
    expect(text.contains('​'), isFalse);
  });

  test('blockText extracts delta and external text', () {
    final inline = BlockPB(
      data: jsonEncode({
        'delta': [
          {'insert': 'hello '},
          {'insert': 'world'},
        ],
      }),
    );
    expect(McpTools.blockText(inline, null), 'hello world');

    final external = BlockPB(externalType: 'text', externalId: 'ext1');
    final meta = MetaPB(
      textMap: {
        'ext1': jsonEncode({
          'delta': [
            {'insert': '外部文本'},
          ],
        }),
      },
    );
    expect(McpTools.blockText(external, meta), '外部文本');

    expect(McpTools.blockText(BlockPB(data: 'not-json'), null), '');
  });
}

class _WriteTestDocumentService extends DocumentService {
  late DocumentDataPB saved;
  bool saveWrites = false;
  bool failRead = false;

  @override
  Future<FlowyResult<void, FlowyError>> createExternalText({
    required String documentId,
    required String textId,
    String? delta,
  }) async =>
      FlowyResult.success(null);

  @override
  Future<FlowyResult<void, FlowyError>> applyAction({
    required String documentId,
    required Iterable<BlockActionPB> actions,
  }) async {
    if (saveWrites) {
      for (final action in actions) {
        saved.blocks[action.payload.block.id] = action.payload.block.deepCopy();
      }
    }
    return FlowyResult.success(null);
  }

  @override
  Future<FlowyResult<DocumentDataPB, FlowyError>> getDocument({
    required String documentId,
    String? workspaceId,
  }) async {
    if (failRead) throw StateError('backend read failed');
    return FlowyResult.success(saved);
  }
}
