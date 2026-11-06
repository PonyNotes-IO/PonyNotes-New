let buffer = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => {
  buffer += chunk;
  let end;
  while ((end = buffer.indexOf('\n')) >= 0) {
    const line = buffer.slice(0, end); buffer = buffer.slice(end + 1);
    if (!line.trim()) continue;
    const request = JSON.parse(line);
    if (request.id === undefined) continue;
    let result = {};
    if (request.method === 'initialize') result = { protocolVersion: '2025-03-26', capabilities: { tools: {}, resources: {} }, serverInfo: { name: 'stdio-test', version: '1.0.0' } };
    if (request.method === 'tools/list') result = { tools: [{ name: 'echo', description: 'echo', inputSchema: { type: 'object', properties: { text: { type: 'string' } }, required: ['text'] } }] };
    if (request.method === 'tools/call') result = { content: [{ type: 'text', text: `echo:${request.params.arguments.text}` }] };
    if (request.method === 'resources/list') result = { resources: [{ uri: 'test://resource', name: 'resource', mimeType: 'text/plain' }] };
    process.stdout.write(`${JSON.stringify({ jsonrpc: '2.0', id: request.id, result })}\n`);
  }
});
