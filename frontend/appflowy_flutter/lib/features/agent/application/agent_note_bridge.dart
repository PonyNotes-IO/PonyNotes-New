import 'package:appflowy/features/mcp/application/mcp_tools.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Validation and authorization run again at the business boundary, after approval.
class AgentNoteBridge {
  AgentNoteBridge({
    required this.tools,
    required this.workspaceId,
    required this.isCurrent,
    required this.approve,
  });
  final McpTools tools;
  final String workspaceId;
  final Future<bool> Function() isCurrent;
  final Future<bool> Function(McpToolSpec, Map<String, dynamic>) approve;

  Future<CallToolResult> execute(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    try {
      if (!await isCurrent()) throw StateError('账号、工作区或任务授权已失效');
      if (arguments['workspace_id'] != null &&
          arguments['workspace_id'] != workspaceId) {
        throw StateError('工具不属于当前工作区');
      }
      final spec =
          tools.toolSpecs.where((spec) => spec.name == name).firstOrNull;
      if (spec == null) throw StateError('未知笔记工具');
      spec.inputSchema.validate(arguments);
      if (tools.isToolAllowed?.call(name) == false) {
        throw StateError('此笔记工具已被禁用');
      }
      if (!spec.readOnly && !await approve(spec, arguments)) {
        throw StateError('用户拒绝执行');
      }
      if (!await isCurrent()) throw StateError('账号、工作区或任务授权已失效');
      return tools.executeTool(name, arguments);
    } catch (error) {
      return CallToolResult(
        content: [TextContent(text: '$error')],
        isError: true,
      );
    }
  }
}
