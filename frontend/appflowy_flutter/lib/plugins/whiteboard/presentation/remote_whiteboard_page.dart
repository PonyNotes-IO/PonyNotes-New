import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_exit_flush.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_mirror_service.dart';
import 'package:appflowy/plugins/whiteboard/presentation/webview_async_eval.dart';
import 'package:appflowy/plugins/whiteboard/presentation/whiteboard_guard_script.dart';
import 'package:appflowy/plugins/whiteboard/presentation/whiteboard_export_action.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

class RemoteWhiteboardPage extends StatefulWidget {
  const RemoteWhiteboardPage({
    super.key,
    required this.view,
    required this.roomId,
    required this.roomKey,
  });

  final ViewPB view;
  final String roomId;
  final String roomKey;

  @override
  State<RemoteWhiteboardPage> createState() => _RemoteWhiteboardPageState();
}

class _RemoteWhiteboardPageState extends State<RemoteWhiteboardPage>
    with WidgetsBindingObserver {
  InAppWebViewController? _controller;
  bool _isLoading = true;
  bool _isDisposed = false;
  String? _loadingError;
  String? _userNickname;
  bool _ownsExportController = false;
  bool _isExporting = false;
  String? _lastHostTheme;
  Timer? _brightnessPollTimer;
  // 本地镜像（严格单向：只写「服务器 → 本地」，永不回推 room）。
  final WhiteboardMirrorService _mirrorService = WhiteboardMirrorService();
  // Flutter 侧再做一次按 sceneVersion 去重，避免重复落盘。
  int _lastMirroredVersion = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // iOS 的 PlatformView 场景下，系统亮度事件偶尔不会传递到 Flutter 页面。
    // 轮询只在检测到亮度变化时同步，作为原生事件监听的兜底。
    _brightnessPollTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _syncSystemBrightness(
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
      ),
    );
    // 【慢机器丢最后编辑修复】注册"切走前冲刷保存"回调，供上游 TabsBloc 在真正
    // dispose 本页前 await（保证最后一次保存在 WebView 销毁前完成或超时）。
    // 用本 State 实例作为 key，避免同一 viewId 新旧页面重建时互相误删注册项。
    WhiteboardExitFlush.instance.register(this, _flushSave);
    _registerExportController();
    _loadUserNickname();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _brightnessPollTimer?.cancel();
    _brightnessPollTimer = null;
    _isDisposed = true;
    // 注销冲刷回调（本页已销毁，不再参与上游冲刷）
    WhiteboardExitFlush.instance.unregister(this);
    _unregisterExportController();
    // 【白板丢内容修复】销毁 WebView 前再尽力触发一次退出保存作为兜底：
    // 正常切换/关闭标签已由上游 TabsBloc await _flushSave 完成冲刷；此处覆盖
    // 少数不经 TabsBloc 的销毁路径（如应用关闭、路由异常）。dispose 为同步方法、
    // 无法 await，配合守护脚本的 500ms 防抖保存，丢失窗口已压缩到 <1 秒。
    // 修复：先捕获 controller 引用并解除 _controller，避免兜底 JS 调用期间
    // 其他路径继续访问已失效的 controller。
    final controller = _controller;
    _controller = null;
    controller
        ?.evaluateJavascript(
      source: 'window.__xmForceSave && window.__xmForceSave("dispose");',
    )
        .catchError((e) {
      Log.warn('[RemoteWhiteboard] 退出保存触发失败: $e');
      return null;
    });
    // 延迟一帧销毁原生实例，避免与渲染线程竞态。
    if (controller != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          controller.dispose();
        } catch (e) {
          Log.warn('[RemoteWhiteboard] controller.dispose() failed: $e');
        }
      });
    }
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    _syncSystemBrightness(
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
  }

  void _syncSystemBrightness(Brightness brightness) {
    if (_isDisposed) return;

    final theme = brightness == Brightness.dark ? 'dark' : 'light';
    if (_lastHostTheme == theme) return;

    Log.info('[RemoteWhiteboard] 系统外观变化: $theme');
    _lastHostTheme = theme;
    Log.info('[RemoteWhiteboard] 系统外观已变化: $theme，开始同步 Excalidraw');
    if (mounted) {
      setState(() {});
    }
    // 不依赖页面重建或 URL 重新加载，直接更新当前远程 Excalidraw。
    _scheduleRemoteThemeSync(theme);
  }

  void _scheduleRemoteThemeSync(String theme) {
    void sync() {
      if (!_isDisposed) {
        unawaited(_applyRemoteTheme(theme));
      }
    }

    sync();
    WidgetsBinding.instance.addPostFrameCallback((_) => sync());
    Future<void>.delayed(const Duration(milliseconds: 180), sync);
    Future<void>.delayed(const Duration(milliseconds: 600), sync);
  }

  /// 协作白板由远程 WebView 承载，仍需注册导出控制器供页面“更多”菜单调用。
  ///
  /// 原先只有本地 [WhiteboardPage] 注册此控制器，协作白板画布已可见时，
  /// 菜单会错误提示“请先打开白板视图”。
  void _registerExportController() {
    try {
      final getIt = GetIt.instance;
      final instanceName = '${widget.view.id}_export';
      if (getIt.isRegistered<WhiteboardExportController>(
        instanceName: instanceName,
      )) {
        Log.warn('[RemoteWhiteboard] 导出控制器已存在: ${widget.view.id}');
        return;
      }

      getIt.registerSingleton<WhiteboardExportController>(
        WhiteboardExportController(
          viewId: widget.view.id,
          exportCallback: _performExport,
        ),
        instanceName: instanceName,
      );
      _ownsExportController = true;
      Log.info('[RemoteWhiteboard] 注册导出控制器: ${widget.view.id}');
    } catch (e) {
      Log.warn('[RemoteWhiteboard] 注册导出控制器失败: $e');
    }
  }

  void _unregisterExportController() {
    if (!_ownsExportController) return;

    try {
      GetIt.instance.unregister<WhiteboardExportController>(
        instanceName: '${widget.view.id}_export',
      );
      Log.info('[RemoteWhiteboard] 注销导出控制器: ${widget.view.id}');
    } catch (e) {
      Log.warn('[RemoteWhiteboard] 注销导出控制器失败: $e');
    } finally {
      _ownsExportController = false;
    }
  }

  void _performExport(String format) {
    if (format != 'png' && format != 'svg') {
      showToastNotification(
        message: '协作白板暂不支持导出此格式',
        type: ToastificationType.warning,
      );
      return;
    }
    unawaited(_exportImage(format));
  }

  /// 打开远程 Excalidraw 的原生导出面板，并自动选择用户请求的图片格式。
  ///
  /// 图片二进制仍由远程页面创建 Blob/Data URL，随后复用本页现有下载拦截和
  /// [saveBase64File] 处理器写入设备，避免读取或修改协作 room 的加密数据。
  Future<void> _exportImage(String format) async {
    if (_isDisposed || _controller == null) {
      showToastNotification(
        message: '白板正在加载，请稍后再试',
        type: ToastificationType.warning,
      );
      return;
    }
    if (_isExporting) return;

    _isExporting = true;
    try {
      final controller = _controller!;
      final result = await evaluateAsyncJavascript(
        controller,
        asyncBody: '''
if (typeof window.__xmExportImage !== 'function') {
  return { ok: false, reason: 'export-bridge-unavailable' };
}
return await window.__xmExportImage('$format');
''',
        timeout: const Duration(seconds: 6),
        isCancelled: () => _isDisposed,
        debugLabel: ' exportImage view=${widget.view.id} format=$format',
      );

      if (result is Map && result['ok'] == true) {
        Log.info('[RemoteWhiteboard] 已触发 $format 图片导出: ${widget.view.id}');
      } else if (!_isDisposed) {
        final reason = result is Map ? result['reason'] : 'unknown';
        Log.warn(
          '[RemoteWhiteboard] 未能触发 $format 图片导出: '
          '${widget.view.id}, reason=$reason',
        );
        showToastNotification(
          message: '导出图片失败，请稍后再试',
          type: ToastificationType.error,
        );
      }
    } catch (e) {
      Log.error('[RemoteWhiteboard] 导出 $format 图片失败: $e');
      if (!_isDisposed) {
        showToastNotification(
          message: '导出图片失败，请稍后再试',
          type: ToastificationType.error,
        );
      }
    } finally {
      _isExporting = false;
    }
  }

  /// 切走白板前的"冲刷保存"：触发退出保存并等待其真正完成，最多等待 2 秒。
  ///
  /// 等待页面内 __xmForceSave 返回的 Promise（该 Promise 在
  /// saveCollabRoomToFirebase 真正落盘后才 resolve），从而在 WebView 被销毁前
  /// 把最后一小段编辑推到协作服务器。超时兜底确保绝不卡住 UI。
  ///
  /// 这里**不能**用 controller.callAsyncJavaScript：它在 macOS 上会调到弱导入的
  /// WebKit Swift overlay 符号，在部分系统上该符号解析为 0，调用即整进程崩溃
  /// （详见 webview_async_eval.dart）。改用等价的「JS 侧 await + 信箱轮询」。
  Future<void> _flushSave() async {
    // 修复：dispose 后 _controller 会被置 null 且 _isDisposed 为 true，
    // 此处提前返回避免向已销毁的原生 WebView 发送 MethodChannel 消息。
    if (_isDisposed) return;
    final controller = _controller;
    if (controller == null) return;
    try {
      // 超时/失败由 evaluateAsyncJavascript 内部消化并返回 null，不再抛
      // TimeoutException；它自身也会记录超时日志。
      final value = await evaluateAsyncJavascript(
        controller,
        asyncBody:
            'return await (window.__xmForceSave ? window.__xmForceSave("flush") : false);',
        timeout: const Duration(seconds: 2),
        isCancelled: () => _isDisposed,
        debugLabel: ' flushSave view=${widget.view.id}',
      );
      if (value != null) {
        Log.info('[RemoteWhiteboard] 切走前冲刷保存完成 view=${widget.view.id}');
      } else {
        Log.warn(
          '[RemoteWhiteboard] 切走前冲刷保存未确认完成，继续销毁 view=${widget.view.id}',
        );
      }
    } catch (e) {
      Log.warn('[RemoteWhiteboard] 切走前冲刷保存失败: $e');
    }
  }

  Future<void> _loadUserNickname() async {
    Log.info('[RemoteWhiteboard] 🔍 Starting to load user nickname...');
    final userProfileResult = await UserBackendService.getCurrentUserProfile();
    String nickname = userProfileResult.fold(
      (profile) {
        Log.info(
            '[RemoteWhiteboard] ✅ Got user profile: id=${profile.id}, name=${profile.name}, email=${profile.email}');
        return profile.name;
      },
      (error) {
        Log.error('[RemoteWhiteboard] ❌ Failed to get user nickname: $error');
        return '';
      },
    );

    if (nickname.isEmpty) {
      nickname = '小马笔记用户';
      Log.info(
          '[RemoteWhiteboard] 📌 Nickname is empty, using default: "$nickname"');
    }

    setState(() {
      _userNickname = nickname;
    });
    Log.info(
        '[RemoteWhiteboard] 📌 Final nickname: "$nickname", isEmpty: ${nickname.isEmpty}, length: ${nickname.length}');
  }

  @override
  Widget build(BuildContext context) {
    final hostTheme =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark
            ? 'dark'
            : 'light';
    if (_lastHostTheme != null && _lastHostTheme != hostTheme) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applyRemoteTheme(hostTheme);
      });
    }
    _lastHostTheme = hostTheme;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor:
          hostTheme == 'dark' ? const Color(0xFF121212) : Colors.white,
      body: _userNickname == null
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : Stack(
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
                    // 【白板丢内容修复】持久化守护脚本：兜底保存 + 空场景防覆盖 +
                    // 退出保存入口（必须 AT_DOCUMENT_START，先于页面首次场景加载）
                    UserScript(
                      source: whiteboardGuardScript,
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
                          document.addEventListener('keydown', function(event) {
                            if (event.altKey && event.shiftKey && event.code === 'KeyD' && !event.__ponynotesThemeSync) {
                              event.preventDefault();
                              event.stopImmediatePropagation();
                            }
                          }, true);
                          var syncExcalidrawEditorTheme = function(theme) {
                            var root = document.querySelector('.excalidraw');
                            if (!root) return;
                            var currentTheme = root.classList.contains('theme--dark') ? 'dark' : 'light';
                            if (currentTheme === theme) return;
                            var event = new KeyboardEvent('keydown', {
                              bubbles: true,
                              cancelable: true,
                              altKey: true,
                              shiftKey: true,
                              code: 'KeyD',
                              key: 'd'
                            });
                            Object.defineProperty(event, '__ponynotesThemeSync', { value: true });
                            document.dispatchEvent(event);
                            console.info('[PonyNotes] React editor theme synchronized:', theme);
                          };
                          var style = document.createElement('style');
                          style.textContent = '.dropdown-menu-item-base:has(input[name="theme"]), [data-testid="toggle-dark-mode"] { display:none!important; pointer-events:none!important; }';
                          (document.head || document.documentElement).appendChild(style);
                          window.__ponynotesApplyTheme = function(theme) {
                            window.__ponynotesHostTheme = theme === 'dark' ? 'dark' : 'light';
                            try { window.localStorage.setItem('excalidraw-theme', window.__ponynotesHostTheme); } catch (_) {}
                            syncExcalidrawEditorTheme(window.__ponynotesHostTheme);
                            document.documentElement.classList.toggle('dark', window.__ponynotesHostTheme === 'dark');
                            var api = window.excalidrawAPI || window._excalidrawAPI || window.__EXCALIDRAW_API__;
                            console.info('[PonyNotes] host theme requested:', window.__ponynotesHostTheme, 'apiReady=', !!api);
                            if (api && typeof api.updateScene === 'function') {
                              api.updateScene({ appState: {
                                theme: window.__ponynotesHostTheme,
                                viewBackgroundColor: window.__ponynotesHostTheme === 'dark' ? '#121212' : '#ffffff'
                              }, commitToHistory: false });
                              document.querySelectorAll('.excalidraw').forEach(function(root) {
                                root.classList.toggle('theme--dark', window.__ponynotesHostTheme === 'dark');
                              });
                            }
                          };
                          document.addEventListener('change', function(event) {
                            if (event.target && event.target.name === 'theme') {
                              event.preventDefault();
                              event.stopImmediatePropagation();
                              window.__ponynotesApplyTheme(window.__ponynotesHostTheme);
                            }
                          }, true);
                          setInterval(function() {
                            window.__ponynotesApplyTheme(window.__ponynotesHostTheme);
                          }, 500);
                        })();

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
                    if (_isDisposed) return;
                    _controller = controller;
                    _setupDownloadHandler(controller);
                    _setupMirrorHandler(controller);
                  },
                  onLoadStart: (controller, url) {
                    setState(() {
                      _isLoading = true;
                      _loadingError = null;
                    });
                    Log.debug('🔄 [RemoteWhiteboard] Loading: $url');
                  },
                  onLoadStop: (controller, url) {
                    setState(() {
                      _isLoading = false;
                    });
                    _applyRemoteTheme(hostTheme);
                    Log.debug('✅ [RemoteWhiteboard] Loaded: $url');
                  },
                  onReceivedError: (controller, request, error) {
                    setState(() {
                      _isLoading = false;
                      _loadingError = error.description;
                    });
                    Log.error(
                        '❌ [RemoteWhiteboard] Load error: ${error.type} - ${error.description}');
                  },
                  // 【白板丢内容修复】把页面 console 输出写入客户端日志，
                  // 页内 JS 故障（此前完全不可见）从此可以在 log 文件中定位
                  onConsoleMessage: (controller, consoleMessage) {
                    final msg = consoleMessage.message;
                    final level = consoleMessage.messageLevel;
                    if (level == ConsoleMessageLevel.ERROR) {
                      Log.error('[RemoteWhiteboard][JS] $msg');
                    } else if (level == ConsoleMessageLevel.WARNING) {
                      Log.warn('[RemoteWhiteboard][JS] $msg');
                    } else {
                      Log.info('[RemoteWhiteboard][JS] $msg');
                    }
                  },
                  // 【白板丢内容修复】WebView 内容进程被系统终止（内存压力等）时
                  // 自动重载页面，避免停留在"白屏假活"状态（网络进程仍存活、
                  // 页面 JS 已死，绘制与保存全部静默失效）
                  onWebContentProcessDidTerminate: (controller) async {
                    // 修复：页面已 dispose 时不应再 reload，避免向已销毁的
                    // 原生 WebView 发送 MethodChannel 消息触发空指针崩溃。
                    if (!mounted || _isDisposed) return;
                    Log.error(
                        '[RemoteWhiteboard] ⚠️ WebView 内容进程已终止，自动重新加载白板页面');
                    await controller.reload();
                  },
                  shouldOverrideUrlLoading:
                      (controller, navigationAction) async {
                    final url = navigationAction.request.url?.toString();
                    final headers = navigationAction.request.headers;
                    final filename = headers != null
                        ? (headers['Content-Disposition']
                                ?.split('filename=')
                                .last ??
                            headers['content-disposition']
                                ?.split('filename=')
                                .last ??
                            'download')
                        : 'download';

                    if (url != null && url.startsWith('blob:')) {
                      Log.info(
                          '[RemoteWhiteboard] 🚫 Blocking blob navigation, starting download: $url, filename: $filename');
                      _downloadBlobUrl(
                          controller, url, filename.replaceAll('"', ''));
                      return NavigationActionPolicy.CANCEL;
                    }
                    if (url != null && url.startsWith('data:')) {
                      Log.info(
                          '[RemoteWhiteboard] 🚫 Blocking data URL navigation, starting download: $url, filename: $filename');
                      _saveDataUrlToFile(url, filename.replaceAll('"', ''));
                      return NavigationActionPolicy.CANCEL;
                    }
                    return NavigationActionPolicy.ALLOW;
                  },
                  onDownloadStartRequest:
                      (controller, downloadStartRequest) async {
                    Log.info(
                        '[RemoteWhiteboard] 📥 Download request: ${downloadStartRequest.url}');
                    await _handleDownloadRequest(downloadStartRequest);
                  },
                ),
                if (_isLoading)
                  const Positioned.fill(
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
                if (_loadingError != null)
                  Positioned.fill(
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
                            '加载失败: $_loadingError',
                            style: const TextStyle(fontSize: 16),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              _controller?.reload();
                            },
                            child: const Text('重新加载'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  String _buildRemoteUrl() {
    Log.info('[RemoteWhiteboard] 🔨 Building remote URL...');
    Log.info('[RemoteWhiteboard] 🔨 _userNickname: "$_userNickname"');

    final encodedNickname = Uri.encodeComponent(_userNickname ?? '');
    Log.info('[RemoteWhiteboard] 🔨 Encoded nickname: "$encodedNickname"');

    final hostTheme =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark
            ? 'dark'
            : 'light';
    final url =
        'https://xm-arts.xiaomabiji.com/?ua=$encodedNickname&hostTheme=$hostTheme#room=${widget.roomId},${widget.roomKey}';
    Log.info('[RemoteWhiteboard] ✅ Built URL: $url');
    return url;
  }

  Future<void> _applyRemoteTheme(String theme) async {
    final controller = _controller;
    if (_isDisposed || controller == null) return;
    try {
      await controller.evaluateJavascript(source: '''
        if (typeof window.__ponynotesApplyTheme === 'function') {
          window.__ponynotesApplyTheme('${theme == 'dark' ? 'dark' : 'light'}');
        }
      ''');
      Log.info('[RemoteWhiteboard] WebView 主题同步脚本已发送: $theme');
    } catch (e) {
      Log.warn('[RemoteWhiteboard] WebView 主题同步失败（页面可能尚未就绪）: $e');
    }
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
              '[RemoteWhiteboard] 📥 downloadBlobFile handler: blobUrl=$blobUrl, filename=$filename');

          if (blobUrl.startsWith('data:')) {
            await _saveDataUrlToFile(blobUrl, filename);
          } else if (blobUrl.startsWith('blob:')) {
            await _downloadBlobUrl(controller, blobUrl, filename);
          }
        } catch (e) {
          Log.error('[RemoteWhiteboard] ❌ downloadBlobFile handler error: $e');
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

  /// 注册「本地镜像」回传通道（严格单向：只写「服务器 → 本地」）。
  ///
  /// XMGuard 在 room 场景加载/保存成功后，把**已解密**的活场景快照通过此 handler 回传，
  /// 由本方法写入独立的本地镜像文件（`{userId}/whiteboard_mirrors/{viewId}.json`）。
  /// 这里没有、也绝不会有任何「本地 → room」的写回分支，杜绝本地推空覆盖真数据。
  /// 纯旁路：任何异常静默吞掉，不影响在线协作。
  void _setupMirrorHandler(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: 'saveWhiteboardMirror',
      callback: (args) async {
        try {
          if (args.isEmpty) return;
          final raw = args[0];
          final Map<String, dynamic> payload = raw is String
              ? (jsonDecode(raw) as Map<String, dynamic>)
              : Map<String, dynamic>.from(raw as Map);

          final version = payload['sceneVersion'];
          final versionInt = version is int
              ? version
              : (version is num ? version.toInt() : -1);
          // Flutter 侧按版本去重，避免重复落盘。
          if (versionInt >= 0 && versionInt == _lastMirroredVersion) {
            return;
          }

          final saved = await _mirrorService.saveMirror(
            widget.view.id,
            payload,
          );
          if (saved && versionInt >= 0) {
            _lastMirroredVersion = versionInt;
          }
        } catch (e) {
          Log.warn('[RemoteWhiteboard] 本地镜像回传处理失败(已忽略): $e');
        }
      },
    );
  }

  Future<void> _handleDownloadRequest(
      DownloadStartRequest downloadStartRequest) async {
    try {
      final url = downloadStartRequest.url.toString();
      Log.info('[RemoteWhiteboard] 📥 Handling download request: $url');

      if (url.startsWith('data:')) {
        final filename = downloadStartRequest.suggestedFilename ?? 'download';
        await _saveDataUrlToFile(url, filename);
      } else if (url.startsWith('blob:')) {
        if (_controller != null) {
          final filename = downloadStartRequest.suggestedFilename ?? 'download';
          await _downloadBlobUrl(_controller!, url, filename);
        }
      } else {
        Log.warn('[RemoteWhiteboard] ⚠️ Unsupported download URL scheme: $url');
      }
    } catch (e) {
      Log.error('[RemoteWhiteboard] ❌ _handleDownloadRequest error: $e');
    }
  }

  Future<void> _downloadBlobUrl(InAppWebViewController controller,
      String blobUrl, String filename) async {
    Log.info('[RemoteWhiteboard] 📥 Downloading blob URL: $blobUrl');

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
      Log.error('[RemoteWhiteboard] ❌ _downloadBlobUrl error: $e');
    }
  }

  Future<void> _saveDataUrlToFile(String dataUrl, String filename) async {
    try {
      final parts = dataUrl.split(',');
      if (parts.length < 2) {
        Log.error('[RemoteWhiteboard] ❌ Invalid data URL format');
        return;
      }

      final String mimeType = parts[0].split(':')[1].split(';')[0];
      final String base64Data = parts[1];

      await _saveBase64ToFile(base64Data, filename, mimeType);
    } catch (e) {
      Log.error('[RemoteWhiteboard] ❌ _saveDataUrlToFile error: $e');
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
          Log.info('[RemoteWhiteboard] 用户取消保存图片');
          return;
        }
        Log.info('[RemoteWhiteboard] 图片已保存: $savePath');
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
      Log.info('[RemoteWhiteboard] ✅ File saved: ${file.path}');

      showToastNotification(
        message: '文件已保存到: ${file.path.split('/').last}',
        type: ToastificationType.success,
        description: file.path,
      );

      await OpenFilex.open(file.path);
    } catch (e) {
      Log.error('[RemoteWhiteboard] ❌ _saveBase64ToFile error: $e');
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
