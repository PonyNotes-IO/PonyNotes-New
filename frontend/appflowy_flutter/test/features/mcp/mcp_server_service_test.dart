import 'dart:async';
import 'dart:convert';

import 'package:appflowy/features/mcp/application/mcp_server_service.dart';
import 'package:appflowy/features/mcp/application/mcp_tools.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart'
    hide quoteNode;
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor_plugins/appflowy_editor_plugins.dart';
import 'package:appflowy/workspace/presentation/widgets/date_picker/widgets/reminder_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart';

void main() {
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
  test('工具注册表覆盖全部 17 个工具，只读/破坏性标记正确', () async {
    final tools = McpTools(endpoint: 'test', version: '1.0.0');
    final specs = tools.toolSpecs;

    expect(specs.length, 17);
    expect(specs.map((spec) => spec.name).toSet().length, 17,
        reason: '工具名不应重复');
    expect(
      specs.where((spec) => spec.readOnly).map((spec) => spec.name),
      unorderedEquals([
        'get_context',
        'list_workspaces',
        'list_pages',
        'get_page',
        'list_blocks',
        'search_notes',
      ]),
    );
    expect(
      specs.where((spec) => spec.destructive).map((spec) => spec.name),
      unorderedEquals(['delete_page', 'delete_block']),
    );
    expect(specs.where((spec) => !spec.readOnly).length, 11);

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
