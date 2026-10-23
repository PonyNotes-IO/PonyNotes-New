import 'dart:io';

import 'package:mcp_stdio_bridge/bridge.dart';

Future<void> main(List<String> args) async {
  final url =
      Platform.environment['PONYNOTES_MCP_URL'] ?? 'http://127.0.0.1:27861/mcp';
  final token = Platform.environment['PONYNOTES_MCP_TOKEN']?.trim() ?? '';
  if (token.isEmpty) {
    stderr.writeln('PONYNOTES_MCP_TOKEN is required');
    exit(64);
  }

  try {
    await PonyNotesBridge(url: Uri.parse(url), token: token).run();
  } catch (error, stackTrace) {
    // stdout 保留给 MCP 协议，诊断信息只写 stderr
    stderr.writeln('failed to connect to $url: $error');
    stderr.writeln(stackTrace);
    exit(1);
  }
}
