import http from 'node:http';
import { timingSafeEqual } from 'node:crypto';
import { WebSocketServer } from 'ws';
import { AgentHost } from './host.mjs';
const token = process.env.PONYNOTES_AGENT_TOKEN;
delete process.env.PONYNOTES_AGENT_TOKEN;
if (!token || token.length < 32) throw Error('PONYNOTES_AGENT_TOKEN must contain at least 32 characters; use a dedicated runtime per user');
const dataRoot = process.env.PONYNOTES_AGENT_DATA || '.data';
const skillDirectories = JSON.parse(process.env.PONYNOTES_AGENT_SKILLS || '[]');
if (!Array.isArray(skillDirectories) || skillDirectories.some(value => typeof value !== 'string')) throw Error('PONYNOTES_AGENT_SKILLS must be a JSON array of trusted skill directories');
const server = http.createServer((_req, res) => { res.writeHead(200, { 'content-type': 'application/json' }); res.end('{"service":"ponynotes-agent","version":"1.0.0"}'); });
const wss = new WebSocketServer({ noServer: true, maxPayload: 32 * 1024 * 1024 });
const hosts = new Set();
let leased = false;
server.on('upgrade', (req, socket, head) => {
  const auth = Buffer.from(req.headers.authorization || '');
  const expected = Buffer.from(`Bearer ${token}`);
  if (req.url !== '/agent' || auth.length !== expected.length || !timingSafeEqual(auth, expected)) {
    socket.write('HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n'); socket.destroy(); return;
  }
  // A dedicated runtime has one active owner; two clients must not mutate the same session.
  if (leased) { socket.write('HTTP/1.1 409 Conflict\r\nConnection: close\r\n\r\n'); socket.destroy(); return; }
  leased = true;
  wss.handleUpgrade(req, socket, head, ws => wss.emit('connection', ws));
});
wss.on('connection', ws => {
  const host = new AgentHost({ dataRoot, remote: true, skillDirectories, allowCommands: process.env.PONYNOTES_AGENT_ALLOW_COMMANDS === 'true', send: record => { if (ws.readyState === 1) ws.send(JSON.stringify(record)); } });
  hosts.add(host);
  ws.on('message', data => { try { void host.receive(JSON.parse(data.toString())); } catch { ws.close(1007, 'Invalid JSON'); } });
  ws.on('close', () => { void host.close().finally(() => { hosts.delete(host); leased = false; }); });
  ws.on('error', () => { void host.close(); });
  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });
});
const heartbeat = setInterval(() => { for (const ws of wss.clients) { if (!ws.isAlive) ws.terminate(); else { ws.isAlive = false; ws.ping(); } } }, 15000);
server.on('close', () => clearInterval(heartbeat));
const shutdown = async () => {
  clearInterval(heartbeat);
  await Promise.all([...hosts].map(host => host.close()));
  for (const ws of wss.clients) ws.terminate();
  server.close(() => process.exit(0));
};
process.on('SIGTERM', shutdown); process.on('SIGINT', shutdown);
server.listen(Number(process.env.PORT || 4319), process.env.HOST || '127.0.0.1', () => console.log(`PonyNotes agent runtime listening on ${server.address().port}`));
