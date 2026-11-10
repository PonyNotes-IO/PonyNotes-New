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
    const rawUser = body.messages[userIndex]?.content;
    const latestUser = typeof rawUser === 'string' ? rawUser : (rawUser || []).filter(part => part.type === 'text').map(part => part.text).join('\n');
    const directAnswer = mode === 'text' || (mode === 'auto' && typeof latestUser === 'string' && latestUser.includes('什么是'));
    if (!hasResult && tool && !directAnswer) {
      res.write(choice({ role: 'assistant', tool_calls: [{ index: 0, id: `call-${requests.length}`, type: 'function', function: { name: tool, arguments: JSON.stringify(mode === 'external' ? { text: 'hello' } : mode === 'file' ? { path: 'result.txt', content: 'approved result' } : { workspace_id: 'workspace-1', query: '会议' }) } }] }));
      res.write(choice({}, 'tool_calls'));
    } else {
      res.write(choice({ role: 'assistant', content: hasResult ? '已查询笔记。' : '你好。' })); res.write(choice({}, 'stop'));
    }
    res.write(`data: ${JSON.stringify({ id: 'mock-1', object: 'chat.completion.chunk', choices: [], usage: { prompt_tokens: 100, completion_tokens: 12, total_tokens: 112, prompt_tokens_details: { cached_tokens: 20 } } })}\n\n`);
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

test('custom model responses with token usage finish without a cost calculation error', async t => {
  const f = await fixture(t, 'text');
  await f.host.receive({ type: 'initialize', id: 'init', config: f.config });
  await f.host.receive({ type: 'prompt', id: 'question', message: '你好' });
  const answer = f.host.session.messages.findLast(message => message.role === 'assistant');
  assert.equal(answer.stopReason, 'stop', answer.errorMessage);
  assert.equal(answer.usage.input, 80);
  assert.equal(answer.usage.output, 12);
  assert.equal(answer.usage.cacheRead, 20);
  assert.ok(Number.isFinite(answer.usage.cost.total));
  assert.ok(!f.records.some(record => record.type === 'notice' && record.kind === 'error'));
});

test('model and thinking controls update the actual request and keep the document transcript', async t => {
  const f = await fixture(t, 'text');
  f.config.documentId = 'model-controls-document';
  await f.host.receive({ type: 'initialize', id: 'init', config: f.config });
  await f.host.receive({ type: 'prompt', id: 'first', message: '记住这个文档' });
  const sessionId = f.host.session.sessionId;
  await f.host.receive({ type: 'configure_model', id: 'configure', config: { ...f.config, model: 'custom-reasoner', supportsReasoning: true, thinkingLevel: 'high' } });
  assert.equal(f.records.find(r => r.id === 'configure').success, true);
  assert.equal(f.host.session.sessionId, sessionId);
  assert.equal(f.host.session.thinkingLevel, 'high');
  await f.host.receive({ type: 'prompt', id: 'second', message: '继续' });
  assert.equal(f.requests.at(-1).model, 'custom-reasoner');
  assert.equal(f.requests.at(-1).reasoning_effort, 'high');
  assert.ok(f.requests.at(-1).messages.some(m => m.role === 'user' && JSON.stringify(m.content).includes('记住这个文档')));
  await f.host.receive({ type: 'configure_model', id: 'invalid', config: { ...f.config, thinkingLevel: 'impossible' } });
  assert.equal(f.records.find(r => r.id === 'invalid').success, false);
  assert.equal(f.host.session.thinkingLevel, 'high');
  await f.host.receive({ type: 'configure_model', id: 'plain', config: { ...f.config, supportsReasoning: false, thinkingLevel: 'high' } });
  await f.host.receive({ type: 'prompt', id: 'third', message: '直接回答' });
  assert.equal(f.host.session.thinkingLevel, 'off');
  assert.equal(f.requests.at(-1).reasoning_effort, undefined);
});

test('real pi runs a multi-turn note tool loop and restores the native transcript', async t => {
  const f = await fixture(t);
  f.config.documentId = 'existing-agent-document';
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

test('one Agent document answers and executes tasks in the same session without nested sessions', async t => {
  const f = await fixture(t, 'auto');
  f.config.documentId = 'ask-ai-document';
  await f.host.receive({ type: 'initialize', id: 'init', config: f.config });
  const sessionId = f.host.session.sessionId;
  await f.host.receive({ type: 'prompt', id: 'question', message: '什么是知识图谱？' });
  assert.equal(f.records.filter(record => record.type === 'note_call').length, 0);
  assert.equal(f.records.filter(record => record.type === 'plan').length, 0);
  const system = f.requests[0].messages.find(message => message.role === 'system' || message.role === 'developer').content;
  assert.match(system, /当前处于 Agent 模式/);
  assert.match(system, /信息已经足够时不调用工具/);
  assert.match(system, /建议和讨论不是执行授权/);
  await f.host.receive({ type: 'prompt', id: 'task', message: '帮我找会议笔记' });
  assert.equal(f.host.session.sessionId, sessionId);
  assert.equal(f.records.filter(record => record.type === 'note_call').length, 1);
  assert.ok(f.requests.at(-1).messages.some(message => message.role === 'user' && JSON.stringify(message.content).includes('什么是知识图谱？')));
  await f.host.receive({ type: 'new_session', id: 'split' });
  assert.equal(f.records.find(record => record.id === 'split').success, false);
  assert.equal(f.host.session.sessionId, sessionId);
});

test('an initial Agent document request cannot execute twice', async t => {
  const f = await fixture(t, 'text');
  f.config.documentId = 'legacy-document';
  await f.host.receive({ type: 'initialize', id: 'init', config: f.config });
  assert.equal(f.host.session.messages.length, 0);
  await f.host.receive({ type: 'prompt', id: 'once', initialRequest: 'legacy-document', message: '继续分析' });
  const count = f.requests.length;
  await f.host.receive({ type: 'prompt', id: 'again', initialRequest: 'legacy-document', message: '继续分析' });
  assert.equal(f.requests.length, count);
  assert.equal(f.host.session.messages.filter(message => message.role === 'user' && JSON.stringify(message.content).includes('继续分析')).length, 1);
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
  f.config.directory = f.directory;
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
  await mkdir(f.config.directory);
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

test('default session directory enables tools and restores its artifacts', async t => {
  const f = await fixture(t, 'file');
  f.config.documentId = 'default-directory-document';
  f.config.mcpServers = { local: { command: process.execPath, args: [path.resolve('test/stdio-mcp-fixture.mjs')] } };
  await f.host.receive({ type: 'initialize', id: 'init', config: f.config });
  const tools = f.host.session.getActiveToolNames();
  assert.ok(tools.includes('notes_search_notes'));
  for (const name of ['read', 'write', 'edit', 'ls', 'run_command']) assert.ok(tools.includes(name), name);
  const cwd = f.host.cwd;
  assert.match(path.relative(path.join(f.directory, 'artifacts'), cwd), /^\d{4}-\d{2}-\d{2}[\\/]user-workspace-chat$/);
  await f.host.receive({ type: 'prompt', id: 'denied', message: 'Write a file' });
  assert.equal(f.records.filter(r => r.type === 'approval').length, 1);
  f.approvals.allowed = true;
  await f.host.receive({ type: 'prompt', id: 'approved', message: 'Write a file' });
  assert.equal(await readFile(path.join(cwd, 'result.txt'), 'utf8'), 'approved result');
  await f.host.close();
  const restored = new AgentHost({ dataRoot: f.directory, send: () => {} });
  await restored.initialize(f.config);
  assert.equal(restored.cwd, cwd);
  assert.equal(await readFile(path.join(restored.cwd, 'result.txt'), 'utf8'), 'approved result');
  await restored.close();
});

test('remote default directory keeps command policy and existing selected remote directory', async t => {
  const f = await fixture(t, 'text');
  const remote = new AgentHost({ dataRoot: f.directory, remote: true, send: () => {} });
  await remote.initialize(f.config);
  assert.ok(remote.session.getActiveToolNames().includes('write'));
  assert.ok(!remote.session.getActiveToolNames().includes('run_command'));
  assert.ok(remote.cwd.startsWith(path.join(f.directory, 'artifacts')));
  await remote.close();
  const selected = new AgentHost({ dataRoot: f.directory, remote: true, allowCommands: true, send: () => {} });
  await selected.initialize({ ...f.config, directory: 'remote-workspace' });
  assert.equal(selected.cwd, path.join(f.directory, f.config.scope, 'files'));
  assert.ok(selected.session.getActiveToolNames().includes('run_command'));
  await selected.close();
});

test('permission modes: auto edits inside the directory without asking, full asks nothing', async t => {
  const f = await fixture(t, 'file');
  f.config.directory = path.join(f.directory, 'work');
  await mkdir(f.config.directory);
  await f.host.receive({ type: 'initialize', id: 'init', config: { ...f.config, permissionMode: 'auto' } });
  await f.host.receive({ type: 'prompt', id: 'auto', message: 'Write a file' });
  assert.equal(f.records.filter(r => r.type === 'approval').length, 0);
  assert.equal(await readFile(path.join(f.config.directory, 'result.txt'), 'utf8'), 'approved result');
  await f.host.receive({ type: 'configure_workspace', id: 'ask', config: { permissionMode: 'ask' } });
  assert.equal(f.records.find(r => r.id === 'ask').data.permissionMode, 'ask');
  await f.host.receive({ type: 'prompt', id: 'asked', message: 'Write again' });
  assert.equal(f.records.filter(r => r.type === 'approval').length, 1);
  await f.host.receive({ type: 'configure_workspace', id: 'bad', config: { permissionMode: 'root' } });
  assert.equal(f.records.find(r => r.id === 'bad').success, false);
});

test('changing the working directory keeps the document transcript', async t => {
  const f = await fixture(t, 'text');
  await f.host.receive({ type: 'initialize', id: 'init', config: f.config });
  await f.host.receive({ type: 'prompt', id: 'q', message: '记住代号 alpha' });
  const sessionId = f.host.session.sessionId;
  const work = path.join(f.directory, 'project');
  await mkdir(work);
  await f.host.receive({ type: 'configure_workspace', id: 'dir', config: { directory: work } });
  assert.equal(f.records.find(r => r.id === 'dir').success, true, f.records.find(r => r.id === 'dir').error);
  assert.equal(f.host.session.sessionId, sessionId);
  assert.ok(f.host.session.getActiveToolNames().includes('write'));
  assert.ok(f.host.session.messages.some(m => m.role === 'user' && JSON.stringify(m.content).includes('alpha')));
  await f.host.receive({ type: 'configure_workspace', id: 'default', config: { directory: '' } });
  assert.ok(f.host.cwd.startsWith(path.join(f.directory, 'artifacts')));
  assert.equal(f.host.session.sessionId, sessionId);
  await f.host.receive({ type: 'configure_workspace', id: 'dir-again', config: { directory: work } });
  await f.host.receive({ type: 'configure_workspace', id: 'missing', config: { directory: path.join(f.directory, 'nope') } });
  assert.equal(f.records.find(r => r.id === 'missing').success, false);
  assert.equal(f.host.state().directory, work);
});

test('the model is told it is 小马 Agent and never sees engine names', async t => {
  const f = await fixture(t, 'text');
  await f.host.receive({ type: 'initialize', id: 'init', config: f.config });
  await f.host.receive({ type: 'prompt', id: 'q', message: '你是谁' });
  const system = f.requests[0].messages.find(m => m.role === 'system' || m.role === 'developer').content;
  assert.match(system, /小马 Agent/);
  assert.doesNotMatch(system, /running inside pi|coding agent harness|Pi documentation|pi-coding-agent/i);
  assert.match(system, /默认工作目录/);
});
