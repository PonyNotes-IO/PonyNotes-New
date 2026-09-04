/// 远程白板持久化守护脚本（注入到 xm-arts 白板页面）
///
/// 背景（2026-07-14 白板内容丢失根因分析）：
/// 远程白板页面自身的保存链路是 onChange → syncElements → 20 秒节流 POST /api/scenes。
/// 该链路在部分客户端 WebView 环境中会静默失效（页面存活但零广播、零保存），
/// 且页面在"画布为空 + 房间已连接"状态下 20 秒后会把空场景回写，覆盖服务器已有内容。
///
/// 本脚本在客户端 WebView 内提供三层防护，使客户端编辑达到与浏览器一致的持久化效果：
/// 1. 改动防抖保存：短轮询检测场景版本变化，改动后 ~500ms 防抖直接调用页面内部
///    Collab.saveCollabRoomToFirebase 强制保存（不依赖页面自身的 onChange 管线），
///    把"最后一笔编辑未保存窗口"从 3 秒缩小到 <1 秒；另有每 5 秒兜底轮询防漏检；
///    pagehide/visibilitychange 时同样触发；
/// 2. 空场景防覆盖：拦截页面的 fetch，阻断 sceneVersion=0 的空场景 POST 覆盖服务器非空内容；
/// 3. 对外暴露 window.__xmForceSave(reason)，供 Flutter 侧在销毁 WebView 前触发退出保存。
///
/// 实现说明：
/// - Collab 实例通过 DOM 节点上的 React fiber（__reactFiber$*）遍历定位；
///   线上构建中 saveCollabRoomToFirebase / excalidrawAPI / portal 等实例属性名
///   由 class field 语法定义，压缩后保留原名（已在 index-DkfX8tLU.js 构建上验证）。
/// - 本脚本必须以 AT_DOCUMENT_START 注入，以保证 fetch 拦截先于页面首次场景加载。
/// - 已在浏览器中对线上页面实测：绘制 → 强制保存 → 服务器落盘 → 刷新恢复，全链路可用。
const String whiteboardGuardScript = r'''
(function () {
  if (window.__xmGuardInstalled) return;
  window.__xmGuardInstalled = true;

  var roomId = null;
  try {
    var m = (location.hash || '').match(/room=([A-Za-z0-9_-]+),/);
    roomId = m && m[1];
  } catch (e) {}

  // 服务器上已知的场景版本（null 表示尚未从服务器加载过）
  var lastServerVersion = null;
  var origFetch = window.fetch.bind(window);

  function log(msg) {
    try { console.log('[XMGuard] ' + msg); } catch (e) {}
  }

  // ---- 第 2 层：fetch 拦截，防止空场景覆盖服务器已有内容 ----
  window.fetch = function (input, init) {
    var url = typeof input === 'string' ? input : (input && input.url) || '';
    var method = ((init && init.method) || (input && input.method) || 'GET').toUpperCase();

    var isSceneGet = method === 'GET' && /\/api\/scenes\/[A-Za-z0-9_-]+$/.test(url);
    var isScenePost = method === 'POST' && /\/api\/scenes\/?($|\?)/.test(url);

    if (isScenePost && init && typeof init.body === 'string') {
      try {
        var body = JSON.parse(init.body);
        var postVersion = Number(body && body.sceneVersion) || 0;
        if ((!roomId || body.roomId === roomId) &&
            postVersion === 0 &&
            lastServerVersion !== null && lastServerVersion > 0) {
          console.warn('[XMGuard] 已拦截空场景保存（服务器版本=' + lastServerVersion +
              '），防止覆盖服务器已有内容');
          return Promise.resolve(new Response('{"blocked":true}', {
            status: 200,
            headers: { 'Content-Type': 'application/json' },
          }));
        }
      } catch (e) {}
    }

    var p = origFetch(input, init);

    if (isSceneGet) {
      p = p.then(function (resp) {
        try {
          if (resp && resp.ok) {
            resp.clone().json().then(function (data) {
              var v = Number(data && data.sceneVersion) || 0;
              if (lastServerVersion === null || v > lastServerVersion) {
                lastServerVersion = v;
              }
              log('已加载服务器场景 version=' + v);
              // 【本地镜像·单向下载】服务器场景加载成功后，等场景应用到画布再镜像一次。
              scheduleMirror('scene-get');
            }).catch(function () {});
          }
        } catch (e) {}
        return resp;
      });
    } else if (isScenePost) {
      p = p.then(function (resp) {
        try {
          if (resp && resp.ok && init && typeof init.body === 'string') {
            var saved = JSON.parse(init.body);
            var v = Number(saved && saved.sceneVersion) || 0;
            if (v > (lastServerVersion || 0)) lastServerVersion = v;
            // 【本地镜像·单向下载】保存成功即代表服务器已有该新版本，镜像一份到本地。
            scheduleMirror('scene-post');
          }
        } catch (e) {}
        return resp;
      });
    }
    return p;
  };

  // ---- 通过 React fiber 定位页面内部的 Collab 实例 ----
  var collab = null;
  function findCollab() {
    if (collab && collab.portal) return collab;
    try {
      var el = document.querySelector('.excalidraw') || document.body;
      var fiber = null;
      var node = el;
      while (node && !fiber) {
        var keys = Object.keys(node);
        for (var i = 0; i < keys.length; i++) {
          if (keys[i].indexOf('__reactFiber$') === 0 ||
              keys[i].indexOf('__reactContainer$') === 0) {
            fiber = node[keys[i]];
            break;
          }
        }
        node = node.parentElement;
      }
      if (!fiber) return null;
      var root = fiber;
      while (root.return) root = root.return;
      var stack = [root];
      var steps = 0;
      while (stack.length && steps < 300000) {
        var f = stack.pop();
        steps++;
        var sn = f && f.stateNode;
        if (sn && typeof sn.saveCollabRoomToFirebase === 'function' &&
            sn.portal && sn.excalidrawAPI) {
          collab = sn;
          log('已定位 Collab 实例（遍历 ' + steps + ' 个 fiber 节点）');
          return collab;
        }
        if (f.child) stack.push(f.child);
        if (f.sibling) stack.push(f.sibling);
      }
    } catch (e) {}
    return null;
  }

  // Export bridge entry point: the remote app keeps this API on its Collab
  // React instance instead of exposing it on window.
  window.__xmGetExcalidrawAPI = function () {
    var c = findCollab();
    return c && c.excalidrawAPI ? c.excalidrawAPI : null;
  };

  // ---- 第 1 层：改动防抖保存（改动后 ~500ms 防抖，缩小未保存窗口）----
  var lastSavedVersion = -1;   // 已成功落盘的版本
  var lastSeenVersion = -1;    // 上一次轮询看到的版本（用于检测改动）
  var savingPromise = null;    // 进行中的保存链（null 表示空闲），用于串行化，flush 时不漏最后一笔
  var debounceTimer = null;

  function sceneVersion(els) {
    var s = 0;
    for (var i = 0; i < els.length; i++) s += els[i].version || 0;
    return s;
  }

  // 真正执行一次保存（原有"不推空"守卫与非空正常保存流程逻辑零改动）
  function doSaveOnce(reason) {
    var c = findCollab();
    if (!c || !c.excalidrawAPI) return Promise.resolve(false);
    var els, liveCount, v;
    try {
      els = c.excalidrawAPI.getSceneElementsIncludingDeleted();
      liveCount = 0;
      for (var i = 0; i < els.length; i++) {
        if (!els[i].isDeleted) liveCount++;
      }
      v = sceneVersion(els);
    } catch (e) {
      return Promise.resolve(false);
    }
    // 版本没变化或画布从未有过内容：无需保存
    if (v === lastSavedVersion || v === 0) return Promise.resolve(true);
    // 【向网页机制看齐 · 空场景绝不强推】只要当前活元素为 0（含"全部删除只剩墓碑"
    // 这种 version>0 但实际为空的情况），一律不强制保存。切换视图时 excalidraw 组件
    // 卸载/远端广播清空会造成过渡性空场景，XMGuard 的强推(interval/visibilitychange/
    // dispose)若把它推到协作服务器就会覆盖真数据——这正是网页客户端(无 XMGuard 强推)
    // 不丢、而本客户端丢的根因。此处无条件拦截，不再依赖 lastServerVersion(它可能因
    // 仅走 websocket 同步而为 null，导致漏判)。合法的"全部删除"由页面自身保存管线处理。
    if (liveCount === 0) {
      console.warn('[XMGuard] 跳过强制保存：当前画布为空(活元素0)，不覆盖协作内容 原因=' + reason);
      return Promise.resolve(false);
    }
    return Promise.resolve(c.saveCollabRoomToFirebase(els)).then(function () {
      lastSavedVersion = v;
      log('兜底保存成功 version=' + v + ' 元素数=' + els.length + ' 原因=' + reason);
      try { if (c.triggerFileUpload) c.triggerFileUpload(); } catch (e) {}
      return true;
    }).catch(function (e) {
      console.warn('[XMGuard] 兜底保存失败: ' + (e && e.message));
      return false;
    });
  }

  // 串行化保存：若已有保存在进行，链在其后再存一次，保证捕获最新版本
  // （切走白板 flush 时即便有防抖保存正在进行，也不会漏掉最后一笔改动）
  function forceSave(reason) {
    if (savingPromise) {
      savingPromise = savingPromise.then(function () { return doSaveOnce(reason); });
    } else {
      savingPromise = doSaveOnce(reason);
    }
    var p = savingPromise;
    var clear = function () { if (savingPromise === p) savingPromise = null; };
    p.then(clear, clear);
    return p;
  }

  // 改动检测 → 500ms 防抖保存：连续绘制不断重置计时，停手 ~500ms 后保存一次
  function scheduleDebouncedSave() {
    if (debounceTimer) clearTimeout(debounceTimer);
    debounceTimer = setTimeout(function () {
      debounceTimer = null;
      forceSave('debounce');
    }, 500);
  }

  function currentVersion() {
    var c = findCollab();
    if (!c || !c.excalidrawAPI) return -1;
    try {
      return sceneVersion(c.excalidrawAPI.getSceneElementsIncludingDeleted());
    } catch (e) {
      return -1;
    }
  }

  // ---- 本地镜像：严格单向「服务器 → 本地」下载 ----
  // 只读取当前画布的已解密场景，通过 callHandler('saveWhiteboardMirror', ...) 回传 Flutter
  // 存本地镜像文件。绝不回推 room：这里没有、也不会有任何写服务器的分支。
  // 去重：按 sceneVersion；节流：两次镜像至少间隔 minMirrorIntervalMs，避免大场景频繁大回传卡顿。
  var lastMirroredVersion = -1;
  var lastMirrorTime = 0;
  var mirrorTimer = null;
  var minMirrorIntervalMs = 2000;

  function doReportMirror(reason) {
    var c = findCollab();
    if (!c || !c.excalidrawAPI) return;
    var els, liveEls, v, files, appState;
    try {
      var all = c.excalidrawAPI.getSceneElementsIncludingDeleted();
      v = sceneVersion(all);
      // 只镜像「活元素」快照（排除墓碑），减小体积、便于离线只读渲染。
      liveEls = [];
      for (var i = 0; i < all.length; i++) {
        if (!all[i].isDeleted) liveEls.push(all[i]);
      }
    } catch (e) {
      return;
    }
    // 【红线·空场景绝不镜像】活元素为 0 一律跳过，杜绝空场景把本地有效镜像抹掉。
    if (!liveEls.length) return;
    // 版本无变化：无需重复镜像。
    if (v === lastMirroredVersion) return;

    try {
      files = (typeof c.excalidrawAPI.getFiles === 'function')
        ? (c.excalidrawAPI.getFiles() || {}) : {};
    } catch (e) { files = {}; }
    try {
      var st = (typeof c.excalidrawAPI.getAppState === 'function')
        ? c.excalidrawAPI.getAppState() : {};
      appState = {
        viewBackgroundColor: st && st.viewBackgroundColor,
        gridSize: st && st.gridSize
      };
    } catch (e) { appState = {}; }

    // 仅保留被当前活元素引用到的文件，避免把整块无关 base64 一起回传。
    var usedFiles = {};
    try {
      var used = {};
      for (var j = 0; j < liveEls.length; j++) {
        if (liveEls[j].fileId) used[liveEls[j].fileId] = true;
      }
      for (var fid in files) {
        if (Object.prototype.hasOwnProperty.call(files, fid) && used[fid]) {
          usedFiles[fid] = files[fid];
        }
      }
    } catch (e) { usedFiles = files; }

    var payload;
    try {
      payload = JSON.stringify({
        sceneVersion: v,
        elements: liveEls,
        files: usedFiles,
        appState: appState
      });
    } catch (e) { return; }

    try {
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('saveWhiteboardMirror', payload);
        lastMirroredVersion = v;
        lastMirrorTime = Date.now();
        log('已回传本地镜像 version=' + v + ' 活元素=' + liveEls.length +
            ' files=' + Object.keys(usedFiles).length + ' 原因=' + reason);
      }
    } catch (e) {
      // 纯旁路：镜像失败绝不影响在线协作。
    }
  }

  // 节流调度：GET 场景加载后需给画布应用留时间，故用短延时；两次镜像间隔不小于阈值。
  function scheduleMirror(reason) {
    if (mirrorTimer) return;
    var elapsed = Date.now() - lastMirrorTime;
    var wait = elapsed >= minMirrorIntervalMs ? 600 : (minMirrorIntervalMs - elapsed);
    mirrorTimer = setTimeout(function () {
      mirrorTimer = null;
      try { doReportMirror(reason); } catch (e) {}
    }, wait);
  }

  // ---- 第 3 层：暴露给 Flutter 侧的退出保存入口（返回 Promise，保存真正完成后 resolve）----
  window.__xmForceSave = forceSave;

  // Android 原生选图直插后，等待场景保存并显式启动文件上传。调用入口只由
  // RemoteWhiteboardPage 的 Android 专用桥设置，其他平台不进入此路径。
  window.__xmCommitImageInsert = function () {
    return forceSave('android-image-insert').then(function (saved) {
      var c = findCollab();
      if (!c || typeof c.triggerFileUpload !== 'function') return saved;
      try {
        return Promise.resolve(c.triggerFileUpload()).then(function () {
          return saved;
        }).catch(function (e) {
          console.warn('[XMGuard] Android 插图文件上传失败: ' +
              (e && e.message));
          return saved;
        });
      } catch (e) {
        console.warn('[XMGuard] Android 插图文件上传触发失败: ' +
            (e && e.message));
        return saved;
      }
    });
  };

  // ---- 协作白板图片导出桥接 ----
  // xm-arts 并不稳定地把 excalidrawAPI 暴露到 window。复用上面的 React fiber
  // 定位逻辑取得真实 API，再打开其原生图片导出面板并触发对应格式按钮。文件下载
  // 仍由页面自身创建 Blob/Data URL，Flutter 侧既有下载处理器负责保存到设备。
  window.__xmExportImage = async function (format) {
    var buttonIndex = format === 'png' ? 0 : format === 'svg' ? 1 : -1;
    if (buttonIndex < 0) return { ok: false, reason: 'unsupported-format' };

    // Mobile Flutter injects flutter_bridge.js, whose export function returns
    // the bytes to the native save handler without opening a browser picker.
    if (typeof window.exportExcalidraw === 'function') {
      try {
        await window.exportExcalidraw(format);
        return { ok: true, direct: true };
      } catch (e) {
        log('直接导出失败，回退原生导出面板: ' + (e && e.message));
      }
    }

    var deadline = Date.now() + 5000;
    var c = null;
    while (Date.now() < deadline) {
      c = findCollab();
      if (c && c.excalidrawAPI &&
          typeof c.excalidrawAPI.updateScene === 'function') {
        break;
      }
      await new Promise(function (resolve) { setTimeout(resolve, 50); });
    }
    if (!c || !c.excalidrawAPI) {
      return { ok: false, reason: 'excalidraw-api-unavailable' };
    }

    try {
      c.excalidrawAPI.updateScene({
        appState: { openDialog: { name: 'imageExport' } },
      });
    } catch (e) {
      return { ok: false, reason: 'open-export-dialog-failed', error: String(e) };
    }

    while (Date.now() < deadline) {
      var buttons = document.querySelectorAll(
        '.ImageExportModal__settings__buttons__button',
      );
      if (buttons.length > buttonIndex) {
        buttons[buttonIndex].click();
        log('已触发 ' + format + ' 图片导出');
        return { ok: true };
      }
      await new Promise(function (resolve) { setTimeout(resolve, 50); });
    }
    return { ok: false, reason: 'export-dialog-unavailable' };
  };

  // 短轮询检测场景版本变化（发现改动即启动/重置 500ms 防抖）
  setInterval(function () {
    var v = currentVersion();
    if (v < 0) return;
    if (lastSeenVersion === -1) { lastSeenVersion = v; return; }
    if (v !== lastSeenVersion) {
      lastSeenVersion = v;
      scheduleDebouncedSave();
    }
  }, 300);

  // 兜底轮询：防止漏检，每 5 秒强制冲刷一次（主保存仍靠防抖）
  setInterval(function () { forceSave('interval-fallback'); }, 5000);

  window.addEventListener('pagehide', function () { forceSave('pagehide'); });
  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'hidden') forceSave('visibilitychange');
  });

  log('守护脚本已安装 room=' + roomId);
})();
''';
