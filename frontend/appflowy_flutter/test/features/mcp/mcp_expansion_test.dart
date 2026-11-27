import 'dart:convert';
import 'dart:io';

import 'package:appflowy/features/mcp/application/mcp_tools.dart';
import 'package:appflowy/features/mcp/application/mcp_permissions.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mcp_dart/mcp_dart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('new tools require opt-in and preserve legacy choices', () async {
    SharedPreferences.setMockInitialValues({
      'mcp_disabled_tools': ['delete_page'],
    });
    final permissions = McpPermissions.instance;
    await permissions.load();
    expect(permissions.isAllowed('get_page'), isTrue);
    expect(permissions.isAllowed('delete_page'), isFalse);
    expect(permissions.isAllowed('workspace_members'), isFalse);
    await permissions.setAllowed('workspace_members', true);
    await permissions.load();
    expect(permissions.isAllowed('workspace_members'), isTrue);
    expect(permissions.isAllowed('delete_page'), isFalse);
    await permissions.setAllowed('workspace_members', false);
  });

  test(
      'database query filters numeric values, retains same-name field IDs and stable order',
      () {
    Map<String, dynamic> row(String id, String a, String b) => {
          'row_id': id,
          'cells_by_id': {
            'a': {'text': a},
            'b': {'text': b},
          },
        };
    final data = [
      row('one', '2', 'x'),
      row('two', '10', 'y'),
      row('three', '10', 'z'),
    ];
    final selected = filterDatabaseRows(data, [
      {'field_id': 'a', 'operator': 'gte', 'value': '10'},
    ], [
      {'field_id': 'a', 'direction': 'desc'},
    ]);
    expect(selected.map((r) => r['row_id']), ['two', 'three']);
    expect(selected.first['cells_by_id'], containsPair('b', {'text': 'y'}));
    expect(data.first['row_id'], 'one');
  });

  test('transfers tolerate new block IDs and reject changed content or order',
      () {
    Document doc(List<String> lines) => Document(
            root: pageNode(
          children: lines.map((line) => paragraphNode(text: line)).toList(),
        ));
    expect(mcpTransferContentMatches(doc(['one', 'two']), doc(['one', 'two'])),
        isTrue);
    expect(mcpTransferContentMatches(doc(['one', 'two']), doc(['two', 'one'])),
        isFalse);
    expect(
        mcpTransferContentMatches(doc(['one', 'two']), doc(['one'])), isFalse);
  });

  test('whiteboard update advertises and requires the element version', () {
    final spec = McpTools(endpoint: 'test', version: 'test')
        .toolSpecs
        .firstWhere((tool) => tool.name == 'whiteboards');
    final operation = <String, dynamic>{
      'action': 'update',
      'element_id': 'element',
      'properties': {'x': 30},
    };
    final args = <String, dynamic>{
      'workspace_id': 'w',
      'view_id': 'v',
      'action': 'edit_whiteboard',
      'operations': [operation],
    };
    expect(() => spec.inputSchema.validate(args), throwsA(anything));
    operation['expected_version'] = 3;
    spec.inputSchema.validate(args);
  });

  test('native schema preserves enums and rejects unknown parameters', () {
    final schema = mcpMessageSchema(UpdateFieldTypePayloadPB());
    schema.validate({'viewId': 'v', 'fieldId': 'f', 'fieldType': 'Relation'});
    expect(
      () => schema.validate({'viewId': 'v', 'fieldType': 'invented'}),
      throwsA(anything),
    );
    expect(
      () => schema.validate({'viewId': 'v', 'unrecognized': 'x'}),
      throwsA(anything),
    );
  });

  test('registered contracts are unique and fit cloud relay limits', () {
    final specs = McpTools(endpoint: 'test', version: 'test').toolSpecs;
    final approved = jsonDecode(
      File('test/fixtures/mcp-approved-tools.json').readAsStringSync(),
    ) as Map;
    final selected = (approved['tools'] as List).cast<Map>();
    expect(selected.length, approved['approved_count']);
    expect(specs.map((s) => s.name).toSet(), {
      ...McpPermissions.legacyTools,
      ...selected.map((t) => t['name'] as String),
      // 远端 feat/mcp 分支新增：在侧栏创建私有/协作空间，不在原建议清单内。
      'create_space',
    });
    for (final entry in selected) {
      final spec = specs.firstWhere((s) => s.name == entry['name']);
      final actions =
          (spec.inputSchema.toJson()['properties'] as Map)['action'] as Map?;
      for (final action in (entry['actions'] as List).cast<String>()) {
        expect(
          actions?['enum'],
          contains(action),
          reason: '${entry['name']}.$action',
        );
      }
    }
    expect(specs.map((s) => s.name).toSet().length, specs.length);
    expect(specs.length, lessThanOrEqualTo(100));
    for (final spec in specs) {
      expect(
        jsonEncode(
          {'name': spec.name, 'inputSchema': spec.inputSchema.toJson()},
        ).length,
        lessThanOrEqualTo(32000),
        reason: spec.name,
      );
    }
    final output = Platform.environment['PONY_MCP_CONTRACTS'];
    if (output != null) {
      File(output).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(
          specs
              .map(
                (s) => {
                  'name': s.name,
                  'description': s.description,
                  'read_only': s.readOnly,
                  'destructive': s.destructive,
                  'inputSchema': s.inputSchema.toJson(),
                },
              )
              .toList(),
        ),
      );
    }
  });

  test('action-specific native schema rejects a request for another operation',
      () {
    final spec = McpTools(endpoint: 'test', version: 'test')
        .toolSpecs
        .firstWhere((s) => s.name == 'database_fields');
    spec.inputSchema.validate({
      'workspace_id': 'w',
      'view_id': 'v',
      'action': 'duplicate_database_field',
      'request': {'viewId': 'v', 'fieldId': 'f'},
    });
    expect(
      () => spec.inputSchema.validate({
        'workspace_id': 'w',
        'view_id': 'v',
        'action': 'duplicate_database_field',
        'request': {'unexpected': 'x'},
      }),
      throwsA(anything),
    );
    expect(
      () => spec.inputSchema.validate({
        'workspace_id': 'w',
        'view_id': 'v',
        'action': 'execute_arbitrary_event',
        'request': {},
      }),
      throwsA(anything),
    );
  });
}
