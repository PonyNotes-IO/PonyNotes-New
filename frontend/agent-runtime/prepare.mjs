import { cp, copyFile, mkdir, readFile, writeFile, access } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
const root = path.dirname(fileURLToPath(import.meta.url));
const [major, minor] = process.versions.node.split('.').map(Number);
if (major < 22 || (major === 22 && minor < 19)) throw Error('Agent build requires Node >=22.19');
const destination = process.argv[2] ? path.resolve(process.argv[2]) : path.join(root, 'bundle');
try { await access(path.join(root, 'node_modules', '@earendil-works/pi-coding-agent/dist/index.js')); }
catch { execFileSync(process.platform === 'win32' ? 'npm.cmd' : 'npm', ['ci', '--ignore-scripts', '--no-audit', '--no-fund'], { cwd: root, stdio: 'inherit', shell: process.platform === 'win32' }); }
await mkdir(destination, { recursive: true });
await cp(path.join(root, 'src'), path.join(destination, 'src'), { recursive: true });
await cp(path.join(root, 'node_modules'), path.join(destination, 'node_modules'), { recursive: true, dereference: true });
await copyFile(path.join(root, 'package.json'), path.join(destination, 'package.json'));
await copyFile(path.join(root, 'package-lock.json'), path.join(destination, 'package-lock.json'));
await copyFile(process.execPath, path.join(destination, process.platform === 'win32' ? 'node.exe' : 'node'));
let nodeLicense;
try { nodeLicense = await readFile(path.join(path.dirname(process.execPath), 'LICENSE'), 'utf8'); }
catch {
  const response = await fetch(`https://nodejs.org/dist/v${process.versions.node}/LICENSE`, { signal: AbortSignal.timeout(15000) });
  if (!response.ok) throw Error('Unable to retrieve the Node.js distribution license');
  nodeLicense = await response.text();
}
await writeFile(path.join(destination, 'NODE-LICENSE.txt'), nodeLicense);
await copyFile(path.join(root, 'PI-LICENSE.txt'), path.join(destination, 'PI-LICENSE.txt'));
console.log(`Agent runtime ready: ${destination}`);
