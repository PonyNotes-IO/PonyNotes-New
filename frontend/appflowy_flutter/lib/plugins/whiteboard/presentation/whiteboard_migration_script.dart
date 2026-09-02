/// 白板跨空间「内容迁移」注入脚本（仅注入到迁移用的隐藏 xm-arts webview）。
///
/// 背景：协作白板内容在 xm-arts / 若依 上是「加密」存储的（excalidraw collab
/// AES-GCM，密钥为 roomKey）。客户端无法可靠复现该加解密，因此跨空间迁移一律
/// 委托 xm-arts 页面自身的 collab 能力完成加解密：
/// - 私有→协作（PUSH）：把本地明文元素灌入画布，调用页面内部
///   `saveCollabRoomToFirebase` 让页面自己加密并 POST /api/scenes 上传。
/// - 协作→私有（PULL）：让页面自己 GET+解密+渲染，读出画布上的明文元素回传。
///
/// 该脚本**只在隐藏迁移 webview 里注入**，不注入到正常的 A 套协作页
/// （`RemoteWhiteboardPage`），因此对在线协作零影响。脚本本身不含任何定时器/
/// 自动保存，一切动作都由 Flutter 侧显式调用（`window.__xmMig.*`），行为确定。
///
/// 安全说明：
/// - PULL 只读画布明文，不写 room；
/// - PUSH 只在 Flutter 明确调用 loadAndSave 时才会写 room；
/// - 通过 fetch 钩子记录最近一次 GET/POST /api/scenes 的状态与服务器场景版本，
///   供 Flutter 侧判定「服务器确有内容却读到空」这类异常并中止迁移，杜绝丢数据。
/// 迁移页允许识别的场景写入路径。
///
/// 线上 xm-arts 同时存在旧版 `/api/scenes`、带 roomId 的变体以及
/// `/api/scenes/v2/post/`。PULL 页必须拦住这些写入，但不能误伤 files 上传。
const String whiteboardMigrationScenePostPattern =
    r'\/api\/scenes(?:\/v2(?:\/post)?|\/[A-Za-z0-9_-]+)?\/?($|[?#])';

const String whiteboardMigrationScript = r'''
(function () {
  if (window.__xmMigInstalled) return;
  window.__xmMigInstalled = true;

  var state = {
    lastGetStatus: null,      // 最近一次 GET /api/scenes 的 HTTP 状态（null=未发生）
    lastGetSceneVersion: null,// 最近一次 GET 返回体里的 sceneVersion（服务器权威版本）
    lastPostStatus: null,     // 最近一次 POST /api/scenes 的 HTTP 状态
    lastPostOk: false,        // 最近一次 POST 是否 2xx
    lastPostSceneVersion: null,
    // 是否允许本页向 room 写入（POST /api/scenes）。
    //
    // 默认 false 是**数据安全红线**：协作→私有（PULL）方向本页只该读，
    // 但 excalidraw 自身带自动保存 —— 迁移页开着一块空画布，它会把
    // 空场景 POST 进 room，直接抹掉原内容。线上诊断已实证到这一点
    // （lastGetStatus=null 却 lastPostStatus=200，用户侧表现为「原有内容丢失」）。
    // 只有 PUSH 方向在调用 loadAndSave 时才临时放开。
    allowPost: false,
    blockedPostCount: 0,
    sceneProbeStarted: false,
    pullStableCount: 0,
    lastLocalSceneVersion: null,
    lastLocalLiveCount: null,
  };

  var origFetch = window.fetch.bind(window);
  window.fetch = function (input, init) {
    var url = typeof input === 'string' ? input : (input && input.url) || '';
    var method = ((init && init.method) || (input && input.method) || 'GET').toUpperCase();
    var isSceneGet = method === 'GET' && /\/api\/scenes(?:\/v2)?\/[A-Za-z0-9_-]+\/?($|[?#])/.test(url);
    var isScenePost = method === 'POST' && /''' +
    whiteboardMigrationScenePostPattern +
    r'''/.test(url);

    // 数据安全红线：未放行时，直接掐掉对 room 的写入，不让请求出去。
    // PULL 方向本页画布是空的，excalidraw 的自动保存一旦 POST 出去，
    // room 里的原内容就被空场景覆盖了（线上已实测到）。
    if (isScenePost && !state.allowPost) {
      state.blockedPostCount++;
      log('已拦截未授权的 room 写入（第 ' + state.blockedPostCount + ' 次）');
      return Promise.resolve(new Response('{"blocked":true}', {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }));
    }

    var p = origFetch(input, init);
    if (isSceneGet) {
      p = p.then(function (resp) {
        try {
          state.lastGetStatus = resp && resp.status;
          if (resp && resp.ok) {
            resp.clone().json().then(function (data) {
              var v = Number(data && data.sceneVersion);
              state.lastGetSceneVersion = isNaN(v) ? 0 : v;
            }).catch(function () { state.lastGetSceneVersion = 0; });
          } else {
            // 404 = 房间从未有内容，服务器版本视为 0。
            state.lastGetSceneVersion = 0;
          }
        } catch (e) {}
        return resp;
      }, function (err) { state.lastGetStatus = -1; throw err; });
    } else if (isScenePost) {
      p = p.then(function (resp) {
        try {
          state.lastPostStatus = resp && resp.status;
          state.lastPostOk = !!(resp && resp.ok);
          if (resp && resp.ok && init && typeof init.body === 'string') {
            var saved = JSON.parse(init.body);
            var v = Number(saved && saved.sceneVersion);
            state.lastPostSceneVersion = isNaN(v) ? 0 : v;
          }
        } catch (e) {}
        return resp;
      }, function (err) { state.lastPostStatus = -1; state.lastPostOk = false; throw err; });
    }
    return p;
  };

  // xm-arts 的不同版本有的使用 fetch，有的使用 XMLHttpRequest。仅钩住
  // fetch 会留下两个数据安全缺口：PULL 页面自动保存的空场景可能绕过拦截，
  // PUSH 页面真正成功后 Flutter 又收不到状态，最终出现“副本已创建但内容为空”。
  // XHR 这里复用同一份 allowPost 和状态字段，保持两种网络实现行为一致。
  try {
    var Xhr = window.XMLHttpRequest;
    if (Xhr && Xhr.prototype && !Xhr.prototype.__xmMigPatched) {
      var xhrOpen = Xhr.prototype.open;
      var xhrSend = Xhr.prototype.send;
      Xhr.prototype.open = function (method, url) {
        this.__xmMigMethod = String(method || 'GET').toUpperCase();
        this.__xmMigUrl = String(url || '');
        return xhrOpen.apply(this, arguments);
      };
      Xhr.prototype.send = function (body) {
        var xhr = this;
        var method = xhr.__xmMigMethod || 'GET';
        var url = xhr.__xmMigUrl || '';
        var isGet = method === 'GET' && /\/api\/scenes(?:\/v2)?\/[A-Za-z0-9_-]+\/?($|[?#])/.test(url);
        var isPost = method === 'POST' && /''' +
    whiteboardMigrationScenePostPattern +
    r'''/.test(url);
        if (isPost && !state.allowPost) {
          state.blockedPostCount++;
          log('已拦截未授权的 XHR room 写入（第 ' + state.blockedPostCount + ' 次）');
          // 不触发真实请求；异步触发完成回调，避免页面因请求永远 pending 而卡住。
          setTimeout(function () {
            try { if (typeof xhr.onload === 'function') xhr.onload(); } catch (e) {}
            try { if (typeof xhr.onloadend === 'function') xhr.onloadend(); } catch (e) {}
          }, 0);
          return;
        }
        if (isGet || isPost) {
          var onLoad = xhr.onload;
          xhr.onload = function () {
            try {
              if (isGet) {
                state.lastGetStatus = xhr.status;
                if (xhr.status >= 200 && xhr.status < 300) {
                  var data = JSON.parse(xhr.responseText || '{}');
                  var v = Number(data && data.sceneVersion);
                  state.lastGetSceneVersion = isNaN(v) ? 0 : v;
                } else {
                  state.lastGetSceneVersion = 0;
                }
              } else {
                state.lastPostStatus = xhr.status;
                state.lastPostOk = xhr.status >= 200 && xhr.status < 300;
              }
            } catch (e) {}
            if (typeof onLoad === 'function') return onLoad.apply(xhr, arguments);
          };
        }
        return xhrSend.apply(this, arguments);
      };
      Xhr.prototype.__xmMigPatched = true;
    }
  } catch (e) {
    log('XHR 迁移钩子安装失败: ' + (e && e.message));
  }

  function log(msg) { try { console.log('[XMMig] ' + msg); } catch (e) {} }

  // xm-arts 部分版本通过 XHR/socket 拉场景，fetch 钩子观察不到 GET。主动做一次
  // 同源只读探测，只记录服务端 sceneVersion，不参与解密或修改 room。
  function probeScenePath(path, onDone) {
    origFetch(path, { method: 'GET' }).then(function (resp) {
      state.lastGetStatus = resp && resp.status;
      if (!resp || !resp.ok) {
        state.lastGetSceneVersion = 0;
        onDone && onDone(false);
        return;
      }
      return resp.clone().json().then(function (data) {
        var v = Number(data && data.sceneVersion);
        state.lastGetSceneVersion = isNaN(v) ? 0 : v;
        onDone && onDone(true);
      }).catch(function () {
        state.lastGetSceneVersion = 0;
        onDone && onDone(true);
      });
    }).catch(function () {
      state.lastGetStatus = -1;
      onDone && onDone(false);
    });
  }

  function probeScene() {
    if (state.sceneProbeStarted) return;
    state.sceneProbeStarted = true;
    var match = location.hash.match(/^#room=([^,]+)/);
    if (!match || !match[1]) return;
    var room = encodeURIComponent(match[1]);
    // 协作页线上版本仍可能使用旧路径；v2 只作为兼容回退。
    probeScenePath('/api/scenes/' + room, function (ok) {
      if (!ok) probeScenePath('/api/scenes/v2/' + room);
    });
  }

  probeScene();

  // 通过 React fiber 定位页面内部的 Collab 实例（与 XMGuard 同法，独立实现避免耦合）。
  var collab = null;
  function findCollab() {
    if (collab && collab.portal && collab.excalidrawAPI) return collab;
    try {
      var el = document.querySelector('.excalidraw') || document.body;
      var fiber = null, node = el;
      while (node && !fiber) {
        var keys = Object.keys(node);
        for (var i = 0; i < keys.length; i++) {
          if (keys[i].indexOf('__reactFiber$') === 0 || keys[i].indexOf('__reactContainer$') === 0) {
            fiber = node[keys[i]]; break;
          }
        }
        node = node.parentElement;
      }
      if (!fiber) return null;
      var root = fiber;
      while (root.return) root = root.return;
      var stack = [root], steps = 0;
      while (stack.length && steps < 300000) {
        var f = stack.pop(); steps++;
        var sn = f && f.stateNode;
        if (sn && typeof sn.saveCollabRoomToFirebase === 'function' && sn.excalidrawAPI) {
          collab = sn; log('已定位 Collab 实例'); return collab;
        }
        if (f.child) stack.push(f.child);
        if (f.sibling) stack.push(f.sibling);
      }
    } catch (e) {}
    return null;
  }

  function sceneVersion(els) {
    var s = 0;
    for (var i = 0; i < els.length; i++) s += els[i].version || 0;
    return s;
  }

  function liveElements(all) {
    var live = [];
    for (var i = 0; i < all.length; i++) if (!all[i].isDeleted) live.push(all[i]);
    return live;
  }

  window.__xmMig = {
    // PULL 就绪：excalidrawAPI 可用且至少发生过一次 GET（200 有内容 / 404 空房）。
    pullReady: function () {
      var c = findCollab();
      if (!c || !c.excalidrawAPI) return false;
      try {
        var all = c.excalidrawAPI.getSceneElementsIncludingDeleted();
        var localVersion = sceneVersion(all);
        var liveCount = liveElements(all).length;
        var getDone = state.lastGetStatus === 404 ||
          (state.lastGetStatus >= 200 && state.lastGetStatus < 300);
        if (!getDone) return false;
        if (state.lastLocalSceneVersion === localVersion &&
            state.lastLocalLiveCount === liveCount) {
          state.pullStableCount++;
        } else {
          state.lastLocalSceneVersion = localVersion;
          state.lastLocalLiveCount = liveCount;
          state.pullStableCount = 1;
        }
        // GET 完成且画布连续两次保持稳定，才允许 Flutter 读取；不依赖 portal
        // 或 socket 字段，因为移动端页面可能只暴露 REST + excalidrawAPI。
        if (state.pullStableCount < 2) return false;
        if (liveCount > 0) return true;
        // 404/版本为 0 是合法空房；有服务端版本时允许全是删除墓碑的场景。
        if (state.lastGetStatus === 404 || state.lastGetSceneVersion === 0) return true;
        return localVersion >= state.lastGetSceneVersion;
      } catch (e) {}
      return false;
    },
    // 就绪判定失败时的诊断快照：区分「没找到 collab 实例」与「GET 从未发生」。
    //
    // 两者都表现为 pullReady/pushReady 恒 false、最终 30s 超时，但成因和修法
    // 完全不同：前者是页面结构变化导致 fiber 树里找不到 Collab（xm-arts 改版
    // 会打中这里），后者是 /api/scenes 的 GET 没被发出或没被拦到。
    // 超时时把这份快照打进日志，避免只能靠猜。
    diag: function () {
      var c = findCollab();
      var el = document.querySelector('.excalidraw');
      return {
        hasCollab: !!c,
        hasExcalidrawApi: !!(c && c.excalidrawAPI),
        hasPortal: !!(c && c.portal),
        socketConnected: !!(c && c.portal && c.portal.socket && c.portal.socket.connected),
        lastGetStatus: state.lastGetStatus,
        lastPostStatus: state.lastPostStatus,
        blockedPostCount: state.blockedPostCount,
        lastGetSceneVersion: state.lastGetSceneVersion,
        lastLocalSceneVersion: state.lastLocalSceneVersion,
        lastLocalLiveCount: state.lastLocalLiveCount,
        pullStableCount: state.pullStableCount,
        allowPost: state.allowPost,
        excalidrawElPresent: !!el,
        readyState: document.readyState,
        href: location.href,
      };
    },
    // PUSH 就绪：collab + 画布 + 协作 socket 均就绪（saveCollabRoomToFirebase 需要 socket）。
    pushReady: function () {
      var c = findCollab();
      if (!c || !c.excalidrawAPI || !c.portal) return false;
      var s = c.portal.socket;
      return !!(s && s.connected);
    },
    // 读取当前画布的「活元素」明文场景（PULL 用）。返回 null 表示尚不可读。
    getScene: function () {
      var c = findCollab();
      if (!c || !c.excalidrawAPI) return null;
      try {
        var all = c.excalidrawAPI.getSceneElementsIncludingDeleted();
        var live = liveElements(all);
        var files = {};
        try { files = (typeof c.excalidrawAPI.getFiles === 'function') ? (c.excalidrawAPI.getFiles() || {}) : {}; } catch (e) {}
        // 只保留被活元素引用的文件。
        var used = {}, usedFiles = {};
        for (var j = 0; j < live.length; j++) if (live[j].fileId) used[live[j].fileId] = true;
        for (var fid in files) if (Object.prototype.hasOwnProperty.call(files, fid) && used[fid]) usedFiles[fid] = files[fid];
        var st = {};
        try { st = (typeof c.excalidrawAPI.getAppState === 'function') ? c.excalidrawAPI.getAppState() : {}; } catch (e) {}
        return {
          sceneVersion: sceneVersion(all),
          liveCount: live.length,
          elements: live,
          files: usedFiles,
          appState: { viewBackgroundColor: st && st.viewBackgroundColor, gridSize: st && st.gridSize },
          serverStatus: state.lastGetStatus,
          serverSceneVersion: state.lastGetSceneVersion,
        };
      } catch (e) { return null; }
    },
    // PUSH：把本地明文元素灌入画布，并调用页面自身 collab 加密上传。
    // 入参 payloadJson = { elements:[...], files:{...} }。返回 {ok, error, sceneVersion, postStatus}。
    loadAndSave: async function (payloadJson) {
      // PUSH 是唯一被授权写 room 的路径：在这里放行，函数结束后立即收回，
      // 使「自动保存把空场景写进 room」在其余任何时刻都不可能发生。
      state.allowPost = true;
      try {
        return await this._loadAndSaveInner(payloadJson);
      } finally {
        state.allowPost = false;
      }
    },
    _loadAndSaveInner: async function (payloadJson) {
      var c = findCollab();
      if (!c || !c.excalidrawAPI || typeof c.saveCollabRoomToFirebase !== 'function') {
        return { ok: false, error: 'collab-not-ready' };
      }
      var payload;
      try { payload = JSON.parse(payloadJson); } catch (e) { return { ok: false, error: 'bad-payload' }; }
      var elements = (payload && payload.elements) || [];
      var files = (payload && payload.files) || {};
      if (!elements.length) {
        // 空场景无需上传（新房间保持空即可，切区不丢内容）。
        return { ok: true, empty: true };
      }
      try {
        // 先把文件注入（图片作为 dataURL/URL 随元素带过去，不搬物理文件）。
        try {
          var fileArr = [];
          for (var fid in files) {
            if (Object.prototype.hasOwnProperty.call(files, fid)) {
              var f = files[fid];
              if (f && !f.id) f.id = fid;
              fileArr.push(f);
            }
          }
          if (fileArr.length && typeof c.excalidrawAPI.addFiles === 'function') {
            c.excalidrawAPI.addFiles(fileArr);
          }
        } catch (e) { log('注入 files 失败(忽略): ' + (e && e.message)); }

        c.excalidrawAPI.updateScene({ elements: elements });
        // 给画布一帧应用时间。
        await new Promise(function (r) { setTimeout(r, 350); });

        var all = c.excalidrawAPI.getSceneElementsIncludingDeleted();
        var live = liveElements(all);
        if (!live.length) return { ok: false, error: 'scene-empty-after-load' };

        state.lastPostOk = false; state.lastPostStatus = null;
        await Promise.resolve(c.saveCollabRoomToFirebase(all));
        try { if (typeof c.triggerFileUpload === 'function') c.triggerFileUpload(); } catch (e) {}
        // 等待 POST /api/scenes 落定（saveCollabRoomToFirebase 内部发起）。
        var waited = 0;
        while (state.lastPostStatus === null && waited < 8000) {
          await new Promise(function (r) { setTimeout(r, 200); });
          waited += 200;
        }
        return {
          ok: !!state.lastPostOk,
          error: state.lastPostOk ? null : ('post-failed:' + state.lastPostStatus),
          sceneVersion: sceneVersion(all),
          postStatus: state.lastPostStatus,
        };
      } catch (e) {
        return { ok: false, error: 'save-exception:' + (e && e.message) };
      }
    },
  };

  log('迁移脚本已安装');
})();
''';
