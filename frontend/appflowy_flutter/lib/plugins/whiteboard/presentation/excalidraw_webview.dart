import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/clipboard_service.dart';
import 'package:appflowy/plugins/whiteboard/application/local_asset_server.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/startup/tasks/webview2_task.dart';
import 'package:http/http.dart' as http;

import '../application/whiteboard_data_service.dart';
import '../application/whiteboard_image_cache_service.dart';
import '../application/whiteboard_collab_adapter.dart';
import 'package:appflowy/plugins/import_page/file_upload_service.dart';
import 'package:appflowy_backend/log.dart';
import 'webview_async_eval.dart';

// 白板逐元素同步开关：出问题时置 false 回退到旧整段 elements 推送路径。
const bool kWhiteboardPerElementSync = true;

/// 由文件扩展名推断白板插图的 MIME 类型。Excalidraw 仅接受
/// png/jpeg/gif/svg/webp/bmp/ico，未知扩展名按 png 兜底。
String _imageMimeTypeForExtension(String ext) {
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'gif':
      return 'image/gif';
    case 'svg':
      return 'image/svg+xml';
    case 'webp':
      return 'image/webp';
    case 'bmp':
      return 'image/bmp';
    case 'ico':
      return 'image/x-icon';
    case 'png':
    default:
      return 'image/png';
  }
}

// 全局InAppWebView实例计数器，确保每个InAppWebView的PlatformView ID全局唯一
int _globalInAppWebViewInstanceCounter = 0;

/// Excalidraw WebView 组件
/// 使用 flutter_inappwebview 实现跨平台支持（包括 Windows）
/// 集成 Excalidraw 编辑器和 excalidraw-libraries 图形库
class ExcalidrawWebView extends StatefulWidget {
  const ExcalidrawWebView({
    super.key,
    required this.viewId,
    required this.sessionTraceId,
    required this.loadTraceId,
    this.reloadToken = 0,
    this.initialData,
    this.initialDataLoaded = false,
    this.deferInitialDataLoad = false,
    this.onDataChanged,
    this.onExport,
    this.onError,
    this.onInitialReady,
  });

  final String viewId;
  final String sessionTraceId;
  final String loadTraceId;
  final int reloadToken;
  final Map<String, dynamic>? initialData;
  final bool initialDataLoaded;
  final bool deferInitialDataLoad;
  final Function(String type, Map<String, dynamic> data)? onDataChanged;
  final Function(String format, dynamic data)? onExport;
  final Function(String error)? onError;
  final VoidCallback? onInitialReady;

  @override
  State<ExcalidrawWebView> createState() => ExcalidrawWebViewState();
}

/// ExcalidrawWebView的State类，暴露公共方法供外部调用
class ExcalidrawWebViewState extends State<ExcalidrawWebView> {
  // scrollX/scrollY 故意不包含在此集合中。
  // 原因：每次触发 resize 事件时 Excalidraw 会根据新旧视口尺寸之差调整
  // scrollX/scrollY 以保持视口中心点不变；若视口尺寸与保存时不一致，
  // 每次 resize 都会产生偏移量，导致画布持续漂移。
  // 与 whiteboard_collab_adapter.dart 中的同名常量保持一致。
  static const Set<String> _stableAppStateKeys = {
    'gridModeEnabled',
    'gridSize',
    'theme',
    'viewBackgroundColor',
    'zoom',
    'zenModeEnabled',
  };

  // 内部状态（保持原有实现）
  InAppWebViewController? _controller;
  bool _isLoading = true;
  bool _isInitializing = false; // ✅ 新增：用于跟踪初始化状态
  bool _isDisposed = false;
  String? _loadingError;
  final _assetServer = LocalAssetServer();
  String? _whiteboardUrl;
  late InAppWebViewSettings _settings;
  bool _webViewCreated = false;
  bool _pageLoaded = false;
  String? _lastObservedHostTheme;
  String? _pendingHostTheme;
  int _themeSyncRequestId = 0;
  Future<void>? _themeSyncInFlight;
  bool _initialReadyNotified = false;
  late final int _inAppWebViewInstanceId; // 每个InAppWebView的全局唯一ID
  // iOS 在应用重启/引擎切换期间可能留下一个已经失效的平台视图控制器。
  // 递增该值会强制 Flutter 创建新的 InAppWebView，而不是继续复用旧通道。
  int _webViewRecoveryNonce = 0;
  int _localServerRecoveryAttempts = 0;
  bool _isRecoveringLocalServer = false;
  Completer<void>? _initializationCompleter; // ✅ 新增：用于等待初始化完成
  final bool _perElementSyncEnabled = kWhiteboardPerElementSync;
  Size? _stableWebViewSize;
  Size? _pendingWebViewSize;
  Timer? _webViewResizeSettleTimer;
  static const _webViewResizeSettleDuration = Duration(milliseconds: 220);
  static const _javaScriptHandlerNames = [
    'readWhiteboardClipboard',
    'initData',
    'localStorageOnSet',
    'whiteboardImageSceneSnapshot',
    'localStorageOnRemove',
    'localStorageOnClear',
    'downloadCloudImages',
    'onExport',
    'onExportError',
  ];

  /// 在销毁 WebView 前冲刷 JS -> Flutter 的 elements/files 防抖队列。
  /// 返回 false 表示页面尚未完成初始化或 JS 未确认执行，调用方仍可继续走
  /// adapter 的 forceSync 兜底，但不能把它当作 WebView 数据已送达的保证。
  Future<bool> flushPendingStorageSyncs() async {
    if (_isDisposed || !mounted || _controller == null) return false;
    final value = await evaluateAsyncJavascript(
      _controller!,
      asyncBody:
          'return await (window.__ponynotesFlushStorageSyncs ? window.__ponynotesFlushStorageSyncs() : false);',
      timeout: const Duration(seconds: 2),
      isCancelled: () => _isDisposed,
      debugLabel: ' flushPendingStorageSyncs view=${widget.viewId}',
    );
    return value == true;
  }

  /// 由 Dart 直接注入的宿主主题桥接。
  ///
  /// 移动端调试会话可能只热更新 Dart，手机 rootBundle 中的
  /// flutter_bridge.js 仍是旧版本。主题同步不能依赖该静态资源已重新打包，
  /// 因此在 document-start 阶段安装独立桥接，并持续校正 React 根节点与画布状态。
  static String _hostThemeBootstrapScript(String initialTheme) => '''
    (function() {
      var normalizeTheme = function(theme) {
        return theme === 'dark' ? 'dark' : 'light';
      };
      var requestedTheme = normalizeTheme('$initialTheme');
      var lastReportedTheme = null;

      var ensureHostThemeStyle = function() {
        var style = document.getElementById('ponynotes-host-theme-style');
        if (!style) {
          style = document.createElement('style');
          style.id = 'ponynotes-host-theme-style';
          (document.head || document.documentElement).appendChild(style);
        }
        // React 重新渲染时可能短暂移除 .theme--dark。以宿主 html.dark
        // 作为第二个稳定条件，确保 canvas 不会在这段窗口恢复成白色。
        style.textContent = '\n' +
          'html.dark #root .excalidraw canvas.excalidraw__canvas,' +
          'html.dark #root .excalidraw canvas.static,' +
          'html.dark #root .excalidraw canvas.interactive {' +
          '-webkit-filter: invert(93%) hue-rotate(180deg) !important;' +
          'filter: invert(93%) hue-rotate(180deg) !important;' +
          '}' +
          'html.dark #root .excalidraw {' +
          'background-color: #121212 !important;' +
          '}' +
          'html:not(.dark) #root .excalidraw canvas.excalidraw__canvas,' +
          'html:not(.dark) #root .excalidraw canvas.static,' +
          'html:not(.dark) #root .excalidraw canvas.interactive {' +
          '-webkit-filter: none !important;' +
          'filter: none !important;' +
          '}';
      };

      // Excalidraw 的工具栏主题由 React 状态维护，等待其 setter 出现后
      // 再同步；用共享状态避免 document-start 桥接与 flutter_bridge.js
      // 在同一次系统切换中重复触发 React 更新。
      window.__ponynotesApplyReactTheme = function(theme) {
        var setter = window.__ponynotesSetHostTheme;
        if (typeof setter !== 'function') return;
        var normalized = normalizeTheme(theme);
        var last = window.__ponynotesReactThemeState;
        if (last && last.setter === setter && last.theme === normalized) return;
        try {
          setter(normalized);
          window.__ponynotesReactThemeState = {
            setter: setter,
            theme: normalized
          };
        } catch (_) {}
      };

      var applyTheme = function(theme, report) {
        requestedTheme = normalizeTheme(theme);
        window.__ponynotesHostTheme = requestedTheme;
        try {
          window.localStorage.setItem('excalidraw-theme', requestedTheme);
        } catch (_) {}

        var isDark = requestedTheme === 'dark';
        var uiBackgroundColor = isDark ? '#121212' : '#ffffff';
        ensureHostThemeStyle();
        window.__ponynotesApplyReactTheme(requestedTheme);
        document.documentElement.classList.toggle('dark', isDark);
        if (document.body) {
          document.body.style.backgroundColor = uiBackgroundColor;
        }
        var roots = document.querySelectorAll('.excalidraw');
        roots.forEach(function(root) {
          if (root.classList.contains('theme--dark') !== isDark) {
            root.classList.toggle('theme--dark', isDark);
          }
        });

        var api = window._excalidrawAPI || window.excalidrawAPI ||
          window.__EXCALIDRAW_API__;
        var sceneNeedsUpdate = true;
        var legacyDarkBackground = false;
        if (api && typeof api.getAppState === 'function') {
          var state = api.getAppState();
          legacyDarkBackground = !!state &&
            typeof state.viewBackgroundColor === 'string' &&
            state.viewBackgroundColor.toLowerCase() === '#121212';
          sceneNeedsUpdate = !state || state.theme !== requestedTheme ||
            legacyDarkBackground;
        }
        if (api && sceneNeedsUpdate && typeof api.updateScene === 'function') {
          var appState = { theme: requestedTheme };
          // Excalidraw 深色主题会对 canvas 使用反色滤镜，场景背景不能
          // 直接设为深色，否则滤镜会把它再次反转成白色。
          if (legacyDarkBackground) appState.viewBackgroundColor = '#ffffff';
          api.updateScene({
            appState: appState,
            commitToHistory: false
          });
        }

        if (report && lastReportedTheme !== requestedTheme) {
          lastReportedTheme = requestedTheme;
          console.info(
            '[PonyNotes] Dart host theme applied:',
            requestedTheme,
            'apiReady=', !!api,
            'officialUpdateScene=', !!(api &&
                typeof api.updateScene === 'function')
          );
        }
      };

      window.__ponynotesDartSetHostTheme = function(theme) {
        applyTheme(theme, true);
      };

      // 即使 Flutter 没有收到 iOS 的亮度回调，也由当前 WKWebView 直接
      // 监听系统外观。以全局标记保证运行时脚本重复注入时不会注册多个监听。
      if (!window.__ponynotesSystemThemeListenerInstalled) {
        var systemThemeQuery = window.matchMedia('(prefers-color-scheme: dark)');
        var syncThemeFromSystem = function() {
          var systemTheme = systemThemeQuery.matches ? 'dark' : 'light';
          if (window.__ponynotesHostTheme === systemTheme) return;
          var apply = window.setHostTheme || window.__ponynotesDartSetHostTheme;
          if (typeof apply === 'function') {
            try { apply(systemTheme); } catch (_) {}
          }
        };
        if (typeof systemThemeQuery.addEventListener === 'function') {
          systemThemeQuery.addEventListener('change', syncThemeFromSystem);
        } else if (typeof systemThemeQuery.addListener === 'function') {
          systemThemeQuery.addListener(syncThemeFromSystem);
        }
        window.__ponynotesSystemThemeListenerInstalled = true;
      }

      document.addEventListener('DOMContentLoaded', function() {
        applyTheme(requestedTheme, false);
      }, { once: true });
      window.setInterval(function() {
        applyTheme(requestedTheme, false);
      }, 500);
      applyTheme(requestedTheme, true);
    })();
  ''';

  /// 在已经创建的 WebView 中安装/执行主题桥接。
  ///
  /// `initialUserScripts` 只会在原生 WebView 创建时执行，而 Flutter 调试
  /// 热更新、页面复用或旧 PlatformView 恢复时不会再次执行。运行时同步不能
  /// 假设 document-start 脚本仍然存在，因此每次主题变更都带上一个幂等的
  /// 自愈实现，确保旧页面也能更新画布背景和 Excalidraw appState。
  static String _hostThemeRuntimeScript(String theme) => '''
    (function() {
      var requestedTheme = '$theme' === 'dark' ? 'dark' : 'light';
      var uiBackgroundColor = requestedTheme === 'dark' ? '#121212' : '#ffffff';
      window.__ponynotesHostTheme = requestedTheme;

      // 运行时自愈脚本也安装系统监听，覆盖旧 PlatformView 未重新执行
      // document-start 脚本的情况。
      if (!window.__ponynotesSystemThemeListenerInstalled &&
          typeof window.matchMedia === 'function') {
        var systemThemeQuery = window.matchMedia('(prefers-color-scheme: dark)');
        var syncThemeFromSystem = function() {
          var systemTheme = systemThemeQuery.matches ? 'dark' : 'light';
          if (window.__ponynotesHostTheme === systemTheme) return;
          var apply = window.setHostTheme || window.__ponynotesDartSetHostTheme;
          if (typeof apply === 'function') {
            try { apply(systemTheme); } catch (_) {}
          }
        };
        if (typeof systemThemeQuery.addEventListener === 'function') {
          systemThemeQuery.addEventListener('change', syncThemeFromSystem);
        } else if (typeof systemThemeQuery.addListener === 'function') {
          systemThemeQuery.addListener(syncThemeFromSystem);
        }
        window.__ponynotesSystemThemeListenerInstalled = true;
      }

      var style = document.getElementById('ponynotes-host-theme-style');
      if (!style) {
        style = document.createElement('style');
        style.id = 'ponynotes-host-theme-style';
        (document.head || document.documentElement).appendChild(style);
      }
      // 不依赖 React 是否刚好保留 .theme--dark，html.dark 直接控制画布滤镜。
      style.textContent = '\n' +
        'html.dark #root .excalidraw canvas.excalidraw__canvas,' +
        'html.dark #root .excalidraw canvas.static,' +
        'html.dark #root .excalidraw canvas.interactive {' +
        '-webkit-filter: invert(93%) hue-rotate(180deg) !important;' +
        'filter: invert(93%) hue-rotate(180deg) !important;' +
        '}' +
        'html.dark #root .excalidraw {' +
        'background-color: #121212 !important;' +
        '}' +
        'html:not(.dark) #root .excalidraw canvas.excalidraw__canvas,' +
        'html:not(.dark) #root .excalidraw canvas.static,' +
        'html:not(.dark) #root .excalidraw canvas.interactive {' +
        '-webkit-filter: none !important;' +
        'filter: none !important;' +
        '}';

      try {
        window.localStorage.setItem('excalidraw-theme', requestedTheme);
      } catch (_) {}

      // flutter_bridge.js 维护了内部的强制主题和看门狗。必须通过公开入口
      // 更新该状态，否则看门狗会在下一次 tick 把 URL 初始主题写回画布。
      var hostThemeSetter = window.setHostTheme;
      if (typeof hostThemeSetter === 'function') {
        try { hostThemeSetter(requestedTheme); } catch (_) {}
      }

      // 新版集成版 Excalidraw 提供 React 状态 setter；旧主包没有该入口时，
      // 下面的 DOM 类和官方 API 兜底仍可保证工具栏外壳与画布变暗。
      var setter = window.__ponynotesSetHostTheme;
      if (typeof setter === 'function') {
        try { setter(requestedTheme); } catch (_) {}
      }

      document.documentElement.classList.toggle('dark', requestedTheme === 'dark');
      if (document.body) {
        document.body.style.backgroundColor = uiBackgroundColor;
      }
      document.querySelectorAll('.excalidraw').forEach(function(root) {
        root.classList.toggle('theme--dark', requestedTheme === 'dark');
        root.style.backgroundColor = uiBackgroundColor;
      });
      document.querySelectorAll('.excalidraw__canvas, canvas.static, canvas.interactive')
        .forEach(function(canvas) {
          // 清理旧版本可能留下的 inline 背景；canvas 像素由 Excalidraw
          // 根据 viewBackgroundColor 绘制，深色主题再通过 theme-filter 反转。
          canvas.style.backgroundColor = '';
        });

      var api = window._excalidrawAPI || window.excalidrawAPI ||
        window.__EXCALIDRAW_API__;
      if (api && typeof api.updateScene === 'function') {
        var state = typeof api.getAppState === 'function' ? api.getAppState() : null;
        var legacyDarkBackground = !!state &&
          typeof state.viewBackgroundColor === 'string' &&
          state.viewBackgroundColor.toLowerCase() === '#121212';
        if (!state || state.theme !== requestedTheme ||
            legacyDarkBackground) {
          var appState = { theme: requestedTheme };
          if (legacyDarkBackground) appState.viewBackgroundColor = '#ffffff';
          api.updateScene({
            appState: appState,
            commitToHistory: false
          });
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
          var currentApi = window._excalidrawAPI || window.excalidrawAPI ||
            window.__EXCALIDRAW_API__;
          if (currentApi && typeof currentApi.getAppState === 'function' &&
              typeof currentApi.updateScene === 'function') {
            var currentState = currentApi.getAppState();
            var legacyDarkBackground = !!currentState &&
              typeof currentState.viewBackgroundColor === 'string' &&
              currentState.viewBackgroundColor.toLowerCase() === '#121212';
            if (!currentState || currentState.theme !== currentTheme ||
                legacyDarkBackground) {
              var currentAppState = { theme: currentTheme };
              if (legacyDarkBackground) {
                currentAppState.viewBackgroundColor = '#ffffff';
              }
              currentApi.updateScene({
                appState: currentAppState,
                commitToHistory: false
              });
            }
          }
          document.documentElement.classList.toggle('dark', currentTheme === 'dark');
          document.querySelectorAll('.excalidraw').forEach(function(root) {
            root.classList.toggle('theme--dark', currentTheme === 'dark');
            root.style.backgroundColor = currentUiBackground;
          });
          document.querySelectorAll('.excalidraw__canvas, canvas.static, canvas.interactive')
            .forEach(function(canvas) {
              canvas.style.backgroundColor = '';
            });
        }, 500);
      }

      console.info('[PonyNotes] Dart host theme applied:', requestedTheme,
        'apiReady=', !!api,
        'officialUpdateScene=', !!(api && typeof api.updateScene === 'function'));
    })();
  ''';

  Brightness _currentSystemBrightness() {
    // WebView 需要跟随 Flutter 当前实际生效的主题，而不是只读取设备系统
    // 亮度。否则应用内切换 ThemeMode 后，只有重建白板页面才会更新画布。
    return Theme.of(context).brightness;
  }

  @override
  void initState() {
    super.initState();
    // 生成全局唯一的InAppWebView实例ID
    _globalInAppWebViewInstanceCounter++;
    _inAppWebViewInstanceId = _globalInAppWebViewInstanceCounter;
    Log.debug(
        '🌐 [WBCollab] Created with global instance ID: $_inAppWebViewInstanceId, viewId: ${widget.viewId}');

    _initializeSettings();
    _loadExcalidrawHTML();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = _currentSystemBrightness();
    final theme = brightness == Brightness.dark ? 'dark' : 'light';
    if (_lastObservedHostTheme == theme) return;
    _lastObservedHostTheme = theme;
    if (_whiteboardUrl == null && !_webViewCreated) return;
    // 让 WebView 自身也订阅 MediaQuery，覆盖没有外层白板 State 监听的入口
    // （例如离线镜像）；主题队列会在原生 WebView 就绪后自动补发。
    unawaited(_syncHostThemeWhenReady(theme));
  }

  @override
  void didUpdateWidget(covariant ExcalidrawWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 把真实数据补推进 WebView 的两种情形：
    //   1) reloadToken 变化（如导入文件后强制重载）；
    //   2) 【根因A修复】迟到数据：deferInitialDataLoad 模式下首帧 initialData 可能为
    //      null，WebView 的 initData 会用 {} 把场景初始化为空；当真实数据随后加载
    //      完成（initialDataLoaded 由 false→true）时，必须把真实数据补推进去，否则
    //      画板会停留在“被清空”的状态——这正是“偶尔什么也没动画板就清空、重开又有”
    //      的根因之一。
    final reloadTokenChanged = oldWidget.reloadToken != widget.reloadToken;
    final dataArrivedLate =
        !oldWidget.initialDataLoaded && widget.initialDataLoaded;
    if ((reloadTokenChanged || dataArrivedLate) &&
        widget.initialDataLoaded &&
        widget.initialData != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          loadData(
            widget.initialData!,
            preserveLocalSceneForBlankData:
                dataArrivedLate && !reloadTokenChanged,
          );
        }
      });
    }
  }

  /// 统一的 JS 执行入口：在引擎重启/插件尚未就绪等场景下进行重试，避免 MissingPluginException
  Future<void> _safeEvalJs(
    String source, {
    String tag = 'eval',
    int maxAttempts = 10,
    Duration initialDelay = const Duration(milliseconds: 60),
    bool logFailures = true,
  }) async {
    if (!mounted || _isDisposed) return;
    var attempt = 0;
    var delay = initialDelay;
    while (mounted && attempt < maxAttempts) {
      attempt++;
      try {
        if (_controller != null &&
            !_isDisposed &&
            _webViewCreated &&
            _pageLoaded &&
            !_isLoading) {
          await _controller!.evaluateJavascript(source: source);
          return;
        }
      } on MissingPluginException catch (e) {
        if (logFailures) {
          Log.warn(
              '⚠️ [ExcalidrawWebView] MissingPluginException on $tag attempt#$attempt: $e');
        }
      } catch (e) {
        if (logFailures) {
          Log.error(
              '⚠️ [ExcalidrawWebView] error on $tag attempt#$attempt: $e');
        }
      }
      await Future.delayed(delay);
      delay += const Duration(milliseconds: 60);
    }
    if (logFailures) {
      Log.error(
          '❌ [ExcalidrawWebView] $tag failed after $maxAttempts attempts, giving up.');
    }
  }

  /// 主题切换可能发生在 WebView 创建和 initData 恢复之间。
  /// 先记录最后一次请求，待页面真正可执行脚本后补发，避免切换事件被
  /// _safeEvalJs 的就绪状态门槛吞掉。
  Future<void> _syncHostThemeWhenReady(String theme) {
    final normalizedTheme = theme == 'dark' ? 'dark' : 'light';
    _pendingHostTheme = normalizedTheme;
    _themeSyncRequestId++;
    final inFlight = _themeSyncInFlight;
    if (inFlight != null) return inFlight;

    final future = _drainHostThemeSync();
    _themeSyncInFlight = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_themeSyncInFlight, future)) {
          _themeSyncInFlight = null;
        }
      }),
    );
    return future;
  }

  Future<void> _drainHostThemeSync() async {
    while (mounted && !_isDisposed) {
      final theme = _pendingHostTheme;
      final requestId = _themeSyncRequestId;
      if (theme == null) return;

      await _safeEvalJs(
        _hostThemeRuntimeScript(theme),
        tag: 'updateTheme($theme)',
        maxAttempts: 30,
        initialDelay: const Duration(milliseconds: 100),
      );

      // 如果等待期间系统又切换过，立即处理最新值，丢弃旧值的后续重试。
      if (requestId == _themeSyncRequestId && theme == _pendingHostTheme) {
        return;
      }
    }
  }

  void _initializeSettings() {
    _settings = InAppWebViewSettings(
      // 开发者工具
      isInspectable: kDebugMode,
      javaScriptEnabled: true,
      transparentBackground: true,
      useShouldOverrideUrlLoading: true,
      mediaPlaybackRequiresUserGesture: false,
      cacheEnabled: true,
      // Android 特定设置
      useHybridComposition: true,
      thirdPartyCookiesEnabled: false,
      // iOS/macOS 特定设置
      allowsInlineMediaPlayback: true,
      allowsBackForwardNavigationGestures: false,
    );
  }

  void _scheduleStableWebViewResize(Size nextSize) {
    if (_isDisposed || nextSize.width <= 0 || nextSize.height <= 0) {
      return;
    }

    final stableWebViewSize = _stableWebViewSize;
    if (stableWebViewSize != null &&
        (stableWebViewSize.width - nextSize.width).abs() < 1 &&
        (stableWebViewSize.height - nextSize.height).abs() < 1) {
      return;
    }

    _pendingWebViewSize = nextSize;
    _webViewResizeSettleTimer?.cancel();
    _webViewResizeSettleTimer = Timer(_webViewResizeSettleDuration, () {
      if (!mounted || _isDisposed || _pendingWebViewSize == null) {
        return;
      }

      setState(() {
        _stableWebViewSize = _pendingWebViewSize;
        _pendingWebViewSize = null;
      });
    });
  }

  Future<void> _loadExcalidrawHTML({bool restartServer = false}) async {
    try {
      // debug log removed

      // 启动本地HTTP服务器
      final baseUrl = restartServer
          ? await _assetServer.restart()
          : await _assetServer.start();

      // 使用带 viewId 的URL（用于调试和日志追踪）
      // macOS 的 WKWebView 对 localStorage 有固定的来源配额。
      // macOS 使用内存兼容层，白板权威数据仍由 Flutter/collab 持久化；
      // Windows 保持现有 localStorage 行为，避免本次修复扩大平台影响范围。
      final viewId = Uri.encodeQueryComponent(widget.viewId);
      final storageMode = defaultTargetPlatform == TargetPlatform.macOS
          ? 'memory'
          : 'persistent';
      // 将 Flutter 读取到的系统亮度传给 WebView，规避部分 iOS WKWebView
      // 的 prefers-color-scheme 与系统设置不同步，确保 React 首屏即为暗色。
      final hostTheme =
          _currentSystemBrightness() == Brightness.dark ? 'dark' : 'light';
      // 入口页包含首屏主题初始化脚本，版本变化用于主动淘汰设备上的旧 WebView 缓存。
      const cacheVersion = 'ponynotes-whiteboard-v12';
      final url =
          '$baseUrl/index.html?viewId=$viewId&storageMode=$storageMode&hostTheme=$hostTheme&v=$cacheVersion';

      Log.info('✅ [ExcalidrawWebView] 服务器已启动: $baseUrl');
      // debug logs removed

      // ✅ 关键：设置 URL 并触发重新构建
      if (mounted) {
        setState(() {
          _whiteboardUrl = url;
        });
      }

      // 如果 controller 已创建，直接加载 URL。引擎重启或热重启后旧 controller
      // 可能仍被 Dart 持有，但其 platform channel 已不存在；此时必须重建原生视图。
      if (_controller != null && mounted) {
        try {
          await _controller!.loadUrl(
            urlRequest: URLRequest(url: WebUri(_whiteboardUrl!)),
          );
        } on MissingPluginException catch (e, stackTrace) {
          Log.warn(
            '⚠️ [ExcalidrawWebView] loadUrl 命中失效插件通道，重建 WebView: $e',
          );
          Log.debug('[ExcalidrawWebView] stale controller stack: $stackTrace');
          if (!mounted || _isDisposed) return;
          setState(() {
            _controller = null;
            _webViewCreated = false;
            _pageLoaded = false;
            _isLoading = true;
            _loadingError = null;
            _webViewRecoveryNonce++;
          });
        }
      }
      // 否则在 build 方法中通过 initialUrlRequest 加载
    } catch (e) {
      Log.error('❌ 加载Excalidraw失败: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingError = '加载Excalidraw失败: $e';
        });
      }
      widget.onError?.call('加载Excalidraw失败: $e');
    }
  }

  Future<void> _recoverLocalAssetServer(String error) async {
    if (_isRecoveringLocalServer ||
        _isDisposed ||
        !mounted ||
        _localServerRecoveryAttempts >= 2) {
      if (mounted && !_isDisposed && _localServerRecoveryAttempts >= 2) {
        setState(() {
          _isLoading = false;
          _loadingError = error;
        });
        widget.onError?.call('WebView加载错误: $error');
      }
      return;
    }

    _isRecoveringLocalServer = true;
    _localServerRecoveryAttempts++;
    Log.warn(
      '[ExcalidrawWebView] 本地资源服务连接失败，执行第 '
      '$_localServerRecoveryAttempts 次自动恢复: $error',
    );
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadingError = null;
      });
    }

    try {
      await _loadExcalidrawHTML(restartServer: true);
    } finally {
      _isRecoveringLocalServer = false;
    }
  }

  void _setupJavaScriptHandlers(InAppWebViewController controller) {
    // ✅ 新增：初始化完成器
    _initializationCompleter = Completer<void>();

    controller.addJavaScriptHandler(
      handlerName: "readWhiteboardClipboard",
      callback: (args) async {
        if (_isDisposed) return null;
        try {
          final data = await ClipboardService().getData();
          final image = data.image;
          final imageBytes = image?.$2;
          final imageFormat = image?.$1;
          final imageMimeType =
              imageFormat == null ? null : 'image/$imageFormat';

          return {
            'plainText': data.plainText,
            'html': data.html,
            'imageMimeType':
                imageBytes?.isNotEmpty == true ? imageMimeType : null,
            'imageBase64': imageBytes?.isNotEmpty == true
                ? base64Encode(imageBytes!)
                : null,
          };
        } catch (e, stack) {
          Log.error(
            '[ExcalidrawWebView] readWhiteboardClipboard failed: $e\n$stack',
          );
          return {
            'plainText': null,
            'html': null,
            'imageMimeType': null,
            'imageBase64': null,
            'error': e.toString(),
          };
        }
      },
    );

    // 白板插图：改由 Flutter 原生选图，绕开 WebView 里那条会「重编码为 PNG
    // 后 >4MB 被 Excalidraw 内部 fileTooBig 静默丢弃」的原生 picker 链路。
    // bridge 拦截 image 类型 <input> 的 click，转调此 handler 取字节，再在
    // WebView 侧 canvas 降采样到 <4MB 后回填 input.files，交由 Excalidraw
    // 原生插图管线建元素（该管线在 <4MB 时已被证实可靠）。
    controller.addJavaScriptHandler(
      handlerName: "pickWhiteboardImage",
      callback: (args) async {
        if (_isDisposed) return null;
        try {
          final result = await FilePicker.platform.pickFiles(
            type: FileType.image,
            allowMultiple: false,
            withData: true,
          );
          if (result == null || result.files.isEmpty) {
            return {'canceled': true};
          }
          final file = result.files.first;
          Uint8List? bytes = file.bytes;
          // 部分平台 withData 不回填 bytes，需按路径回读。
          if ((bytes == null || bytes.isEmpty) && file.path != null) {
            bytes = await File(file.path!).readAsBytes();
          }
          if (bytes == null || bytes.isEmpty) {
            return {'error': 'empty file bytes'};
          }
          final ext = file.extension?.toLowerCase() ?? 'png';
          final mimeType = _imageMimeTypeForExtension(ext);
          return {
            'name': file.name,
            'mimeType': mimeType,
            'base64': base64Encode(bytes),
          };
        } catch (e, stack) {
          Log.error(
            '[ExcalidrawWebView] pickWhiteboardImage failed: $e\n$stack',
          );
          return {'error': e.toString()};
        }
      },
    );

    controller.addJavaScriptHandler(
        handlerName: "initData",
        callback: (args) async {
          if (_isDisposed) return null;
          Log.info(
              '[WBCollab][ExcalidrawWebView] 🚀 initData called, loading whiteboard data...');

          try {
            final data = widget.initialDataLoaded || widget.deferInitialDataLoad
                ? Map<String, dynamic>.from(widget.initialData ?? const {})
                : await WhiteboardDataService().loadWhiteboardData(
                    widget.viewId,
                  );

            Log.info(
                '[WBCollab][ExcalidrawWebView] ✅ Data loaded, ${data.keys.length} keys found');

            // ✅ 关键修复：标准化数据键名
            // 后端可能返回 localStorage 原始键名（excalidraw, excalidraw-state）
            // 也可能返回标准键名（elements, appState）
            // 统一转换为标准键名，避免重复存储
            final normalizedData = _normalizeDataKeys(data);

            if (normalizedData.containsKey('elements')) {
              final elements = normalizedData['elements'];
              if (elements is List) {
                Log.info(
                    '[WBCollab][ExcalidrawWebView] 📝 Elements count: ${elements.length}');
              } else if (elements is String) {
                Log.info(
                    '[WBCollab][ExcalidrawWebView] 📝 Elements is string, length: ${elements.length}');
              }
            }
            // 不在 initData 阶段同步下载图片，避免白板首屏被大量 base64 转换阻塞。
            // JS 恢复流程会通过 downloadCloudImages 兜底补全云端图片。
            if (normalizedData.containsKey('files') &&
                normalizedData['files'] is Map) {
              final files = normalizedData['files'] as Map<String, dynamic>;
              Log.info(
                  '[WBCollab][ExcalidrawWebView] 📸 Files count: ${files.length}');
            }

            // ✅ 标记初始化完成
            if (!_initializationCompleter!.isCompleted) {
              _initializationCompleter!.complete();
            }

            // ⚡ 本地缓存优先：为返回给 JS 的 payload 补全本地缓存命中的 dataURL。
            // 这样 flutter_bridge.js 的 _injectFiles 可直接 addFiles（toAdd 分支），
            // 无需再发起 downloadCloudImages 网络往返 —— 切换视图/重开客户端秒开。
            // 注意：仅 enrich 返回值（_initPayload），不写入 localStorage
            // （base64 体积大，避免撑爆 localStorage 配额，与 Excalidraw 原生策略一致）。
            final enrichedData = await _enrichFilesWithCache(normalizedData);

            // ✅ 关键修复：将加载的数据作为返回值传给 JavaScript
            // flutter_bridge.js 会将此数据保存到 _initPayload 变量中
            // 用于在 Excalidraw API 就绪后恢复数据（不依赖 localStorage，避免竞态条件）
            return enrichedData;
          } catch (e, stack) {
            Log.error('[ExcalidrawWebView] ❌ initData failed: $e\n$stack');
            if (_initializationCompleter != null &&
                !_initializationCompleter!.isCompleted) {
              _initializationCompleter!.completeError(e);
            }
            return null;
          }
        });
    controller.addJavaScriptHandler(
        handlerName: "localStorageOnSet",
        callback: (args) {
          if (_isDisposed) return;
          if (args.isNotEmpty) {
            final arg = args[0];
            if (arg is Map &&
                arg.containsKey('key') &&
                arg.containsKey('value')) {
              final key = arg['key'].toString();
              final value = arg['value'];

              // ✅ 关键修复：标准化所有 localStorage 键名
              // 将 Excalidraw 的 localStorage 键名转换为后端存储使用的标准键名
              // 避免 _fullData 中出现重复键（elements + excalidraw 同时存在导致数据混乱）

              // 📸 拦截 excalidraw-files 并转换为标准的 files 键
              if (key.endsWith('excalidraw-files') && value is String) {
                try {
                  final filesMap = jsonDecode(value);
                  if (filesMap is Map) {
                    Log.debug(
                        '[WBCollab][ExcalidrawWebView] 📸 Intercepted files update, count: ${filesMap.length}');
                    widget.onDataChanged?.call('update', {'files': filesMap});
                    return;
                  }
                } catch (e) {
                  Log.warn(
                      '⚠️ [ExcalidrawWebView] Failed to parse files JSON: $e');
                }
              }

              // ✅ 标准化 excalidraw -> elements（解析 JSON 字符串为实际数据）
              if (key == 'excalidraw' || key.endsWith('_excalidraw')) {
                if (value is String) {
                  try {
                    final parsed = jsonDecode(value);
                    widget.onDataChanged?.call('update', {'elements': parsed});
                    return;
                  } catch (e) {
                    Log.warn(
                        '⚠️ [ExcalidrawWebView] Failed to parse elements: $e');
                  }
                }
                widget.onDataChanged?.call('update', {'elements': value});
                return;
              }

              // ✅ 标准化 excalidraw-state -> appState（解析 JSON 字符串为实际数据）
              if (key == 'excalidraw-state' ||
                  key.endsWith('_excalidraw-state')) {
                if (value is String) {
                  try {
                    final parsed = _sanitizeAppState(jsonDecode(value));
                    widget.onDataChanged?.call('update', {'appState': parsed});
                    return;
                  } catch (e) {
                    Log.warn(
                        '⚠️ [ExcalidrawWebView] Failed to parse appState: $e');
                  }
                }
                widget.onDataChanged?.call(
                  'update',
                  {'appState': _sanitizeAppState(value)},
                );
                return;
              }

              // 其他键直接传递（如 theme、language 等）
              if (key == 'revision') {
                return;
              }
              final singleEntryMap = {key: value};
              widget.onDataChanged?.call('update', singleEntryMap);
            } else {
              // 防护：不符合预期的结构
              Log.warn(
                  '⚠️ [localStorageOnSet] Unexpected argument structure: $arg');
            }
          }
        });
    controller.addJavaScriptHandler(
        handlerName: 'whiteboardImageSceneSnapshot',
        callback: (args) {
          if (_isDisposed || args.isEmpty || args.first is! Map) {
            return false;
          }
          final snapshot = Map<dynamic, dynamic>.from(args.first as Map);
          final elements = snapshot['elements'];
          final files = snapshot['files'];
          if (elements is! List || files is! Map || files.isEmpty) {
            return false;
          }

          // iOS 原生图片选择器会临时暂停 WebView 的 LocalData 写入。
          // 这个快照来自 Excalidraw onChange，元素和对应 files 必须作为同一
          // 次 Flutter 更新交给本地 Collab，避免第二次选图才补发第一张。
          Log.info(
            '[WBCollab][ExcalidrawWebView] iOS image scene snapshot: elements=${elements.length}, files=${files.length}',
          );
          widget.onDataChanged?.call('update', {
            'elements': List<dynamic>.from(elements),
            'files': Map<String, dynamic>.from(files),
          });
          return true;
        });
    controller.addJavaScriptHandler(
        handlerName: "localStorageOnRemove",
        callback: (args) {
          // debug log removed
        });
    controller.addJavaScriptHandler(
        handlerName: "localStorageOnClear",
        callback: (args) {
          // debug log removed
        });
    // ✅ 关键修复：添加云端图片下载handler
    // 当 JS 端发现文件只有云 URL（没有 base64 dataURL）时，请求 Flutter 下载
    controller.addJavaScriptHandler(
      handlerName: "downloadCloudImages",
      callback: (args) async {
        if (_isDisposed) return [];
        try {
          if (args.isEmpty) return [];
          final cloudFiles = args[0];
          if (cloudFiles is! List) return [];

          Log.info(
              '[WBCollab][ExcalidrawWebView] 📸 downloadCloudImages: ${cloudFiles.length} files to download');

          final results = <Map<String, dynamic>>[];

          // 先过滤出有效项（fileId/url 齐全）
          final validItems = <Map>[];
          for (final item in cloudFiles) {
            if (item is! Map) continue;
            if (item['fileId'] is String && item['url'] is String) {
              validItems.add(item);
            }
          }

          // 并发下载：每批最多 6 张，避免串行逐张等待导致多图白板加载特别慢。
          const concurrency = 6;
          for (var i = 0; i < validItems.length; i += concurrency) {
            final batch = validItems.skip(i).take(concurrency);
            final batchResults = await Future.wait(
              batch.map((item) async {
                final fileId = item['fileId'] as String;
                final url = item['url'] as String;
                final mimeType = item['mimeType'] as String? ?? 'image/png';
                try {
                  // ⚡ 优先读取本地磁盘缓存，命中则直接使用，无需回源云端。
                  final cachedBytes =
                      await WhiteboardImageCacheService().read(fileId);
                  if (cachedBytes != null && cachedBytes.isNotEmpty) {
                    final dataURL =
                        'data:$mimeType;base64,${base64Encode(cachedBytes)}';
                    Log.info(
                        '[ExcalidrawWebView] ⚡ Cache hit for image: $fileId (${cachedBytes.length} bytes)');
                    return <String, dynamic>{
                      'fileId': fileId,
                      'dataURL': dataURL,
                      'mimeType': mimeType,
                      'created': DateTime.now().millisecondsSinceEpoch,
                    };
                  }

                  Log.info(
                      '[WBCollab][ExcalidrawWebView] 📸 Cache miss, downloading cloud image: $fileId from $url');

                  // 使用 HTTP 下载图片（带认证）
                  final imageBytes = await _downloadCloudImage(url);
                  if (imageBytes != null && imageBytes.isNotEmpty) {
                    // ⚡ 下载成功后写入本地缓存，下次加载直接命中。
                    await WhiteboardImageCacheService()
                        .write(fileId, imageBytes);

                    // 转换为 base64 dataURL
                    final base64Data = base64Encode(imageBytes);
                    final dataURL = 'data:$mimeType;base64,$base64Data';

                    Log.info(
                        '[ExcalidrawWebView] ✅ Downloaded cloud image: $fileId (${imageBytes.length} bytes)');
                    return <String, dynamic>{
                      'fileId': fileId,
                      'dataURL': dataURL,
                      'mimeType': mimeType,
                      'created': DateTime.now().millisecondsSinceEpoch,
                    };
                  } else {
                    Log.warn(
                        '[ExcalidrawWebView] ⚠️ Downloaded empty image for: $fileId');
                  }
                } catch (e) {
                  Log.error(
                      '[ExcalidrawWebView] ❌ Failed to download cloud image $fileId: $e');
                }
                return null;
              }),
            );
            results.addAll(batchResults.whereType<Map<String, dynamic>>());
          }

          Log.info(
              '[ExcalidrawWebView] 📸 Downloaded ${results.length}/${cloudFiles.length} cloud images');
          return results;
        } catch (e) {
          Log.error(
              '[ExcalidrawWebView] ❌ downloadCloudImages handler error: $e');
          return [];
        }
      },
    );
    controller.addJavaScriptHandler(
      handlerName: "onExport",
      callback: (args) async {
        if (_isDisposed) return;
        try {
          if (args.isEmpty) return;
          final payload = args[0];
          if (payload is Map &&
              payload.containsKey('format') &&
              payload.containsKey('data')) {
            final format = payload['format'] as String;
            final data = payload['data'];
            widget.onExport?.call(format, data);
          }
        } catch (e) {
          Log.error('[ExcalidrawWebView] onExport handler error: $e');
          widget.onError?.call('导出处理失败: $e');
        }
      },
    );
    controller.addJavaScriptHandler(
      handlerName: "onExportError",
      callback: (args) async {
        if (_isDisposed) return;
        try {
          if (args.isEmpty) return;
          final payload = args[0];
          if (payload is Map && payload.containsKey('message')) {
            final message = payload['message'] as String;
            widget.onError?.call('导出失败: $message');
          }
        } catch (e) {
          Log.error('[ExcalidrawWebView] onExportError handler error: $e');
          widget.onError?.call('导出失败: $e');
        }
      },
    );
  }

  Future<void> _initializeExcalidraw() async {
    if (!mounted || _controller == null || !_webViewCreated) return;
    try {
      // debug logs removed

      // 准备加载的数据（包含viewId）
      Map<String, dynamic> dataToLoad = {};
      if (widget.initialData != null) {
        // 1. 尝试从标准格式加载 (elements, appState, files)
        if (widget.initialData!.containsKey('elements')) {
          dataToLoad['elements'] = widget.initialData!['elements'];
        }
        if (widget.initialData!.containsKey('appState')) {
          dataToLoad['appState'] =
              _sanitizeAppState(widget.initialData!['appState']);
        }
        if (widget.initialData!.containsKey('files')) {
          dataToLoad['files'] = widget.initialData!['files'];
        }

        // 2. 尝试从 LocalStorage 格式加载 (key_excalidraw, key_excalidraw-state, key_excalidraw-files)
        // 这种格式是 WhiteboardDataService 保存的格式
        widget.initialData!.forEach((key, value) {
          if (value is String) {
            try {
              if (key.endsWith('_excalidraw')) {
                dataToLoad['elements'] = jsonDecode(value);
              } else if (key.endsWith('_excalidraw-state')) {
                dataToLoad['appState'] = _sanitizeAppState(jsonDecode(value));
              } else if (key.endsWith('_excalidraw-files')) {
                // 📸 关键修复：从自定义 key 加载 files
                dataToLoad['files'] = jsonDecode(value);
              }
            } catch (e) {
              Log.warn(
                  '⚠️ [ExcalidrawWebView] Failed to parse LS key $key: $e');
            }
          }
        });

        // debug log removed
      } else {
        // debug log removed
      }

      // 🔑 关键：添加 viewId 到数据中
      dataToLoad['viewId'] = widget.viewId;

      final dataJson = jsonEncode(dataToLoad);
      // debug log removed

      /*
      await _controller?.evaluateJavascript(source: '''
        console.log('[ExcalidrawWebView] Loading data into Excalidraw with viewId: ${widget.viewId}');
        if (window.loadExcalidrawData) {
          window.loadExcalidrawData($dataJson);
          console.log('[ExcalidrawWebView] Data loaded successfully');
        } else {
          console.error('[ExcalidrawWebView] window.loadExcalidrawData not found!');
        }
      ''');
      */
      // debug log removed

      // 首先隐藏加载时的底图标志（尽早执行，避免闪现）
      await _hideLoadingLogo();

      // 隐藏主菜单（汉堡菜单）
      await _hideMainMenu();

      // 隐藏欢迎界面和其他不需要的UI元素
      await _hideUnwantedUI();
      await _improveContextMenuTextRendering();

      // 设置主题
      final theme =
          _currentSystemBrightness() == Brightness.dark ? 'dark' : 'light';
      await _syncHostThemeWhenReady(theme);
      // 注入弹性滚动防护 + 诊断
      // 根因分析：macOS 26.x WKWebView 的 NSScrollView 发生弹性回弹（elastic bounce），
      // 使内容视觉上偏右约 32px，但 JS 的 window.scrollX 始终报 0（弹性偏移在 native 层）。
      // 所有 JS 坐标系（clientX、getBoundingClientRect、:hover）均在弹前坐标系中运算，
      // 导致点击/hover 都偏左一位。
      // 修复：CSS overscroll-behavior:none（映射 NSScrollView.elasticity=none）+
      //       initialUserScript 在 document-start 早期生效，阻止弹性回弹产生。
      // 诊断注入仅在 debug 构建启用：clickDiag / scroll / device 日志会在全屏、
      // 侧栏切换时被 focus/mouse/scroll 事件高频触发，经 onConsoleMessage 逐条
      // 跨桥回传，在 Windows 上淹没 Flutter 主线程消息队列
      // （Failed to post message to main thread）。功能性的滚动重置由
      // forceResetScroll + CSS + initialUserScripts 兜底，与此诊断无关。
      if (kDebugMode) {
        await _safeEvalJs(
          '''
        (function() {
          setTimeout(function() {
            // ===== 诊断：设备信息、弹性滚动状态和工具栏按钮位置 =====
            var overscrollVal = getComputedStyle(document.documentElement).overscrollBehavior || 'N/A';
            console.log('[PonyNotes] devicePixelRatio=' + window.devicePixelRatio
              + ' innerWidth=' + window.innerWidth
              + ' scrollX=' + window.scrollX + '/' + document.documentElement.scrollLeft
              + ' overscroll-behavior=' + overscrollVal);
            var labels = document.querySelectorAll('.App-toolbar label.ToolIcon');
            console.log('[PonyNotes] 工具按钮数量=' + labels.length);
            for (var i = 0; i < labels.length; i++) {
              var r = labels[i].getBoundingClientRect();
              var inp = labels[i].querySelector('[data-testid]');
              var tid = inp ? (inp.getAttribute('data-testid') || '?') : '?';
              console.log('[PonyNotes] label[' + i + '] ' + tid + ' x=[' + Math.round(r.left) + ',' + Math.round(r.right) + ']');
            }

            // 强制重置任何残留弹性偏移（overscroll-behavior 阻止新弹性，此处清除旧的）
            window.scrollTo(0, 0);

            // ===== 诊断：点击拦截（60秒），含 scrollX/pageX 对比 =====
            function clickDiag(e) {
              var allLbl = document.querySelectorAll('.App-toolbar label.ToolIcon');
              var tLabel = e.target ? e.target.closest('label.ToolIcon') : null;
              var tInp = tLabel ? tLabel.querySelector('[data-testid]') : null;
              var byTarget = tInp ? tInp.getAttribute('data-testid') : 'none';
              var byRect = 'none';
              for (var j = 0; j < allLbl.length; j++) {
                var lr = allLbl[j].getBoundingClientRect();
                if (e.clientX >= lr.left && e.clientX < lr.right && e.clientY >= lr.top && e.clientY < lr.bottom) {
                  var li = allLbl[j].querySelector('[data-testid]');
                  byRect = li ? li.getAttribute('data-testid') : 'label-' + j;
                  break;
                }
              }
              // pageX - clientX = scrollX；若两者不等说明 JS 层有可见滚动
              console.log('[PonyNotes] CLICK clientX=' + Math.round(e.clientX)
                + ' pageX=' + Math.round(e.pageX)
                + ' scrollX=' + Math.round(window.scrollX)
                + ' byTarget=' + byTarget + ' byRect=' + byRect
                + (byTarget !== byRect ? ' *** MISMATCH' : ''));
            }
            document.addEventListener('pointerdown', clickDiag, true);
            setTimeout(function() { document.removeEventListener('pointerdown', clickDiag, true); }, 60000);

            // 监控 JS 层面可见的滚动（NSScrollView 弹性偏移在此不可见，但作为保底）
            window.addEventListener('scroll', function() {
              if (window.scrollX !== 0 || window.scrollY !== 0) {
                console.log('[PonyNotes] ⚠️ JS滚动: scrollX=' + window.scrollX + ' scrollY=' + window.scrollY + '，已重置');
                window.scrollTo(0, 0);
              }
            }, true);

            console.log('[PonyNotes] 弹性滚动防护 + 诊断已启用（60秒）');
          }, 2500);
        })();
      ''',
          tag: 'overscrollFix',
        );
      }

      // ✅ 关键修复：在初始化完成后立即强制重置滚动偏移
      // 避免 macOS WKWebView 的 NSScrollView 弹性滚动导致的偏移
      await _safeEvalJs('''
        (function() {
          // 日志仅在 debug 构建输出：以下 focus/mouse/可见性/滚动监控会在全屏、
          // 侧栏切换时被高频触发；console 日志经 onConsoleMessage 逐条跨桥回传，
          // 在 Windows 上会淹没 Flutter 主线程消息队列。功能逻辑保持不变。
          const __pnDebug = $kDebugMode;
          // 立即重置滚动偏移
          const resetScroll = function() {
            window.scrollTo(0, 0);
            document.documentElement.scrollLeft = 0;
            document.documentElement.scrollTop = 0;
            document.body.scrollLeft = 0;
            document.body.scrollTop = 0;
            
            // 强制应用 overscroll-behavior: none
            document.documentElement.style.overscrollBehavior = 'none';
            document.documentElement.style.overscrollBehaviorX = 'none';
            document.documentElement.style.overscrollBehaviorY = 'none';
            document.body.style.overscrollBehavior = 'none';
            document.body.style.overscrollBehaviorX = 'none';
            document.body.style.overscrollBehaviorY = 'none';
            
            // 禁止任何滚动
            document.documentElement.style.overflow = 'hidden';
            document.body.style.overflow = 'hidden';
          };
          
          // 立即执行一次
          resetScroll();
          
          // ✅ 高频周期性检测：每 50ms 检查一次，持续 10 秒
          // 防止滚动偏移在后续操作中再次出现（特别是作为子控件时）
          let checkCount = 0;
          const maxChecks = 200; // 200 * 50ms = 10秒
          const scrollWatchdog = setInterval(function() {
            if (checkCount >= maxChecks) {
              clearInterval(scrollWatchdog);
              if (__pnDebug) console.log('[PonyNotes] ✅ 高频滚动监控结束');
              // 切换到低频监控（每 500ms）
              startLowFrequencyWatchdog();
              return;
            }
            
            // 检查是否有意外滚动
            if (window.scrollX !== 0 || window.scrollY !== 0 ||
                document.documentElement.scrollLeft !== 0 ||
                document.documentElement.scrollTop !== 0) {
              resetScroll();
              if (__pnDebug) console.log('[PonyNotes] ⚠️ 高频检测到意外滚动，已重置');
            }
            
            checkCount++;
          }, 50);
          
          // 低频监控（持续运行）
          let lowFrequencyWatchdog = null;
          const startLowFrequencyWatchdog = function() {
            if (lowFrequencyWatchdog) return;
            lowFrequencyWatchdog = setInterval(function() {
              if (window.scrollX !== 0 || window.scrollY !== 0 ||
                  document.documentElement.scrollLeft !== 0 ||
                  document.documentElement.scrollTop !== 0) {
                resetScroll();
                if (__pnDebug) console.log('[PonyNotes] ⚠️ 低频检测到意外滚动，已重置');
              }
            }, 500);
          };
          
          // ✅ 焦点变化时重置滚动
          // 这是解决鼠标在白板区域外移动导致漂移的关键修复
          const onFocusChange = function() {
            resetScroll();
            if (__pnDebug) console.log('[PonyNotes] ⚠️ 焦点变化，重置滚动');
          };
          
          // 监听各种焦点相关事件
          document.addEventListener('focus', onFocusChange, true);
          document.addEventListener('blur', onFocusChange, true);
          document.addEventListener('focusin', onFocusChange, true);
          document.addEventListener('focusout', onFocusChange, true);
          
          // ✅ 鼠标进入/离开时重置滚动
          document.addEventListener('mouseenter', onFocusChange, true);
          document.addEventListener('mouseleave', onFocusChange, true);
          
          // ✅ 窗口获得/失去焦点时重置滚动
          window.addEventListener('focus', onFocusChange);
          window.addEventListener('blur', onFocusChange);
          
          // ✅ 页面可见性变化时重置滚动
          document.addEventListener('visibilitychange', function() {
            resetScroll();
            if (__pnDebug) console.log('[PonyNotes] ⚠️ 页面可见性变化，重置滚动');
          });
          
          // 保存到全局，便于调试
          window._ponynotesScrollWatchdog = scrollWatchdog;
          window._ponynotesLowFrequencyWatchdog = lowFrequencyWatchdog;
          window._ponynotesResetScroll = resetScroll;
          window._ponynotesOnFocusChange = onFocusChange;

          if (__pnDebug) console.log('[PonyNotes] ✅ 初始化完成，强制重置滚动偏移，启动滚动监控');
        })();
      ''', tag: 'forceResetScroll');

      // 数据恢复可能携带旧的 appState.theme，在初始化最后再覆盖一次，确保
      // 私有空间白板不会因协作数据回放而回到浅色；同时迁移旧版本写入的
      // #121212 场景背景，避免与 Excalidraw 深色滤镜叠加后变成白色。
      final finalTheme = _pendingHostTheme ?? theme;
      await _syncHostThemeWhenReady(finalTheme);

      // debug log removed
    } catch (e) {
      Log.error('❌ [ExcalidrawWebView] Initialization failed: $e');
      widget.onError?.call('初始化Excalidraw失败: $e');
    }
  }

  /// 主动清除 Excalidraw 工具栏的 hover 状态。
  ///
  /// 触发场景：鼠标在外层 Flutter 视图快速移动时，由于 macOS WKWebView 的
  /// NSScrollView 弹性偏移和 PlatformView 事件转发延迟，工具栏按钮的 CSS
  /// :hover 状态可能粘滞未清除。此方法在鼠标离开 WebView 区域时由
  /// MouseRegion.onExit 触发，通过 JS 临时禁用工具栏 pointer-events
  /// 强制浏览器清除 :hover 状态，下一帧恢复以确保鼠标重新进入时能正常 hover。
  Future<void> _clearToolbarHover() async {
    if (_isDisposed || !mounted || _controller == null) return;
    await _safeEvalJs(
      '''
        (function() {
          var toolbar = document.querySelector('.App-toolbar');
          if (!toolbar) return;
          // 临时禁用 pointer-events，让浏览器立即清除 :hover 状态
          // （pointer-events: none 的元素不会被 hit-test 命中，:hover 自动失效）
          toolbar.style.setProperty('pointer-events', 'none', 'important');
          // 强制 reflow，确保样式同步生效
          void toolbar.offsetHeight;
          // 下一帧恢复，确保鼠标重新进入工具栏时能正常触发 hover
          requestAnimationFrame(function() {
            requestAnimationFrame(function() {
              toolbar.style.setProperty('pointer-events', '');
            });
          });
        })();
      ''',
      tag: 'clearToolbarHover',
      maxAttempts: 1,
      logFailures: false,
    );
  }

  /// 隐藏Excalidraw主菜单
  /// 重要：使用精确选择器，避免影响工具栏按钮
  Future<void> _hideMainMenu() async {
    // 使用CSS和JavaScript隐藏主菜单
    await _safeEvalJs('''
      (function() {
        // 注入CSS隐藏菜单 - 使用精确的类名选择器
        const style = document.createElement('style');
        style.id = 'ponynotes-hide-menu-style';
        style.textContent = `
          /* 隐藏主菜单按钮 - 精确匹配 */
          .main-menu-trigger,
          [data-testid="main-menu-trigger"] {
            display: none !important;
            visibility: hidden !important;
          }
          
          /* 隐藏菜单容器 */
          .main-menu-dropdown {
            display: none !important;
          }

          /* 白板主题强制跟随宿主系统，隐藏 Excalidraw 内置主题切换项。 */
          [data-testid="toggle-dark-mode"],
          [data-testid="toggle-theme"],
          .dropdown-menu-item[data-testid*="theme"],
          .dropdown-menu-item-base:has(input[name="theme"]) {
            display: none !important;
            visibility: hidden !important;
            pointer-events: none !important;
          }
        `;
        
        document.head.appendChild(style);
        
        // 隐藏主菜单的函数
        const hideMainMenu = () => {
          // 只使用精确的选择器
          document.querySelectorAll('.main-menu-trigger, [data-testid="main-menu-trigger"]').forEach(trigger => {
            trigger.style.display = 'none';
            trigger.style.visibility = 'hidden';
          });
          
          document.querySelectorAll('.main-menu-dropdown').forEach(container => {
            container.style.display = 'none';
          });

          document.querySelectorAll('[data-testid="toggle-dark-mode"], [data-testid="toggle-theme"], .dropdown-menu-item').forEach(item => {
            const text = (item.textContent || '').toLowerCase();
            const label = (item.getAttribute('aria-label') || '').toLowerCase();
            if (text.includes('dark mode') || text.includes('light mode') ||
                text.includes('system mode') || text.includes('主题') ||
                text.includes('模式') || label.includes('theme') ||
                label.includes('mode')) {
              item.style.display = 'none';
              item.style.visibility = 'hidden';
              item.style.pointerEvents = 'none';
            }
          });

          // 移动端主题菜单使用 input[name="theme"] 单选组，没有主题按钮的
          // data-testid；隐藏其整行并拦截 change，避免用户改写宿主系统主题。
          document.querySelectorAll('input[name="theme"]').forEach(input => {
            const item = input.closest('.dropdown-menu-item-base') || input.parentElement?.parentElement;
            if (item) {
              item.style.display = 'none';
              item.style.visibility = 'hidden';
              item.style.pointerEvents = 'none';
            }
            if (!input.dataset.ponynotesThemeGuarded) {
              input.dataset.ponynotesThemeGuarded = 'true';
              input.addEventListener('change', event => {
                event.preventDefault();
                event.stopImmediatePropagation();
              }, true);
            }
          });
        };
        
        // 初始执行
        hideMainMenu();
        
        // 使用防抖的 MutationObserver
        let debounceTimer = null;
        const debouncedHide = () => {
          if (debounceTimer) {
            clearTimeout(debounceTimer);
          }
          debounceTimer = setTimeout(hideMainMenu, 100);
        };
        
        const observer = new MutationObserver(debouncedHide);
        
        // 只观察 body 的直接子元素变化
        observer.observe(document.body, {
          childList: true,
          subtree: false
        });
        
        // 延迟执行
        setTimeout(hideMainMenu, 100);
        setTimeout(hideMainMenu, 300);
        
        // 保存observer到window
        window._ponynotesMenuObserver = observer;
      })();
    ''', tag: 'hideMainMenu');
  }

  /// 隐藏不需要的UI元素（欢迎界面、Excalidraw+按钮、帮助按钮等）
  /// 重要：此方法已优化，避免使用过于宽泛的选择器影响工具栏按钮的点击区域
  Future<void> _hideUnwantedUI() async {
    await _safeEvalJs('''
      (function() {
        // 注入CSS隐藏不需要的UI元素
        // 重要：使用精确选择器，避免影响工具栏中的绘图工具按钮
        const style = document.createElement('style');
        style.id = 'ponynotes-hide-ui-style';
        style.textContent = `
          /* 隐藏欢迎界面 - 不影响工具栏 */
          .welcome-screen:not(.App-toolbar *),
          .welcome-screen-center:not(.App-toolbar *) {
            display: none !important;
            visibility: hidden !important;
          }
          
          /* 隐藏Excalidraw+按钮和横幅 */
          .plus-banner,
          [href*="excalidraw.com/plus"],
          a[href*="/plus"] {
            display: none !important;
            visibility: hidden !important;
          }
          
          /* 隐藏帮助按钮 - 精确匹配，不影响工具栏 */
          .HelpButton,
          button.help-icon,
          [data-testid="help-icon"] {
            display: none !important;
            visibility: hidden !important;
          }
          
          /* 隐藏实时协作按钮 - 精确匹配 */
          .collab-button,
          [data-testid="collab-button"] {
            display: none !important;
            visibility: hidden !important;
          }
          
          /* 隐藏素材库按钮 - 使用精确的类名选择器 */
          .default-sidebar-trigger,
          .sidebar-trigger,
          label.sidebar-trigger__label-element {
            display: none !important;
            visibility: hidden !important;
          }
          
          /* 确保工具栏及可见按钮响应点击。
             重要：不对 .App-toolbar * 全量设置 pointer-events: auto，
             否则会误启用工具按钮内部隐藏的 <input type="radio">（.ToolIcon_type_radio）
             的点击响应，导致鼠标点击工具时选中相邻工具（偏移一位）。 */
          .App-toolbar {
            pointer-events: auto !important;
          }
          .App-toolbar label.ToolIcon,
          .App-toolbar .ToolIcon__icon,
          .App-toolbar button,
          .App-toolbar .DropdownMenu-trigger {
            pointer-events: auto !important;
          }
          /* 明确保持隐藏 radio/checkbox input 的 pointer-events: none */
          .App-toolbar .ToolIcon_type_radio,
          .App-toolbar .ToolIcon_type_checkbox {
            pointer-events: none !important;
          }

          .App-toolbar {
            min-height: 49px !important;
            padding: 7px 11px !important;
            gap: 7px !important;
            align-items: center !important;
            background: rgba(255, 255, 255, 0.96) !important;
            border-bottom: 1px solid rgba(17, 24, 39, 0.08) !important;
            box-shadow: 0 8px 20px rgba(15, 23, 42, 0.06) !important;
          }

          .excalidraw.theme--dark .App-toolbar {
            background: rgba(35, 35, 41, 0.96) !important;
            border-bottom-color: rgba(255, 255, 255, 0.12) !important;
            box-shadow: 0 8px 20px rgba(0, 0, 0, 0.24) !important;
          }
          
          /* 确保工具栏按钮可以正常点击 */
          .App-toolbar .ToolIcon,
          .App-toolbar .Shape,
          .App-toolbar label.ToolIcon {
            pointer-events: auto !important;
            display: inline-flex !important;
            visibility: visible !important;
            opacity: 1 !important;
            min-width: 30px !important;
            min-height: 30px !important;
            border-radius: 7px !important;
            align-items: center !important;
            justify-content: center !important;
          }

          .App-toolbar svg {
            width: 15px !important;
            height: 15px !important;
          }

          html,
          body,
          #root,
          .excalidraw,
          .excalidraw-container {
            width: 100% !important;
            height: 100% !important;
          }
          /* 防止页面滚动及 NSScrollView 弹性回弹（macOS WKWebView 特有）
             overscroll-behavior:none 会映射到 NSScrollView.horizontalScrollElasticity=.none
             从而消除弹性偏移导致的点击坐标与视觉位置不一致 */
          html, body {
            overflow: hidden !important;
            overscroll-behavior: none !important;
            scroll-behavior: auto !important;
          }
        `;
        
        // 如果样式已存在，先移除
        const existingStyle = document.getElementById('ponynotes-hide-ui-style');
        if (existingStyle) {
          existingStyle.remove();
        }
        
        document.head.appendChild(style);
        
        // 精确隐藏素材库按钮的函数
        const hideLibraryButton = () => {
          // 只使用精确的类名选择器，避免影响其他按钮
          const librarySelectors = [
            '.default-sidebar-trigger',
            '.sidebar-trigger',
            'label.sidebar-trigger__label-element'
          ];
          
          librarySelectors.forEach(selector => {
            try {
              const elements = document.querySelectorAll(selector);
              elements.forEach(el => {
                el.style.display = 'none';
                el.style.visibility = 'hidden';
              });
            } catch (e) {
              // 忽略选择器错误
            }
          });
        };
        
        // 隐藏不需要元素的函数（不使用 MutationObserver 持续监听，避免干扰点击事件）
        const hideElements = () => {
          // 隐藏欢迎界面（确保不影响工具栏）
          document.querySelectorAll('.welcome-screen, .welcome-screen-center').forEach(el => {
            if (!el.closest('.App-toolbar')) {
              el.style.display = 'none';
              el.style.visibility = 'hidden';
            }
          });
          
          // 隐藏Excalidraw+按钮
          document.querySelectorAll('.plus-banner, a[href*="/plus"]').forEach(el => {
            el.style.display = 'none';
            el.style.visibility = 'hidden';
          });
          
          // 隐藏实时协作按钮
          document.querySelectorAll('.collab-button, [data-testid="collab-button"]').forEach(el => {
            el.style.display = 'none';
            el.style.visibility = 'hidden';
          });
          
          // 隐藏素材库按钮
          hideLibraryButton();
        };
        
        // 初始执行一次
        hideElements();
      })();
    ''', tag: 'hideUnwantedUI');
  }

  /// 优化右键菜单中文渲染；Improve Excalidraw context-menu text rendering.
  Future<void> _improveContextMenuTextRendering() async {
    final isWindows = defaultTargetPlatform == TargetPlatform.windows;
    final menuFontFamily = isWindows
        ? '"Segoe UI", "Microsoft YaHei UI", "Microsoft YaHei", '
            '"Noto Sans CJK SC", "Source Han Sans SC", sans-serif'
        : '-apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", '
            '"Noto Sans CJK SC", "Source Han Sans SC", sans-serif';
    final fontSmoothing = isWindows ? 'antialiased' : 'antialiased';
    final mozFontSmoothing = isWindows ? 'grayscale' : 'grayscale';
    final textRendering =
        isWindows ? 'geometricPrecision' : 'optimizeLegibility';
    final menuFontSize = isWindows ? '15' : '13';
    final shortcutFontSize = isWindows ? '13' : '11';
    final menuFontWeight = isWindows ? 600 : 500;
    final shortcutFontWeight = isWindows ? 500 : 500;

    await _safeEvalJs(
      '''
      (function() {
        const style = document.createElement('style');
        style.id = 'ponynotes-context-menu-font-style';
        style.textContent = `
          .excalidraw,
          .excalidraw .context-menu,
          .excalidraw [role="menu"] {
            --ui-font: $menuFontFamily !important;
          }

          .excalidraw .context-menu,
          .excalidraw .context-menu *,
          .excalidraw [role="menu"],
          .excalidraw [role="menu"] *,
          .excalidraw .context-menu-item,
          .excalidraw .context-menu-item *,
          .excalidraw .context-menu-item__label,
          .excalidraw .context-menu-item__shortcut {
            font-family: $menuFontFamily !important;
            -webkit-font-smoothing: $fontSmoothing !important;
            -moz-osx-font-smoothing: $mozFontSmoothing !important;
            text-rendering: $textRendering !important;
            font-synthesis: none !important;
            font-kerning: normal !important;
            letter-spacing: 0 !important;
          }

          .excalidraw .context-menu,
          .excalidraw [role="menu"] {
            filter: none !important;
            backdrop-filter: none !important;
            -webkit-backdrop-filter: none !important;
            opacity: 1 !important;
            backface-visibility: visible !important;
            perspective: none !important;
            will-change: auto !important;
            contain: none !important;
            transform-style: flat !important;
          }

          .excalidraw .context-menu,
          .excalidraw [role="menu"] {
            border: 1px solid rgba(90, 104, 122, 0.32) !important;
            box-shadow: 0 10px 24px rgba(15, 23, 42, 0.18) !important;
            background-clip: padding-box !important;
          }

          .excalidraw .popover.context-menu-popover,
          .excalidraw .context-menu-popover,
          .excalidraw .Island:has(.context-menu) {
            background: transparent !important;
            border: none !important;
            box-shadow: none !important;
            width: auto !important;
            height: auto !important;
            min-width: 0 !important;
            min-height: 0 !important;
          }

          .excalidraw .context-menu-item {
            font-size: ${menuFontSize}px !important;
            line-height: 1.45 !important;
            font-weight: $menuFontWeight !important;
            min-height: 30px !important;
            color: rgba(17, 24, 39, 0.96) !important;
            text-shadow: none !important;
          }

          .excalidraw .context-menu-item .context-menu-item__shortcut {
            font-size: ${shortcutFontSize}px !important;
            font-weight: $shortcutFontWeight !important;
            color: rgba(55, 65, 81, 0.88) !important;
          }

          .excalidraw.theme--dark .context-menu-item {
            color: rgba(243, 244, 246, 0.96) !important;
          }

          .excalidraw.theme--dark .context-menu-item .context-menu-item__shortcut {
            color: rgba(209, 213, 219, 0.88) !important;
          }
        `;

        const existingStyle =
          document.getElementById('ponynotes-context-menu-font-style');
        if (existingStyle) {
          existingStyle.remove();
        }

        document.head.appendChild(style);

        const menuSelectors = [
          '.excalidraw .context-menu',
          '.excalidraw [role="menu"]',
        ];

        const snapContextMenuToPixels = () => {
          const menus = document.querySelectorAll(menuSelectors.join(','));
          for (const menu of menus) {
            const computed = window.getComputedStyle(menu);
            if (computed.display === 'none' || computed.visibility === 'hidden') {
              continue;
            }

            const dpr = Math.max(1, window.devicePixelRatio || 1);
            const snap = (value) => Math.round(value * dpr) / dpr;
            const left = parseFloat(menu.style.left || computed.left);
            const top = parseFloat(menu.style.top || computed.top);
            if (Number.isFinite(left) && computed.position !== 'static') {
              menu.style.setProperty('left', snap(left) + 'px', 'important');
            }
            if (Number.isFinite(top) && computed.position !== 'static') {
              menu.style.setProperty('top', snap(top) + 'px', 'important');
            }

            if (computed.transform && computed.transform !== 'none') {
              try {
                const matrix = new DOMMatrixReadOnly(computed.transform);
                const roundedX = snap(matrix.m41);
                const roundedY = snap(matrix.m42);
                menu.style.setProperty(
                  'transform',
                  `matrix(\${matrix.a}, \${matrix.b}, \${matrix.c}, \${matrix.d}, \${roundedX}, \${roundedY})`,
                  'important',
                );
              } catch (_) {
                // Keep the original transform if the browser cannot parse it.
              }
            }

            menu.style.setProperty('filter', 'none', 'important');
            menu.style.setProperty('backdrop-filter', 'none', 'important');
            menu.style.setProperty('-webkit-backdrop-filter', 'none', 'important');
            menu.style.setProperty('will-change', 'auto', 'important');
            menu.style.setProperty('contain', 'none', 'important');
            menu.style.setProperty('translate', 'none', 'important');
          }
        };

        const scheduleSnap = () => {
          cancelAnimationFrame(window.__ponynotesContextMenuSnapFrame);
          window.__ponynotesContextMenuSnapFrame =
            requestAnimationFrame(snapContextMenuToPixels);
          setTimeout(snapContextMenuToPixels, 40);
          setTimeout(snapContextMenuToPixels, 120);
        };

        if (window.__ponynotesContextMenuObserver) {
          window.__ponynotesContextMenuObserver.disconnect();
        }
        window.__ponynotesContextMenuObserver =
          new MutationObserver(scheduleSnap);
        window.__ponynotesContextMenuObserver.observe(document.body, {
          childList: true,
          subtree: true,
          attributes: true,
          attributeFilter: ['class', 'style'],
        });

        document.removeEventListener(
          'contextmenu',
          window.__ponynotesContextMenuSnapHandler || scheduleSnap,
          true,
        );
        window.__ponynotesContextMenuSnapHandler = scheduleSnap;
        document.addEventListener('contextmenu', scheduleSnap, true);
        scheduleSnap();
      })();
    ''',
      tag: 'improveContextMenuTextRendering',
    );
  }

  Future<void> _hideLoadingLogo() async {
    await _safeEvalJs('''
      (function() {
        // 立即注入CSS，在DOM加载前就隐藏
        const style = document.createElement('style');
        style.id = 'ponynotes-hide-loading-logo';
        style.textContent = `
          /* 只隐藏欢迎界面中心的LOGO和文字，不隐藏工具栏 */
          .welcome-screen-center,
          [class*="WelcomeScreen.Center"],
          [class*="welcome-screen-center"],
          .welcome-screen-center *,
          [class*="WelcomeScreen.Center"] * {
            display: none !important;
            visibility: hidden !important;
          }
          
          /* 确保工具栏始终显示。
             注意：只精确匹配 .App-toolbar，不使用 [class*="App-toolbar"]
             （会误匹配 App-toolbar-container 并破坏其 grid 布局），
             也不使用 [data-testid*="toolbar"]（会误匹配工具按钮内部
             隐藏的 <input type="radio"> 元素）。 */
          .App-toolbar {
            display: flex !important;
            visibility: visible !important;
          }
        `;

        // 如果样式已存在，先移除
        const existingStyle = document.getElementById('ponynotes-hide-loading-logo');
        if (existingStyle) {
          existingStyle.remove();
        }

        // 立即插入到head，确保尽早生效
        if (document.head) {
          document.head.appendChild(style);
        } else {
          // 如果head还没准备好，等待DOMContentLoaded
          document.addEventListener('DOMContentLoaded', () => {
            document.head.appendChild(style);
          });
        }

        // 隐藏欢迎界面中心的函数
        const hideWelcomeCenter = () => {
          document.querySelectorAll('.welcome-screen-center').forEach(el => {
            if (!el.closest('.App-toolbar')) {
              el.style.display = 'none';
              el.style.visibility = 'hidden';
            }
          });
        };

        // 立即执行
        hideWelcomeCenter();
        
        // 使用防抖的 MutationObserver，减少触发频率
        let debounceTimer = null;
        const debouncedHide = () => {
          if (debounceTimer) {
            clearTimeout(debounceTimer);
          }
          debounceTimer = setTimeout(hideWelcomeCenter, 50);
        };
        
        const observer = new MutationObserver(debouncedHide);

        // 只观察 body 的直接子元素变化，减少触发频率
        observer.observe(document.body || document.documentElement, {
          childList: true,
          subtree: false
        });
        
        // 延迟执行，确保捕获动态创建的元素
        setTimeout(hideWelcomeCenter, 100);
        setTimeout(hideWelcomeCenter, 300);

        window._ponynotesLoadingObserver = observer;
      })();
    ''', tag: 'hideLoadingLogo');
  }

  /// ✅ 关键修复：标准化数据键名
  /// 将 localStorage 原始键名转换为标准键名，避免重复存储
  /// excalidraw -> elements, excalidraw-state -> appState, excalidraw-files -> files
  /// ⚡ 用本地磁盘缓存补全 files 的 dataURL（仅用于返回给 JS 的 payload）。
  /// 对"只有云 url、无 dataURL"的图片，查本地缓存命中则注入 dataURL，
  /// 使 flutter_bridge.js 走 addFiles 直显，省去 downloadCloudImages 网络往返。
  /// 读盘 + base64 编码远快于网络下载；未命中的图片保持原样，仍由 JS 兜底下载。
  Future<Map<String, dynamic>> _enrichFilesWithCache(
    Map<String, dynamic> normalizedData,
  ) async {
    try {
      final files = normalizedData['files'];
      if (files is! Map || files.isEmpty) {
        return normalizedData;
      }

      final enrichedFiles = <String, dynamic>{};
      var hitCount = 0;
      await Future.wait(
        files.entries.map((entry) async {
          final fileId = entry.key.toString();
          final fileData = entry.value;
          if (fileData is! Map) {
            enrichedFiles[fileId] = fileData;
            return;
          }
          final map = Map<String, dynamic>.from(fileData);
          final dataURL = map['dataURL'];
          final hasDataUrl = dataURL is String && dataURL.startsWith('data:');
          final url = map['url'];
          final hasCloudUrl = url is String && url.startsWith('http');

          if (!hasDataUrl && hasCloudUrl) {
            final cached = await WhiteboardImageCacheService().read(fileId);
            if (cached != null && cached.isNotEmpty) {
              final mimeType = map['mimeType'] as String? ?? 'image/png';
              map['dataURL'] = 'data:$mimeType;base64,${base64Encode(cached)}';
              hitCount++;
            }
          }
          enrichedFiles[fileId] = map;
        }),
      );

      if (hitCount > 0) {
        Log.info(
            '[WBCollab][ExcalidrawWebView] ⚡ initData cache-injected $hitCount/${files.length} images (no network)');
      }

      final result = Map<String, dynamic>.from(normalizedData);
      result['files'] = enrichedFiles;
      return result;
    } catch (e) {
      Log.warn('[ExcalidrawWebView] _enrichFilesWithCache failed: $e');
      return normalizedData;
    }
  }

  Map<String, dynamic> _normalizeDataKeys(Map<String, dynamic> data) {
    final normalized = <String, dynamic>{};

    for (final entry in data.entries) {
      final key = entry.key;
      final value = entry.value;

      if (key == 'excalidraw' || key.endsWith('_excalidraw')) {
        // excalidraw -> elements（如果 elements 键已存在且有效，跳过）
        if (!normalized.containsKey('elements') ||
            (normalized['elements'] is List &&
                (normalized['elements'] as List).isEmpty)) {
          if (value is String) {
            try {
              normalized['elements'] = jsonDecode(value);
            } catch (e) {
              normalized['elements'] = value;
            }
          } else {
            normalized['elements'] = value;
          }
        }
      } else if (key == 'excalidraw-state' ||
          key.endsWith('_excalidraw-state')) {
        // excalidraw-state -> appState
        if (!normalized.containsKey('appState') ||
            (normalized['appState'] is Map &&
                (normalized['appState'] as Map).isEmpty)) {
          if (value is String) {
            try {
              normalized['appState'] = _sanitizeAppState(jsonDecode(value));
            } catch (e) {
              normalized['appState'] = _sanitizeAppState(value);
            }
          } else {
            normalized['appState'] = _sanitizeAppState(value);
          }
        }
      } else if (key == 'excalidraw-files' ||
          key.endsWith('_excalidraw-files')) {
        // excalidraw-files -> files
        if (!normalized.containsKey('files') ||
            (normalized['files'] is Map &&
                (normalized['files'] as Map).isEmpty)) {
          if (value is String) {
            try {
              normalized['files'] = jsonDecode(value);
            } catch (e) {
              normalized['files'] = value;
            }
          } else {
            normalized['files'] = value;
          }
        }
      } else if (key == 'elements' || key == 'appState' || key == 'files') {
        // 标准键名直接使用（优先级高于 localStorage 键名）
        if (value is String &&
            (key == 'elements' || key == 'appState' || key == 'files')) {
          try {
            final parsed = jsonDecode(value);
            normalized[key] =
                key == 'appState' ? _sanitizeAppState(parsed) : parsed;
          } catch (e) {
            normalized[key] =
                key == 'appState' ? _sanitizeAppState(value) : value;
          }
        } else {
          normalized[key] =
              key == 'appState' ? _sanitizeAppState(value) : value;
        }
      } else {
        // 其他键直接保留
        normalized[key] = value;
      }
    }

    return normalized;
  }

  Map<String, dynamic> _sanitizeAppState(dynamic value) {
    if (value is! Map) {
      return <String, dynamic>{};
    }

    final source = Map<String, dynamic>.from(value);
    final sanitized = <String, dynamic>{};
    for (final key in _stableAppStateKeys) {
      if (source.containsKey(key)) {
        sanitized[key] = source[key];
      }
    }
    return sanitized;
  }

  Future<Uint8List?> _downloadCloudImage(String url) async {
    try {
      final token = await FileUploadService.getValidAccessToken();

      final response = await http.get(
        Uri.parse(url),
        headers: token.isNotEmpty ? {'Authorization': 'Bearer $token'} : {},
      );

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        Log.warn(
            '[ExcalidrawWebView] ⚠️ Token expired (${response.statusCode}), refreshing and retrying...');
        final freshToken = await FileUploadService.forceRefreshAccessToken();
        if (freshToken != null && freshToken.isNotEmpty) {
          final retryResponse = await http.get(
            Uri.parse(url),
            headers: {'Authorization': 'Bearer $freshToken'},
          );
          if (retryResponse.statusCode == 200) {
            Log.info(
                '[ExcalidrawWebView] ✅ Cloud image downloaded after token refresh');
            return retryResponse.bodyBytes;
          }
          Log.error(
              '[ExcalidrawWebView] ❌ Retry failed: ${retryResponse.statusCode}');
        }
      }

      Log.error(
          '[ExcalidrawWebView] ❌ Cloud image download failed: ${response.statusCode} for $url');
      return null;
    } catch (e) {
      Log.error('[ExcalidrawWebView] ❌ Cloud image download error: $e');
      return null;
    }
  }

  @override
  void dispose() {
    // ⚠️ 不要停止本地HTTP服务器！
    // LocalAssetServer是单例，被所有白板视图共享
    // 如果在这里stop()，会导致其他白板视图的服务器也被停止
    // 服务器应该在应用关闭时统一清理，而不是在每个Widget dispose时
    // _assetServer.stop(); // ❌ 这会导致切换白板时服务器被停止

    _isDisposed = true;
    _webViewCreated = false;
    _pageLoaded = false;
    _webViewResizeSettleTimer?.cancel();
    _webViewResizeSettleTimer = null;
    _pendingWebViewSize = null;
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      // 【macOS 切换文档崩溃修复 2026-07-29】
      // 根因：flutter_inappwebview_macos 的 WebViewChannelDelegate.handle() 在
      // 原生 webView weak 引用变 nil 时仍被 MethodChannel 调用，导致空指针解引用。
      // 原实现将 JS handler 移除放在延迟 100ms 的 teardownController 中，导致在这
      // 100ms 窗口内 JS 端仍可通过 callHandler 触发 MethodChannel 消息，而此时原生
      // webView 可能已被系统回收 → 崩溃。
      //
      // 修复：将 JS handler 移除提到 dispose 中立即（同步）执行，切断 JS → Flutter
      // 的 MethodChannel 调用路径。配合 _isDisposed=true（阻断 _safeEvalJs 新发起
      // evaluateJavascript）和 _controller=null（阻断外部 pushData 等调用），延迟
      // 窗口内唯一残留的 MethodChannel 消息来源是正在 await 中的 evaluateJavascript，
      // 该路径概率极低且无法从 Dart 侧取消，但移除 handler 后整体崩溃概率大幅下降。
      for (final handlerName in _javaScriptHandlerNames) {
        try {
          controller.removeJavaScriptHandler(handlerName: handlerName);
        } catch (_) {
          // Controller may already be disposed by the platform view.
        }
      }

      // 【纹理销毁竞态加固 2026-07-20】原实现在 dispose 内同步销毁原生 controller。
      // Windows 上引擎光栅线程可能仍在把本 WebView 的 D3D 外部纹理绘制到最后一帧，
      // 同帧销毁纹理会触发 ExternalTextureD3d::PopulateTexture 抛 C++ 异常 →
      // noexcept 边界 → std::terminate → 0xC0000409 闪退（PonyNotes.exe.28208.dmp
      // 崩溃栈实锤）。改为等本帧渲染完成后再延迟一小段销毁：widget 已从树上摘除、
      // 后续帧不会再引用该纹理，延迟销毁即可避开竞态。controller.dispose 幂等
      // （插件在 platform view teardown 时也会销毁），双重销毁已由 try/catch 兜底。
      //
      // 注意：handler 已在上面同步移除，此处 teardownController 仅负责 dispose。
      void teardownController() {
        try {
          controller.dispose();
        } catch (_) {
          // InAppWebView also disposes its controller during platform view teardown.
        }
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future<void>.delayed(
          const Duration(milliseconds: 100),
          teardownController,
        );
      });
    }

    final initializationCompleter = _initializationCompleter;
    if (initializationCompleter != null &&
        !initializationCompleter.isCompleted) {
      initializationCompleter.complete();
    }
    _initializationCompleter = null;

    super.dispose();
  }

  /// 导出绘图
  Future<void> exportDrawing(String format) async {
    try {
      await _safeEvalJs('''
        if (window.exportExcalidraw) {
          window.exportExcalidraw('$format');
        }
      ''', tag: 'export($format)');
    } catch (e) {
      widget.onError?.call('导出失败: $e');
    }
  }

  /// 清空画布
  Future<void> clearCanvas() async {
    try {
      await _safeEvalJs('''
        if (window.clearCanvas) {
          window.clearCanvas();
        }
      ''', tag: 'clearCanvas');
    } catch (e) {
      widget.onError?.call('清空画布失败: $e');
    }
  }

  /// 撤销操作
  Future<void> undo() async {
    try {
      await _safeEvalJs('''
        if (window.undo) {
          window.undo();
        }
      ''', tag: 'undo');
    } catch (e) {
      widget.onError?.call('撤销失败: $e');
    }
  }

  /// 重做操作
  Future<void> redo() async {
    try {
      await _safeEvalJs('''
        if (window.redo) {
          window.redo();
        }
      ''', tag: 'redo');
    } catch (e) {
      widget.onError?.call('重做失败: $e');
    }
  }

  /// 更新主题（公共方法，供外部调用）
  Future<void> updateTheme(String theme) async {
    try {
      await _syncHostThemeWhenReady(theme);
    } catch (e) {
      widget.onError?.call('更新主题失败: $e');
    }
  }

  /// 进入/退出只读浏览模式（公共方法，供外部调用）。
  ///
  /// 用于「断网离线只读镜像」场景：以 Excalidraw viewMode 渲染本地镜像，
  /// 禁止编辑、仅保留浏览与缩放。直接调用 Excalidraw API 的 updateScene，
  /// 绕过只保留稳定键的 pickStableAppState，确保 viewModeEnabled 生效。
  Future<void> setViewMode(bool enabled) async {
    try {
      await _safeEvalJs('''
        (function() {
          var api = window._excalidrawAPI || window.excalidrawAPI || window.__EXCALIDRAW_API__;
          if (api && typeof api.updateScene === 'function') {
            api.updateScene({ appState: { viewModeEnabled: $enabled }, commitToHistory: false });
          }
        })();
      ''', tag: 'setViewMode($enabled)');
    } catch (e) {
      Log.warn('[ExcalidrawWebView] setViewMode 失败: $e');
    }
  }

  /// 加载数据（公共方法，供外部调用）
  /// 注意：此方法会重置整个场景
  Future<void> loadData(
    Map<String, dynamic> data, {
    bool preserveLocalSceneForBlankData = false,
  }) async {
    try {
      if (mounted) {
        setState(() => _isInitializing = true);
      }
      // 先沿用原有就绪重试，确保异步信箱只在页面脚本和 WebView 通道可用后启动。
      await _safeEvalJs(
        '''
          if (!window.loadExcalidrawData) {
            throw new Error('loadExcalidrawData is not ready');
          }
        ''',
        tag: 'loadData readiness',
      );
      // 必须等待 JS 侧异步恢复完成。此前这里只启动 Promise 就立即返回，
      // 用户在初始数据迟到期间插入的图片可能随后被旧场景 updateScene 覆盖。
      await evaluateAsyncJavascript(
        _controller!,
        asyncBody: '''
          if (window.loadExcalidrawData) {
            await window.loadExcalidrawData(${jsonEncode(data)}, {
              preserveLocalSceneForBlankData: $preserveLocalSceneForBlankData
            });
          }
          return true;
        ''',
        timeout: const Duration(seconds: 10),
        isCancelled: () => _isDisposed || !mounted,
        debugLabel: ' loadData view=${widget.viewId}',
      );

      // 加载数据后重新初始化UI，确保工具栏等元素正确显示
      await reinitializeUI();
    } catch (e) {
      widget.onError?.call('加载数据失败: $e');
    } finally {
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    }
  }

  void _notifyInitialReadyOnce() {
    if (_initialReadyNotified || _isDisposed) {
      return;
    }

    _initialReadyNotified = true;
    widget.onInitialReady?.call();
  }

  /// 推送数据（公共方法，供外部调用）
  /// 用于实时、增量的同步变更（不刷新页面）
  Future<void> pushData(String key, dynamic value) async {
    if (!mounted || _controller == null) return;

    try {
      if (key == WhiteboardCollabAdapter.whiteboardElementsDeltaKey) {
        if (value is Map) {
          await pushWhiteboardElements(
            List<dynamic>.from(value['changed'] as List? ?? const []),
            fallbackElements: value['elements'],
          );
        } else if (value is List) {
          await pushWhiteboardElements(value);
        }
        return;
      }

      // ✅ 关键：包装为 {key, value} 结构，与 JS 接口匹配
      if (key == 'appState') {
        value = _sanitizeAppState(value);
        if (value.isEmpty) {
          return;
        }
      }

      final pushPayload = {
        'key': key,
        'value': value,
      };

      await _safeEvalJs('''
        if (window.pushWhiteboardData) {
          window.pushWhiteboardData(${jsonEncode(pushPayload)});
        }
      ''', tag: 'pushWhiteboardData', maxAttempts: 1, logFailures: false);
    } catch (e) {
      Log.debug(
          '[WBCollab][ExcalidrawWebView] pushData skipped for key $key: $e');
    }
  }

  Future<void> pushWhiteboardElements(
    List<dynamic> changed, {
    dynamic fallbackElements,
  }) async {
    if (!mounted || _controller == null || changed.isEmpty) return;

    try {
      if (!_perElementSyncEnabled) {
        if (fallbackElements is List) {
          await pushData('elements', fallbackElements);
        } else {
          Log.warn(
            '[WBCollab][ExcalidrawWebView] Per-element sync disabled without fallback elements.',
          );
        }
        return;
      }

      await _safeEvalJs('''
        if (window.pushWhiteboardElements) {
          window.pushWhiteboardElements(${jsonEncode(changed)});
        }
      ''', tag: 'pushWhiteboardElements', maxAttempts: 1, logFailures: false);
    } catch (e) {
      Log.debug(
        '[WBCollab][ExcalidrawWebView] pushWhiteboardElements skipped: $e',
      );
    }
  }

  /// 重新初始化UI（公共方法，供外部调用）
  /// 用于在导入数据后恢复UI状态
  Future<void> reinitializeUI() async {
    try {
      // 隐藏加载时的底图标志
      await _hideLoadingLogo();

      // 隐藏主菜单（汉堡菜单）
      await _hideMainMenu();

      // 隐藏欢迎界面和其他不需要的UI元素
      await _hideUnwantedUI();
      await _improveContextMenuTextRendering();

      // 设置主题
      final theme =
          _currentSystemBrightness() == Brightness.dark ? 'dark' : 'light';
      // 重新初始化也必须经过主题同步队列，避免恢复流程中的旧请求
      // 在系统主题切换后晚于最新值执行。
      await _syncHostThemeWhenReady(theme);
    } catch (e) {
      Log.error('❌ [ExcalidrawWebView] Reinitialize UI failed: $e');
      widget.onError?.call('重新初始化UI失败: $e');
    }
  }

  /// 获取当前数据（公共方法，供外部调用）
  Future<Map<String, dynamic>?> getData() async {
    // TODO: 通过JavaScript获取当前白板数据
    // 这需要Excalidraw提供相应的API
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              '白板加载失败',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              _loadingError!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade600,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _loadingError = null;
                  _isLoading = true;
                });
                _loadExcalidrawHTML();
              },
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    // 如果 URL 还未准备好，显示加载指示器
    if (_whiteboardUrl == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    // ✅ 关键修复：使用 LayoutBuilder 获取父容器的精确尺寸约束
    // 作为子控件时，必须确保 InAppWebView 获得明确的、固定的尺寸
    // 避免 macOS WKWebView 的 NSScrollView 因尺寸变化产生缩放漂移
    return LayoutBuilder(
      builder: (context, constraints) {
        // ✅ 使用整数尺寸，避免小数精度问题导致的布局抖动
        final width = constraints.maxWidth.floorToDouble();
        final height = constraints.maxHeight.floorToDouble();
        final constrainedSize = Size(width, height);
        _stableWebViewSize ??= constrainedSize;
        _scheduleStableWebViewResize(constrainedSize);
        final webViewSize = _stableWebViewSize ?? constrainedSize;

        return Stack(
          children: [
            // 使用明确尺寸约束包裹 InAppWebView，但不能把 key 绑定到尺寸。
            // 侧边栏伸缩/全屏会改变 width/height，尺寸 key 会销毁并重建原生 WebView。
            Positioned.fill(
              child: ClipRect(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: webViewSize.width,
                    height: webViewSize.height,
                    child: InAppWebView(
                      // ✅ 关键修复：InAppWebView（PlatformView）必须有全局唯一的key
                      // 原因：InAppWebView底层使用PlatformView与原生代码通信
                      // 问题：如果没有唯一key，Flutter可能会错误地复用或重复创建PlatformView
                      // 解决：使用全局唯一的实例ID确保每个InAppWebView的key绝对唯一
                      // 格式：viewId（业务标识） + 全局递增ID（确保唯一性）
                      key: ValueKey(
                        'inappwebview_${widget.viewId}_r${widget.reloadToken}_recovery_$_webViewRecoveryNonce'
                        '_global_$_inAppWebViewInstanceId',
                      ),
                      initialUrlRequest: URLRequest(
                        url: WebUri(_whiteboardUrl!),
                      ),
                      initialSettings: _settings,
                      // 在 document-start 阶段就禁用弹性回弹，比 onLoadStop 注入 CSS 更早
                      initialUserScripts: UnmodifiableListView([
                        UserScript(
                          source: _hostThemeBootstrapScript(
                            _currentSystemBrightness() == Brightness.dark
                                ? 'dark'
                                : 'light',
                          ),
                          injectionTime:
                              UserScriptInjectionTime.AT_DOCUMENT_START,
                        ),
                        UserScript(
                          source: '''
                        document.documentElement.style.overscrollBehavior = 'none';
                        document.documentElement.style.overscrollBehaviorX = 'none';
                        document.documentElement.style.overscrollBehaviorY = 'none';
                        document.body.style.overscrollBehavior = 'none';
                        document.body.style.overscrollBehaviorX = 'none';
                        document.body.style.overscrollBehaviorY = 'none';
                        window.scrollTo(0, 0);
                      ''',
                          injectionTime:
                              UserScriptInjectionTime.AT_DOCUMENT_START,
                        ),
                      ]),
                      webViewEnvironment: sharedWebViewEnvironment,

                      onWebViewCreated: (controller) {
                        // 修复：dispose 后不应再持有 controller 引用，避免
                        // 延迟销毁窗口内被外部方法误用。
                        if (_isDisposed) return;
                        _controller = controller;
                        _webViewCreated = true;
                        _setupJavaScriptHandlers(controller);
                        // ✅ 修复：不再在 onWebViewCreated 中设置 localStorage
                        // 原因：flutter_bridge.js 的 IIFE 会先清空当前白板的隔离缓存
                        // 然后通过 initData handler 重新加载数据
                        // 所以在这里设置 localStorage 是无用的（会被立即清空）
                        Log.debug('🌐 [ExcalidrawWebView] WebView created');
                      },

                      shouldOverrideUrlLoading:
                          (controller, navigationAction) async {
                        // 允许加载本地服务器的所有资源
                        final url = navigationAction.request.url.toString();
                        if (url.startsWith('http://localhost:') ||
                            url.startsWith('http://127.0.0.1:')) {
                          Log.debug(
                              '✅ [ExcalidrawWebView] Allowing navigation to: $url');
                          return NavigationActionPolicy.ALLOW;
                        }
                        Log.debug(
                            '⚠️ [ExcalidrawWebView] Blocking navigation to: $url');
                        return NavigationActionPolicy.CANCEL;
                      },

                      onLoadStart: (controller, url) {
                        if (mounted) {
                          setState(() {
                            _isLoading = true;
                            _loadingError = null;
                            _pageLoaded = false;
                          });
                        }
                        Log.debug(
                            '🔄 [ExcalidrawWebView] Loading started: $url');
                      },

                      onLoadStop: (controller, url) async {
                        if (mounted && _controller != null) {
                          setState(() {
                            _isLoading = false;
                            _pageLoaded = true;
                            _localServerRecoveryAttempts = 0;
                          });

                          // ✅ 关键：等待 initData 完成后再初始化 UI
                          if (_initializationCompleter != null &&
                              !_initializationCompleter!.isCompleted) {
                            Log.info(
                                '[ExcalidrawWebView] ⏳ Waiting for data initialization...');
                            _isInitializing = true;
                            setState(() {});

                            try {
                              await _initializationCompleter!.future.timeout(
                                const Duration(seconds: 10),
                                onTimeout: () {
                                  Log.warn(
                                      '[ExcalidrawWebView] ⏰ initData timeout, proceeding anyway');
                                },
                              );
                              Log.info(
                                  '[ExcalidrawWebView] ✅ Data initialization complete');
                            } catch (e) {
                              Log.warn(
                                  '[ExcalidrawWebView] ⚠️ initData error: $e, proceeding anyway');
                            }

                            _isInitializing = false;
                            if (mounted) {
                              setState(() {});
                            }
                          }

                          await _initializeExcalidraw();
                          // 系统切换若发生在页面加载/数据恢复期间，补发最后一次
                          // 主题请求，避免首次调用落在 WebView 未就绪窗口。
                          final pendingTheme = _pendingHostTheme ??
                              (_currentSystemBrightness() == Brightness.dark
                                  ? 'dark'
                                  : 'light');
                          await _syncHostThemeWhenReady(pendingTheme);
                          _notifyInitialReadyOnce();
                        }
                        Log.debug(
                            '✅ [ExcalidrawWebView] Loading finished: $url');
                      },

                      onProgressChanged: (controller, progress) {
                        // 可以在这里更新进度条
                        // print('📊 [ExcalidrawWebView] Loading progress: $progress%');
                      },

                      onReceivedError: (controller, request, error) {
                        // 字体、图片等子资源失败不能覆盖整个白板；仅处理主页面失败。
                        if (request.isForMainFrame == false) return;
                        final message = error.description;
                        final failedUrl = request.url.toString();
                        Log.error(
                          '❌ [ExcalidrawWebView] Load error: $message '
                          '(type: ${error.type}, url: $failedUrl)',
                        );
                        if (failedUrl.startsWith('http://127.0.0.1:') ||
                            failedUrl.startsWith('http://localhost:')) {
                          unawaited(_recoverLocalAssetServer(message));
                          return;
                        }
                        if (mounted) {
                          setState(() {
                            _isLoading = false;
                            _loadingError = message;
                          });
                        }
                        widget.onError?.call('WebView加载错误: $message');
                      },

                      onLoadHttpError:
                          (controller, url, statusCode, description) {
                        if (mounted) {
                          setState(() {
                            _isLoading = false;
                            _loadingError = 'HTTP错误 $statusCode: $description';
                          });
                        }
                        Log.error(
                            '❌ [ExcalidrawWebView] HTTP error: $statusCode - $description');
                      },

                      onConsoleMessage: (controller, consoleMessage) {
                        // 打印 WebView 控制台消息（用于调试）
                        // 只打印关键日志，避免刷屏
                        final message = consoleMessage.message;
                        // 只打印包含特定关键词的日志
                        if (message.contains('[PonyNotes]') ||
                            message.contains('Error') ||
                            message.contains('error') ||
                            message.contains('Failed') ||
                            message.contains('❌') ||
                            message.contains('✅')) {
                          // 主题链路需要在手机日志中可见，用 info 区分“系统事件
                          // 已触发”和“WebView 已实际应用”两个阶段。
                          if (message.contains('host theme applied') ||
                              message
                                  .contains('Host system appearance changed') ||
                              message.contains('iOS image decoded') ||
                              message.contains('iOS image decode fallback') ||
                              message.contains('iOS image viewport') ||
                              message.contains('image decoded') ||
                              message.contains('image decode fallback') ||
                              message.contains('image viewport') ||
                              message.contains(
                                  'iOS inserted image cache rebuilt') ||
                              // 插图失败诊断：这些是 Excalidraw / bridge 在插图
                              // 环节抛出的错误，历史上被 console.error 吞掉、日志
                              // 不可见，导致「大图重编码 >4MB 被 fileTooBig 丢弃」
                              // 长期静默。纳入白名单确保失败即可见。
                              message.contains('whiteboard image insert') ||
                              message.contains('whiteboard image picker') ||
                              message.contains('File is too big') ||
                              message.contains('fileTooBig') ||
                              message.contains('imageInsertError') ||
                              message.contains(
                                  'New element size or position is too large') ||
                              message
                                  .contains('iOS zero-size image repaired') ||
                              message.contains('zero-size image repaired') ||
                              message.contains(
                                  'iOS image decode refresh installed')) {
                            Log.info('[WebView Console] $message');
                          } else {
                            Log.debug('[WebView Console] $message');
                          }
                        }
                      },
                    ),
                  ),
                ),
              ),
            ), // InAppWebView

            // 鼠标离开监听层：透明，不拦截事件，仅监听鼠标离开 WebView 区域
            // 用于在鼠标离开 WebView 时清除 Excalidraw 工具栏的 hover 状态
            // （opaque: false 确保不消费鼠标事件，不影响 InAppWebView 的正常交互）
            Positioned.fill(
              child: MouseRegion(
                opaque: false,
                onExit: (_) => _clearToolbarHover(),
                child: const SizedBox.expand(),
              ),
            ),

            // 加载覆盖层 - 使用完全不透明背景遮挡 Excalidraw 的加载界面
            if (_isLoading || _isInitializing)
              Builder(
                builder: (context) {
                  final isDark = _currentSystemBrightness() == Brightness.dark;
                  return Container(
                    // 使用完全不透明的背景色，根据主题切换，彻底遮挡底层的 Excalidraw 加载界面
                    color: isDark ? const Color(0xFF121212) : Colors.white,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // 小马笔记 Logo - 50% 透明度
                          Opacity(
                            opacity: 0.5,
                            child: FlowySvg(
                              FlowySvgs.pony_notes_logo_xl,
                              blendMode: null,
                              size: const Size.square(80),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // 小马笔记白板 文字 - 与图标保持一致的透明度
                          Opacity(
                            opacity: 0.5,
                            child: Text(
                              _isInitializing ? '正在加载白板数据...' : '小马AI笔记白板',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                                letterSpacing: 2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          // 加载指示器
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                isDark ? Colors.white38 : Colors.grey.shade400,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _isInitializing ? '正在恢复图片和画布内容...' : '正在加载白板编辑器...',
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark
                                  ? Colors.white54
                                  : Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}
