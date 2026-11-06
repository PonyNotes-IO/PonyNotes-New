import { AgentHost } from './host.mjs';
const dataRoot = process.argv[2];
if (!dataRoot) throw Error('Missing application data directory');
const host = new AgentHost({ dataRoot, send: record => process.stdout.write(`${JSON.stringify(record)}\n`) });
let buffer = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => {
  buffer += chunk;
  if (buffer.length > 32 * 1024 * 1024) { void host.close().finally(() => process.exit(1)); return; }
  let end;
  while ((end = buffer.indexOf('\n')) >= 0) {
    const line = buffer.slice(0, end); buffer = buffer.slice(end + 1);
    if (!line.trim()) continue;
    try { void host.receive(JSON.parse(line)); }
    catch { process.stderr.write('Invalid JSONL record\n'); }
  }
});
process.stdin.on('end', async () => { await host.close(); process.exit(0); });
process.on('SIGTERM', async () => { await host.close(); process.exit(0); });
process.on('SIGINT', async () => { await host.close(); process.exit(0); });
