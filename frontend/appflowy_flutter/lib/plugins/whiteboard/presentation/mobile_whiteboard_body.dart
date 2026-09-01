import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_room_service.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_data_service.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/clipboard_service.dart';
import 'whiteboard_clipboard_bridge.dart';

const String _mobileWhiteboardReadinessScript = r'''
(function () {
  if (window.__xmMobileReadinessInstalled) return;
  window.__xmMobileReadinessInstalled = true;

  var collab = null;
  function findCollab() {
    if (collab && collab.portal && collab.excalidrawAPI) return collab;
    try {
      var node = document.querySelector('.excalidraw') || document.body;
      var fiber = null;
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
        var current = stack.pop();
        steps++;
        var stateNode = current && current.stateNode;
        if (stateNode && stateNode.portal && stateNode.excalidrawAPI &&
            typeof stateNode.excalidrawAPI.getAppState === 'function') {
          collab = stateNode;
          return collab;
        }
        if (current.child) stack.push(current.child);
        if (current.sibling) stack.push(current.sibling);
      }
    } catch (_) {}
    return null;
  }

  window.__xmIsMobileWhiteboardReady = function () {
    var instance = findCollab();
    if (!instance || !instance.portal ||
        instance.portal.socketInitialized !== true) {
      return false;
    }
    try {
      var state = instance.excalidrawAPI.getAppState();
      return !!state && state.isLoading === false &&
        Number(state.width) > 0 && Number(state.height) > 0;
    } catch (_) {
      return false;
    }
  };
})();
''';

class MobileWhiteboardBody extends StatefulWidget {
  const MobileWhiteboardBody({
    super.key,
    required this.view,
  });

  final ViewPB view;

  @override
  State<MobileWhiteboardBody> createState() => _MobileWhiteboardBodyState();
}

class _MobileWhiteboardBodyState extends State<MobileWhiteboardBody>
    with WidgetsBindingObserver {
  InAppWebViewController? _controller;
  bool _isLoading = true;
  bool _isDisposed = false;
  String? _loadingError;
  String? _userNickname;
  String? _roomId;
  String? _roomKey;
  bool _isFetchingRoom = false;
  String? _lastHostTheme;
  Timer? _brightnessPollTimer;
  int _themeSyncGeneration = 0;
  int _pageLoadGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 与协作空间 RemoteWhiteboardPage 保持一致：iOS PlatformView 偶尔不会
    // 转发系统外观事件，轮询作为兜底，确保白板停留时也能实时切换。
    _brightnessPollTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _syncSystemBrightness(_currentSystemBrightness()),
    );
    _loadUserNickname();
    _tryFetchRoomInfo();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _brightnessPollTimer?.cancel();
    _brightnessPollTimer = null;
    _themeSyncGeneration++;
    _pageLoadGeneration++;
    _isDisposed = true;
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    _syncSystemBrightness(_currentSystemBrightness());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery 变化通常先于 PlatformView 的原生亮度回调到达，直接从
    // 当前页面依赖读取可以让白板在停留状态下立即切换主题。
    _syncSystemBrightness(_currentSystemBrightness(), rebuild: false);
  }

  Brightness _currentSystemBrightness() {
    // Theme.of(context) 表示应用当前实际生效的亮度，能够捕获应用内主题
    // 模式切换；MediaQuery/平台分发器只作为无主题上下文时的兜底。
    return Theme.of(context).brightness;
  }

  void _syncSystemBrightness(Brightness brightness, {bool rebuild = true}) {
    if (_isDisposed) return;

    final theme = brightness == Brightness.dark ? 'dark' : 'light';
    if (_lastHostTheme == theme) return;

    _lastHostTheme = theme;
    Log.info('[MobileWhiteboard] 系统外观变化: $theme');
    if (rebuild && mounted) setState(() {});
    _scheduleThemeSync(theme);
  }

  void _scheduleThemeSync(String theme) {
    final generation = ++_themeSyncGeneration;

    void sync() {
      if (!_isDisposed && generation == _themeSyncGeneration) {
        unawaited(_applyTheme(theme));
      }
    }

    sync();
    WidgetsBinding.instance.addPostFrameCallback((_) => sync());
    Future<void>.delayed(const Duration(milliseconds: 180), sync);
    Future<void>.delayed(const Duration(milliseconds: 600), sync);
  }

  Future<void> _applyTheme(String theme) async {
    final controller = _controller;
    if (_isDisposed || controller == null) return;

    final normalizedTheme = theme == 'dark' ? 'dark' : 'light';
    try {
      await controller.evaluateJavascript(source: '''
        (function() {
          var requestedTheme = '$normalizedTheme';
          var uiBackgroundColor = requestedTheme === 'dark' ? '#121212' : '#ffffff';
          var hostStyle = document.getElementById('ponynotes-host-theme-style');
          if (!hostStyle) {
            hostStyle = document.createElement('style');
            hostStyle.id = 'ponynotes-host-theme-style';
            (document.head || document.documentElement).appendChild(hostStyle);
          }
          hostStyle.textContent = 'html.dark #root .excalidraw canvas.excalidraw__canvas,' +
            'html.dark #root .excalidraw canvas.static,' +
            'html.dark #root .excalidraw canvas.interactive {' +
            '-webkit-filter: invert(93%) hue-rotate(180deg) !important;' +
            'filter: invert(93%) hue-rotate(180deg) !important;' +
            '} html.dark #root .excalidraw { background-color: #121212 !important; }' +
            ' html:not(.dark) #root .excalidraw canvas.excalidraw__canvas,' +
            'html:not(.dark) #root .excalidraw canvas.static,' +
            'html:not(.dark) #root .excalidraw canvas.interactive {' +
            '-webkit-filter: none !important; filter: none !important; }';
          // 同步本地 flutter_bridge.js 的内部强制主题，避免其看门狗把
          // URL 初始主题重新写回，导致切换后很快恢复旧颜色。
          if (typeof window.setHostTheme === 'function') {
            try { window.setHostTheme(requestedTheme); } catch (_) {}
          }
          // 先调用页面已有桥接，再执行下面的 DOM/API 兜底；这样旧页面和
          // 新页面都能在不重建 PlatformView 的情况下即时变更画布。
          if (typeof window.__ponynotesApplyTheme === 'function') {
            try { window.__ponynotesApplyTheme(requestedTheme); } catch (_) {}
          }
          window.__ponynotesHostTheme = requestedTheme;
          try { window.localStorage.setItem('excalidraw-theme', requestedTheme); } catch (_) {}
          var setter = window.__ponynotesSetHostTheme;
          if (typeof setter === 'function') {
            try { setter(requestedTheme); } catch (_) {}
          }
          document.documentElement.classList.toggle('dark', requestedTheme === 'dark');
          if (document.body) document.body.style.backgroundColor = uiBackgroundColor;
          document.querySelectorAll('.excalidraw').forEach(function(root) {
            root.classList.toggle('theme--dark', requestedTheme === 'dark');
            root.style.backgroundColor = uiBackgroundColor;
          });
          document.querySelectorAll('.excalidraw__canvas, canvas.static, canvas.interactive').forEach(function(canvas) {
            canvas.style.backgroundColor = '';
          });
          var api = window.excalidrawAPI || window._excalidrawAPI || window.__EXCALIDRAW_API__;
          if (api && typeof api.updateScene === 'function') {
            var state = typeof api.getAppState === 'function' ? api.getAppState() : null;
            var legacyDarkBackground = !!state && typeof state.viewBackgroundColor === 'string' && state.viewBackgroundColor.toLowerCase() === '#121212';
            if (!state || state.theme !== requestedTheme || legacyDarkBackground) {
              var appState = { theme: requestedTheme };
              if (legacyDarkBackground) appState.viewBackgroundColor = '#ffffff';
              api.updateScene({ appState: appState, commitToHistory: false });
            }
          }
          if (!window.__ponynotesRuntimeThemeWatchdog) {
            window.__ponynotesRuntimeThemeWatchdog = window.setInterval(function() {
              var currentTheme = window.__ponynotesHostTheme;
              if (currentTheme !== 'dark' && currentTheme !== 'light') return;
              var currentUiBackground = currentTheme === 'dark' ? '#121212' : '#ffffff';
              var currentSetter = window.__ponynotesSetHostTheme;
              if (typeof currentSetter === 'function') {
                try { currentSetter(currentTheme); } catch (_) {}
              }
              var currentApi = window.excalidrawAPI || window._excalidrawAPI || window.__EXCALIDRAW_API__;
              if (currentApi && typeof currentApi.getAppState === 'function' && typeof currentApi.updateScene === 'function') {
                var currentState = currentApi.getAppState();
                var legacyDarkBackground = !!currentState && typeof currentState.viewBackgroundColor === 'string' && currentState.viewBackgroundColor.toLowerCase() === '#121212';
                if (!currentState || currentState.theme !== currentTheme || legacyDarkBackground) {
                  var currentAppState = { theme: currentTheme };
                  if (legacyDarkBackground) currentAppState.viewBackgroundColor = '#ffffff';
                  currentApi.updateScene({ appState: currentAppState, commitToHistory: false });
                }
              }
              document.documentElement.classList.toggle('dark', currentTheme === 'dark');
              document.querySelectorAll('.excalidraw').forEach(function(root) {
                root.classList.toggle('theme--dark', currentTheme === 'dark');
                root.style.backgroundColor = currentUiBackground;
              });
              document.querySelectorAll('.excalidraw__canvas, canvas.static, canvas.interactive').forEach(function(canvas) {
                canvas.style.backgroundColor = '';
              });
            }, 500);
          }
          console.info('[PonyNotes] Dart host theme applied:', requestedTheme, 'apiReady=', !!api);
        })();
      ''');
      Log.info('[MobileWhiteboard] WebView 主题同步脚本已发送: $normalizedTheme');
    } catch (e) {
      Log.warn('[MobileWhiteboard] WebView 主题同步失败（页面可能尚未就绪）: $e');
    }
  }

  String _currentHostTheme() {
    return _currentSystemBrightness() == Brightness.dark ? 'dark' : 'light';
  }

  Future<void> _loadUserNickname() async {
    Log.info('[MobileWhiteboard] 🔍 Starting to load user nickname...');
    final userProfileResult = await UserBackendService.getCurrentUserProfile();
    String nickname = userProfileResult.fold(
      (profile) {
        Log.info(
            '[MobileWhiteboard] ✅ Got user profile: id=${profile.id}, name=${profile.name}, email=${profile.email}');
        return profile.name;
      },
      (error) {
        Log.error('[MobileWhiteboard] ❌ Failed to get user nickname: $error');
        return '';
      },
    );

    if (nickname.isEmpty) {
      nickname = '小马笔记用户';
      Log.info(
          '[MobileWhiteboard] 📌 Nickname is empty, using default: "$nickname"');
    }

    if (!mounted) return;
    setState(() {
      _userNickname = nickname;
    });
    Log.info(
        '[MobileWhiteboard] 📌 Final nickname: "$nickname", isEmpty: ${nickname.isEmpty}, length: ${nickname.length}');
  }

  Future<void> _tryFetchRoomInfo() async {
    Log.debug('🔍 [MobileWhiteboard] Initial view: id=${widget.view.id}');

    if (_isFetchingRoom) return;
    setState(() => _isFetchingRoom = true);

    try {
      final room = await WhiteboardRoomService.getRoom(widget.view.id);

      if (room != null) {
        Log.debug(
            '🟢 [MobileWhiteboard] Found room in local storage: roomId=${room.roomId}');
        // 本地 room 已足够构造远程白板 URL。不要在每次打开时再读取完整
        // collab 场景：该调用会先 openWhiteboard 再拉取整块 JSON，移动端会被
        // 网络和大白板数据拖住；白板页面会自行从 room 恢复场景。
        if (!mounted) return;
        setState(() {
          _roomId = room.roomId;
          _roomKey = room.roomKey;
        });
        Log.debug(
            '⚡ [MobileWhiteboard] Local room fast path, skip collab preload');
        return;
      }

      final whiteboardData =
          await WhiteboardDataService().loadWhiteboardData(widget.view.id);
      Log.debug(
          '🔍 [MobileWhiteboard] Loaded whiteboard data keys: ${whiteboardData.keys}');

      final serverRoomId = whiteboardData['roomId'];
      final serverRoomKey = whiteboardData['roomKey'];

      if (serverRoomId != null &&
          serverRoomId.toString().isNotEmpty &&
          serverRoomKey != null &&
          serverRoomKey.toString().isNotEmpty) {
        final roomIdStr =
            serverRoomId is String ? serverRoomId : serverRoomId.toString();
        final roomKeyStr =
            serverRoomKey is String ? serverRoomKey : serverRoomKey.toString();

        Log.debug(
            '🟢 [MobileWhiteboard] Found room in server data: roomId=$roomIdStr');

        if (roomIdStr != _roomId || roomKeyStr != _roomKey) {
          await WhiteboardRoomService.saveRoom(
              widget.view.id, roomIdStr, roomKeyStr);
          Log.debug(
              '✅ [MobileWhiteboard] Synced server room to local storage: roomId=$roomIdStr');
        }

        if (!mounted) return;
        setState(() {
          _roomId = roomIdStr;
          _roomKey = roomKeyStr;
        });
        return;
      }

      if (_roomId != null && _roomKey != null) {
        Log.debug(
            '🟢 [MobileWhiteboard] Using existing room from local storage: roomId=$_roomId');
        return;
      }

      Log.debug(
          '🟡 [MobileWhiteboard] No room found for view ${widget.view.id}, generating new one');
      final newRoomId = WhiteboardRoomService.generateRoomId();
      final newRoomKey = WhiteboardRoomService.generateRoomKey();

      Log.info(
          '🆕 [MobileWhiteboard] Generated NEW roomId=$newRoomId, roomKey=$newRoomKey for view ${widget.view.id}');

      await WhiteboardRoomService.saveRoom(
          widget.view.id, newRoomId, newRoomKey);
      Log.info(
          '✅ [MobileWhiteboard] Saved room to local storage: viewId=${widget.view.id}, roomId=$newRoomId');

      Log.info('📤 [MobileWhiteboard] Saving room info to server...');
      final saveResult = await WhiteboardDataService().saveWhiteboardData(
        widget.view.id,
        {
          'roomId': newRoomId,
          'roomKey': newRoomKey,
        },
        source: 'room-init',
      );

      if (saveResult) {
        Log.info(
            '✅ [MobileWhiteboard] SUCCESSFULLY saved room info to server: roomId=$newRoomId, roomKey=$newRoomKey');
      } else {
        Log.error('❌ [MobileWhiteboard] FAILED to save room info to server');
      }

      if (!mounted) return;
      setState(() {
        _roomId = newRoomId;
        _roomKey = newRoomKey;
      });
    } catch (e) {
      Log.error('❌ [MobileWhiteboard] Error fetching/generating room: $e');
    } finally {
      if (mounted) {
        setState(() => _isFetchingRoom = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isFetchingRoom ||
        _userNickname == null ||
        _roomId == null ||
        _roomKey == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    final hostTheme = _currentHostTheme();
    if (_lastHostTheme == null) _lastHostTheme = hostTheme;

    return Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(
            url: WebUri(_buildRemoteUrl()),
          ),
          initialSettings: InAppWebViewSettings(
            useShouldOverrideUrlLoading: true,
            useOnDownloadStart: true,
            mediaPlaybackRequiresUserGesture: false,
            javaScriptEnabled: true,
            javaScriptCanOpenWindowsAutomatically: true,
            supportZoom: true,
            allowFileAccessFromFileURLs: true,
            allowUniversalAccessFromFileURLs: true,
          ),
          initialUserScripts: UnmodifiableListView([
            UserScript(
              source: whiteboardClipboardBridgeScript,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
            // 必须在页面脚本之前安装，就绪检查会同时确认协作房间初始化、
            // initialData 应用和画布尺寸测量均已完成。
            UserScript(
              source: _mobileWhiteboardReadinessScript,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
            UserScript(
              source: '''
                (function() {
                  var params = new URLSearchParams(window.location.search || '');
                  var hostTheme = params.get('hostTheme') === 'dark' ? 'dark' : 'light';
                  window.__ponynotesHostTheme = hostTheme;
                  try { window.localStorage.setItem('excalidraw-theme', hostTheme); } catch (_) {}
                  document.documentElement.classList.toggle('dark', hostTheme === 'dark');

                  var style = document.createElement('style');
                  style.textContent = '.dropdown-menu-item-base:has(input[name="theme"]), [data-testid="toggle-dark-mode"] { display:none!important; pointer-events:none!important; }';
                  (document.head || document.documentElement).appendChild(style);

                  window.__ponynotesApplyTheme = function(theme) {
                    var normalizedTheme = theme === 'dark' ? 'dark' : 'light';
                    var uiBackgroundColor = normalizedTheme === 'dark' ? '#121212' : '#ffffff';
                    var hostStyle = document.getElementById('ponynotes-host-theme-style');
                    if (!hostStyle) {
                      hostStyle = document.createElement('style');
                      hostStyle.id = 'ponynotes-host-theme-style';
                      (document.head || document.documentElement).appendChild(hostStyle);
                    }
                    hostStyle.textContent = 'html.dark #root .excalidraw canvas.excalidraw__canvas,' +
                      'html.dark #root .excalidraw canvas.static,' +
                      'html.dark #root .excalidraw canvas.interactive {' +
                      '-webkit-filter: invert(93%) hue-rotate(180deg) !important;' +
                      'filter: invert(93%) hue-rotate(180deg) !important;' +
                      '} html.dark #root .excalidraw { background-color: #121212 !important; }' +
                      ' html:not(.dark) #root .excalidraw canvas.excalidraw__canvas,' +
                      'html:not(.dark) #root .excalidraw canvas.static,' +
                      'html:not(.dark) #root .excalidraw canvas.interactive {' +
                      '-webkit-filter: none !important; filter: none !important; }';
                    window.__ponynotesHostTheme = normalizedTheme;
                    try { window.localStorage.setItem('excalidraw-theme', normalizedTheme); } catch (_) {}
                    var setter = window.__ponynotesSetHostTheme;
                    if (typeof setter === 'function') {
                      try { setter(normalizedTheme); } catch (_) {}
                    }
                    document.documentElement.classList.toggle('dark', normalizedTheme === 'dark');
                    if (document.body) document.body.style.backgroundColor = uiBackgroundColor;
                    document.querySelectorAll('.excalidraw').forEach(function(root) {
                      root.classList.toggle('theme--dark', normalizedTheme === 'dark');
                      root.style.backgroundColor = uiBackgroundColor;
                    });
                    document.querySelectorAll('.excalidraw__canvas, canvas.static, canvas.interactive').forEach(function(canvas) {
                      canvas.style.backgroundColor = '';
                    });
                    var api = window.excalidrawAPI || window._excalidrawAPI || window.__EXCALIDRAW_API__;
                    if (api && typeof api.updateScene === 'function') {
                      var state = typeof api.getAppState === 'function' ? api.getAppState() : null;
                      var legacyDarkBackground = !!state && typeof state.viewBackgroundColor === 'string' && state.viewBackgroundColor.toLowerCase() === '#121212';
                      if (!state || state.theme !== normalizedTheme || legacyDarkBackground) {
                        var appState = { theme: normalizedTheme };
                        if (legacyDarkBackground) appState.viewBackgroundColor = '#ffffff';
                          api.updateScene({ appState: appState, commitToHistory: false });
                      }
                    }
                  };

                  document.addEventListener('change', function(event) {
                    if (event.target && event.target.name === 'theme') {
                      event.preventDefault();
                      event.stopImmediatePropagation();
                      window.__ponynotesApplyTheme(window.__ponynotesHostTheme);
                    }
                  }, true);
                  var systemThemeQuery = window.matchMedia('(prefers-color-scheme: dark)');
                  var syncThemeFromSystem = function() {
                    var systemTheme = systemThemeQuery.matches ? 'dark' : 'light';
                    if (window.__ponynotesHostTheme === systemTheme) return;
                    window.__ponynotesApplyTheme(systemTheme);
                  };
                  if (typeof systemThemeQuery.addEventListener === 'function') {
                    systemThemeQuery.addEventListener('change', syncThemeFromSystem);
                  } else if (typeof systemThemeQuery.addListener === 'function') {
                    systemThemeQuery.addListener(syncThemeFromSystem);
                  }
                  setInterval(function() {
                    window.__ponynotesApplyTheme(window.__ponynotesHostTheme);
                  }, 500);
                  window.__ponynotesApplyTheme(hostTheme);
                })();
              ''',
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
            UserScript(
              source: '''
                (function() {
                  var originalDownload = HTMLAnchorElement.prototype.download;
                  Object.defineProperty(HTMLAnchorElement.prototype, 'download', {
                    set: function(value) {
                      if (this.href && (this.href.startsWith('blob:') || this.href.startsWith('data:'))) {
                        window.flutter_inappwebview.callHandler('downloadBlobFile', this.href, value || 'download');
                      }
                      originalDownload = value;
                    },
                    get: function() {
                      return originalDownload;
                    }
                  });
                  
                  window.addEventListener('click', function(e) {
                    var target = e.target;
                    while (target) {
                      if (target.tagName === 'A' && target.download !== undefined) {
                        if (target.href && (target.href.startsWith('blob:') || target.href.startsWith('data:'))) {
                          e.preventDefault();
                          e.stopPropagation();
                          window.flutter_inappwebview.callHandler('downloadBlobFile', target.href, target.download || 'download');
                        }
                      }
                      target = target.parentElement;
                    }
                  }, true);
                })();
              ''',
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
          ]),
          onWebViewCreated: (controller) {
            _controller = controller;
            _setupDownloadHandler(controller);
            _setupClipboardHandler(controller);
          },
          onLoadStart: (controller, url) {
            _pageLoadGeneration++;
            setState(() {
              _isLoading = true;
              _loadingError = null;
            });
            Log.debug('🔄 [MobileWhiteboard] Loading: $url');
          },
          onLoadStop: (controller, url) async {
            final loadGeneration = _pageLoadGeneration;
            unawaited(_applyTheme(_currentHostTheme()));

            // WKWebView/Android WebView 的 onLoadStop 只代表 HTML 资源加载完成，
            // 不代表协作房间的异步初始场景已经应用。若此时允许选图，迟到的
            // initialData 会覆盖刚插入的图片，表现为首次导入无显示。
            final ready = await _waitForWhiteboardReady(
              controller,
              loadGeneration: loadGeneration,
            );
            if (!mounted ||
                _isDisposed ||
                loadGeneration != _pageLoadGeneration) {
              return;
            }
            setState(() {
              _isLoading = false;
              if (!ready) {
                _loadingError = LocaleKeys.error_loadingViewError.tr();
              }
            });
            if (ready) {
              Log.info('✅ [MobileWhiteboard] 协作场景初始化完成: $url');
            } else {
              Log.warn(
                '⚠️ [MobileWhiteboard] 等待协作场景就绪超时，已阻止未就绪状态下操作: $url',
              );
            }
          },
          onReceivedError: (controller, request, error) {
            // 子资源（图片、字体等）失败不代表白板主页面加载失败，也不能
            // 取消正在进行的协作场景就绪等待。
            if (request.isForMainFrame == false) {
              Log.warn(
                '[MobileWhiteboard] Subresource load error: ${request.url} - ${error.description}',
              );
              return;
            }
            _pageLoadGeneration++;
            setState(() {
              _isLoading = false;
              _loadingError = error.description;
            });
            Log.error(
                '❌ [MobileWhiteboard] Load error: ${error.type} - ${error.description}');
          },
          shouldOverrideUrlLoading: (controller, navigationAction) async {
            final url = navigationAction.request.url?.toString();
            final headers = navigationAction.request.headers;
            final filename = headers != null
                ? (headers['Content-Disposition']?.split('filename=').last ??
                    headers['content-disposition']?.split('filename=').last ??
                    'download')
                : 'download';

            if (url != null && url.startsWith('blob:')) {
              Log.info(
                  '[MobileWhiteboard] 🚫 Blocking blob navigation, starting download: $url, filename: $filename');
              unawaited(_downloadBlobUrl(
                  controller, url, filename.replaceAll('"', '')));
              return NavigationActionPolicy.CANCEL;
            }
            if (url != null && url.startsWith('data:')) {
              Log.info(
                  '[MobileWhiteboard] 🚫 Blocking data URL navigation, starting download: $url, filename: $filename');
              unawaited(_saveDataUrlToFile(url, filename.replaceAll('"', '')));
              return NavigationActionPolicy.CANCEL;
            }
            return NavigationActionPolicy.ALLOW;
          },
          onDownloadStartRequest: (controller, downloadStartRequest) async {
            Log.info(
                '[MobileWhiteboard] 📥 Download request: ${downloadStartRequest.url}');
            await _handleDownloadRequest(downloadStartRequest);
          },
        ),
        if (_isLoading)
          const Positioned.fill(
            child: AbsorbPointer(
              child: ColoredBox(
                color: Colors.transparent,
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
          ),
        if (_loadingError != null)
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      LocaleKeys.error_cannotLoadPage.tr(),
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        _loadingError!,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        _controller?.reload();
                      },
                      child: Text(LocaleKeys.button_retry.tr()),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<bool> _waitForWhiteboardReady(
    InAppWebViewController controller, {
    required int loadGeneration,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));

    while (!_isDisposed &&
        loadGeneration == _pageLoadGeneration &&
        DateTime.now().isBefore(deadline)) {
      try {
        final result = await controller.evaluateJavascript(source: r'''
          (function() {
            try {
              return typeof window.__xmIsMobileWhiteboardReady === 'function' &&
                window.__xmIsMobileWhiteboardReady();
            } catch (_) {
              return false;
            }
          })();
        ''');
        if (result == true || result == 1 || result?.toString() == 'true') {
          return true;
        }
      } catch (e) {
        Log.debug('[MobileWhiteboard] 白板就绪检查暂未可用: $e');
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    return false;
  }

  String _buildRemoteUrl() {
    Log.info('[MobileWhiteboard] 🔨 Building remote URL...');
    Log.info('[MobileWhiteboard] 🔨 _userNickname: "$_userNickname"');

    final encodedNickname = Uri.encodeComponent(_userNickname ?? '');
    Log.info('[MobileWhiteboard] 🔨 Encoded nickname: "$encodedNickname"');

    final hostTheme = _currentHostTheme();
    final url =
        'https://xm-arts.xiaomabiji.com/?ua=$encodedNickname&hostTheme=$hostTheme#room=$_roomId,$_roomKey';
    Log.info('[MobileWhiteboard] ✅ Built URL: $url');
    return url;
  }

  void _setupDownloadHandler(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: 'downloadBlobFile',
      callback: (args) async {
        if (args.isEmpty) return;
        try {
          final String blobUrl = args[0];
          final String filename = args.length > 1 ? args[1] : 'download';
          Log.info(
              '[MobileWhiteboard] 📥 downloadBlobFile handler: blobUrl=$blobUrl, filename=$filename');

          if (blobUrl.startsWith('data:')) {
            await _saveDataUrlToFile(blobUrl, filename);
          } else if (blobUrl.startsWith('blob:')) {
            await _downloadBlobUrl(controller, blobUrl, filename);
          }
        } catch (e) {
          Log.error('[MobileWhiteboard] ❌ downloadBlobFile handler error: $e');
        }
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'saveBase64File',
      callback: (args) async {
        if (args.length >= 2) {
          String base64Data = args[0];
          final String filename = args[1];
          String mimeType = args.length > 2 ? args[2] : '';

          if (base64Data.startsWith('data:')) {
            final parts = base64Data.split(',');
            if (parts.length >= 2) {
              mimeType = parts[0].split(':')[1].split(';')[0];
              base64Data = parts[1];
            }
          }

          await _saveBase64ToFile(base64Data, filename, mimeType);
        }
      },
    );
  }

  void _setupClipboardHandler(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: 'writeWhiteboardClipboard',
      callback: (args) async {
        if (_isDisposed || args.isEmpty || args.first is! Map) return;
        try {
          final payload = Map<String, dynamic>.from(args.first as Map);
          final imageBase64 = payload['imageBase64'] as String?;
          final imageFormat = whiteboardClipboardImageFormat(
              payload['imageMimeType'] as String?);
          final image = imageBase64 == null ||
                  imageBase64.isEmpty ||
                  imageFormat == null
              ? null
              : (imageFormat, Uint8List.fromList(base64Decode(imageBase64)));
          await ClipboardService().setData(ClipboardServiceData(
            plainText:
                payload['plainText'] as String? ?? payload['html'] as String?,
            html: payload['html'] as String?,
            image: image,
          ));
          Log.info('[MobileWhiteboard] 已写入系统剪贴板');
        } catch (e) {
          Log.error('[MobileWhiteboard] 写入系统剪贴板失败: $e');
        }
      },
    );
  }

  Future<void> _handleDownloadRequest(
      DownloadStartRequest downloadStartRequest) async {
    try {
      final url = downloadStartRequest.url.toString();
      Log.info('[MobileWhiteboard] 📥 Handling download request: $url');

      if (url.startsWith('data:')) {
        final filename = downloadStartRequest.suggestedFilename ?? 'download';
        await _saveDataUrlToFile(url, filename);
      } else if (url.startsWith('blob:')) {
        if (_controller != null) {
          final filename = downloadStartRequest.suggestedFilename ?? 'download';
          await _downloadBlobUrl(_controller!, url, filename);
        }
      } else {
        Log.warn('[MobileWhiteboard] ⚠️ Unsupported download URL scheme: $url');
      }
    } catch (e) {
      Log.error('[MobileWhiteboard] ❌ _handleDownloadRequest error: $e');
    }
  }

  Future<void> _downloadBlobUrl(InAppWebViewController controller,
      String blobUrl, String filename) async {
    Log.info('[MobileWhiteboard] 📥 Downloading blob URL: $blobUrl');

    try {
      final jsCode = '''
        (async function() {
          const response = await fetch('$blobUrl');
          const blob = await response.blob();
          const reader = new FileReader();
          reader.onloadend = function() {
            const base64Data = reader.result;
            const mimeType = blob.type;
            window.flutter_inappwebview.callHandler('saveBase64File', base64Data, '$filename', mimeType);
          };
          reader.readAsDataURL(blob);
        })();
      ''';

      await controller.evaluateJavascript(source: jsCode);
    } catch (e) {
      Log.error('[MobileWhiteboard] ❌ _downloadBlobUrl error: $e');
    }
  }

  Future<void> _saveDataUrlToFile(String dataUrl, String filename) async {
    try {
      final parts = dataUrl.split(',');
      if (parts.length < 2) {
        Log.error('[MobileWhiteboard] ❌ Invalid data URL format');
        return;
      }

      final String mimeType = parts[0].split(':')[1].split(';')[0];
      final String base64Data = parts[1];

      await _saveBase64ToFile(base64Data, filename, mimeType);
    } catch (e) {
      Log.error('[MobileWhiteboard] ❌ _saveDataUrlToFile error: $e');
    }
  }

  Future<void> _saveBase64ToFile(
      String base64Data, String filename, String mimeType) async {
    try {
      final String cleanBase64 =
          base64Data.replaceAll('\n', '').replaceAll('\r', '');
      final List<int> bytes = base64Decode(cleanBase64);

      String ext = '';
      if (mimeType.isNotEmpty) {
        ext = _mapMimeTypeToExtension(mimeType);
      } else {
        ext = _getFileExtensionFromFilename(filename);
      }

      if (ext.isEmpty) {
        ext = _detectExtensionFromBytes(bytes);
      }

      final String finalFilename = _ensureFilenameExtension(filename, ext);
      if (Platform.isAndroid || Platform.isIOS) {
        final savePath = await GetIt.instance<FilePickerService>().saveFile(
          dialogTitle: '保存白板图片',
          fileName: finalFilename,
          type: FileType.custom,
          allowedExtensions: [ext],
          bytes: Uint8List.fromList(bytes),
        );
        if (savePath == null) {
          Log.info('[MobileWhiteboard] 用户取消保存图片');
          return;
        }
        Log.info('[MobileWhiteboard] 图片已保存: $savePath');
        showToastNotification(
          message: '图片已保存',
          type: ToastificationType.success,
        );
        return;
      }

      final Directory downloadsDir = await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      await downloadsDir.create(recursive: true);
      final File file = File('${downloadsDir.path}/$finalFilename');

      await file.writeAsBytes(bytes);
      Log.info('[MobileWhiteboard] ✅ File saved: ${file.path}');

      showToastNotification(
        message: '文件已保存到: ${file.path.split('/').last}',
        type: ToastificationType.success,
        description: file.path,
      );

      await OpenFilex.open(file.path);
    } catch (e) {
      Log.error('[MobileWhiteboard] ❌ _saveBase64ToFile error: $e');
      showToastNotification(
        message: '保存文件失败',
        type: ToastificationType.error,
        description: e.toString(),
      );
    }
  }

  String _mapMimeTypeToExtension(String mimeType) {
    switch (mimeType.toLowerCase()) {
      case 'image/png':
        return 'png';
      case 'image/svg+xml':
        return 'svg';
      case 'image/jpeg':
      case 'image/jpg':
        return 'jpg';
      case 'image/gif':
        return 'gif';
      case 'application/pdf':
        return 'pdf';
      case 'application/vnd.excalidraw+json':
        return 'excalidraw';
      case 'application/json':
        return 'json';
      default:
        return '';
    }
  }

  String _getFileExtensionFromFilename(String filename) {
    final parts = filename.split('.');
    if (parts.length > 1) {
      return parts.last.toLowerCase();
    }
    return '';
  }

  String _detectExtensionFromBytes(List<int> bytes) {
    if (bytes.length >= 4) {
      if (bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47) {
        return 'png';
      }
      if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
        return 'jpg';
      }
      if (bytes.length >= 10 && (bytes[0] == 0x3C && bytes[1] == 0x73) ||
          (bytes[0] == 0x3C && bytes[1] == 0x3F)) {
        return 'svg';
      }
      if (bytes[0] == 0x7B) {
        return 'json';
      }
    }
    return 'bin';
  }

  String _ensureFilenameExtension(String filename, String ext) {
    if (ext.isEmpty) return filename;
    if (filename.toLowerCase().endsWith('.$ext')) {
      return filename;
    }
    return '$filename.$ext';
  }
}
