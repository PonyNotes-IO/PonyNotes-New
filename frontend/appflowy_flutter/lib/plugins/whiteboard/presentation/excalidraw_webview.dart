import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:appflowy/plugins/whiteboard/application/local_asset_server.dart';

import '../application/whiteboard_data_service.dart';
import 'package:appflowy_backend/log.dart';

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
  State<ExcalidrawWebView> createState() => _ExcalidrawWebViewState();
}

class _ExcalidrawWebViewState extends State<ExcalidrawWebView> {
  InAppWebViewController? _controller;
  bool _isLoading = true;
  String? _loadingError;
  final _assetServer = LocalAssetServer();
  String? _whiteboardUrl;
  late InAppWebViewSettings _settings;
  bool _webViewCreated = false;
  bool _pageLoaded = false;

  @override
  void initState() {
    super.initState();
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

  /// 获取当前白板数据
  Future<void> getData() async {
    try {
      await _safeEvalJs('''
        console.log('window.getExcalidrawData',window.getExcalidrawData);
        if (window.getExcalidrawData) {
          window.getExcalidrawData();
        }
      ''', tag: 'getData');
    } catch (e) {
      widget.onError?.call('获取数据失败: $e');
    }
  }

  /// 加载白板数据
  Future<void> loadData(Map<String, dynamic> data) async {
    try {
      await _safeEvalJs('''
        if (window.loadExcalidrawData) {
          window.loadExcalidrawData(${jsonEncode(data)});
        }
      ''', tag: 'loadData');
    } catch (e) {
      widget.onError?.call('加载数据失败: $e');
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

  /// 更新主题
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
          // ❌ 不要使用 widget.key！会导致热重启时 view id 冲突
          // ✅ InAppWebView 不需要 key，因为父 widget 已经有唯一 key 了
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
