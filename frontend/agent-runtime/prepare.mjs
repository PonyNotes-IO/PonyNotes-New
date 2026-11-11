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
// 官方 tarball 把 node 放 bin/、LICENSE 放包根目录；nvm 等同理，所以不能只看 execPath 同级。
let nodeLicense;
const execDir = path.dirname(process.execPath);
for (const candidate of [path.join(execDir, 'LICENSE'), path.join(execDir, '..', 'LICENSE')]) {
  try { nodeLicense = await readFile(candidate, 'utf8'); break; } catch {}
}
if (!nodeLicense) {
  // nodejs.org/dist 没有 LICENSE 文件，该地址会 404，仅作最后的兜底尝试。
  const response = await fetch(`https://nodejs.org/dist/v${process.versions.node}/LICENSE`, { signal: AbortSignal.timeout(15000) })
    .catch(() => undefined);
  if (!response?.ok) {
    throw Error(`Unable to locate the Node.js distribution license next to ${process.execPath}; checked LICENSE and ../LICENSE`);
  }
  nodeLicense = await response.text();
}
await writeFile(path.join(destination, 'NODE-LICENSE.txt'), nodeLicense);
await copyFile(path.join(root, 'PI-LICENSE.txt'), path.join(destination, 'PI-LICENSE.txt'));
console.log(`Agent runtime ready: ${destination}`);
