import 'package:mcp_dart/mcp_dart.dart';

/// 把 stdio 上的 MCP 会话转发到本地 PonyNotes HTTP 端点。
///
/// 只代理工具调用，不重复实现笔记业务。Token 通过环境变量传入，
/// 不写入 URL 或日志。
class PonyNotesBridge {
  PonyNotesBridge({required this.url, required this.token});

  final Uri url;
  final String token;

  Future<void> run() async {
    final client = McpClient(
      const Implementation(name: 'ponynotes-stdio-bridge', version: '0.1.0'),
    );
    final transport = StreamableHttpClientTransport(
      url,
      opts: StreamableHttpClientTransportOptions(
        requestInit: {
          'headers': {'Authorization': 'Bearer $token'},
        },
      ),
    );
    await client.connect(transport);

    final proxy = await buildProxyServer(client);
    await proxy.connect(StdioServerTransport());
  }
}

/// 从上游客户端拉取工具列表，并以相同的名称、schema 和描述注册代理工具。
Future<McpServer> buildProxyServer(McpClient client) async {
  final tools = await client.listTools();
  final server = McpServer(
    const Implementation(name: 'ponynotes', version: '0.1.0'),
    options: const McpServerOptions(
      capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
    ),
  );

  for (final tool in tools.tools) {
    server.registerTool(
      tool.name,
      title: tool.title,
      description: tool.description,
      inputSchema: JsonObject.fromJson(tool.inputSchema.toJson()),
      annotations: tool.annotations,
      callback: (args, extra) => client.callTool(
        CallToolRequest(name: tool.name, arguments: args),
      ),
    );
  }
  return server;
}
