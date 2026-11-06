import 'package:appflowy/features/agent/application/agent_note_bridge.dart';
import 'package:appflowy/features/mcp/application/mcp_tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart';

class _Tools extends McpTools {
  _Tools({bool Function(String)? allowed})
      : super(endpoint: 'test', version: '1', isToolAllowed: allowed);
  int writes = 0;
  @override
  List<McpToolSpec> get toolSpecs => [
        McpToolSpec(
          name: 'write',
          description: 'write',
          inputSchema: JsonObject(
            properties: {
              'workspace_id': JsonString(),
              'text': JsonString(),
            },
            required: [
              'workspace_id',
              'text',
            ],
            additionalProperties: false,
          ),
          handler: (_) async {
            writes++;
            return const CallToolResult(content: []);
          },
        ),
      ];
}

void main() {
  test('write rejection and invalid arguments never reach the business handler',
      () async {
    final tools = _Tools();
    int approvals = 0;
    final bridge = AgentNoteBridge(
      tools: tools,
      workspaceId: 'one',
      isCurrent: () async => true,
      approve: (_, __) async {
        approvals++;
        return false;
      },
    );
    expect(
      (await bridge.execute('write', {'workspace_id': 'one', 'text': 'new'}))
          .isError,
      true,
    );
    expect(
      (await bridge.execute('write', {'workspace_id': 'one'})).isError,
      true,
    );
    expect(
      (await bridge.execute('write', {'workspace_id': 'two', 'text': 'new'}))
          .isError,
      true,
    );
    expect(tools.writes, 0);
    expect(approvals, 1);
  });
  test(
      'switching accounts or cancelling while approval is open invalidates the pending write',
      () async {
    bool current = true;
    final tools = _Tools();
    final bridge = AgentNoteBridge(
      tools: tools,
      workspaceId: 'one',
      isCurrent: () async => current,
      approve: (_, __) async {
        current = false;
        return true;
      },
    );
    expect(
      (await bridge.execute('write', {'workspace_id': 'one', 'text': 'new'}))
          .isError,
      true,
    );
    expect(tools.writes, 0);
  });
  test('approved writes execute once and disabled tools remain unavailable',
      () async {
    bool allowed = true;
    final tools = _Tools(allowed: (_) => allowed);
    final bridge = AgentNoteBridge(
      tools: tools,
      workspaceId: 'one',
      isCurrent: () async => true,
      approve: (_, __) async => true,
    );
    expect(
      (await bridge.execute('write', {'workspace_id': 'one', 'text': 'new'}))
          .isError,
      false,
    );
    expect(tools.writes, 1);
    allowed = false;
    expect(
      (await bridge.execute('write', {'workspace_id': 'one', 'text': 'new'}))
          .isError,
      true,
    );
    expect(tools.writes, 1);
  });
}
