import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:appflowy/plugins/whiteboard/application/local_asset_server.dart';

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
  final Function(String type,Map<String, dynamic> data)? onDataChanged;
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
  String? _loadingError;
  final _assetServer = LocalAssetServer();
  String? _whiteboardUrl;
  late InAppWebViewSettings _settings;
  bool _webViewCreated = false;
  bool _pageLoaded = false;
  late final int _inAppWebViewInstanceId; // 每个InAppWebView的全局唯一ID

  @override
  void initState() {
    super.initState();
    // 生成全局唯一的InAppWebView实例ID
    _globalInAppWebViewInstanceCounter++;
    _inAppWebViewInstanceId = _globalInAppWebViewInstanceCounter;
    Log.debug('🌐 [ExcalidrawWebView] Created with global instance ID: $_inAppWebViewInstanceId, viewId: ${widget.viewId}');
    
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
        if (_controller != null && _webViewCreated && _pageLoaded && !_isLoading) {
          await _controller!.evaluateJavascript(source: source);
          return;
        }
      } on MissingPluginException catch (e) {
        Log.warn('⚠️ [ExcalidrawWebView] MissingPluginException on $tag attempt#$attempt: $e');
      } catch (e) {
        Log.error('⚠️ [ExcalidrawWebView] error on $tag attempt#$attempt: $e');
      }
      await Future.delayed(delay);
      delay += const Duration(milliseconds: 60);
    }
    Log.error('❌ [ExcalidrawWebView] $tag failed after $maxAttempts attempts, giving up.');
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
    controller.addJavaScriptHandler(handlerName: "initData", callback:(args) async{
      final service = WhiteboardDataService();
      final data = await service.loadWhiteboardData(widget.viewId);

      data.forEach((key, value) async {
        await _controller!.webStorage.localStorage.setItem(
          key: key,
          value: value,
        );
        // debug log removed
      });
    });
    controller.addJavaScriptHandler(handlerName: "localStorageOnSet", callback:(args){
      if (args.isNotEmpty) {
        final arg = args[0];
        if (arg is Map && arg.containsKey('key') && arg.containsKey('value')) {
          final singleEntryMap = {arg['key'].toString(): arg['value']};
          widget.onDataChanged?.call('update',singleEntryMap);
        } else {
          // 防护：不符合预期的结构
          Log.warn('⚠️ [localStorageOnSet] Unexpected argument structure: $arg');
        }
      }
    });
    controller.addJavaScriptHandler(handlerName: "localStorageOnRemove", callback:(args){
      // debug log removed
    });
    controller.addJavaScriptHandler(handlerName: "localStorageOnClear", callback:(args){
      // debug log removed
    });
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
        dataToLoad = Map.from(widget.initialData!);
        // debug log removed
      } else {
        // debug log removed
      }

      // 🔑 关键：添加 viewId 到数据中
      dataToLoad['viewId'] = widget.viewId;

      final dataJson = jsonEncode(dataToLoad);
      // debug log removed

      // await _controller?.evaluateJavascript(source: '''
      //   console.log('[ExcalidrawWebView] Loading data into Excalidraw with viewId: ${widget.viewId}');
      //   if (window.loadExcalidrawData) {
      //     window.loadExcalidrawData($dataJson);
      //     console.log('[ExcalidrawWebView] Data loaded successfully');
      //   } else {
      //     console.error('[ExcalidrawWebView] window.loadExcalidrawData not found!');
      //   }
      // ''');
      // debug log removed

      // 首先隐藏加载时的底图标志（尽早执行，避免闪现）
      await _hideLoadingLogo();
      
      // 隐藏主菜单（汉堡菜单）
      await _hideMainMenu();
      
      // 隐藏欢迎界面和其他不需要的UI元素
      await _hideUnwantedUI();

      // 设置主题
      final theme = Theme.of(context).brightness == Brightness.dark ? 'dark' : 'light';
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
  Future<void> _hideMainMenu() async {
    // 使用CSS和JavaScript隐藏主菜单
    await _safeEvalJs('''
      (function() {
        // 注入CSS隐藏菜单
        const style = document.createElement('style');
        style.id = 'ponynotes-hide-menu-style';
        style.textContent = `
          /* 隐藏主菜单按钮 */
          .main-menu-trigger,
          [data-testid="main-menu-trigger"],
          button[aria-label*="menu"],
          button[aria-label*="Menu"] {
            display: none !important;
            visibility: hidden !important;
          }
          
          /* 隐藏菜单容器 */
          .main-menu-dropdown,
          .dropdown-menu-content[data-placement*="bottom"] {
            display: none !important;
          }
        `;
        
        // 如果样式已存在，先移除
        const existingStyle = document.getElementById('ponynotes-hide-menu-style');
        if (existingStyle) {
          existingStyle.remove();
        }
        
        document.head.appendChild(style);
        
        // 使用MutationObserver持续监听并隐藏菜单
        const observer = new MutationObserver(function(mutations) {
          // 隐藏菜单按钮
          const menuTriggers = document.querySelectorAll(
            '.main-menu-trigger, [data-testid="main-menu-trigger"], button[aria-label*="menu"], button[aria-label*="Menu"]'
          );
          menuTriggers.forEach(trigger => {
            trigger.style.display = 'none';
            trigger.style.visibility = 'hidden';
          });
          
          // 隐藏菜单容器
          const menuContainers = document.querySelectorAll(
            '.main-menu-dropdown, .dropdown-menu-content'
          );
          menuContainers.forEach(container => {
            if (container.closest('.main-menu-trigger')) {
              container.style.display = 'none';
            }
          });
        });
        
        // 开始观察
        observer.observe(document.body, {
          childList: true,
          subtree: true,
          attributes: true,
          attributeFilter: ['style', 'class']
        });
        
        // 立即执行一次隐藏
        setTimeout(() => {
          const menuTriggers = document.querySelectorAll(
            '.main-menu-trigger, [data-testid="main-menu-trigger"], button[aria-label*="menu"], button[aria-label*="Menu"]'
          );
          menuTriggers.forEach(trigger => {
            trigger.style.display = 'none';
            trigger.style.visibility = 'hidden';
          });
        }, 100);
        
        // 保存observer到window，以便后续清理
        window._ponynotesMenuObserver = observer;
      })();
    ''', tag: 'hideMainMenu');
  }

  /// 隐藏不需要的UI元素（欢迎界面、Excalidraw+按钮、帮助按钮等）
  Future<void> _hideUnwantedUI() async {
    await _safeEvalJs('''
      (function() {
        // 注入CSS隐藏不需要的UI元素
        const style = document.createElement('style');
        style.id = 'ponynotes-hide-ui-style';
        style.textContent = `
          /* 隐藏欢迎界面 */
          .welcome-screen,
          [class*="WelcomeScreen"],
          [class*="welcome-screen"],
          .welcome-screen-center,
          [data-testid*="welcome"],
          [data-testid*="Welcome"] {
            display: none !important;
            visibility: hidden !important;
          }
          
          /* 隐藏Excalidraw+按钮和横幅 */
          .plus-banner,
          [class*="plus-banner"],
          [class*="ExcalidrawPlus"],
          [href*="excalidraw.com/plus"],
          button:has-text("Excalidraw+"),
          a:has-text("Excalidraw+") {
            display: none !important;
            visibility: hidden !important;
          }
          
          /* 隐藏帮助按钮和快捷键按钮 */
          [data-testid*="help"],
          [data-testid*="Help"],
          [aria-label*="help"],
          [aria-label*="Help"],
          [aria-label*="快捷键"],
          [aria-label*="shortcut"],
          [aria-label*="Shortcut"],
          button[title*="帮助"],
          button[title*="help"],
          button[title*="Help"],
          button[title*="快捷键"],
          .help-button,
          .shortcut-button,
          [class*="help-button"],
          [class*="shortcut-button"] {
            display: none !important;
            visibility: hidden !important;
          }
          
          /* 隐藏欢迎界面的提示元素 */
          .welcome-screen-hint,
          [class*="WelcomeScreen.Hints"],
          [class*="welcome-screen-hint"] {
            display: none !important;
            visibility: hidden !important;
          }
          
          /* 隐藏实时协作按钮 */
          .collab-button,
          [class*="collab-button"],
          [data-testid="collab-button"],
          button[title*="实时协作"],
          button[title*="liveCollaboration"],
          button[title*="LiveCollaboration"],
          button[title*="协作"],
          [aria-label*="实时协作"],
          [aria-label*="liveCollaboration"] {
            display: none !important;
            visibility: hidden !important;
          }
          
          /* 隐藏素材库按钮 - 增强版 */
          [class*="library"],
          [class*="Library"],
          [class*="DefaultSidebar.Trigger"],
          [class*="DefaultSidebarTrigger"],
          [class*="DefaultSidebar"],
          [class*="SidebarTrigger"],
          [class*="sidebar-trigger"],
          button[title*="library"],
          button[title*="Library"],
          button[title*="素材"],
          button[title*="素材库"],
          [aria-label*="library"],
          [aria-label*="Library"],
          [aria-label*="素材库"],
          [aria-label*="素材"],
          [data-testid*="library"],
          [data-testid*="Library"],
          [data-testid*="sidebar-trigger"],
          [data-testid*="default-sidebar"],
          /* 工具栏中的素材库按钮 */
          .App-toolbar [class*="library"],
          .App-toolbar [class*="Library"],
          .App-toolbar button[title*="素材库"],
          .App-toolbar button[aria-label*="素材库"],
          /* 可能包含素材库文字的容器 */
          [class*="toolbar"] [class*="library"],
          [class*="Toolbar"] [class*="Library"],
          /* SVG图标相关 */
          svg[title*="素材库"],
          svg[aria-label*="素材库"] {
            display: none !important;
            visibility: hidden !important;
            opacity: 0 !important;
            pointer-events: none !important;
          }
        `;
        
        // 如果样式已存在，先移除
        const existingStyle = document.getElementById('ponynotes-hide-ui-style');
        if (existingStyle) {
          existingStyle.remove();
        }
        
        document.head.appendChild(style);
        
        // 使用MutationObserver持续监听并隐藏元素
        const observer = new MutationObserver(function(mutations) {
          // 隐藏欢迎界面（但确保不是工具栏的一部分）
          const welcomeScreens = document.querySelectorAll(
            '.welcome-screen, [class*="WelcomeScreen"], [class*="welcome-screen"], [data-testid*="welcome"], [data-testid*="Welcome"]'
          );
          welcomeScreens.forEach(el => {
            // 确保不是工具栏内的元素
            if (!el.closest('.App-toolbar') && !el.closest('[class*="App-toolbar"]') && !el.closest('[data-testid*="toolbar"]')) {
              el.style.display = 'none';
              el.style.visibility = 'hidden';
            }
          });
          
          // 隐藏Excalidraw+按钮
          const plusButtons = document.querySelectorAll(
            '.plus-banner, [class*="plus-banner"], [class*="ExcalidrawPlus"], [href*="excalidraw.com/plus"], a[href*="/plus"]'
          );
          plusButtons.forEach(el => {
            const text = el.textContent || '';
            if (text.includes('Excalidraw+') || el.href?.includes('plus')) {
              el.style.display = 'none';
              el.style.visibility = 'hidden';
            }
          });
          
          // 隐藏帮助和快捷键按钮（但确保不是工具栏的一部分）
          const helpButtons = document.querySelectorAll(
            '[data-testid*="help"], [data-testid*="Help"], [aria-label*="help"], [aria-label*="Help"], [aria-label*="快捷键"], button[title*="帮助"], button[title*="help"], .help-button, [class*="help-button"]'
          );
          helpButtons.forEach(el => {
            // 确保不是工具栏内的元素
            if (!el.closest('.App-toolbar') && !el.closest('[class*="App-toolbar"]') && !el.closest('[data-testid*="toolbar"]')) {
              el.style.display = 'none';
              el.style.visibility = 'hidden';
            }
          });
          
          // 隐藏欢迎界面中心内容
          const welcomeCenter = document.querySelectorAll(
            '.welcome-screen-center, [class*="WelcomeScreen.Center"]'
          );
          welcomeCenter.forEach(el => {
            // 确保不是工具栏内的元素
            if (!el.closest('.App-toolbar') && !el.closest('[class*="App-toolbar"]')) {
              el.style.display = 'none';
              el.style.visibility = 'hidden';
            }
          });
          
          // 隐藏实时协作按钮
          const collabButtons = document.querySelectorAll(
            '.collab-button, [class*="collab-button"], [data-testid="collab-button"], button[title*="实时协作"], button[title*="liveCollaboration"], [aria-label*="实时协作"]'
          );
          collabButtons.forEach(el => {
            // 确保不是工具栏内的其他元素
            if (!el.closest('.App-toolbar') || el.classList.contains('collab-button')) {
              el.style.display = 'none';
              el.style.visibility = 'hidden';
            }
          });
          
          // 隐藏素材库按钮 - 增强版
          const hideLibraryButton = () => {
            // 扩展选择器列表
            const selectors = [
              '[class*="library"]',
              '[class*="Library"]',
              '[class*="DefaultSidebar"]',
              '[class*="SidebarTrigger"]',
              '[class*="sidebar-trigger"]',
              'button[title*="library"]',
              'button[title*="Library"]',
              'button[title*="素材"]',
              'button[title*="素材库"]',
              '[aria-label*="library"]',
              '[aria-label*="Library"]',
              '[aria-label*="素材库"]',
              '[aria-label*="素材"]',
              '[data-testid*="library"]',
              '[data-testid*="Library"]',
              '[data-testid*="sidebar-trigger"]',
              '[data-testid*="default-sidebar"]',
              '[role="button"]'
            ];
            
            // 使用所有选择器查找元素
            selectors.forEach(selector => {
              try {
                const elements = document.querySelectorAll(selector);
                elements.forEach(el => {
                  const text = (el.textContent || '').toLowerCase();
                  const title = (el.getAttribute('title') || '').toLowerCase();
                  const aria = (el.getAttribute('aria-label') || '').toLowerCase();
                  const className = (el.className || '').toString().toLowerCase();
                  
                  // 检查是否与素材库相关
                  const isLibrary =
                    text.includes('library') ||
                    text.includes('素材') ||
                    title.includes('library') ||
                    title.includes('素材库') ||
                    title.includes('素材') ||
                    aria.includes('library') ||
                    aria.includes('素材库') ||
                    aria.includes('素材') ||
                    className.includes('library') ||
                    className.includes('sidebar') ||
                    className.includes('sidebartrigger');
                  
                  if (isLibrary) {
                    // 隐藏元素及其父按钮（如果存在）
                    const target = el.closest('button') || el;
                    target.style.display = 'none';
                    target.style.visibility = 'hidden';
                    target.style.opacity = '0';
                    target.style.pointerEvents = 'none';
                    
                    // 同时隐藏所有子元素
                    const children = target.querySelectorAll('*');
                    children.forEach(child => {
                      child.style.display = 'none';
                      child.style.visibility = 'hidden';
                    });
                  }
                });
              } catch (e) {
                // 忽略选择器错误
              }
            });
            
            // 额外检查：查找包含"素材库"文字的所有元素
            const allElements = document.querySelectorAll('*');
            allElements.forEach(el => {
              const text = el.textContent || '';
              if (text.includes('素材库') && el.tagName === 'BUTTON') {
                el.style.display = 'none';
                el.style.visibility = 'hidden';
                el.style.opacity = '0';
                el.style.pointerEvents = 'none';
              }
            });
          };
          hideLibraryButton();
          
          // 确保工具栏始终显示
          const toolbars = document.querySelectorAll(
            '.App-toolbar, [class*="App-toolbar"], [data-testid*="toolbar"]'
          );
          toolbars.forEach(el => {
            el.style.display = '';
            el.style.visibility = '';
          });
        });
        
        // 开始观察
        observer.observe(document.body, {
          childList: true,
          subtree: true,
          attributes: true,
          attributeFilter: ['style', 'class', 'href']
        });
        
        // 立即执行一次隐藏
        setTimeout(() => {
          // 隐藏欢迎界面（但确保不是工具栏的一部分）
          const welcomeScreens = document.querySelectorAll(
            '.welcome-screen, [class*="WelcomeScreen"], [class*="welcome-screen"], [data-testid*="welcome"]'
          );
          welcomeScreens.forEach(el => {
            // 确保不是工具栏内的元素
            if (!el.closest('.App-toolbar') && !el.closest('[class*="App-toolbar"]') && !el.closest('[data-testid*="toolbar"]')) {
              el.style.display = 'none';
              el.style.visibility = 'hidden';
            }
          });
          
          // 隐藏Excalidraw+按钮
          const plusButtons = document.querySelectorAll(
            '.plus-banner, [class*="plus-banner"], [href*="excalidraw.com/plus"], a[href*="/plus"]'
          );
          plusButtons.forEach(el => {
            const text = el.textContent || '';
            if (text.includes('Excalidraw+') || el.href?.includes('plus')) {
              el.style.display = 'none';
              el.style.visibility = 'hidden';
            }
          });
          
          // 隐藏帮助按钮（但确保不是工具栏的一部分）
          const helpButtons = document.querySelectorAll(
            '[data-testid*="help"], [aria-label*="help"], [aria-label*="快捷键"], button[title*="帮助"]'
          );
          helpButtons.forEach(el => {
            // 确保不是工具栏内的元素
            if (!el.closest('.App-toolbar') && !el.closest('[class*="App-toolbar"]') && !el.closest('[data-testid*="toolbar"]')) {
              el.style.display = 'none';
              el.style.visibility = 'hidden';
            }
          });
          
          // 隐藏实时协作按钮
          const collabButtons = document.querySelectorAll(
            '.collab-button, [class*="collab-button"], [data-testid="collab-button"], button[title*="实时协作"], button[title*="liveCollaboration"], [aria-label*="实时协作"]'
          );
          collabButtons.forEach(el => {
            el.style.display = 'none';
            el.style.visibility = 'hidden';
          });
          
          // 隐藏素材库按钮 - 增强版（setTimeout中调用）
          const hideLibraryButtonDelayed = () => {
            // 扩展选择器列表
            const selectors = [
              '[class*="library"]',
              '[class*="Library"]',
              '[class*="DefaultSidebar"]',
              '[class*="SidebarTrigger"]',
              '[class*="sidebar-trigger"]',
              'button[title*="library"]',
              'button[title*="Library"]',
              'button[title*="素材"]',
              'button[title*="素材库"]',
              '[aria-label*="library"]',
              '[aria-label*="Library"]',
              '[aria-label*="素材库"]',
              '[aria-label*="素材"]',
              '[data-testid*="library"]',
              '[data-testid*="Library"]',
              '[data-testid*="sidebar-trigger"]',
              '[data-testid*="default-sidebar"]',
              '[role="button"]'
            ];
            
            // 使用所有选择器查找元素
            selectors.forEach(selector => {
              try {
                const elements = document.querySelectorAll(selector);
                elements.forEach(el => {
                  const text = (el.textContent || '').toLowerCase();
                  const title = (el.getAttribute('title') || '').toLowerCase();
                  const aria = (el.getAttribute('aria-label') || '').toLowerCase();
                  const className = (el.className || '').toString().toLowerCase();
                  
                  // 检查是否与素材库相关
                  const isLibrary =
                    text.includes('library') ||
                    text.includes('素材') ||
                    title.includes('library') ||
                    title.includes('素材库') ||
                    title.includes('素材') ||
                    aria.includes('library') ||
                    aria.includes('素材库') ||
                    aria.includes('素材') ||
                    className.includes('library') ||
                    className.includes('sidebar') ||
                    className.includes('sidebartrigger') ||
                    className.includes('defaultsidebar');
                  
                  if (isLibrary) {
                    // 隐藏元素及其父按钮（如果存在）
                    const target = el.closest('button') || el;
                    target.style.display = 'none';
                    target.style.visibility = 'hidden';
                    target.style.opacity = '0';
                    target.style.pointerEvents = 'none';
                    
                    // 同时隐藏所有子元素
                    const children = target.querySelectorAll('*');
                    children.forEach(child => {
                      child.style.display = 'none';
                      child.style.visibility = 'hidden';
                    });
                  }
                });
              } catch (e) {
                // 忽略选择器错误
              }
            });
            
            // 额外检查：查找包含"素材库"文字的所有元素
            const allElements = document.querySelectorAll('*');
            allElements.forEach(el => {
              const text = el.textContent || '';
              if (text.includes('素材库') && el.tagName === 'BUTTON') {
                el.style.display = 'none';
                el.style.visibility = 'hidden';
                el.style.opacity = '0';
                el.style.pointerEvents = 'none';
              }
            });
          };
          hideLibraryButtonDelayed();
          
          // 确保工具栏始终显示
          const toolbars = document.querySelectorAll(
            '.App-toolbar, [class*="App-toolbar"], [data-testid*="toolbar"]'
          );
          toolbars.forEach(el => {
            el.style.display = '';
            el.style.visibility = '';
          });
        }, 200);
        
        // 保存observer到window
        window._ponynotesUIObserver = observer;
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

        // 使用MutationObserver持续监听
        const observer = new MutationObserver(() => {
          // 隐藏欢迎界面中心的所有内容
          const welcomeCenters = document.querySelectorAll(
            '.welcome-screen-center, [class*="WelcomeScreen.Center"], [class*="welcome-screen-center"]'
          );
          welcomeCenters.forEach(el => {
            // 确保不是工具栏内的元素
            if (!el.closest('.App-toolbar') && !el.closest('[class*="App-toolbar"]') && !el.closest('[data-testid*="toolbar"]')) {
              el.style.display = 'none';
              el.style.visibility = 'hidden';
            }
          });
          
          // 确保工具栏始终显示
          const toolbars = document.querySelectorAll(
            '.App-toolbar, [class*="App-toolbar"], [data-testid*="toolbar"]'
          );
          toolbars.forEach(el => {
            el.style.display = '';
            el.style.visibility = '';
            // 确保flex布局
            if (getComputedStyle(el).display !== 'flex' && getComputedStyle(el).display !== 'inline-flex') {
              el.style.display = 'flex';
            }
          });
        });

        // 开始观察
        observer.observe(document.body || document.documentElement, {
          childList: true,
          subtree: true,
          attributes: true,
          attributeFilter: ['class', 'style']
        });

        // 立即执行一次（不延迟，避免闪现）
        const hideWelcomeCenter = () => {
          const welcomeCenters = document.querySelectorAll(
            '.welcome-screen-center, [class*="WelcomeScreen.Center"], [class*="welcome-screen-center"]'
          );
          welcomeCenters.forEach(el => {
            if (!el.closest('.App-toolbar') && !el.closest('[class*="App-toolbar"]') && !el.closest('[data-testid*="toolbar"]')) {
              el.style.display = 'none';
              el.style.visibility = 'hidden';
            }
          });
          
          // 确保工具栏显示
          const toolbars = document.querySelectorAll(
            '.App-toolbar, [class*="App-toolbar"], [data-testid*="toolbar"]'
          );
          toolbars.forEach(el => {
            el.style.display = '';
            el.style.visibility = '';
          });
        };

        // 立即执行
        hideWelcomeCenter();
        
        // 也延迟执行一次，确保捕获动态创建的元素
        setTimeout(hideWelcomeCenter, 50);
        setTimeout(hideWelcomeCenter, 200);

        window._ponynotesLoadingObserver = observer;
      })();
    ''', tag: 'hideLoadingLogo');
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
      final theme = Theme.of(context).brightness == Brightness.dark ? 'dark' : 'light';
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
          key: ValueKey('inappwebview_${widget.viewId}_global_$_inAppWebViewInstanceId'),
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
              print('💾 localStorage set: $localStorageKey = $jsonValue');
            });
            print('🌐 [ExcalidrawWebView] WebView created');
          },

          shouldOverrideUrlLoading: (controller, navigationAction) async {
            // 允许加载本地服务器的所有资源
            final url = navigationAction.request.url.toString();
            if (url.startsWith('http://localhost:') || url.startsWith('http://127.0.0.1:')) {
              print('✅ [ExcalidrawWebView] Allowing navigation to: $url');
              return NavigationActionPolicy.ALLOW;
            }
            print('⚠️ [ExcalidrawWebView] Blocking navigation to: $url');
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
            print('🔄 [ExcalidrawWebView] Loading started: $url');
          },

          onLoadStop: (controller, url) async {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _pageLoaded = true;
              });
              await _initializeExcalidraw();
            }
            print('✅ [ExcalidrawWebView] Loading finished: $url');
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
            print('❌ [ExcalidrawWebView] Load error: $message (code: $code)');
            widget.onError?.call('WebView加载错误: $message');
          },

          onLoadHttpError: (controller, url, statusCode, description) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _loadingError = 'HTTP错误 $statusCode: $description';
              });
            }
            print('❌ [ExcalidrawWebView] HTTP error: $statusCode - $description');
          },

          onConsoleMessage: (controller, consoleMessage) {
            // 打印 WebView 控制台消息（用于调试）
            // print('[WebView Console] ${consoleMessage.message}');
          },
        ),

        if (_isLoading)
          Container(
            color: Colors.white.withOpacity(0.9),
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    '正在加载专业白板编辑器...',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
