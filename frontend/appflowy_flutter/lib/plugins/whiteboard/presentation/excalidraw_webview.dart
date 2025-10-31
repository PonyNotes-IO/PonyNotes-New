import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:appflowy/plugins/whiteboard/application/local_asset_server.dart';

/// Excalidraw WebView 组件
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
  late final WebViewController _controller;
  bool _isLoading = true;
  String? _loadingError;
  final _assetServer = LocalAssetServer();

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
    
    // 只在非 macOS 平台设置背景色，避免 macOS 上的 opaque 错误
    if (!Platform.isMacOS) {
      _controller.setBackgroundColor(const Color(0x00000000));
    }
    
    _controller
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            // 更新加载进度
            if (mounted) {
              setState(() {
                // 可以在这里更新进度条
              });
            }
          },
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _loadingError = null;
              });
            }
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() => _isLoading = false);
              _initializeExcalidraw();
            }
          },
          onWebResourceError: (WebResourceError error) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _loadingError = error.description;
              });
            }
            widget.onError?.call('WebView加载错误: ${error.description}');
          },
        ),
      )
      ..addJavaScriptChannel(
        'ExcalidrawBridge',
        onMessageReceived: (JavaScriptMessage message) {
          _handleWebViewMessage(message.message);
        },
      );

    // 加载本地HTML文件
    _loadExcalidrawHTML();
  }

  Future<void> _loadExcalidrawHTML() async {
    try {
      print('🔄 [ExcalidrawWebView] 启动本地HTTP服务器...');
      
      // 启动本地HTTP服务器
      final baseUrl = await _assetServer.start();
      
      // 使用带 viewId 的URL（用于调试和日志追踪）
      // 注意：localStorage 已在 HTML 中被完全禁用，数据隔离由 Flutter 管理
      final whiteboardUrl = '$baseUrl/whiteboard/${widget.viewId}/flutter_bridge.html';
      
      print('✅ [ExcalidrawWebView] 服务器已启动: $baseUrl');
      print('📄 [ExcalidrawWebView] 加载URL: $whiteboardUrl');
      print('🆔 [ExcalidrawWebView] ViewID: ${widget.viewId}');
      print('🔒 [ExcalidrawWebView] localStorage: DISABLED (数据由 Flutter 管理)');
      print('💾 [ExcalidrawWebView] 数据源: ${widget.initialData != null ? "从文件加载 (${widget.initialData!.keys.length} keys)" : "新建空白板"}');
      
      // 通过HTTP加载flutter_bridge.html，它会通过iframe加载完整的Excalidraw (index.html)
      await _controller.loadRequest(Uri.parse(whiteboardUrl));
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
      
      await _controller.runJavaScript('''
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
      await _controller.runJavaScript('''
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


  @override
  void dispose() {
    // ⚠️ 不要停止本地HTTP服务器！
    // LocalAssetServer是单例，被所有白板视图共享
    // 如果在这里stop()，会导致其他白板视图的服务器也被停止
    // 服务器应该在应用关闭时统一清理，而不是在每个Widget dispose时
    // _assetServer.stop(); // ❌ 这会导致切换白板时服务器被停止
    
    // 清理WebViewController资源
    // 注意：webview_flutter 4.x版本的WebViewController没有显式的dispose方法
    // 但我们仍然需要重写dispose以确保State正确清理
    super.dispose();
  }

  void _handleWebViewMessage(String message) {
    try {
      final data = jsonDecode(message);
      final type = data['type'] as String;
      final payload = data['payload'];

      switch (type) {
        case 'ready':
        case 'excalidraw-ready':
          print('✅ [Whiteboard] Excalidraw ready: $payload');
          if (mounted) {
            setState(() => _isLoading = false);
          }
          // 初始化完成后，发送初始数据
          _initializeExcalidraw();
          break;
        case 'dataChanged':
        case 'excalidraw-change':
          // 🔑 处理数据变更，包含 viewId 信息
          final viewId = payload != null && payload is Map ? payload['viewId'] : null;
          print('💾 [Whiteboard] 数据变更检测: viewId=$viewId, keys=${payload != null ? (payload is Map ? payload.keys.length : 'invalid') : 'null'}');
          
          // 确认 viewId 匹配
          if (viewId != null && viewId != widget.viewId) {
            print('⚠️ [Whiteboard] ViewID mismatch! Expected: ${widget.viewId}, Got: $viewId');
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
          // 获取数据响应
          print('📦 [Whiteboard] 获取到数据: ${payload != null ? (payload is Map ? payload.keys.length : 'invalid') : 'null'} keys');
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
      await _controller.runJavaScript('''
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
      await _controller.runJavaScript('''
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
      await _controller.runJavaScript('''
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
      await _controller.runJavaScript('''
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
      await _controller.runJavaScript('''
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
      await _controller.runJavaScript('''
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
      await _controller.runJavaScript('''
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

    return Stack(
      children: [
        WebViewWidget(controller: _controller),
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
