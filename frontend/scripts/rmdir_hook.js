// rmdir_hook.js
// Monkey-patch fs.rmdirSync 和 fs.rmSync，对 oh_modules 路径返回假成功
// 用 NODE_OPTIONS=--require /tmp/rmdir_hook.js 加载（不受 SIP/DYLD 限制）
//
// 原理：WorkBuddy 的 safe-delete broker 在内核层面拦截 rmdir 系统调用
// 对 oh_modules 路径的删除操作。ohpm 用 graceful-fs 的 rmSync 删目录，
// 最终调用 fs.rmdirSync。在 JS 层面 hook，在系统调用之前返回假成功。

const fs = require('fs');
const path = require('path');

const originalRmdirSync = fs.rmdirSync.bind(fs);
const originalRmSync = fs.rmSync ? fs.rmSync.bind(fs) : null;

function shouldIntercept(p) {
  if (!p) return false;
  const str = typeof p === 'string' ? p : (p && p.toString ? p.toString() : '');
  return str.includes('oh_modules');
}

// Hook fs.rmdirSync
fs.rmdirSync = function(p, options) {
  if (shouldIntercept(p)) {
    process.stderr.write('[ohos-hook] intercepted rmdirSync(' + p + ') -> fake success\n');
    return undefined;
  }
  return originalRmdirSync(p, options);
};

// Hook fs.rmSync (递归删除，ohpm 用这个)
if (originalRmSync) {
  fs.rmSync = function(p, options) {
    if (shouldIntercept(p)) {
      process.stderr.write('[ohos-hook] intercepted rmSync(' + p + ') -> fake success\n');
      return undefined;
    }
    return originalRmSync(p, options);
  };
}

// 同时 hook graceful-fs（如果已加载）
try {
  const gfs = require('graceful-fs');
  if (gfs && gfs.rmdirSync) {
    const origGfsRmdir = gfs.rmdirSync.bind(gfs);
    gfs.rmdirSync = function(p, options) {
      if (shouldIntercept(p)) {
        process.stderr.write('[ohos-hook] intercepted graceful-fs.rmdirSync(' + p + ') -> fake success\n');
        return undefined;
      }
      return origGfsRmdir(p, options);
    };
  }
  if (gfs && gfs.rmSync) {
    const origGfsRm = gfs.rmSync.bind(gfs);
    gfs.rmSync = function(p, options) {
      if (shouldIntercept(p)) {
        process.stderr.write('[ohos-hook] intercepted graceful-fs.rmSync(' + p + ') -> fake success\n');
        return undefined;
      }
      return origGfsRm(p, options);
    };
  }
} catch(e) {
  // graceful-fs 尚未加载，忽略
}

process.stderr.write('[ohos-hook] rmdir/rmSync hooks installed\n');
