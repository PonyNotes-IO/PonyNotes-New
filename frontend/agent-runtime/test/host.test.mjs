import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { mkdtemp, rm, readdir, readFile, mkdir, symlink } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { AgentHost, safeKey, insideDirectory } from '../src/host.mjs';

async function fixture(t, mode = 'notes') {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'pony-agent-test-'));
  const records = []; const requests = [];
  const approvals = { allowed: false };
  const server = http.createServer(async (req, res) => {
    const chunks = []; for await (const chunk of req) chunks.push(chunk);
    const body = JSON.parse(Buffer.concat(chunks).toString()); requests.push(body);
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    const userIndex = body.messages.findLastIndex(m => m.role === 'user');
    const hasResult = body.messages.slice(userIndex).some(m => m.role === 'tool');
    const tool = mode === 'external' ? body.tools?.find(t => t.function.name.includes('echo'))?.function.name : mode === 'file' ? 'write' : 'notes_search_notes';
    const choice = (delta, finish_reason = null) => `data: ${JSON.stringify({ id: 'mock-1', object: 'chat.completion.chunk', created: 1, model: 'test-model', choices: [{ index: 0, delta, finish_reason }] })}\n\n`;
    if (!hasResult && tool && mode !== 'text') {
      res.write(choice({ role: 'assistant', tool_calls: [{ index: 0, id: `call-${requests.length}`, type: 'function', function: { name: tool, arguments: JSON.stringify(mode === 'external' ? { text: 'hello' } : mode === 'file' ? { path: 'result.txt', content: 'approved result' } : { workspace_id: 'workspace-1', query: '会议' }) } }] }));
      res.write(choice({}, 'tool_calls'));
    } else {
      res.write(choice({ role: 'assistant', content: hasResult ? '已查询笔记。' : '你好。' })); res.write(choice({}, 'stop'));
    }
    res.end('data: [DONE]\n\n');
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  let host;
  host = new AgentHost({ dataRoot: directory, send: record => {
    records.push(record);
    if (record.type === 'note_call') queueMicrotask(() => host.receive({ type: 'note_result', id: record.id, result: { content: [{ type: 'text', text: '会议纪要' }], isError: false } }));
    if (record.type === 'approval') queueMicrotask(() => host.receive({ type: 'interaction_response', id: record.id, result: approvals.allowed }));
  } });
  t.after(async () => { await host.close(); server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); await rm(directory, { recursive: true, force: true }); });
  const config = { scope: 'user-workspace-chat', workspaceId: 'workspace-1', apiKey: 'secret-never-save-me', model: 'test-model', baseUrl: `http://127.0.0.1:${server.address().port}/v1`, noteTools: [{ name: 'search_notes', description: '搜索笔记', inputSchema: { type: 'object', properties: { workspace_id: { type: 'string' }, query: { type: 'string' } }, required: ['workspace_id', 'query'] } }] };
  return { host, records, requests, config, directory, approvals };
}

test('real pi runs a multi-turn note tool loop and restores the native transcript', async t => {
  const f = await fixture(t);
  await f.host.receive({ type: 'initialize', id: 'init', config: f.config });
  const initialized = f.records.find(r => r.id === 'init');
  assert.equal(initialized?.success, true, initialized?.error);
  assert.ok(f.host.session.getActiveToolNames().includes('notes_search_notes'));
  assert.ok(!f.host.session.getActiveToolNames().includes('bash'));
  await f.host.receive({ type: 'prompt', id: 'q1', message: '找会议笔记' });
  assert.ok(f.records.some(r => r.type === 'note_call'));
  assert.equal(f.requests.length, 2);
  assert.ok(f.host.session.messages.some(m => m.role === 'toolResult'));
  assert.ok(f.records.some(r => r.type === 'settled'));
  await f.host.close();
  const restoredRecords = [];
  const restored = new AgentHost({ dataRoot: f.directory, send: r => restoredRecords.push(r) });
  await restored.receive({ type: 'initialize', id: 'restore', config: f.config });
  assert.equal(restoredRecords.find(r => r.id === 'restore')?.success, true);
  assert.ok(restored.session.messages.some(m => m.role === 'toolResult'));
  await restored.close();
  async function checkSecrets(directory) {
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      const file = path.join(directory, entry.name);
      if (entry.isDirectory()) await checkSecrets(file);
      else assert.ok(!(await readFile(file, 'utf8')).includes(f.config.apiKey), file);
    }
  }
  await checkSecrets(f.directory);
});

test('external MCP initializes and a denied tool never reaches the server', async t => {
  const f = await fixture(t, 'external'); let executed = 0;
  const mcp = http.createServer(async (req, res) => {
    if (req.method !== 'POST') { res.writeHead(405); res.end(); return; }
    const chunks = []; for await (const c of req) chunks.push(c);
    const record = JSON.parse(Buffer.concat(chunks).toString());
    if (!record.id) { res.writeHead(202); res.end(); return; }
    let result = {};
    if (record.method === 'initialize') result = { protocolVersion: '2025-03-26', capabilities: { tools: {} }, serverInfo: { name: 'test', version: '1.0.0' } };
    if (record.method === 'tools/list') result = { tools: [{ name: 'echo', description: 'echo', inputSchema: { type: 'object', properties: { text: { type: 'string' } }, required: ['text'] } }] };
    if (record.method === 'tools/call') { executed++; result = { content: [{ type: 'text', text: 'unexpected execution' }] }; }
    res.writeHead(200, { 'content-type': 'application/json' }); res.end(JSON.stringify({ jsonrpc: '2.0', id: record.id, result }));
  });
  await new Promise(resolve => mcp.listen(0, '127.0.0.1', resolve));
  t.after(() => { mcp.closeAllConnections(); mcp.close(); });
  f.config.mcpServers = { fixture: { url: `http://127.0.0.1:${mcp.address().port}/mcp` } };
  await f.host.receive({ type: 'initialize', id: 'init', config: f.config });
  assert.equal(f.records.find(r => r.id === 'init')?.success, true, JSON.stringify(f.records));
  await f.host.receive({ type: 'prompt', id: 'q', message: 'Use echo' });
  assert.ok(f.records.some(r => r.type === 'approval'), JSON.stringify(f.records));
  assert.equal(executed, 0);
});

test('namespace and canonical paths reject traversal and links outside the selected directory', async t => {
  assert.throws(() => safeKey('../other-account'));
  const root = await mkdtemp(path.join(os.tmpdir(), 'pony-paths-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  await mkdir(path.join(root, 'allowed'));
  await mkdir(path.join(root, 'other'));
  assert.equal(await insideDirectory(path.join(root, 'allowed'), '../other/new.txt'), false);
  assert.equal(await insideDirectory(path.join(root, 'allowed'), 'new.txt'), true);
  await symlink(path.join(root, 'other'), path.join(root, 'allowed', 'link'), process.platform === 'win32' ? 'junction' : 'dir');
  assert.equal(await insideDirectory(path.join(root, 'allowed'), 'link/new.txt'), false);
});

test('disconnect rejects a pending interaction instead of granting approval', async () => {
  const host = new AgentHost({ dataRoot: os.tmpdir(), send: () => {} });
  const pending = host.request('approval', { title: 'write' });
  const rejected = assert.rejects(pending, /停止/);
  await host.close();
  await rejected;
  assert.equal(host.pending.size, 0);
});

test('manual context compaction uses pi and leaves a persisted summary', async t => {
  const f = await fixture(t, 'text');
  await f.host.receive({ type: 'initialize', id: 'init', config: f.config });
  await f.host.receive({ type: 'prompt', id: 'q', message: '记住：项目的截止日期是星期五。' });
  f.host.session.settingsManager.applyOverrides({ compaction: { enabled: true, keepRecentTokens: 1 } });
  await f.host.receive({ type: 'prompt', id: 'q2', message: '请保留这个决定。' });
  await f.host.receive({ type: 'compact', id: 'compact' });
  const response = f.records.find(r => r.id === 'compact');
  assert.equal(response.success, true, response.error);
  assert.ok(f.host.session.sessionManager.getEntries().some(e => e.type === 'compaction'));
});

test('pi file tools are usable without extra native downloads and writes require approval', async t => {
  const f = await fixture(t, 'file');
  f.config.directory = path.join(f.directory, 'authorized-files');
  await f.host.receive({ type: 'initialize', id: 'init', config: f.config });
  assert.equal(f.records.find(r => r.id === 'init')?.success, true);
  assert.ok(f.host.session.getActiveToolNames().includes('write'));
  assert.ok(!f.host.session.getActiveToolNames().includes('grep'));
  await f.host.receive({ type: 'prompt', id: 'denied', message: 'Write a file' });
  await assert.rejects(readFile(path.join(f.config.directory, 'result.txt')), /ENOENT/);
  f.approvals.allowed = true;
  await f.host.receive({ type: 'prompt', id: 'approved', message: 'Write the file after approval' });
  assert.equal(await readFile(path.join(f.config.directory, 'result.txt'), 'utf8'), 'approved result');
});

test('pi connects a stdio MCP server and executes its approved tool', async t => {
  const f = await fixture(t, 'external');
  f.approvals.allowed = true;
  f.config.mcpServers = { local: { command: process.execPath, args: [path.resolve('test/stdio-mcp-fixture.mjs')] } };
  await f.host.receive({ type: 'initialize', id: 'init', config: f.config });
  await f.host.receive({ type: 'prompt', id: 'q', message: 'Use the echo tool' });
  assert.ok(f.host.session.messages.some(message => message.role === 'toolResult' && JSON.stringify(message).includes('echo:hello')));
  assert.ok(f.host.session.getActiveToolNames().includes('read_mcp_resource'));
});
