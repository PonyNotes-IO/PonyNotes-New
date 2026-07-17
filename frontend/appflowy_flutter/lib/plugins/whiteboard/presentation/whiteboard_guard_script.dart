/// 远程白板持久化守护脚本（注入到 xm-arts 白板页面）
///
/// 背景（2026-07-14 白板内容丢失根因分析）：
/// 远程白板页面自身的保存链路是 onChange → syncElements → 20 秒节流 POST /api/scenes。
/// 该链路在部分客户端 WebView 环境中会静默失效（页面存活但零广播、零保存），
/// 且页面在"画布为空 + 房间已连接"状态下 20 秒后会把空场景回写，覆盖服务器已有内容。
///
/// 本脚本在客户端 WebView 内提供三层防护，使客户端编辑达到与浏览器一致的持久化效果：
/// 1. 兜底保存：每 3 秒检测场景版本变化，直接调用页面内部 Collab.saveCollabRoomToFirebase
///    强制保存（不依赖页面自身的 onChange 管线）；pagehide/visibilitychange 时同样触发；
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

  // ---- 第 1 层：版本变化检测 + 兜底保存 ----
  var lastSavedVersion = -1;
  var saving = false;

  function sceneVersion(els) {
    var s = 0;
    for (var i = 0; i < els.length; i++) s += els[i].version || 0;
    return s;
  }

  function forceSave(reason) {
    if (saving) return Promise.resolve(false);
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
    saving = true;
    return Promise.resolve(c.saveCollabRoomToFirebase(els)).then(function () {
      lastSavedVersion = v;
      log('兜底保存成功 version=' + v + ' 元素数=' + els.length + ' 原因=' + reason);
      try { if (c.triggerFileUpload) c.triggerFileUpload(); } catch (e) {}
      return true;
    }).catch(function (e) {
      console.warn('[XMGuard] 兜底保存失败: ' + (e && e.message));
      return false;
    }).finally(function () {
      saving = false;
    });
  }

  // ---- 第 3 层：暴露给 Flutter 侧的退出保存入口 ----
  window.__xmForceSave = forceSave;

  setInterval(function () { forceSave('interval'); }, 3000);
  window.addEventListener('pagehide', function () { forceSave('pagehide'); });
  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'hidden') forceSave('visibilitychange');
  });

  log('守护脚本已安装 room=' + roomId);
})();
''';
