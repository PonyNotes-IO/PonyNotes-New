import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:mcp_stdio_bridge/bridge.dart';
import 'package:test/test.dart';

void main() {
  late StreamableMcpServer upstream;
  late McpClient upstreamClient;
  late McpServer proxy;
  late McpClient downstreamClient;
  late StreamController<List<int>> toProxy;
  late StreamController<List<int>> toClient;

  McpServer fakeServer() {
    final server = McpServer(
      const Implementation(name: 'fake-ponynotes', version: '1.0.0'),
      options: const McpServerOptions(
        capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
      ),
    );
    server.registerTool(
      'echo',
      description: 'echo text',
      inputSchema: const JsonObject(
        properties: {'text': JsonString()},
        required: ['text'],
        additionalProperties: false,
      ),
      callback: (args, extra) => CallToolResult(
        content: [TextContent(text: args['text'] as String)],
      ),
    );
    return server;
  }

  setUp(() async {
    upstream = StreamableMcpServer(
      serverFactory: (_) => fakeServer(),
      host: '127.0.0.1',
      port: 0,
      authenticator: (request) =>
          request.headers.value('authorization') == 'Bearer test-token',
    );
    await upstream.start();
    final url = Uri.parse('http://127.0.0.1:${upstream.boundPort}/mcp');

    upstreamClient = McpClient(
      const Implementation(name: 'bridge-test-upstream', version: '1.0.0'),
    );
    await upstreamClient.connect(
      StreamableHttpClientTransport(
        url,
        opts: StreamableHttpClientTransportOptions(
          requestInit: {
            'headers': {'Authorization': 'Bearer test-token'},
          },
        ),
      ),
    );

    proxy = await buildProxyServer(upstreamClient);
    toProxy = StreamController<List<int>>();
    toClient = StreamController<List<int>>();
    await proxy.connect(
      IOStreamTransport(stream: toProxy.stream, sink: toClient.sink),
    );

    downstreamClient = McpClient(
      const Implementation(name: 'bridge-test-downstream', version: '1.0.0'),
    );
    await downstreamClient.connect(
      IOStreamTransport(stream: toClient.stream, sink: toProxy.sink),
    );
  });

  tearDown(() async {
    await downstreamClient.close();
    await proxy.close();
    await toProxy.close();
    await toClient.close();
    await upstreamClient.close();
    await upstream.stop();
  });

  test('proxy exposes upstream tools', () async {
    final tools = await downstreamClient.listTools();
    expect(tools.tools.map((tool) => tool.name), contains('echo'));
    final schema = tools.tools.first.inputSchema.toJson();
    expect(schema['required'], contains('text'));
  });

  test('proxy forwards tool calls', () async {
    final result = await downstreamClient.callTool(
      const CallToolRequest(name: 'echo', arguments: {'text': 'hello'}),
    );
    expect(result.isError, isFalse);
    expect(
      result.content.whereType<TextContent>().first.text,
      'hello',
    );
  });

  test('wrong token is rejected', () async {
    final client = McpClient(
      const Implementation(name: 'bridge-test-bad-token', version: '1.0.0'),
    );
    final transport = StreamableHttpClientTransport(
      Uri.parse('http://127.0.0.1:${upstream.boundPort}/mcp'),
      opts: StreamableHttpClientTransportOptions(
        requestInit: {
          'headers': {'Authorization': 'Bearer wrong-token'},
        },
      ),
    );
    await expectLater(client.connect(transport), throwsA(anything));
  });

  test('stdio entry forwards protocol messages', () async {
    final process = await Process.start(
      Platform.resolvedExecutable,
      ['run', 'bin/mcp_stdio_bridge.dart'],
      workingDirectory: Directory.current.path,
      environment: {
        ...Platform.environment,
        'PONYNOTES_MCP_URL': 'http://127.0.0.1:${upstream.boundPort}/mcp',
        'PONYNOTES_MCP_TOKEN': 'test-token',
      },
    );
    addTearDown(process.kill);

    final waiters = <int, Completer<Map<String, dynamic>>>{};
    final stderrBuffer = StringBuffer();
    process.stderr.transform(utf8.decoder).listen(stderrBuffer.write);
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      final decoded = jsonDecode(line);
      if (decoded is Map<String, dynamic>) {
        final id = decoded['id'];
        if (id is int) waiters[id]?.complete(decoded);
      }
    });

    Future<Map<String, dynamic>> request(
      int id,
      String method, [
      Map<String, dynamic>? params,
    ]) {
      final completer = Completer<Map<String, dynamic>>();
      waiters[id] = completer;
      process.stdin.writeln(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': id,
          'method': method,
          'params': params ?? <String, dynamic>{},
        }),
      );
      return completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException(
          'no response for $method; stderr: $stderrBuffer',
        ),
      );
    }

    final initialize = await request(1, 'initialize', {
      'protocolVersion': '2025-06-18',
      'capabilities': <String, dynamic>{},
      'clientInfo': {'name': 'stdio-test', 'version': '1.0.0'},
    });
    expect(initialize['result'], isNotNull);

    process.stdin.writeln(
      jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}),
    );
    final tools = await request(2, 'tools/list');
    final toolNames =
        (tools['result']['tools'] as List).map((tool) => (tool as Map)['name']);
    expect(toolNames, contains('echo'));

    final call = await request(3, 'tools/call', {
      'name': 'echo',
      'arguments': {'text': 'stdio'},
    });
    expect(call['result']['content'][0]['text'], 'stdio');
  });
}
