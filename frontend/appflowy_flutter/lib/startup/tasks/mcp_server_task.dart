import 'dart:io';

import 'package:appflowy/features/mcp/application/mcp_server_service.dart';
import 'package:appflowy/startup/startup.dart';

/// 桌面端启动时恢复用户此前开启的本地 MCP Server。
class McpServerTask extends LaunchTask {
  const McpServerTask();

  @override
  Future<void> initialize(LaunchContext context) async {
    await super.initialize(context);
    if (!(Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
      return;
    }
    await McpServerService.instance.restore();
  }

  @override
  Future<void> dispose() async {
    await McpServerService.instance.shutdown();
    await super.dispose();
  }
}
