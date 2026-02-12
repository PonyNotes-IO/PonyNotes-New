import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:appflowy/plugins/whiteboard/application/local_asset_server.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:http/http.dart' as http;

import '../application/whiteboard_data_service.dart';
import 'package:appflowy_backend/log.dart';

// 全局InAppWebView实例计数器，确保每个InAppWebView的PlatformView ID全局唯一
int _globalInAppWebViewInstanceCounter = 0;

/// Excalidraw WebView 组件
/// 使用 flutter_inappwebview 实现跨平台支持（包括 Windows）
/// 集成 Excalidraw 编辑器和 excalidraw-libraries 图形库
class ExcalidrawWebView extends StatefulWidget {
  const ExcalidrawWebView({
    super.key,
    required this.viewId,
    this.initialData,
    this.onDataChanged,
    this.onExport,
    this.onError,
  });

  final String viewId;
  final Map<String, dynamic>? initialData;
  final Function(String type, Map<String, dynamic> data)? onDataChanged;
  final Function(String format, dynamic data)? onExport;
  final Function(String error)? onError;

  @override
  State<ExcalidrawWebView> createState() => ExcalidrawWebViewState();
}

/// ExcalidrawWebView的State类，暴露公共方法供外部调用
class ExcalidrawWebViewState extends State<ExcalidrawWebView> {
  // 内部状态（保持原有实现）
  InAppWebViewController? _controller;
  bool _isLoading = true;
  bool _isInitializing = false; // ✅ 新增：用于跟踪初始化状态
  String? _loadingError;
  final _assetServer = LocalAssetServer();
  String? _whiteboardUrl;
  late InAppWebViewSettings _settings;
  bool _webViewCreated = false;
  bool _pageLoaded = false;
  late final int _inAppWebViewInstanceId; // 每个InAppWebView的全局唯一ID
  Completer<void>? _initializationCompleter; // ✅ 新增：用于等待初始化完成

  @override
  void initState() {
    super.initState();
    // 生成全局唯一的InAppWebView实例ID
    _globalInAppWebViewInstanceCounter++;
    _inAppWebViewInstanceId = _globalInAppWebViewInstanceCounter;
    Log.debug(
        '🌐 [ExcalidrawWebView] Created with global instance ID: $_inAppWebViewInstanceId, viewId: ${widget.viewId}');

    _initializeSettings();
    _loadExcalidrawHTML();
  }

  /// 统一的 JS 执行入口：在引擎重启/插件尚未就绪等场景下进行重试，避免 MissingPluginException
  Future<void> _safeEvalJs(
    String source, {
    String tag = 'eval',
    int maxAttempts = 10,
    Duration initialDelay = const Duration(milliseconds: 60),
  }) async {
    if (!mounted) return;
    var attempt = 0;
    var delay = initialDelay;
    while (mounted && attempt < maxAttempts) {
      attempt++;
      try {
        if (_controller != null &&
            _webViewCreated &&
            _pageLoaded &&
            !_isLoading) {
          await _controller!.evaluateJavascript(source: source);
          return;
        }
      } on MissingPluginException catch (e) {
        Log.warn(
            '⚠️ [ExcalidrawWebView] MissingPluginException on $tag attempt#$attempt: $e');
      } catch (e) {
        Log.error('⚠️ [ExcalidrawWebView] error on $tag attempt#$attempt: $e');
      }
      await Future.delayed(delay);
      delay += const Duration(milliseconds: 60);
    }
    Log.error(
        '❌ [ExcalidrawWebView] $tag failed after $maxAttempts attempts, giving up.');
  }

  void _initializeSettings() {
    _settings = InAppWebViewSettings(
      // 开发者工具
      isInspectable: kDebugMode,
      javaScriptEnabled: true,
      transparentBackground: true,
      useShouldOverrideUrlLoading: true,
      mediaPlaybackRequiresUserGesture: false,
      cacheEnabled: false,
      // Android 特定设置
      useHybridComposition: true,
      thirdPartyCookiesEnabled: false,
      // iOS 特定设置
      allowsInlineMediaPlayback: true,
      allowsBackForwardNavigationGestures: false,
    );
  }

  Future<void> _loadExcalidrawHTML() async {
    try {
      // debug log removed

      // 启动本地HTTP服务器
      final baseUrl = await _assetServer.start();

      // 使用带 viewId 的URL（用于调试和日志追踪）
      // 注意：localStorage 已在 HTML 中被完全禁用，数据隔离由 Flutter 管理
      final url = '$baseUrl/index.html';

      Log.info('✅ [ExcalidrawWebView] 服务器已启动: $baseUrl');
      // debug logs removed

      // ✅ 关键：设置 URL 并触发重新构建
      if (mounted) {
        setState(() {
          _whiteboardUrl = url;
        });
      }

      // 如果 controller 已创建，直接加载 URL
      if (_controller != null && mounted) {
        await _controller!.loadUrl(
          urlRequest: URLRequest(url: WebUri(_whiteboardUrl!)),
        );
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

  void _setupJavaScriptHandlers(InAppWebViewController controller) {
    // ✅ 新增：初始化完成器
    _initializationCompleter = Completer<void>();

    controller.addJavaScriptHandler(
        handlerName: "initData",
        callback: (args) async {
          Log.info('[ExcalidrawWebView] 🚀 initData called, loading whiteboard data...');
          
          try {
            final service = WhiteboardDataService();
            final data = await service.loadWhiteboardData(widget.viewId);
            
            Log.info('[ExcalidrawWebView] ✅ Data loaded, ${data.keys.length} keys found');
            if (data.containsKey('elements')) {
              final elements = data['elements'];
              if (elements is List) {
                Log.info('[ExcalidrawWebView] 📝 Elements count: ${elements.length}');
              }
            }
            if (data.containsKey('files')) {
              final files = data['files'];
              if (files is Map) {
                Log.info('[ExcalidrawWebView] 📸 Files count: ${files.length}');
                // ⚠️ 注意：不在这里做耗时的文件预处理（如下载云URL图片）
                // 原因：initData 必须尽快完成，否则 Excalidraw 会在 elements 设置到
                // localStorage 之前就读取空数据，导致绘图对象丢失
                // 文件的云URL处理放在 JS 端的 _injectFilesFromStorage 和
                // downloadCloudImages handler 中异步完成
              }
            }

            // 设置数据到 LocalStorage
            int setCount = 0;
            for (final entry in data.entries) {
              final key = entry.key;
              final value = entry.value;
              
              // 跳过非白板数据键
              if (key == 'viewId' || key == 'savedAt' || key == '__test__') {
                continue;
              }
              
              // 修复：确保 value 是 JSON 字符串
              final stringValue = value is String ? value : jsonEncode(value);

              // 修复：映射键名到 Excalidraw 期望的 LocalStorage 键
              String lsKey = key;
              if (key == 'files') {
                lsKey = 'excalidraw-files';
              } else if (key == 'elements') {
                lsKey = 'excalidraw';
              } else if (key == 'appState') {
                lsKey = 'excalidraw-state';
              }

              await _controller!.webStorage.localStorage.setItem(
                key: lsKey,
                value: stringValue,
              );
              setCount++;
            }
            
            Log.info('[ExcalidrawWebView] ✅ Set $setCount items to localStorage');
            
            // ✅ 关键：初始化完成后发送信号给 Excalidraw
            // 这将触发 _onWhiteboardDataReady，它会从 localStorage 读取 files
            // 并使用 api.addFiles() 将图片注入到 Excalidraw 的内部状态中
            await _safeEvalJs('''
              if (window._onWhiteboardDataReady) {
                window._onWhiteboardDataReady($setCount);
              }
            ''', tag: 'initDataReady');
            
            // ✅ 标记初始化完成
            if (!_initializationCompleter!.isCompleted) {
              _initializationCompleter!.complete();
            }
          } catch (e, stack) {
            Log.error('[ExcalidrawWebView] ❌ initData failed: $e\n$stack');
            if (!_initializationCompleter!.isCompleted) {
              _initializationCompleter!.completeError(e);
            }
          }
        });
    controller.addJavaScriptHandler(
        handlerName: "localStorageOnSet",
        callback: (args) {
          if (args.isNotEmpty) {
            final arg = args[0];
            if (arg is Map &&
                arg.containsKey('key') &&
                arg.containsKey('value')) {
              final key = arg['key'].toString();
              final value = arg['value'];

              // 📸 关键修复：拦截 excalidraw-files 并转换为标准的 files 键
              // Excalidraw 将文件数据存储在 key_excalidraw-files 中
              // 我们需要将其解析并以 'files' 键发送给 WhiteboardCollabAdapter，以便它能正确合并数据
              if (key.endsWith('excalidraw-files') && value is String) {
                try {
                  final filesMap = jsonDecode(value);
                  if (filesMap is Map) {
                    Log.debug(
                        '📸 [ExcalidrawWebView] Intercepted files update, count: ${filesMap.length}');
                    widget.onDataChanged?.call('update', {'files': filesMap});
                    return; // 拦截成功，不再发送原始 key
                  }
                } catch (e) {
                  Log.warn(
                      '⚠️ [ExcalidrawWebView] Failed to parse files JSON: $e');
                }
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
        try {
          if (args.isEmpty) return [];
          final cloudFiles = args[0];
          if (cloudFiles is! List) return [];
          
          Log.info('[ExcalidrawWebView] 📸 downloadCloudImages: ${cloudFiles.length} files to download');
          
          final results = <Map<String, dynamic>>[];
          for (final item in cloudFiles) {
            if (item is! Map) continue;
            final fileId = item['fileId'] as String?;
            final url = item['url'] as String?;
            final mimeType = item['mimeType'] as String? ?? 'image/png';
            
            if (fileId == null || url == null) continue;
            
            try {
              Log.info('[ExcalidrawWebView] 📸 Downloading cloud image: $fileId from $url');
              
              // 使用 HTTP 下载图片（带认证）
              final imageBytes = await _downloadCloudImage(url);
              if (imageBytes != null && imageBytes.isNotEmpty) {
                // 转换为 base64 dataURL
                final base64Data = base64Encode(imageBytes);
                final dataURL = 'data:$mimeType;base64,$base64Data';
                
                results.add({
                  'fileId': fileId,
                  'dataURL': dataURL,
                  'mimeType': mimeType,
                  'created': DateTime.now().millisecondsSinceEpoch,
                });
                
                Log.info('[ExcalidrawWebView] ✅ Downloaded cloud image: $fileId (${imageBytes.length} bytes)');
              } else {
                Log.warn('[ExcalidrawWebView] ⚠️ Downloaded empty image for: $fileId');
              }
            } catch (e) {
              Log.error('[ExcalidrawWebView] ❌ Failed to download cloud image $fileId: $e');
            }
          }
          
          Log.info('[ExcalidrawWebView] 📸 Downloaded ${results.length}/${cloudFiles.length} cloud images');
          return results;
        } catch (e) {
          Log.error('[ExcalidrawWebView] ❌ downloadCloudImages handler error: $e');
          return [];
        }
      },
    );
    controller.addJavaScriptHandler(
      handlerName: "onExport",
      callback: (args) async {
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
          dataToLoad['appState'] = widget.initialData!['appState'];
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
                dataToLoad['appState'] = jsonDecode(value);
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

      // 设置主题
      final theme =
          Theme.of(context).brightness == Brightness.dark ? 'dark' : 'light';
      // debug log removed
      await _safeEvalJs('''
        console.log('[ExcalidrawWebView] Setting theme to $theme');
        if (window.setTheme) {
          window.setTheme('$theme');
        } else {
          console.error('[ExcalidrawWebView] window.setTheme not found!');
        }
      ''', tag: 'setTheme');
      // debug log removed
    } catch (e) {
      Log.error('❌ [ExcalidrawWebView] Initialization failed: $e');
      widget.onError?.call('初始化Excalidraw失败: $e');
    }
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
          
          /* 确保工具栏始终正常显示和响应点击 */
          .App-toolbar,
          .App-toolbar * {
            pointer-events: auto !important;
          }
          
          /* 确保工具栏按钮可以正常点击 */
          .App-toolbar .ToolIcon,
          .App-toolbar .Shape,
          .App-toolbar label.ToolIcon {
            pointer-events: auto !important;
            display: inline-flex !important;
            visibility: visible !important;
            opacity: 1 !important;
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

  /// 隐藏加载阶段的 Excalidraw 底图标志（闪屏）
  /// 注意：只隐藏欢迎界面中心的LOGO，不隐藏工具栏和其他功能元素
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
          
          /* 确保工具栏始终显示 */
          .App-toolbar,
          [class*="App-toolbar"],
          [data-testid*="toolbar"] {
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

  /// 预处理文件数据：确保所有文件都有有效的 base64 dataURL
  /// 对于只有云 URL 的文件，下载并转换为 dataURL
  Future<Map<String, dynamic>> _preprocessFilesForLoading(
    Map<String, dynamic> files,
  ) async {
    final result = <String, dynamic>{};
    
    for (final entry in files.entries) {
      final fileId = entry.key;
      final fileData = entry.value;
      
      if (fileData is! Map) {
        result[fileId] = fileData;
        continue;
      }
      
      final fileDataMap = Map<String, dynamic>.from(fileData as Map);
      
      // 检查是否已有有效的 base64 dataURL
      final dataURL = fileDataMap['dataURL'] as String?;
      final data = fileDataMap['data'] as String?;
      
      final hasValidDataURL = (dataURL != null && dataURL.startsWith('data:')) ||
                               (data != null && data.startsWith('data:'));
      
      if (hasValidDataURL) {
        // 已有 base64 dataURL，直接使用
        result[fileId] = fileDataMap;
        Log.info('[ExcalidrawWebView] 📸 File $fileId has valid dataURL');
        continue;
      }
      
      // 检查是否有云 URL
      final cloudUrl = fileDataMap['url'] as String? ?? 
                       (data != null && data.startsWith('http') ? data : null);
      
      if (cloudUrl != null && cloudUrl.startsWith('http')) {
        // 需要从云端下载
        Log.info('[ExcalidrawWebView] 📸 Downloading cloud image for $fileId: $cloudUrl');
        try {
          final imageBytes = await _downloadCloudImage(cloudUrl);
          if (imageBytes != null && imageBytes.isNotEmpty) {
            final mimeType = fileDataMap['mimeType'] as String? ?? 'image/png';
            final base64Data = base64Encode(imageBytes);
            final newDataURL = 'data:$mimeType;base64,$base64Data';
            
            fileDataMap['dataURL'] = newDataURL;
            result[fileId] = fileDataMap;
            Log.info('[ExcalidrawWebView] ✅ Downloaded and converted cloud image: $fileId (${imageBytes.length} bytes)');
          } else {
            Log.warn('[ExcalidrawWebView] ⚠️ Empty download for $fileId, keeping original');
            result[fileId] = fileDataMap;
          }
        } catch (e) {
          Log.error('[ExcalidrawWebView] ❌ Failed to download $fileId: $e');
          result[fileId] = fileDataMap;
        }
      } else {
        Log.warn('[ExcalidrawWebView] ⚠️ File $fileId has no valid dataURL or cloud URL');
        result[fileId] = fileDataMap;
      }
    }
    
    return result;
  }

  /// 下载云端图片（带认证）
  Future<Uint8List?> _downloadCloudImage(String url) async {
    try {
      // 使用 FileUploadService 的认证机制
      final userResult = await UserBackendService.getCurrentUserProfile();
      final user = userResult.fold(
        (user) => user,
        (error) => null,
      );
      
      if (user == null || user.token.isEmpty) {
        Log.warn('[ExcalidrawWebView] ⚠️ Cannot download cloud image: user not logged in');
        return null;
      }
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer ${user.token}',
        },
      );
      
      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        Log.error('[ExcalidrawWebView] ❌ Cloud image download failed: ${response.statusCode}');
        return null;
      }
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

    // flutter_inappwebview 的 controller 会自动清理
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
      await _safeEvalJs('''
        if (window.setTheme) {
          window.setTheme('$theme');
        }
      ''', tag: 'updateTheme($theme)');
    } catch (e) {
      widget.onError?.call('更新主题失败: $e');
    }
  }

  /// 加载数据（公共方法，供外部调用）
  Future<void> loadData(Map<String, dynamic> data) async {
    try {
      await _safeEvalJs('''
        if (window.loadExcalidrawData) {
          window.loadExcalidrawData(${jsonEncode(data)});
        }
      ''', tag: 'loadData');

      // 加载数据后重新初始化UI，确保工具栏等元素正确显示
      await reinitializeUI();
    } catch (e) {
      widget.onError?.call('加载数据失败: $e');
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

      // 设置主题
      final theme =
          Theme.of(context).brightness == Brightness.dark ? 'dark' : 'light';
      await _safeEvalJs('''
        console.log('[ExcalidrawWebView] Reinitializing UI, setting theme to $theme');
        if (window.setTheme) {
          window.setTheme('$theme');
        } else {
          console.error('[ExcalidrawWebView] window.setTheme not found!');
        }
      ''', tag: 'reinitializeUI');
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

    return Stack(
      children: [
        InAppWebView(
          // ✅ 关键修复：InAppWebView（PlatformView）必须有全局唯一的key
          // 原因：InAppWebView底层使用PlatformView与原生代码通信
          // 问题：如果没有唯一key，Flutter可能会错误地复用或重复创建PlatformView
          // 解决：使用全局唯一的实例ID确保每个InAppWebView的key绝对唯一
          // 格式：viewId（业务标识） + 全局递增ID（确保唯一性）
          key: ValueKey(
              'inappwebview_${widget.viewId}_global_$_inAppWebViewInstanceId'),
          initialUrlRequest: URLRequest(
            url: WebUri(_whiteboardUrl!),
          ),
          initialSettings: _settings,

          onWebViewCreated: (controller) {
            _controller = controller;
            _webViewCreated = true;
            _setupJavaScriptHandlers(controller);
            widget.initialData?.forEach((key, value) async {
              final jsonValue = jsonEncode(value);
              final localStorageKey = 'whiteboard_${widget.viewId}_$key';
              await _controller!.webStorage.localStorage.setItem(
                key: localStorageKey,
                value: jsonValue,
              );
              Log.debug('💾 localStorage set: $localStorageKey = $jsonValue');
            });
            Log.debug('🌐 [ExcalidrawWebView] WebView created');
          },

          shouldOverrideUrlLoading: (controller, navigationAction) async {
            // 允许加载本地服务器的所有资源
            final url = navigationAction.request.url.toString();
            if (url.startsWith('http://localhost:') ||
                url.startsWith('http://127.0.0.1:')) {
              Log.debug('✅ [ExcalidrawWebView] Allowing navigation to: $url');
              return NavigationActionPolicy.ALLOW;
            }
            Log.debug('⚠️ [ExcalidrawWebView] Blocking navigation to: $url');
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
            Log.debug('🔄 [ExcalidrawWebView] Loading started: $url');
          },

          onLoadStop: (controller, url) async {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _pageLoaded = true;
              });
              
              // ✅ 关键：等待 initData 完成后再初始化 UI
              if (_initializationCompleter != null && !_initializationCompleter!.isCompleted) {
                Log.info('[ExcalidrawWebView] ⏳ Waiting for data initialization...');
                _isInitializing = true;
                setState(() {});
                
                try {
                  await _initializationCompleter!.future.timeout(
                    const Duration(seconds: 10),
                    onTimeout: () {
                      Log.warn('[ExcalidrawWebView] ⏰ initData timeout, proceeding anyway');
                    },
                  );
                  Log.info('[ExcalidrawWebView] ✅ Data initialization complete');
                } catch (e) {
                  Log.warn('[ExcalidrawWebView] ⚠️ initData error: $e, proceeding anyway');
                }
                
                _isInitializing = false;
                if (mounted) {
                  setState(() {});
                }
              }
              
              await _initializeExcalidraw();
            }
            Log.debug('✅ [ExcalidrawWebView] Loading finished: $url');
          },

          onProgressChanged: (controller, progress) {
            // 可以在这里更新进度条
            // print('📊 [ExcalidrawWebView] Loading progress: $progress%');
          },

          onLoadError: (controller, url, code, message) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _loadingError = message;
              });
            }
            Log.error(
                '❌ [ExcalidrawWebView] Load error: $message (code: $code)');
            widget.onError?.call('WebView加载错误: $message');
          },

          onLoadHttpError: (controller, url, statusCode, description) {
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
              Log.debug('[WebView Console] $message');
            }
          },
        ),

        // 加载覆盖层 - 使用完全不透明背景遮挡 Excalidraw 的加载界面
        if (_isLoading || _isInitializing)
          Builder(
            builder: (context) {
              final isDark = Theme.of(context).brightness == Brightness.dark;
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
                          _isInitializing ? '正在加载白板数据...' : '小马笔记白板',
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
                        _isInitializing
                            ? '正在恢复图片和画布内容...'
                            : '正在加载白板编辑器...',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white54 : Colors.grey.shade500,
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
  }
}
