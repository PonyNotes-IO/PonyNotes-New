import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import { once } from 'node:events';
import os from 'node:os';
import path from 'node:path';
import { WebSocket } from 'ws';

test('remote runtime authenticates the connection, rejects a second owner and accepts a scoped session', async t => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'pony-remote-test-'));
  const token = 'test-connection-token-never-use-in-production';
  const child = spawn(process.execPath, ['src/server.mjs'], { env: { ...process.env, PORT: '0', HOST: '127.0.0.1', PONYNOTES_AGENT_TOKEN: token, PONYNOTES_AGENT_DATA: root }, stdio: ['ignore', 'pipe', 'pipe'] });
  let diagnostics = ''; child.stderr.on('data', chunk => { diagnostics += chunk; });
  t.after(async () => { child.kill(); await once(child, 'exit').catch(() => {}); await rm(root, { recursive: true, force: true }); });
  const port = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(Error(`server startup failed: ${diagnostics}`)), 10000);
    child.stdout.on('data', chunk => { const found = chunk.toString().match(/listening on (\d+)/); if (found) { clearTimeout(timer); resolve(Number(found[1])); } });
  });
  const url = `ws://127.0.0.1:${port}/agent`;
  const unauthorized = new WebSocket(url);
  const denied = await once(unauthorized, 'error');
  assert.match(denied[0].message, /401/);
  const ws = new WebSocket(url, { headers: { authorization: `Bearer ${token}` } });
  await once(ws, 'open');
  const another = new WebSocket(url, { headers: { authorization: `Bearer ${token}` } });
  assert.match((await once(another, 'error'))[0].message, /409/);
  const responses = [];
  ws.on('message', data => responses.push(JSON.parse(data.toString())));
  ws.send(JSON.stringify({ type: 'initialize', id: 'init', config: { scope: 'remote-user-workspace', workspaceId: 'workspace', baseUrl: 'http://127.0.0.1:1/v1', model: 'test-model', apiKey: 'fake-provider-key', directory: 'untrusted-client-path' } }));
  const response = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(Error('initialize timed out')), 10000);
    ws.on('message', data => { const record = JSON.parse(data); if (record.id === 'init') { clearTimeout(timer); resolve(record); } });
  });
  assert.equal(response.success, true, response.error);
  assert.equal(response.data.location, '远端执行器');
  assert.ok(!response.data.tools.includes('run_command'));
  ws.close(); await once(ws, 'close');
});
