import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
      // 创建一个真正可用的简单绘图HTML页面
      const htmlContent = '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PonyNotes 简易白板</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background: #f8f9fa;
            overflow: hidden;
        }
        
        .whiteboard-container {
            width: 100vw;
            height: 100vh;
            display: flex;
            flex-direction: column;
        }
        
        .toolbar {
            background: white;
            border-bottom: 1px solid #e0e0e0;
            padding: 8px 16px;
            display: flex;
            align-items: center;
            gap: 12px;
            flex-shrink: 0;
        }
        
        .tool-group {
            display: flex;
            gap: 4px;
            align-items: center;
        }
        
        .tool-btn {
            padding: 8px 12px;
            border: 1px solid #ddd;
            background: white;
            border-radius: 6px;
            cursor: pointer;
            font-size: 14px;
            transition: all 0.2s;
        }
        
        .tool-btn:hover {
            background: #f5f5f5;
        }
        
        .tool-btn.active {
            background: #007AFF;
            color: white;
            border-color: #007AFF;
        }
        
        .color-picker {
            width: 32px;
            height: 32px;
            border: 2px solid #ddd;
            border-radius: 50%;
            cursor: pointer;
            background: #000000;
        }
        
        .size-slider {
            width: 100px;
        }
        
        .canvas-container {
            flex: 1;
            position: relative;
            background: white;
            overflow: hidden;
        }
        
        #drawingCanvas {
            position: absolute;
            top: 0;
            left: 0;
            cursor: crosshair;
            background: white;
        }
        
        .status-bar {
            background: #f8f9fa;
            border-top: 1px solid #e0e0e0;
            padding: 4px 16px;
            font-size: 12px;
            color: #666;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
    </style>
</head>
<body>
    <div class="whiteboard-container">
        <!-- 工具栏 -->
        <div class="toolbar">
            <div class="tool-group">
                <button class="tool-btn active" data-tool="pen">✏️ 画笔</button>
                <button class="tool-btn" data-tool="line">📏 直线</button>
                <button class="tool-btn" data-tool="rectangle">⬜ 矩形</button>
                <button class="tool-btn" data-tool="circle">⭕ 圆形</button>
                <button class="tool-btn" data-tool="text">📝 文字</button>
                <button class="tool-btn" data-tool="eraser">🧽 橡皮</button>
            </div>
            
            <div class="tool-group">
                <label>颜色:</label>
                <input type="color" class="color-picker" id="colorPicker" value="#000000">
            </div>
            
            <div class="tool-group">
                <label>粗细:</label>
                <input type="range" class="size-slider" id="sizeSlider" min="1" max="20" value="3">
                <span id="sizeDisplay">3px</span>
            </div>
            
            <div class="tool-group">
                <button class="tool-btn" onclick="clearCanvas()">🗑️ 清空</button>
                <button class="tool-btn" onclick="undoAction()">↶ 撤销</button>
                <button class="tool-btn" onclick="saveDrawing()">💾 保存</button>
            </div>
        </div>
        
        <!-- 画布区域 -->
        <div class="canvas-container">
            <canvas id="drawingCanvas"></canvas>
        </div>
        
        <!-- 状态栏 -->
        <div class="status-bar">
            <span id="statusText">准备就绪</span>
            <span id="coordinatesText">坐标: (0, 0)</span>
        </div>
    </div>

    <script>
        // 全局变量
        let canvas, ctx;
        let isDrawing = false;
        let currentTool = 'pen';
        let currentColor = '#000000';
        let currentSize = 3;
        let startX, startY;
        let drawingHistory = [];
        let historyIndex = -1;
        
        // 初始化画布
        function initCanvas() {
            canvas = document.getElementById('drawingCanvas');
            ctx = canvas.getContext('2d');
            
            // 设置画布大小
            resizeCanvas();
            window.addEventListener('resize', resizeCanvas);
            
            // 绑定事件
            canvas.addEventListener('mousedown', startDrawing);
            canvas.addEventListener('mousemove', draw);
            canvas.addEventListener('mouseup', stopDrawing);
            canvas.addEventListener('mouseout', stopDrawing);
            
            // 触摸事件支持
            canvas.addEventListener('touchstart', handleTouch);
            canvas.addEventListener('touchmove', handleTouch);
            canvas.addEventListener('touchend', handleTouch);
            
            // 鼠标坐标显示
            canvas.addEventListener('mousemove', updateCoordinates);
            
            // 保存初始状态
            saveState();
            
            // 通知Flutter初始化完成
            sendToFlutter('initialized', {
                status: 'ready',
                canvasSize: { width: canvas.width, height: canvas.height }
            });
        }
        
        function resizeCanvas() {
            const container = canvas.parentElement;
            canvas.width = container.clientWidth;
            canvas.height = container.clientHeight;
            
            // 设置画布样式
            ctx.lineCap = 'round';
            ctx.lineJoin = 'round';
        }
        
        function startDrawing(e) {
            isDrawing = true;
            const rect = canvas.getBoundingClientRect();
            startX = e.clientX - rect.left;
            startY = e.clientY - rect.top;
            
            ctx.beginPath();
            ctx.strokeStyle = currentColor;
            ctx.lineWidth = currentSize;
            
            if (currentTool === 'pen' || currentTool === 'eraser') {
                if (currentTool === 'eraser') {
                    ctx.globalCompositeOperation = 'destination-out';
                } else {
                    ctx.globalCompositeOperation = 'source-over';
                }
                ctx.moveTo(startX, startY);
            }
            
            updateStatus('绘制中...');
        }
        
        function draw(e) {
            if (!isDrawing) return;
            
            const rect = canvas.getBoundingClientRect();
            const currentX = e.clientX - rect.left;
            const currentY = e.clientY - rect.top;
            
            ctx.strokeStyle = currentColor;
            ctx.lineWidth = currentSize;
            
            switch (currentTool) {
                case 'pen':
                case 'eraser':
                    ctx.lineTo(currentX, currentY);
                    ctx.stroke();
                    break;
                    
                case 'line':
                    redrawCanvas();
                    ctx.beginPath();
                    ctx.moveTo(startX, startY);
                    ctx.lineTo(currentX, currentY);
                    ctx.stroke();
                    break;
                    
                case 'rectangle':
                    redrawCanvas();
                    ctx.beginPath();
                    ctx.rect(startX, startY, currentX - startX, currentY - startY);
                    ctx.stroke();
                    break;
                    
                case 'circle':
                    redrawCanvas();
                    const radius = Math.sqrt(Math.pow(currentX - startX, 2) + Math.pow(currentY - startY, 2));
                    ctx.beginPath();
                    ctx.arc(startX, startY, radius, 0, 2 * Math.PI);
                    ctx.stroke();
                    break;
            }
        }
        
        function stopDrawing() {
            if (isDrawing) {
                isDrawing = false;
                saveState();
                updateStatus('准备就绪');
                
                // 通知Flutter数据变更
                sendToFlutter('dataChanged', {
                    tool: currentTool,
                    timestamp: Date.now()
                });
            }
        }
        
        function handleTouch(e) {
            e.preventDefault();
            const touch = e.touches[0] || e.changedTouches[0];
            const mouseEvent = new MouseEvent(e.type === 'touchstart' ? 'mousedown' : 
                                            e.type === 'touchmove' ? 'mousemove' : 'mouseup', {
                clientX: touch.clientX,
                clientY: touch.clientY
            });
            canvas.dispatchEvent(mouseEvent);
        }
        
        function updateCoordinates(e) {
            const rect = canvas.getBoundingClientRect();
            const coordX = Math.round(e.clientX - rect.left);
            const coordY = Math.round(e.clientY - rect.top);
            document.getElementById('coordinatesText').textContent = '坐标: (' + coordX + ', ' + coordY + ')';
        }
        
        function saveState() {
            historyIndex++;
            if (historyIndex < drawingHistory.length) {
                drawingHistory.length = historyIndex;
            }
            drawingHistory.push(canvas.toDataURL());
        }
        
        function redrawCanvas() {
            if (historyIndex >= 0) {
                const img = new Image();
                img.onload = function() {
                    ctx.clearRect(0, 0, canvas.width, canvas.height);
                    ctx.drawImage(img, 0, 0);
                };
                img.src = drawingHistory[historyIndex];
            }
        }
        
        function clearCanvas() {
            ctx.clearRect(0, 0, canvas.width, canvas.height);
            saveState();
            updateStatus('画布已清空');
            sendToFlutter('cleared', {});
        }
        
        function undoAction() {
            if (historyIndex > 0) {
                historyIndex--;
                redrawCanvas();
                updateStatus('已撤销');
                sendToFlutter('undone', {});
            }
        }
        
        function saveDrawing() {
            const dataURL = canvas.toDataURL('image/png');
            sendToFlutter('export', {
                format: 'png',
                data: dataURL
            });
            updateStatus('绘图已保存');
        }
        
        function updateStatus(text) {
            document.getElementById('statusText').textContent = text;
        }
        
        // 工具选择
        document.addEventListener('DOMContentLoaded', function() {
            // 工具按钮事件
            document.querySelectorAll('[data-tool]').forEach(btn => {
                btn.addEventListener('click', function() {
                    // 移除所有active类
                    document.querySelectorAll('.tool-btn').forEach(b => b.classList.remove('active'));
                    // 添加active类到当前按钮
                    this.classList.add('active');
                    // 设置当前工具
                    currentTool = this.dataset.tool;
                    updateStatus('已选择: ' + this.textContent);
                });
            });
            
            // 颜色选择器
            document.getElementById('colorPicker').addEventListener('change', function() {
                currentColor = this.value;
                updateStatus('颜色已更改: ' + currentColor);
            });
            
            // 大小滑块
            const sizeSlider = document.getElementById('sizeSlider');
            const sizeDisplay = document.getElementById('sizeDisplay');
            sizeSlider.addEventListener('input', function() {
                currentSize = this.value;
                sizeDisplay.textContent = currentSize + 'px';
                updateStatus('画笔大小: ' + currentSize + 'px');
            });
            
            // 初始化画布
            initCanvas();
        });
        
        // Flutter通信
        function sendToFlutter(type, payload) {
            if (window.ExcalidrawBridge) {
                window.ExcalidrawBridge.postMessage(JSON.stringify({
                    type: type,
                    payload: payload
                }));
            }
        }
        
        // 供Flutter调用的函数
        window.setTool = function(toolName) {
            currentTool = toolName;
            document.querySelector('[data-tool="' + toolName + '"]')?.click();
        };
        
        window.setColor = function(color) {
            currentColor = color;
            document.getElementById('colorPicker').value = color;
        };
        
        window.setSize = function(size) {
            currentSize = size;
            document.getElementById('sizeSlider').value = size;
            document.getElementById('sizeDisplay').textContent = size + 'px';
        };
        
        window.exportDrawing = function(format) {
            if (format === 'png') {
                saveDrawing();
            } else {
                sendToFlutter('export', {
                    format: format,
                    data: canvas.toDataURL()
                });
            }
        };
    </script>
</body>
</html>
      ''';

      await _controller.loadHtmlString(htmlContent);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingError = '加载HTML失败: $e';
        });
      }
      widget.onError?.call('加载HTML失败: $e');
    }
  }

  Future<void> _initializeExcalidraw() async {
    try {
      // 初始化 Excalidraw 配置
      final config = {
        'viewId': widget.viewId,
        'initialData': widget.initialData ?? {
          'elements': [],
          'appState': {
            'theme': Theme.of(context).brightness == Brightness.dark ? 'dark' : 'light',
            'zoom': 1.0,
          },
          'files': {},
        },
        'libraries': await _loadLibraries(),
        'theme': Theme.of(context).brightness == Brightness.dark ? 'dark' : 'light',
        'language': 'zh-CN',
      };

      await _controller.runJavaScript('''
        if (window.initializeExcalidraw) {
          window.initializeExcalidraw(${jsonEncode(config)});
        }
      ''');
    } catch (e) {
      widget.onError?.call('初始化Excalidraw失败: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _loadLibraries() async {
    try {
      // 这里应该加载 excalidraw-libraries 资源
      // 目前返回一个占位符列表
      return [
        {
          'id': 'basic-shapes',
          'name': '基础形状',
          'description': '基本的几何形状',
          'preview': 'placeholder-preview.png',
        },
        {
          'id': 'icons',
          'name': '图标库',
          'description': '常用图标集合',
          'preview': 'placeholder-preview.png',
        },
      ];
    } catch (e) {
      print('加载图形库失败: $e');
      return [];
    }
  }

  void _handleWebViewMessage(String message) {
    try {
      final data = jsonDecode(message);
      final type = data['type'] as String;
      final payload = data['payload'];

      switch (type) {
        case 'ready':
          print('WebView ready: $payload');
          break;
        case 'initialized':
          print('白板初始化完成: $payload');
          if (mounted) {
            setState(() => _isLoading = false);
          }
          break;
        case 'dataChanged':
          print('绘图数据变更: ${payload['tool']} at ${payload['timestamp']}');
          widget.onDataChanged?.call(payload);
          break;
        case 'export':
          print('导出绘图: ${payload['format']}');
          widget.onExport?.call(payload['format'], payload['data']);
          break;
        case 'cleared':
          print('画布已清空');
          widget.onDataChanged?.call({'action': 'cleared'});
          break;
        case 'undone':
          print('撤销操作');
          widget.onDataChanged?.call({'action': 'undone'});
          break;
        case 'error':
          widget.onError?.call(payload['message']);
          break;
        case 'loadLibrary':
          _handleLoadLibrary(payload['path']);
          break;
        default:
          print('Unknown message type: $type');
      }
    } catch (e) {
      print('Error handling WebView message: $e');
      widget.onError?.call('处理WebView消息失败: $e');
    }
  }

  Future<void> _handleLoadLibrary(String libraryPath) async {
    try {
      // 这里应该加载具体的图形库内容
      // 目前返回占位符数据
      final libraryContent = {
        'type': 'excalidrawlib',
        'version': 1,
        'library': [],
      };

      await _controller.runJavaScript('''
        if (window.onLibraryLoaded) {
          window.onLibraryLoaded(${jsonEncode(libraryContent)});
        }
      ''');
    } catch (e) {
      print('Error loading library: $e');
      widget.onError?.call('加载图形库失败: $e');
    }
  }

  /// 导出绘图
  Future<void> exportDrawing(String format) async {
    try {
      await _controller.runJavaScript('''
        if (window.exportDrawing) {
          window.exportDrawing('$format');
        }
      ''');
    } catch (e) {
      widget.onError?.call('导出失败: $e');
    }
  }

  /// 设置绘图工具
  Future<void> setTool(String tool) async {
    try {
      await _controller.runJavaScript('''
        if (window.setTool) {
          window.setTool('$tool');
        }
      ''');
    } catch (e) {
      widget.onError?.call('设置工具失败: $e');
    }
  }

  /// 设置绘图颜色
  Future<void> setColor(String color) async {
    try {
      await _controller.runJavaScript('''
        if (window.setColor) {
          window.setColor('$color');
        }
      ''');
    } catch (e) {
      widget.onError?.call('设置颜色失败: $e');
    }
  }

  /// 设置画笔大小
  Future<void> setSize(int size) async {
    try {
      await _controller.runJavaScript('''
        if (window.setSize) {
          window.setSize($size);
        }
      ''');
    } catch (e) {
      widget.onError?.call('设置大小失败: $e');
    }
  }

  /// 清空画布
  Future<void> clearCanvas() async {
    try {
      await _controller.runJavaScript('''
        if (window.clearCanvas) {
          clearCanvas();
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
        if (window.undoAction) {
          undoAction();
        }
      ''');
    } catch (e) {
      widget.onError?.call('撤销失败: $e');
    }
  }

  /// 加载模板
  Future<void> loadTemplate(Map<String, dynamic> templateData) async {
    try {
      await _controller.runJavaScript('''
        if (window.loadTemplate) {
          window.loadTemplate(${jsonEncode(templateData)});
        }
      ''');
    } catch (e) {
      widget.onError?.call('加载模板失败: $e');
    }
  }

  /// 更新主题
  Future<void> updateTheme(String theme) async {
    try {
      await _controller.runJavaScript('''
        if (excalidrawAPI) {
          excalidrawAPI.updateScene({
            appState: { theme: '$theme' }
          });
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
