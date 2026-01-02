import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:appflowy_backend/log.dart';

import '../../third_party/saber_core/components/canvas/webview/webview_editor_element.dart';

/// WebView在画布上的渲染组件
/// 支持拖拽、缩放和交互
class CanvasWebViewWidget extends StatefulWidget {
  const CanvasWebViewWidget({
    super.key,
    required this.filePath,
    required this.webView,
    required this.pageSize,
    required this.readOnly,
    this.selected = false,
    this.onTap,
    this.onDelete,
    this.onRefresh,
  });

  /// 笔记文件路径
  final String filePath;

  /// WebView元素数据
  final WebViewEditorElement webView;

  /// 页面大小
  final Size pageSize;

  /// 是否只读模式
  final bool readOnly;

  /// 是否被选中
  final bool selected;

  /// 点击回调
  final VoidCallback? onTap;

  /// 删除回调
  final VoidCallback? onDelete;

  /// 刷新回调
  final VoidCallback? onRefresh;

  @override
  State<CanvasWebViewWidget> createState() => _CanvasWebViewWidgetState();
}

class _CanvasWebViewWidgetState extends State<CanvasWebViewWidget> {
  InAppWebViewController? _controller;
  bool _isLoading = true;
  String? _loadingError;
  bool _hasCachedContent = false;

  /// 拖拽相关
  Offset? _dragStartOffset;
  Rect? _initialRect;

  /// 缩放相关
  ResizeHandle? _resizeHandle;
  Offset? _resizeStartOffset;
  Rect? _resizeStartRect;

  @override
  void initState() {
    super.initState();
    _loadWebView();
  }

  Future<void> _loadWebView() async {
    try {
      // 检查是否有缓存
      _hasCachedContent = await widget.webView.hasCachedContent(widget.filePath);
      
      if (mounted) {
        setState(() {
          _isLoading = true;
          _loadingError = null;
        });
      }
    } catch (e) {
      Log.error('加载WebView失败: $e');
      if (mounted) {
        setState(() {
          _loadingError = '加载失败: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _onWebViewCreated(InAppWebViewController controller) async {
    _controller = controller;

    try {
      if (_hasCachedContent) {
        // 加载缓存内容
        final cachedHtml = await widget.webView.getCachedContent(widget.filePath);
        if (cachedHtml != null && mounted) {
          await controller.loadData(
            data: cachedHtml,
            baseUrl: WebUri(widget.webView.url),
          );
          Log.info('加载缓存内容: ${widget.webView.url}');
        } else {
          // 缓存失效,在线加载
          await _loadOnline(controller);
        }
      } else {
        // 在线加载
        await _loadOnline(controller);
      }
    } catch (e) {
      Log.error('WebView创建失败: $e');
      if (mounted) {
        setState(() {
          _loadingError = '加载失败: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadOnline(InAppWebViewController controller) async {
    await controller.loadUrl(
      urlRequest: URLRequest(url: WebUri(widget.webView.url)),
    );
    Log.info('在线加载: ${widget.webView.url}');
  }

  Future<void> _onLoadStop(InAppWebViewController controller, WebUri? url) async {
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }

    // 如果还没有缓存,保存当前内容
    if (!_hasCachedContent) {
      try {
        final html = await controller.evaluateJavascript(
          source: 'document.documentElement.outerHTML',
        );
        if (html != null && html is String) {
          await widget.webView.saveCachedContent(widget.filePath, html);
          if (mounted) {
            setState(() {
              _hasCachedContent = true;
            });
          }
          Log.info('缓存网页内容: ${widget.webView.url}');
        }
      } catch (e) {
        Log.warn('缓存网页内容失败: $e');
      }
    }

    // 获取网页标题
    try {
      final title = await controller.getTitle();
      if (title != null && title.isNotEmpty && widget.webView.title == null) {
        widget.webView.title = title;
        widget.webView.onMiscChange?.call();
      }
    } catch (e) {
      Log.warn('获取网页标题失败: $e');
    }
  }

  void _onPanStart(DragStartDetails details) {
    if (widget.readOnly) return;
    _dragStartOffset = details.localPosition;
    _initialRect = widget.webView.dstRect;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (widget.readOnly || _dragStartOffset == null || _initialRect == null) {
      return;
    }

    final delta = details.localPosition - _dragStartOffset!;
    final newRect = _initialRect!.shift(delta);

    // 确保不超出画布边界
    final constrainedRect = Rect.fromLTWH(
      newRect.left.clamp(0.0, widget.pageSize.width - newRect.width),
      newRect.top.clamp(0.0, widget.pageSize.height - newRect.height),
      newRect.width,
      newRect.height,
    );

    widget.webView.dstRect = constrainedRect;
    widget.webView.onMoveWebView?.call(widget.webView, constrainedRect);
  }

  void _onPanEnd(DragEndDetails details) {
    _dragStartOffset = null;
    _initialRect = null;
  }

  void _onResizeStart(ResizeHandle handle, DragStartDetails details) {
    if (widget.readOnly) return;
    _resizeHandle = handle;
    _resizeStartOffset = details.globalPosition;
    _resizeStartRect = widget.webView.dstRect;
  }

  void _onResizeUpdate(DragUpdateDetails details) {
    if (widget.readOnly || _resizeHandle == null || _resizeStartRect == null) {
      return;
    }

    final delta = details.globalPosition - _resizeStartOffset!;
    Rect newRect = _resizeStartRect!;

    const minSize = 100.0;

    switch (_resizeHandle!) {
      case ResizeHandle.topLeft:
        newRect = Rect.fromLTRB(
          _resizeStartRect!.left + delta.dx,
          _resizeStartRect!.top + delta.dy,
          _resizeStartRect!.right,
          _resizeStartRect!.bottom,
        );
        break;
      case ResizeHandle.topRight:
        newRect = Rect.fromLTRB(
          _resizeStartRect!.left,
          _resizeStartRect!.top + delta.dy,
          _resizeStartRect!.right + delta.dx,
          _resizeStartRect!.bottom,
        );
        break;
      case ResizeHandle.bottomLeft:
        newRect = Rect.fromLTRB(
          _resizeStartRect!.left + delta.dx,
          _resizeStartRect!.top,
          _resizeStartRect!.right,
          _resizeStartRect!.bottom + delta.dy,
        );
        break;
      case ResizeHandle.bottomRight:
        newRect = Rect.fromLTRB(
          _resizeStartRect!.left,
          _resizeStartRect!.top,
          _resizeStartRect!.right + delta.dx,
          _resizeStartRect!.bottom + delta.dy,
        );
        break;
    }

    // 确保最小尺寸
    if (newRect.width >= minSize && newRect.height >= minSize) {
      widget.webView.dstRect = newRect;
      widget.webView.onMoveWebView?.call(widget.webView, newRect);
    }
  }

  void _onResizeEnd(DragEndDetails details) {
    _resizeHandle = null;
    _resizeStartOffset = null;
    _resizeStartRect = null;
  }

  @override
  Widget build(BuildContext context) {
    final rect = widget.webView.dstRect;

    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: GestureDetector(
        onTap: widget.onTap,
        onPanStart: widget.selected ? _onPanStart : null,
        onPanUpdate: widget.selected ? _onPanUpdate : null,
        onPanEnd: widget.selected ? _onPanEnd : null,
        child: Stack(
          children: [
            // WebView主体
            Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: widget.selected
                      ? Colors.blue
                      : Colors.grey.withOpacity(0.3),
                  width: widget.selected ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRect(
                child: _buildWebViewContent(),
              ),
            ),

            // 选中时显示缩放手柄
            if (widget.selected && !widget.readOnly) ...[
              _buildResizeHandle(ResizeHandle.topLeft, Alignment.topLeft),
              _buildResizeHandle(ResizeHandle.topRight, Alignment.topRight),
              _buildResizeHandle(ResizeHandle.bottomLeft, Alignment.bottomLeft),
              _buildResizeHandle(ResizeHandle.bottomRight, Alignment.bottomRight),
            ],

            // 显示URL标签和操作按钮
            if (widget.selected)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: Colors.blue.withOpacity(0.9),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.language,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          widget.webView.title ?? widget.webView.url,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_hasCachedContent)
                        const Icon(
                          Icons.offline_pin,
                          size: 14,
                          color: Colors.white,
                        ),
                      const SizedBox(width: 4),
                      // 刷新按钮
                      if (widget.onRefresh != null)
                        InkWell(
                          onTap: widget.onRefresh,
                          child: const Padding(
                            padding: EdgeInsets.all(2),
                            child: Icon(
                              Icons.refresh,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      // 删除按钮
                      if (widget.onDelete != null)
                        InkWell(
                          onTap: widget.onDelete,
                          child: const Padding(
                            padding: EdgeInsets.all(2),
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebViewContent() {
    if (_loadingError != null) {
      return Container(
        color: Colors.white,
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
                _loadingError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadWebView,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(widget.webView.url)),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            transparentBackground: false,
            supportZoom: widget.webView.isInteractive,
            disableVerticalScroll: !widget.webView.isInteractive,
            disableHorizontalScroll: !widget.webView.isInteractive,
          ),
          onWebViewCreated: _onWebViewCreated,
          onLoadStart: (controller, url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _loadingError = null;
              });
            }
          },
          onLoadStop: _onLoadStop,
          onLoadError: (controller, url, code, message) {
            Log.error('WebView加载错误: $code - $message');
            if (mounted) {
              setState(() {
                _isLoading = false;
                _loadingError = 'HTTP错误 $code';
              });
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
                  Text('正在加载网页...'),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildResizeHandle(ResizeHandle handle, Alignment alignment) {
    return Align(
      alignment: alignment,
      child: GestureDetector(
        onPanStart: (details) => _onResizeStart(handle, details),
        onPanUpdate: _onResizeUpdate,
        onPanEnd: _onResizeEnd,
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: Colors.blue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller = null;
    super.dispose();
  }
}

/// 缩放手柄位置
enum ResizeHandle {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

