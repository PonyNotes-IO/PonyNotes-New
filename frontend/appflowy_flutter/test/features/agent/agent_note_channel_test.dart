import 'package:appflowy/features/agent/application/agent_controller.dart';
import 'package:appflowy/features/agent/application/agent_service.dart';
import 'package:appflowy/features/agent/application/agent_permissions.dart';
import 'package:appflowy/features/mcp/application/mcp_tools.dart';
import 'package:appflowy/features/ai_internal/application/ai_provider_config.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Service extends AgentService {
  Map<String, dynamic>? call;
  final results = <Map<String, dynamic>>[];
  @override
  Future<String> identity(String workspace) async => 'server|user|$workspace';
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String workspace,
    String document,
    String suffix, [
    Map<String, dynamic>? body,
  ]) async {
    if (suffix == '/tool-result') {
      results.add(body!);
      call = null;
    }
    if (suffix.startsWith('/tools?') && method == 'GET') {
      return {
        'calls': [if (call != null) call],
      };
    }
    return {'messages': [], 'sources': {}};
  }
}

class _Tools extends McpTools {
  _Tools() : super(endpoint: 'test', version: '1');
  int writes = 0;
  @override
  List<McpToolSpec> get toolSpecs => [
        for (final name in ['read', 'delete'])
          McpToolSpec(
            name: name,
            description: name,
            readOnly: name == 'read',
            destructive: name == 'delete',
            inputSchema: JsonObject(properties: {}),
            handler: (_) async {
              if (name == 'delete') writes++;
              return const CallToolResult(content: [TextContent(text: '完成')]);
            },
          ),
        McpToolSpec(
          name: 'write',
          description: '写笔记',
          inputSchema: JsonObject(
            properties: {
              'workspace_id': JsonString(),
              'text': JsonString(),
            },
            required: [
              'workspace_id',
              'text',
            ],
          ),
          handler: (_) async {
            writes++;
            return const CallToolResult(content: [TextContent(text: '完成')]);
          },
        ),
      ];
}

class _Controller extends AgentController {
  _Controller(_Service service)
      : super(
          chatId: 'document',
          service: service,
          workspaceId: () async => 'workspace',
        );
  final tools = _Tools();
  @override
  McpTools get noteTools => tools;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  for (final mode in AgentPermissions.modes) {
    for (final tool in ['read', 'write', 'delete']) {
      testWidgets('$mode handles $tool with the selected approval policy',
          (tester) async {
        final service = _Service();
        final controller = _Controller(service)
          ..providerConfig = const AiProviderConfig(modelName: 'custom');
        await controller.connect();
        await controller.configurePermissions(mode: mode);
        service.call = {
          'id': 'policy',
          'name': tool,
          'arguments': tool == 'write'
              ? {'workspace_id': 'workspace', 'text': '内容'}
              : <String, dynamic>{},
        };
        await tester.pump(const Duration(seconds: 1));
        final needsApproval = tool != 'read' &&
            (mode == 'ask' || (mode == 'auto' && tool == 'delete'));
        expect(controller.interactions.length, needsApproval ? 1 : 0);
        if (needsApproval) {
          expect(controller.tools.writes, 0);
          controller.respond(controller.interactions.single, true);
          await tester.pump();
        }
        expect(controller.tools.writes, tool == 'read' ? 0 : 1);
        expect(service.results.single['result']['isError'], isNot(true));
        final saved = AgentPermissions();
        await saved.load('server|user|workspace', 'document');
        expect(saved.mode, mode);
        await controller.disconnect();
        controller.dispose();
        await tester.pump();
      });
    }
  }
  testWidgets('invalid and in-flight mode changes retain the current policy',
      (tester) async {
    final controller = _Controller(_Service())
      ..providerConfig = const AiProviderConfig(modelName: 'custom');
    await controller.connect();
    await expectLater(
      controller.configurePermissions(mode: 'unknown'),
      throwsArgumentError,
    );
    expect(controller.permissions.mode, 'ask');
    controller.running = true;
    await expectLater(
      controller.configurePermissions(mode: 'full'),
      throwsStateError,
    );
    expect(controller.permissions.mode, 'ask');
    await controller.disconnect();
    controller.dispose();
    await tester.pump();
  });
  testWidgets(
      'cloud note calls preserve approval, execute once and cancel pending writes',
      (tester) async {
    final service = _Service();
    final controller = _Controller(service)
      ..providerConfig = const AiProviderConfig(modelName: 'custom');
    await controller.connect();
    service.call = {
      'id': 'one',
      'name': 'write',
      'arguments': {'workspace_id': 'workspace', 'text': '内容'},
    };
    await tester.pump(const Duration(seconds: 1));
    expect(controller.interactions.length, 1);
    expect(controller.tools.writes, 0);
    controller.respond(controller.interactions.single, false);
    await tester.pump();
    expect(service.results.single['result']['isError'], true);
    expect(controller.tools.writes, 0);
    service.call = {
      'id': 'two',
      'name': 'write',
      'arguments': {'workspace_id': 'workspace', 'text': '内容'},
    };
    await tester.pump(const Duration(seconds: 1));
    controller.respond(controller.interactions.single, true);
    await tester.pump();
    expect(controller.tools.writes, 1);
    expect(service.results.last['result']['isError'], isNot(true));
    service.call = {
      'id': 'three',
      'name': 'write',
      'arguments': {'workspace_id': 'workspace', 'text': '内容'},
    };
    await tester.pump(const Duration(seconds: 1));
    expect(controller.interactions.length, 1);
    await controller.disconnect();
    await tester.pump();
    expect(controller.tools.writes, 1);
    expect(controller.interactions, isEmpty);
    controller.dispose();
  });
  test('display text keeps the product identity in engine errors', () {
    expect(
      agentDisplayText('WeKnora upstream error / WEKNORA'),
      '小马 Agent upstream error / 小马 Agent',
    );
  });
}
