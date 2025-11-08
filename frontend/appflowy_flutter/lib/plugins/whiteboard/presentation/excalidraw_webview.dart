import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:appflowy/plugins/whiteboard/application/local_asset_server.dart';

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
  final Function(Map<String, dynamic> data)? onDataChanged;
  final Function(String format, dynamic data)? onExport;
  final Function(String error)? onError;

  @override
  State<ExcalidrawWebView> createState() => _ExcalidrawWebViewState();
}

class _ExcalidrawWebViewState extends State<ExcalidrawWebView> {
  InAppWebViewController? _controller;
  bool _isLoading = true;
  bool isInitialized = false; // 标记 Excalidraw 是否已初始化
  String? _loadingError;
  final _assetServer = LocalAssetServer();
  String? _whiteboardUrl;
  late InAppWebViewSettings _settings;
  
  // 🚀 新增：自动保存定时器
  Timer? _autoSaveTimer;
  String? _lastSavedDataHash; // 用于检测数据是否真正变化

  /// 获取唯一的 WebView key
  /// 优先使用父组件传递的唯一 key，如果没有则使用 viewId
  String _getUniqueWebViewKey() {
    if (widget.key is ValueKey) {
      final valueKey = widget.key as ValueKey;
      // 父组件传递的 key 格式：'${viewId}_global_${instanceId}'
      // 确保 value 是字符串类型
      final keyValue = valueKey.value?.toString() ?? widget.viewId;
      return 'inappwebview_$keyValue';
    }
    // 如果没有 key 或 key 不是 ValueKey，使用 viewId
    return 'inappwebview_${widget.viewId}';
  }

  @override
  void initState() {
    super.initState();
    print('🚀 [ExcalidrawWebView] initState() called for viewId: ${widget.viewId}');
    _initializeSettings();
    _loadExcalidrawHTML();
    // 🚀 延迟启动自动保存，等待 WebView 完全初始化
    // 不在这里立即启动，而是在 onWebViewCreated 中启动
  }

  void _initializeSettings() {
    _settings = InAppWebViewSettings(
      javaScriptEnabled: true,
      transparentBackground: true,
      useShouldOverrideUrlLoading: true,
      mediaPlaybackRequiresUserGesture: false,
      cacheEnabled: false,
      // 🔧 启用调试和控制台日志
      isInspectable: true, // 允许调试（macOS/iOS）
      clearCache: false, // 保留缓存以提高性能
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
      print('🔄 [ExcalidrawWebView] 启动本地HTTP服务器...');
      
      // 启动本地HTTP服务器
      final baseUrl = await _assetServer.start();
      
      // 使用带 viewId 的URL（用于调试和日志追踪）
      // 注意：localStorage 已在 HTML 中被完全禁用，数据隔离由 Flutter 管理
      final url = '$baseUrl/whiteboard/${widget.viewId}/flutter_bridge.html';
      
      print('✅ [ExcalidrawWebView] 服务器已启动: $baseUrl');
      print('📄 [ExcalidrawWebView] 加载URL: $url');
      print('🆔 [ExcalidrawWebView] ViewID: ${widget.viewId}');
      print('🔒 [ExcalidrawWebView] localStorage: DISABLED (数据由 Flutter 管理)');
      print('💾 [ExcalidrawWebView] 数据源: ${widget.initialData != null ? "从文件加载 (${widget.initialData!.keys.length} keys)" : "新建空白板"}');
      
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
      print('❌ 加载Excalidraw失败: $e');
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
    // 注册 JavaScript Handler（替代 addJavaScriptChannel）
    controller.addJavaScriptHandler(
      handlerName: 'ExcalidrawBridge',
      callback: (args) {
        if (args.isNotEmpty) {
          final message = args[0];
          if (message is String) {
            _handleWebViewMessage(message);
          } else if (message is Map) {
            // 如果 JS 端直接传递对象，转换为 JSON 字符串
            _handleWebViewMessage(jsonEncode(message));
          }
        }
      },
    );
  }

  Future<void> _initializeExcalidraw() async {
    try {
      print('🎨 [ExcalidrawWebView] Initializing Excalidraw...');
      print('🆔 [ExcalidrawWebView] ViewID: ${widget.viewId}');
      
      // 准备加载的数据（包含viewId）
      Map<String, dynamic> dataToLoad = {};
      if (widget.initialData != null) {
        dataToLoad = Map.from(widget.initialData!);
        print('📦 [ExcalidrawWebView] Loading initial data: ${dataToLoad.keys.length} keys');
      } else {
        print('⚠️ [ExcalidrawWebView] No initial data, creating empty whiteboard');
      }
      
      // 🔑 关键：添加 viewId 到数据中
      dataToLoad['viewId'] = widget.viewId;
      
      final dataJson = jsonEncode(dataToLoad);
      print('📝 [ExcalidrawWebView] Data JSON length: ${dataJson.length} chars');
      
      await _controller?.evaluateJavascript(source: '''
        console.log('[ExcalidrawWebView] Loading data into Excalidraw with viewId: ${widget.viewId}');
        if (window.loadExcalidrawData) {
          window.loadExcalidrawData($dataJson);
          console.log('[ExcalidrawWebView] Data loaded successfully');
        } else {
          console.error('[ExcalidrawWebView] window.loadExcalidrawData not found!');
        }
      ''');
      print('✅ [ExcalidrawWebView] Initial data loaded with viewId');
      
      // 设置主题
      final theme = Theme.of(context).brightness == Brightness.dark ? 'dark' : 'light';
      print('🎨 [ExcalidrawWebView] Setting theme: $theme');
      await _controller?.evaluateJavascript(source: '''
        console.log('[ExcalidrawWebView] Setting theme to $theme');
        if (window.setTheme) {
          window.setTheme('$theme');
        } else {
          console.error('[ExcalidrawWebView] window.setTheme not found!');
        }
      ''');
      print('✅ [ExcalidrawWebView] Initialization complete');
    } catch (e) {
      print('❌ [ExcalidrawWebView] Initialization failed: $e');
      widget.onError?.call('初始化Excalidraw失败: $e');
    }
  }

  /// 🚀 启动自动保存定时器
  /// 每2秒通过 getExcalidrawData() 获取当前画布数据并保存
  void _startAutoSave() {
    print('⏰ [AutoSave] Starting auto-save timer (interval: 2 seconds)');
    print('⏰ [AutoSave] Will use window.getExcalidrawData() to fetch canvas data');
    
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (_controller == null || !mounted || !isInitialized) {
        return;
      }
      
      try {
        // 🔑 关键修改：调用 window.getExcalidrawData() 触发数据获取
        // 这会通过 iframe postMessage 机制获取当前画布数据
        // 数据会通过 'excalidraw-data' 消息返回到 _handleWebViewMessage
        print('🔄 [AutoSave] Requesting current canvas data...');
        await _controller!.evaluateJavascript(source: '''
          (function() {
            try {
              if (window.getExcalidrawData) {
                console.log('[AutoSave] Calling window.getExcalidrawData()');
                window.getExcalidrawData();
                return true;
              } else {
                console.error('[AutoSave] window.getExcalidrawData not found!');
                return false;
              }
            } catch (e) {
              console.error('[AutoSave] Error calling getExcalidrawData:', e);
              return false;
            }
          })();
        ''');
      } catch (e) {
        print('⚠️ [AutoSave] Error: $e');
      }
    });
  }


  @override
  void dispose() {
    print('🗑️ [ExcalidrawWebView] dispose() called for viewId: ${widget.viewId}');
    
    // 🚀 清理自动保存定时器
    if (_autoSaveTimer != null) {
      _autoSaveTimer!.cancel();
      _autoSaveTimer = null;
      print('⏰ [AutoSave] Timer cancelled for viewId: ${widget.viewId}');
    }
    
    // 清理 controller 引用
    _controller = null;
    
    // ⚠️ 不要停止本地HTTP服务器！
    // LocalAssetServer是单例，被所有白板视图共享
    // 如果在这里stop()，会导致其他白板视图的服务器也被停止
    // 服务器应该在应用关闭时统一清理，而不是在每个Widget dispose时
    // _assetServer.stop(); // ❌ 这会导致切换白板时服务器被停止
    
    // flutter_inappwebview 的 controller 会自动清理
    super.dispose();
    print('✅ [ExcalidrawWebView] dispose() completed for viewId: ${widget.viewId}');
  }

  void _handleWebViewMessage(String message) {
    try {
      print('🔔 [ExcalidrawWebView] Received message (length: ${message.length})');
      
      final data = jsonDecode(message);
      final type = data['type'] as String;
      final payload = data['payload'];

      print('🔔 [ExcalidrawWebView] Message type: $type');
      
      switch (type) {
        case 'ready':
        case 'excalidraw-ready':
          print('✅ [Whiteboard] Excalidraw ready: $payload');
          if (mounted) {
            setState(() {
              _isLoading = false;
              isInitialized = true; // 标记为已初始化
            });
          }
          // 初始化完成后，发送初始数据
          _initializeExcalidraw();
          break;
        case 'dataChanged':
        case 'excalidraw-change':
          // 🔑 处理数据变更，包含 viewId 信息
          final viewId = payload != null && payload is Map ? payload['viewId'] : null;
          final elementsCount = payload != null && payload is Map && payload['elements'] is List ? (payload['elements'] as List).length : 0;
          
          print('💾💾💾 [Whiteboard] 🚨 DATA CHANGE DETECTED! 🚨');
          print('💾 [Whiteboard] viewId: $viewId (expected: ${widget.viewId})');
          print('💾 [Whiteboard] Elements count: $elementsCount');
          print('💾 [Whiteboard] Payload keys: ${payload != null && payload is Map ? payload.keys.toList() : 'null'}');
          
          // 🔍 打印完整 payload 以便调试
          if (payload is Map) {
            print('💾 [Whiteboard] 📄 Full payload: $payload');
            if (payload.containsKey('elements')) {
              final elements = payload['elements'];
              if (elements is List && elements.isNotEmpty) {
                print('💾 [Whiteboard] 📄 First element: ${elements.first}');
              }
            }
          }
          
          // 确认 viewId 匹配
          if (viewId != null && viewId != widget.viewId) {
            print('⚠️ [Whiteboard] ViewID mismatch! Expected: ${widget.viewId}, Got: $viewId');
          }
          
          if (elementsCount == 0) {
            print('⚠️⚠️⚠️ [Whiteboard] WARNING: Elements count is 0! No content to save!');
          } else {
            print('✅ [Whiteboard] Elements detected: $elementsCount items');
          }
          
          widget.onDataChanged?.call(payload);
          break;
        case 'debug-log':
          // 处理来自 iframe 的调试日志
          final level = payload['level'] ?? 'info';
          final msg = payload['message'] ?? '';
          if (level == 'error') {
            print('🔴 [Whiteboard Debug] $msg');
          } else if (level == 'warn') {
            print('⚠️ [Whiteboard Debug] $msg');
          } else {
            print('🔵 [Whiteboard Debug] $msg');
          }
          break;
        case 'export':
          print('📤 [Whiteboard] 导出: ${payload['format']}');
          widget.onExport?.call(payload['format'], payload['data']);
          break;
        case 'error':
        case 'excalidraw-error':
          final errorMsg = payload is Map ? payload['message'] : payload.toString();
          print('❌ [Whiteboard] Excalidraw错误: $errorMsg');
          widget.onError?.call(errorMsg);
          break;
        case 'excalidraw-data':
          // 🔑 获取数据响应（来自自动保存的 getExcalidrawData 调用）
          if (payload != null && payload is Map) {
            // 转换为 Map<String, dynamic>
            final dataMap = Map<String, dynamic>.from(payload);
            final elementsCount = dataMap['elements'] is List ? (dataMap['elements'] as List).length : 0;
            print('📦 [AutoSave] Received canvas data: elements=$elementsCount, keys=${dataMap.keys.length}');
            
            // 计算数据哈希值
            final dataStr = jsonEncode(dataMap);
            final dataHash = dataStr.hashCode.toString();
            
            // 检查数据是否真的变化了
            if (_lastSavedDataHash == dataHash) {
              // 数据没变化，跳过保存
              print('⏭️ [AutoSave] Data unchanged, skipping save');
              return;
            }
            
            // 数据变化了，保存！
            print('💾 [AutoSave] Data changed detected, saving... (hash: $dataHash)');
            print('📦 [AutoSave] Elements: $elementsCount items');
            
            // 通知上层保存
            widget.onDataChanged?.call(dataMap);
            
            // 更新最后保存的哈希值
            _lastSavedDataHash = dataHash;
            
            print('✅ [AutoSave] Data saved successfully');
          } else {
            print('⚠️ [AutoSave] Received invalid data: ${payload?.runtimeType}');
          }
          break;
        default:
          print('❓ [Whiteboard] Unknown message type: $type');
      }
    } catch (e) {
      print('Error handling WebView message: $e');
      widget.onError?.call('处理WebView消息失败: $e');
    }
  }

  /// 导出绘图
  Future<void> exportDrawing(String format) async {
    try {
      await _controller?.evaluateJavascript(source: '''
        if (window.exportExcalidraw) {
          window.exportExcalidraw('$format');
        }
      ''');
    } catch (e) {
      widget.onError?.call('导出失败: $e');
    }
  }

  /// 获取当前白板数据
  Future<void> getData() async {
    try {
      await _controller?.evaluateJavascript(source: '''
        if (window.getExcalidrawData) {
          window.getExcalidrawData();
        }
      ''');
    } catch (e) {
      widget.onError?.call('获取数据失败: $e');
    }
  }

  /// 加载白板数据
  Future<void> loadData(Map<String, dynamic> data) async {
    try {
      await _controller?.evaluateJavascript(source: '''
        if (window.loadExcalidrawData) {
          window.loadExcalidrawData(${jsonEncode(data)});
        }
      ''');
    } catch (e) {
      widget.onError?.call('加载数据失败: $e');
    }
  }

  /// 清空画布
  Future<void> clearCanvas() async {
    try {
      await _controller?.evaluateJavascript(source: '''
        if (window.clearCanvas) {
          window.clearCanvas();
        }
      ''');
    } catch (e) {
      widget.onError?.call('清空画布失败: $e');
    }
  }

  /// 撤销操作
  Future<void> undo() async {
    try {
      await _controller?.evaluateJavascript(source: '''
        if (window.undo) {
          window.undo();
        }
      ''');
    } catch (e) {
      widget.onError?.call('撤销失败: $e');
    }
  }

  /// 重做操作
  Future<void> redo() async {
    try {
      await _controller?.evaluateJavascript(source: '''
        if (window.redo) {
          window.redo();
        }
      ''');
    } catch (e) {
      widget.onError?.call('重做失败: $e');
    }
  }

  /// 更新主题
  Future<void> updateTheme(String theme) async {
    try {
      await _controller?.evaluateJavascript(source: '''
        if (window.setTheme) {
          window.setTheme('$theme');
        }
      ''');
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

    // 🔑 获取唯一的 WebView key
    final webViewKey = _getUniqueWebViewKey();
    print('🔑 [ExcalidrawWebView] Creating InAppWebView with key: $webViewKey');
    print('🔑 [ExcalidrawWebView] ViewId: ${widget.viewId}');
    print('🔑 [ExcalidrawWebView] Widget key: ${widget.key}');
    
    return Stack(
      children: [
        InAppWebView(
          // ✅ 使用父组件传递的唯一 key 来生成 InAppWebView 的 key
          // 父组件的 key 格式：'${viewId}_global_${instanceId}'
          // 这样可以确保每个 WebView 实例都有全局唯一的 key，避免平台视图 ID 冲突
          key: ValueKey(webViewKey),
          initialUrlRequest: URLRequest(
            url: WebUri(_whiteboardUrl!),
          ),
          initialSettings: _settings,
          
          onWebViewCreated: (controller) {
            _controller = controller;
            _setupJavaScriptHandlers(controller);
            print('🌐 [ExcalidrawWebView] WebView created for viewId: ${widget.viewId}');
            print('🌐 [ExcalidrawWebView] WebView key: $webViewKey');
            print('🌐 [ExcalidrawWebView] 视图已创建: ${widget.viewId}');
            
            // 🚀 在 WebView 创建后启动自动保存
            // 延迟3秒，确保 Excalidraw 完全初始化
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted && _controller != null) {
                _startAutoSave();
              }
            });
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
              });
            }
            print('🔄 [ExcalidrawWebView] Loading started: $url');
          },
          
          onLoadStop: (controller, url) async {
            if (mounted) {
              setState(() => _isLoading = false);
              // ⚠️ 不要在这里初始化！
              // Excalidraw 需要时间来加载和初始化
              // 应该等待 'excalidraw-ready' 消息后再初始化
              // await _initializeExcalidraw(); // ❌ 这会导致过早调用，window.loadExcalidrawData 还未定义
              
              // 🔍 测试：执行一段 JavaScript，看看 console.log 是否被捕获
              await controller.evaluateJavascript(source: '''
                console.log('🧪 [TEST] Console test from Dart - this should appear in logs!');
                console.error('🧪 [TEST] Error test from Dart');
                console.warn('🧪 [TEST] Warning test from Dart');
              ''');
              print('🧪 [TEST] JavaScript console test executed');
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
            // 🔍 测试：打印所有控制台消息，不过滤
            final level = consoleMessage.messageLevel;
            final message = consoleMessage.message;
            
            // 先打印一个标记，确认这个回调被调用了
            print('🔔 [WebView Console] Callback triggered! Level: $level');
            
            if (level == ConsoleMessageLevel.ERROR) {
              print('🔴 [WebView Console ERROR] $message');
            } else if (level == ConsoleMessageLevel.WARNING) {
              print('⚠️ [WebView Console WARN] $message');
            } else {
              // 🔍 暂时打印所有日志，不过滤
              print('📺 [WebView Console] $message');
            }
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
