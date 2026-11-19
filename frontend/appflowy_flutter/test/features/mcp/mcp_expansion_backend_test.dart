import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/env/backend_env.dart';
import 'package:appflowy/features/agent/application/agent_internal_service.dart';
import 'package:appflowy/features/mcp/application/mcp_tools.dart';
import 'package:appflowy/plugins/import_page/enhanced_pdf_import_dialog.dart';
import 'package:appflowy/plugins/import_page/enhanced_word_import_dialog.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/startup/tasks/app_widget.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy/plugins/handwriting_saber/application/handwriting_saber_data_service.dart';
import 'package:appflowy/plugins/handwriting_saber/third_party/saber_core/data/editor/editor_core_info.dart';
import 'package:file_picker/file_picker.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/appflowy_backend.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/number_entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Storage extends ApplicationDataStorage {
  _Storage(this.path);
  final String path;
  @override
  Future<String> getPath() async => path;
}

class _Picker extends FilePicker {
  _Picker(this.file);
  final File file;
  @override
  Future<String?> getDirectoryPath(
          {String? dialogTitle,
          bool lockParentWindow = false,
          String? initialDirectory}) async =>
      file.parent.path;
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      FilePickerResult([
        PlatformFile(
          name: file.uri.pathSegments.last,
          size: await file.length(),
          path: file.path,
        ),
      ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sdk = FlowySDK();
  late Directory data;
  late String workspace;
  final tools = McpTools(
    endpoint: 'test',
    version: 'test',
    confirmOperation: (_, __) async => true,
  );
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    Log.shared.disableLog = true;
    data = Directory.systemTemp.createTempSync('ponynotes-mcp-expanded-');
    getIt.registerSingleton<ApplicationDataStorage>(_Storage(data.path));
    await sdk.init(
      jsonEncode(
        AppFlowyConfiguration(
          root: data.path,
          app_version: '1',
          custom_app_path: data.path,
          origin_app_path: data.path,
          device_id: 'mcp-expanded-test',
          platform: Platform.operatingSystem,
          authenticator_type: AuthTypePB.Local.value,
          appflowy_cloud_config: AppFlowyCloudConfiguration.defaultConfig(),
          envs: {},
        ).toJson(),
      ),
    );
    await UserEventSignUp(
      SignUpPayloadPB(
        name: 'MCP test',
        email: 'expanded@localhost',
        password: 'test-password',
        authType: AuthTypePB.Local,
        deviceId: 'mcp-expanded-test',
      ),
    ).send().getOrThrow();
    UserBackendService.clearCurrentUserProfileCache();
    workspace =
        (await FolderEventReadCurrentWorkspace().send().getOrThrow()).id;
  });
  tearDownAll(() async {
    await McpTools.revokeSessionState();
    UserBackendService.clearCurrentUserProfileCache();
    await sdk.dispose();
    await getIt.unregister<ApplicationDataStorage>();
    try {
      await data.delete(recursive: true);
    } on FileSystemException catch (error) {
      if (!Platform.isWindows || error.osError?.errorCode != 32) rethrow;
      // The native SDK can retain process-lifetime handles on Windows.
      debugPrint(
          'Windows retained the synthetic MCP test directory: ${data.path}');
    }
  });

  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> args,
  ) async {
    final result =
        await tools.executeTool(name, {'workspace_id': workspace, ...args});
    final payload = Map<String, dynamic>.from(
      jsonDecode((result.content.single as TextContent).text) as Map,
    );
    expect(result.isError, isFalse, reason: '$name: $payload');
    return payload;
  }

  Future<String> document(String title) async =>
      (await ViewBackendService.createView(
        parentViewId: workspace,
        name: title,
        layoutType: ViewLayoutPB.Document,
        openAfterCreate: false,
      ).getOrThrow())
          .id;

  test('partial rich-text replacement persists and rejects stale source',
      () async {
    final page = await document('Rich text');
    final appended = await call(
      'insert_block',
      {'page_id': page, 'block_type': 'paragraph', 'text': 'hello world'},
    );
    final block = appended['block_id'];
    await call('document_text', {
      'action': 'format_text',
      'page_id': page,
      'block_id': block,
      'expected_text': 'hello world',
      'range': {'start': 0, 'length': 5},
      'attributes': {'bold': true},
    });
    await call('document_text', {
      'action': 'edit_text',
      'page_id': page,
      'block_id': block,
      'expected_text': 'hello world',
      'range': {'start': 6, 'length': 5},
      'replacement_delta': [
        {'insert': 'notes'},
      ],
    });
    final read = await call(
      'document_text',
      {'action': 'get_block', 'page_id': page, 'block_id': block},
    );
    expect(read['text'], 'hello notes');
    expect((read['delta'] as List).first, {
      'insert': 'hello',
      'attributes': {'bold': true},
    });
    final rejected = await tools.executeTool('document_text', {
      'workspace_id': workspace,
      'action': 'edit_text',
      'page_id': page,
      'block_id': block,
      'expected_text': 'old',
      'range': {'start': 0, 'length': 1},
      'replacement_delta': [
        {'insert': 'x'},
      ],
    });
    expect(rejected.isError, isTrue);
    expect(
      (await call('document_text', {
        'action': 'get_block',
        'page_id': page,
        'block_id': block,
      }))['text'],
      'hello notes',
    );
  });

  test(
      'converting and duplicating a nested text block preserves its children and formatting',
      () async {
    final page = await document('Nested blocks');
    final parent = await call(
      'insert_block',
      {'page_id': page, 'block_type': 'paragraph', 'text': 'parent'},
    );
    await call('insert_block', {
      'page_id': page,
      'parent_block_id': parent['block_id'],
      'block_type': 'paragraph',
      'text': 'child',
    });
    await call('document_blocks', {
      'action': 'convert_block',
      'page_id': page,
      'block_id': parent['block_id'],
      'target_type': 'heading1',
    });
    final content =
        await DocumentService().getDocument(documentId: page).getOrThrow();
    final nodes = content.toDocument()!.root.children;
    final converted = nodes.firstWhere((n) => n.type == HeadingBlockKeys.type);
    expect(converted.delta!.toPlainText(), 'parent');
    expect(converted.children.single.delta!.toPlainText(), 'child');
    await call('document_blocks', {
      'action': 'duplicate_block',
      'page_id': page,
      'block_id': converted.id,
    });
    final copy =
        (await DocumentService().getDocument(documentId: page).getOrThrow())
            .toDocument()!;
    final headings = copy.root.children
        .where((n) => n.type == HeadingBlockKeys.type)
        .toList();
    expect(headings.length, 2);
    expect(
      headings[0].children.single.id,
      isNot(headings[1].children.single.id),
    );
  });

  test(
      'database paging can reach the 101st row and returns independent field IDs',
      () async {
    final parent = await document('Database parent');
    final created = await call(
      'insert_block',
      {'page_id': parent, 'block_type': 'grid', 'text': 'Rows'},
    );
    final view = created['database_view_id'] as String;
    final initial = await call('query_database', {'view_id': view});
    final field = (initial['fields'] as List).first as Map;
    for (var i = 0; i < 102; i++) {
      await call('create_database_row', {
        'view_id': view,
        'cells': [
          {'field': field['id'], 'value': 'row-$i'},
        ],
      });
    }
    final first = await call('query_database', {'view_id': view, 'limit': 100});
    final next = await call(
      'query_database',
      {'view_id': view, 'limit': 100, 'offset': first['next_offset']},
    );
    expect(next['returned'], greaterThan(0));
    expect(
      ((next['rows'] as List).first as Map)['cells_by_id'],
      contains(field['id']),
    );
    final firstIds = (first['rows'] as List).map((r) => r['row_id']).toSet();
    expect(
      (next['rows'] as List).any((r) => firstIds.contains(r['row_id'])),
      isFalse,
    );
  });

  test(
      'advanced field conversion, multi-select replacement and clearing use real backend data',
      () async {
    final parent = await document('Options');
    final view = (await call(
      'insert_block',
      {'page_id': parent, 'block_type': 'grid'},
    ))['database_view_id'];
    final field = (await call(
      'create_database_field',
      {'view_id': view, 'name': 'Tags', 'type': 'multi_select'},
    ))['field_id'];
    final currency = await call('create_database_field', {
      'view_id': view,
      'name': 'Price',
      'type': 'number',
      'type_options': {'format': 'Yuan'},
    });
    final row =
        (await call('create_database_row', {'view_id': view}))['row_id'];
    await call('update_database_cell', {
      'view_id': view,
      'row_id': row,
      'field': currency['field_id'],
      'value': '10',
    });
    await call('update_database_cell', {
      'view_id': view,
      'row_id': row,
      'field': field,
      'value': 'alpha,beta',
    });
    await call(
      'update_database_cell',
      {'view_id': view, 'row_id': row, 'field': field, 'operation': 'clear'},
    );
    final read = await call('query_database', {
      'view_id': view,
      'row_ids': [row],
    });
    final fields = read['fields'] as List;
    final price = fields.firstWhere((f) => f['id'] == currency['field_id']);
    expect(
      NumberTypeOptionPB.fromBuffer(
              base64Decode(price['type_options_base64'] as String))
          .format,
      NumberFormatPB.Yuan,
    );
    expect(
      (((read['rows'] as List).single as Map)['cells_by_id'] as Map)[field]
          ['text'],
      '',
    );
    await call(
      'update_database_field',
      {'view_id': view, 'field': field, 'type': 'text'},
    );
    final fresh = await call('query_database', {'view_id': view});
    expect(
      (fresh['fields'] as List).firstWhere((f) => f['id'] == field)['type'],
      'RichText',
    );
  });

  test('database view creation persists and locked views reject row writes',
      () async {
    final parent = await document('Database views');
    final created = await call('database_views', {
      'action': 'create_database_view',
      'parent_id': parent,
      'name': 'Actual grid',
      'layout': 'grid',
    });
    final view = (created['view'] as Map)['page_id'] as String;
    final rows = await call('query_database', {'view_id': view});
    expect(rows['fields'], isNotEmpty);
    final catalog =
        await call('database_views', {'action': 'list_database_views'});
    final database = (catalog['databases'] as List)
        .firstWhere((entry) => entry['view']['page_id'] == view)['database_id'];
    final linked = (await call('database_views', {
      'action': 'create_database_view',
      'parent_id': parent,
      'database_id': database,
      'name': 'Linked grid',
      'layout': 'grid',
    }))['view']['page_id'];
    final shared =
        (await call('create_database_row', {'view_id': view}))['row_id'];
    expect(
        (await call('query_database', {
          'view_id': linked,
          'row_ids': [shared]
        }))['returned'],
        1);
    expect(
      (catalog['databases'] as List)
          .any((entry) => entry['view']['page_id'] == view),
      isTrue,
    );
    await call(
      'page_properties',
      {'action': 'set_page_locked', 'page_id': view, 'locked': true},
    );
    final rejected = await tools.executeTool(
      'create_database_row',
      {'workspace_id': workspace, 'view_id': view},
    );
    expect(rejected.isError, isTrue);
    expect(
      (rejected.content.single as TextContent).text,
      contains('page_locked'),
    );
    await call(
      'page_properties',
      {'action': 'set_page_locked', 'page_id': view, 'locked': false},
    );
    await call('create_database_row', {'view_id': view});
  });

  test('native requests cannot substitute another database view', () async {
    final parent = await document('Scope');
    final view = (await call(
      'insert_block',
      {'page_id': parent, 'block_type': 'grid'},
    ))['database_view_id'];
    final rejected = await tools.executeTool('database_views', {
      'workspace_id': workspace,
      'view_id': view,
      'action': 'manage_database_filters',
      'operation': 'list',
      'request': {'value': 'unrelated-view'},
    });
    expect(rejected.isError, isTrue);
    expect(
      (rejected.content.single as TextContent).text,
      contains('invalid_params'),
    );
    await call('database_views', {
      'view_id': view,
      'action': 'manage_database_filters',
      'operation': 'list',
      'request': {},
    });
  });

  test('native chat settings require a chat in the current workspace',
      () async {
    final page = await document('Not a chat');
    final result = await tools.executeTool('ai_chat_action', {
      'workspace_id': workspace,
      'action': 'get_settings',
      'request': {'value': page},
    });
    final payload =
        jsonDecode((result.content.single as TextContent).text) as Map;
    expect(result.isError, isTrue);
    expect(payload['error']['code'], 'invalid_params', reason: '$payload');
  });

  test('ZIP import rejects a target parent before contacting the cloud',
      () async {
    final page = await document('Not an import destination');
    final result = await tools.executeTool('document_transfer', {
      'workspace_id': workspace,
      'action': 'import_workspace_data',
      'operation': 'start',
      'parent_id': page,
    });
    final payload =
        jsonDecode((result.content.single as TextContent).text) as Map;
    expect(result.isError, isTrue);
    expect(payload['error']['code'], 'invalid_params', reason: '$payload');
  });

  test('ZIP import streams the selected file and queries its server task',
      () async {
    final overrides = HttpOverrides.current;

    HttpOverrides.global = null;
    addTearDown(() {
      HttpOverrides.global = overrides;
    });
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final endpoint = 'http://127.0.0.1:${server.port}';
    final content = [0x50, 0x4b, 3, 4, 21, 0];
    final archive = await File('${data.path}/Sample.zip').writeAsBytes(content);
    FilePicker.platform = _Picker(archive);
    final requests = <String>[];
    Map? create;
    String? host, cloudAuthorization, uploadAuthorization;
    List<int>? uploaded;
    server.listen((request) async {
      final route = '${request.method} ${request.uri.path}';
      requests.add(route);
      request.response.headers.contentType = ContentType.json;
      switch (route) {
        case 'POST /api/import/create':
          create = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          host = request.headers.value('X-Host');
          cloudAuthorization = request.headers.value('Authorization');
          request.response.write(jsonEncode({
            'code': 0,
            'data': {'task_id': 'task-1', 'presigned_url': '$endpoint/upload'},
          }));
        case 'PUT /upload':
          uploadAuthorization = request.headers.value('Authorization');
          uploaded = await request.expand((bytes) => bytes).toList();
        case 'GET /api/import':
          request.response.write(jsonEncode({
            'code': 0,
            'data': {
              'tasks': [
                {'task_id': 'some-other-task', 'status': 2},
                {'task_id': 'task-1', 'status': 1},
              ],
            },
          }));
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    final cloudTools = McpTools(
      endpoint: endpoint,
      version: 'test',
      cloudAccount: () async => AgentCloudAccount(
        baseUrl: endpoint,
        accessToken: 'test-token',
        userId: 'test-user',
      ),
    );
    final picked = await call('system_action', {'operation': 'pick_file'});
    Future<Map> transfer(Map<String, dynamic> args) async {
      final result = await cloudTools.executeTool('document_transfer', {
        'workspace_id': workspace,
        'action': 'import_workspace_data',
        ...args,
      });
      final payload =
          jsonDecode((result.content.single as TextContent).text) as Map;
      expect(result.isError, isFalse, reason: '$payload');
      return payload;
    }

    final task = await transfer({
      'operation': 'start',
      'format': 'zip',
      'source_handle': picked['source_handle'],
    });
    expect(task, {'task_id': 'task-1', 'status': 'submitted'});
    final status =
        await transfer({'operation': 'status', 'task_id': task['task_id']});
    expect(status['status'], 'completed');
    expect(
        create, {'workspace_name': 'Sample', 'content_length': content.length});
    expect(host, endpoint);
    expect(cloudAuthorization, 'Bearer test-token');
    expect(uploadAuthorization, isNull);
    expect(uploaded, content);
    expect(requests,
        ['POST /api/import/create', 'PUT /upload', 'GET /api/import']);
  });

  testWidgets('PDF and Word hand off the selected file to the import dialog',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: AppGlobals.rootNavKey,
      home: const Scaffold(body: SizedBox.shrink()),
    ));
    final parent = (await tester.runAsync(() => document('Import target')))!;
    for (final (format, extension, type) in [
      ('pdf', 'pdf', EnhancedPdfImportDialog),
      ('word', 'docx', EnhancedWordImportDialog),
    ]) {
      await tester.runAsync(() async {
        final file = await File('${data.path}/Selected.$extension')
            .writeAsString('sample');
        FilePicker.platform = _Picker(file);
        final picked = await call('system_action', {'operation': 'pick_file'});
        final result = await call('document_transfer', {
          'action': 'import_document',
          'format': format,
          'parent_id': parent,
          'source_handle': picked['source_handle'],
        });
        expect(result['status'], 'requires_human');
      });
      await tester.pumpAndSettle();
      expect(find.byType(type), findsOneWidget);
      expect(find.text('Selected.$extension'), findsOneWidget);
      AppGlobals.rootNavKey.currentState!.pop();
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('plain-text import preserves Markdown markers as literal text',
      () async {
    final parent = await document('Plain text target');
    final file =
        await File('${data.path}/input.txt').writeAsString('# not a heading');
    FilePicker.platform = _Picker(file);
    final picked = await call('system_action', {'operation': 'pick_file'});
    final result = await call('document_transfer', {
      'action': 'import_document',
      'format': 'text',
      'parent_id': parent,
      'source_handle': picked['source_handle'],
    });
    final page = (result['page'] as Map)['page_id'];
    final blocks = await call('list_blocks', {'page_id': page});
    expect(jsonEncode(blocks), contains('# not a heading'));
  });

  test('PDF export renders a note into the granted directory', () async {
    final page = await document('导出验证');
    await call('append_content', {
      'page_id': page,
      'markdown': '正文回读\n\n- Exported through MCP',
    });
    FilePicker.platform = _Picker(File('${data.path}/parent'));
    final destination =
        await call('system_action', {'operation': 'pick_directory'});
    final args = <String, dynamic>{
      'action': 'export_document',
      'page_id': page,
      'format': 'pdf',
      'destination_handle': destination['destination_handle'],
      'name': 'mcp-pdf-export.pdf',
    };
    final rejected = await McpTools(
      endpoint: 'test',
      version: 'test',
      confirmOperation: (_, __) async => false,
    ).executeTool('document_transfer', {'workspace_id': workspace, ...args});
    expect(rejected.isError, isTrue);
    final file = File('${data.path}/mcp-pdf-export.pdf');
    expect(await file.exists(), isFalse);
    expect((await call('document_transfer', args))['exported'],
        'mcp-pdf-export.pdf');
    final bytes = await file.readAsBytes();
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    expect(bytes.length, greaterThan(1000));
    final sample = Platform.environment['PONY_MCP_PDF_SAMPLE'];
    if (sample != null) await file.copy(sample);
  });

  test('AI writing rejects a range outside the block before provider use',
      () async {
    final page = await document('AI writing');
    final block = (await call('insert_block', {
      'page_id': page,
      'block_type': 'paragraph',
      'text': 'abc',
    }))['block_id'];
    final result = await tools.executeTool('editor_ai_action', {
      'workspace_id': workspace,
      'page_id': page,
      'block_id': block,
      'operation': 'start',
      'instruction': 'rewrite',
      'range': {'start': 2, 'length': 2},
    });
    final payload =
        jsonDecode((result.content.single as TextContent).text) as Map;
    expect(result.isError, isTrue);
    expect(payload['error']['code'], 'invalid_params', reason: '$payload');
  });

  test('simple table edits persist and preserve its last row', () async {
    final page = await document('Table');
    final block = (await call('insert_block', {
      'page_id': page,
      'block_type': 'table',
      'rows': [
        ['a', 'b'],
      ],
    }))['block_id'];
    await call('document_blocks', {
      'action': 'edit_simple_table',
      'page_id': page,
      'block_id': block,
      'operation': 'insert',
      'row': 1,
      'values': ['c', 'd'],
    });
    var table =
        (await DocumentService().getDocument(documentId: page).getOrThrow())
            .toDocument()!
            .root
            .children
            .firstWhere((node) => node.id == block);
    expect(table.children.length, 2);
    expect(
      table.children.last.children.first.children.single.delta!.toPlainText(),
      'c',
    );
    await call('document_blocks', {
      'action': 'edit_simple_table',
      'page_id': page,
      'block_id': block,
      'operation': 'delete',
      'row': 1,
    });
    final rejected = await tools.executeTool('document_blocks', {
      'workspace_id': workspace,
      'action': 'edit_simple_table',
      'page_id': page,
      'block_id': block,
      'operation': 'delete',
      'row': 0,
    });
    expect(rejected.isError, isTrue);
    table = (await DocumentService().getDocument(documentId: page).getOrThrow())
        .toDocument()!
        .root
        .children
        .firstWhere((node) => node.id == block);
    expect(table.children.length, 1);
  });

  test(
      'column widths use the editor ratio and adding columns preserves content',
      () async {
    final page = await document('Columns');
    final block = (await call('insert_block', {
      'page_id': page,
      'block_type': 'columns',
      'column_count': 2
    }))['block_id'];
    await call('document_blocks', {
      'action': 'update_columns',
      'page_id': page,
      'block_id': block,
      'column_count': 3,
      'widths': [2, 1, 1]
    });
    final node =
        (await DocumentService().getDocument(documentId: page).getOrThrow())
            .buildNode(block)!;
    expect(node.children.length, 3);
    expect(node.children.first.attributes['ratio'], 0.5);
    expect(node.children.last.attributes['ratio'], 0.25);
  });

  testWidgets(
      'human confirmation rejects a purge after authorization is revoked',
      (tester) async {
    final font = FontLoader('McpTestChinese')
      ..addFont(rootBundle.load('assets/fonts/chinese.ttf'));
    await font.load();
    final latin = FontLoader('McpTestLatin')
      ..addFont(
        rootBundle.load('assets/google_fonts/Poppins/Poppins-Regular.ttf'),
      );
    await latin.load();
    late String page;
    await tester.runAsync(() async {
      page = await document('Confirmation target');
      await call('delete_page', {'page_id': page});
    });
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            fontFamily: 'McpTestLatin',
            fontFamilyFallback: ['McpTestChinese'],
          ),
          navigatorKey: AppGlobals.rootNavKey,
          home: const Scaffold(body: Text('MCP 授权测试')),
        ),
      ),
    );
    var authorized = true;
    final confirmed = McpTools(
      endpoint: 'test',
      version: 'test',
      isAuthorizationCurrent: () => authorized,
    );
    late Future<CallToolResult> pending;
    await tester.runAsync(() async {
      pending = confirmed.executeTool('trash_actions', {
        'workspace_id': workspace,
        'action': 'purge_trash',
        'page_ids': [page],
      });
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('允许执行 purge_trash？'), findsOneWidget);
    expect(find.textContaining(page), findsOneWidget);
    await tester.runAsync(() async {
      final image = await (boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '../../../outputs/mcp-implementation-20261118/confirmation-dialog.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    authorized = false;
    await tester.tap(find.text('允许'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      expect((await pending).isError, isTrue);
      final trash = await call('list_trash', {});
      expect(jsonEncode(trash), contains(page));
    });
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
      'clipboard cut and paste preserve surrounding text and reject stale selections',
      () async {
    String clipboard = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String;
      }
      return call.method == 'Clipboard.getData' ? {'text': clipboard} : null;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final page = await document('Clipboard');
    final block = (await call('insert_block', {
      'page_id': page,
      'block_type': 'paragraph',
      'text': 'hello world',
    }))['block_id'];
    await call('clipboard_action', {
      'operation': 'cut',
      'page_id': page,
      'block_id': block,
      'expected_text': 'hello world',
      'range': {'start': 6, 'length': 5},
    });
    expect(clipboard, 'world');
    await call('clipboard_action', {
      'operation': 'paste',
      'page_id': page,
      'block_id': block,
      'expected_text': 'hello ',
      'range': {'start': 6, 'length': 0},
    });
    expect(
      (await call('document_text', {
        'action': 'get_block',
        'page_id': page,
        'block_id': block,
      }))['text'],
      'hello world',
    );
    final rejected = await tools.executeTool('clipboard_action', {
      'workspace_id': workspace,
      'operation': 'cut',
      'page_id': page,
      'block_id': block,
      'expected_text': 'stale',
      'range': {'start': 0, 'length': 5},
    });
    expect(rejected.isError, isTrue);
  });

  test('file grants import library files and stop resolving after revocation',
      () async {
    final input = File('${data.path}/example.txt');
    await input.writeAsString('library content');
    FilePicker.platform = _Picker(input);
    final grant = (await call(
      'system_action',
      {'operation': 'pick_file'},
    ))['source_handle'];
    final imported = await call(
      'library_files',
      {'action': 'import_library_file', 'source_handle': grant},
    );
    final list = await call('library_files', {'action': 'list_library_files'});
    expect(
      (list['files'] as List)
          .any((item) => item['file_id'] == imported['file_id']),
      isTrue,
    );
    final destination = (await call('system_action',
        {'operation': 'pick_directory'}))['destination_handle'];
    final exported = await call('document_transfer', {
      'action': 'export_workspace',
      'destination_handle': destination,
      'name': 'workspace-export'
    });
    expect(exported['exported'], greaterThan(0));
    final manifest = jsonDecode(
        await File('${data.path}/workspace-export/manifest.json')
            .readAsString()) as Map;
    expect(manifest['snapshot_backup'], isFalse);
    expect(manifest['views'], isNotEmpty);
    FilePicker.platform =
        _Picker(File('${data.path}/workspace-export/manifest.json'));
    final backup = await call('system_action', {'operation': 'pick_directory'});
    final inspected = await call('document_transfer', {
      'action': 'restore_workspace_data',
      'operation': 'inspect',
      'backup_handle': backup['destination_handle'],
    });
    expect(inspected['format'], 'page_export_directory');
    final unsupported = await tools.executeTool('document_transfer', {
      'workspace_id': workspace,
      'action': 'restore_workspace_data',
      'operation': 'restore',
      'backup_handle': backup['destination_handle'],
    });
    final restoreResult =
        jsonDecode((unsupported.content.single as TextContent).text) as Map;
    expect(restoreResult['error']['code'], 'unsupported_backup');
    final conflict = await tools.executeTool('document_transfer', {
      'workspace_id': workspace,
      'action': 'export_workspace',
      'destination_handle': destination,
      'name': 'workspace-export'
    });
    expect(conflict.isError, isTrue);
    await McpTools.revokeSessionState();
    final denied = await tools.executeTool('library_files', {
      'workspace_id': workspace,
      'action': 'import_library_file',
      'source_handle': grant,
    });
    expect(denied.isError, isTrue);
  });

  test(
      'handwriting object writes persist and stale snapshots cannot overwrite them',
      () async {
    final parent = await document('Canvas parent');
    final page = (await call('create_view', {
      'parent_id': parent,
      'title': 'Canvas',
      'layout': 'handwriting',
    }))['page']['page_id'] as String;
    final current = (await call(
      'handwriting_documents',
      {'view_id': page, 'action': 'get_handwriting'},
    ))['document'];
    await call('handwriting_documents', {
      'view_id': page,
      'action': 'edit_handwriting',
      'expected_document': current,
      'page_index': 0,
      'operations': [
        {
          'action': 'add',
          'kind': 'strokes',
          'id': 'stroke-1',
          'value': {'color': 4278190080, 'width': 2, 'points': []},
        }
      ],
    });
    final fresh = (await call(
      'handwriting_documents',
      {'view_id': page, 'action': 'get_handwriting'},
    ))['document'];
    expect(jsonEncode(fresh), contains('stroke-1'));
    final denied = await tools.executeTool('handwriting_documents', {
      'workspace_id': workspace,
      'view_id': page,
      'action': 'save_handwriting',
      'expected_document': current,
    });
    expect(denied.isError, isTrue);
  });
}
