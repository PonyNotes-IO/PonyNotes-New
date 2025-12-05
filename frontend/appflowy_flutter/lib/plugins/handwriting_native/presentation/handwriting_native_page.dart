import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy/plugins/handwriting_native/application/handwriting_native_service.dart';
import 'package:appflowy/plugins/handwriting_native/presentation/widgets/handwriting_canvas_background_painter.dart';
import 'package:appflowy/plugins/handwriting_native/presentation/widgets/handwriting_page_thumbnails.dart';
import 'package:appflowy/plugins/handwriting_native/presentation/widgets/handwriting_status_bar.dart';
import 'package:appflowy/plugins/handwriting_native/presentation/widgets/handwriting_top_toolbar.dart';

class HandwritingNativePage extends StatefulWidget {
  const HandwritingNativePage({
    super.key,
    required this.view,
    required this.onViewChanged,
  });

  final ViewPB view;
  final Function(ViewPB) onViewChanged;

  @override
  State<HandwritingNativePage> createState() => _HandwritingNativePageState();
}

class _HandwritingNativePageState extends State<HandwritingNativePage> {
  final HandwritingNativeService _service = HandwritingNativeService();
  bool _isInitializing = true;
  String? _errorMessage;
  ImageProvider? _renderedImage;

  /// 当前页面的实际尺寸（来自 Xournal++ 文档），用于坐标映射
  double? _pageWidth;
  double? _pageHeight;

  /// 当前选中的工具
  _HandwritingTool _selectedTool = _HandwritingTool.pen;

  /// 当前画笔颜色
  Color _selectedColor = Colors.orangeAccent;

  /// 当前画笔粗细
  double _strokeWidth = 3.0;

  /// 当前正在收集的一笔笔迹
  final List<Map<String, dynamic>> _currentStrokePoints = [];

   /// 当前正在书写的一笔，用于在 Flutter 侧即时预览（画布坐标）
  final List<Offset> _previewStrokePoints = [];

  /// 当前页面索引（后续支持多页时使用）
  int _currentPageIndex = 0;

  /// 页面数量（用于缩略图和底部状态栏）
  int _pageCount = 1;

  /// 画布缩放倍率（用于渲染 PNG）
  double _zoom = 1.0;

  /// 缩略图缓存
  final Map<int, ImageProvider> _thumbnails = {};

  /// A4纸默认尺寸（点，72 DPI）
  static const double a4Width = 595.275591;
  static const double a4Height = 841.889764;

  @override
  void initState() {
    super.initState();
    print('🎨 [HandwritingNativePage] initState called');
    print('🎨 [HandwritingNativePage] view.id: ${widget.view.id}');
    print('🎨 [HandwritingNativePage] view.name: ${widget.view.name}');
    print('🎨 [HandwritingNativePage] view.layout: ${widget.view.layout}');
    
    _initializeDocument();
  }

  Future<void> _initializeDocument() async {
    try {
      print('🔧 [HandwritingNativePage] Initializing document...');
      final docId = await _service.getOrCreateDoc(widget.view.id);
      
      if (!mounted) {
        return;
      }

        setState(() {
          _isInitializing = false;
          if (docId == null) {
            _errorMessage = '无法创建或打开文档';
          }
        });

      // 文档准备好之后，先获取页面尺寸，再渲染一次空白页面，验证 Xournal++ 渲染链路
      if (docId != null) {
        await _loadPageSize();
        await _loadPageCountAndThumbnails();
        await _renderAndUpdateCanvas();
      }
    } catch (e) {
      print('❌ [HandwritingNativePage] Initialization error: $e');
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = '初始化失败: $e';
        });
      }
    }
  }

  /// 从动态库获取当前页面尺寸，用于 Flutter 画布坐标到文档坐标的映射
  Future<void> _loadPageSize() async {
    try {
      final size = await _service.getPageSize(widget.view.id, _currentPageIndex);
      if (!mounted) {
        return;
      }
      if (size == null) {
        print('⚠️ [HandwritingNativePage] getPageSize returned null');
        return;
      }

      setState(() {
        _pageWidth = size['width'];
        _pageHeight = size['height'];
      });

      print(
        '📐 [HandwritingNativePage] Page size loaded: '
        'width=$_pageWidth, height=$_pageHeight',
      );
    } catch (e) {
      print('❌ [HandwritingNativePage] _loadPageSize error: $e');
    }
  }

  /// 加载页面数量并预渲染缩略图
  Future<void> _loadPageCountAndThumbnails() async {
    try {
      final count = await _service.getPageCount(widget.view.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _pageCount = (count ?? 1).clamp(1, 9999);
      });

      // 预渲染当前页缩略图
      await _renderThumbnail(_currentPageIndex);
    } catch (e) {
      print('❌ [HandwritingNativePage] _loadPageCount error: $e');
    }
  }

  @override
  void dispose() {
    print('🗑️ [HandwritingNativePage] dispose called for view: ${widget.view.id}');
    // 关闭文档
    _service.closeDoc(widget.view.id).then((success) {
      if (success) {
        print('✅ [HandwritingNativePage] Document closed');
      } else {
        print('⚠️ [HandwritingNativePage] Failed to close document');
      }
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    print('🖼️ [HandwritingNativePage] build() called');

    if (_isInitializing) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.view.name),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在初始化手写笔记...'),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.view.name),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        titleSpacing: 8,
        title: Text(widget.view.name),
      ),
      body: Column(
        children: [
          // 顶部工具栏（Xournal++ 风格）
          HandwritingTopToolbar(
            selectedTool: _selectedTool.toToolbarTool(),
            selectedColor: _selectedColor,
            strokeWidth: _strokeWidth,
            onToolSelected: (tool) {
              setState(() {
                _selectedTool = tool.toInternal();
              });
            },
            onColorSelected: (color) {
              setState(() {
                _selectedColor = color;
              });
            },
            onStrokeWidthChanged: (v) {
              setState(() {
                _strokeWidth = v;
              });
            },
            onSave: () => _showSnack(context, '保存功能开发中（将调用 xopp / PNG 导出）'),
            onExport: () => _showSnack(context, '导出功能开发中（计划支持 PNG / PDF）'),
            onUndo: () => _showSnack(context, '撤销功能开发中'),
            onRedo: () => _showSnack(context, '重做功能开发中'),
            onPrevPage: _pageCount > 1 ? () => _switchPage(_currentPageIndex - 1) : null,
            onNextPage: _pageCount > 1 ? () => _switchPage(_currentPageIndex + 1) : null,
          ),
          const Divider(height: 1),
          Expanded(
            child: Row(
              children: [
                // 左侧缩略图栏
                HandwritingPageThumbnails(
                  pageCount: _pageCount,
                  currentPageIndex: _currentPageIndex,
                  onPageSelected: (index) => _switchPage(index),
                  onAddPage: () => _showSnack(context, '新增页面功能开发中'),
                  onRemovePage: () => _showSnack(context, '删除页面功能开发中'),
                  renderThumbnail: (index) => _renderThumbnail(index),
                ),
                const VerticalDivider(width: 1),
                // 画布 + 状态栏
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _buildCanvasArea(theme)),
                      HandwritingStatusBar(
                        currentPageIndex: _currentPageIndex,
                        pageCount: _pageCount,
                        zoom: _zoom,
                        onPrevPage: () => _switchPage(_currentPageIndex - 1),
                        onNextPage: () => _switchPage(_currentPageIndex + 1),
                        onZoomChanged: (v) async {
                          setState(() {
                            _zoom = v;
                          });
                          await _renderAndUpdateCanvas();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 中央画布区域：承载 Xournal++ 渲染结果 + 手势事件
  Widget _buildCanvasArea(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.all(16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withOpacity(0.6),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 使用当前容器尺寸作为画布尺寸参考，并限制在合理范围
            final canvasWidth = constraints.maxWidth.clamp(300, 1600).toDouble();
            final canvasHeight = constraints.maxHeight.clamp(200, 1200).toDouble();

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (details) {
                print('🖊️ [HandwritingNativePage] onPanStart: ${details.localPosition}');
                _startStroke(details.localPosition, canvasWidth, canvasHeight);
              },
              onPanUpdate: (details) {
                print('🖊️ [HandwritingNativePage] onPanUpdate: ${details.localPosition}, points count: ${_previewStrokePoints.length}');
                _continueStroke(details.localPosition, canvasWidth, canvasHeight);
              },
              onPanEnd: (details) async {
                print('🖊️ [HandwritingNativePage] onPanEnd, total points: ${_currentStrokePoints.length}');
                await _endStroke(canvasWidth, canvasHeight);
              },
              child: Stack(
                children: [
                  // 第一层：背景绘制（蓝色横格线 + 红色竖线）
                  Positioned.fill(
                    child: CustomPaint(
                      painter: HandwritingCanvasBackgroundPainter(
                        pageWidth: _pageWidth ?? a4Width,
                        pageHeight: _pageHeight ?? a4Height,
                      ),
                    ),
                  ),

                  // 第二层：Xournal++ 渲染出来的 PNG（如果有）
                  if (_renderedImage != null)
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image(
                          image: _renderedImage!,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),

                  // 第三层：前端即时笔迹预览层（不依赖 Xournal++ 渲染结果）
                  // 始终显示 CustomPaint，即使 points 为空，这样 shouldRepaint 才能正确工作
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _HandwritingPreviewPainter(
                        points: _previewStrokePoints,
                        color: _selectedColor,
                        strokeWidth: _strokeWidth,
                            ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// 开始一笔
  void _startStroke(Offset localPosition, double canvasWidth, double canvasHeight) {
    print('🖊️ [HandwritingNativePage] _startStroke: $localPosition, canvas: ${canvasWidth}x${canvasHeight}');
    setState(() {
    _currentStrokePoints.clear();
      _previewStrokePoints.clear();
      _previewStrokePoints.add(localPosition);
    });
    _currentStrokePoints.add(
      _buildPoint(
        localPosition,
        phase: 0,
        canvasWidth: canvasWidth,
        canvasHeight: canvasHeight,
      ),
    );
    print('🖊️ [HandwritingNativePage] _startStroke done, preview points: ${_previewStrokePoints.length}');
  }

  /// 移动中
  void _continueStroke(Offset localPosition, double canvasWidth, double canvasHeight) {
    setState(() {
      _previewStrokePoints.add(localPosition);
    });
    _currentStrokePoints.add(
      _buildPoint(
        localPosition,
        phase: 1,
        canvasWidth: canvasWidth,
        canvasHeight: canvasHeight,
      ),
    );
    // 每10个点打印一次，避免日志过多
    if (_previewStrokePoints.length % 10 == 0) {
      print('🖊️ [HandwritingNativePage] _continueStroke: $localPosition, preview points: ${_previewStrokePoints.length}');
    }
  }

  /// 结束一笔：发送到原生并触发重新渲染
  Future<void> _endStroke(double canvasWidth, double canvasHeight) async {
    if (_currentStrokePoints.isEmpty) return;
    _currentStrokePoints.add(_buildPoint(
      _extractLastPointOffset(),
      phase: 2,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
    ));

    try {
      final success = await _service.handleStroke(widget.view.id, _currentStrokePoints);
      if (!success) {
        print('❌ [HandwritingNativePage] handleStroke failed');
      }
      await _renderAndUpdateCanvas(
        width: canvasWidth.toInt(),
        height: canvasHeight.toInt(),
      );
    } catch (e) {
      print('❌ [HandwritingNativePage] endStroke error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _currentStrokePoints.clear();
          _previewStrokePoints.clear();
        });
      } else {
      _currentStrokePoints.clear();
        _previewStrokePoints.clear();
      }
    }
  }

  /// 切换页面并重新渲染
  Future<void> _switchPage(int newIndex) async {
    if (newIndex < 0 || newIndex >= _pageCount) {
      return;
    }
    setState(() {
      _currentPageIndex = newIndex;
      _renderedImage = null;
    });
    await _renderAndUpdateCanvas();
    await _renderThumbnail(newIndex);
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 将 Flutter 坐标转换为传给 Xournal++ 的点结构
  Map<String, dynamic> _buildPoint(
    Offset localPosition, {
    required int phase,
    required double canvasWidth,
    required double canvasHeight,
  }) {
    // 获取页面尺寸（使用A4默认值或从动态库获取的值）
    final double pageWidth = _pageWidth ?? a4Width;
    final double pageHeight = _pageHeight ?? a4Height;

    // 计算背景绘制的缩放比例和偏移量（与 HandwritingCanvasBackgroundPainter 保持一致）
    final scaleX = canvasWidth / pageWidth;
    final scaleY = canvasHeight / pageHeight;
    final scale = math.min(scaleX, scaleY);

    final drawWidth = pageWidth * scale;
    final drawHeight = pageHeight * scale;
    final offsetX = (canvasWidth - drawWidth) / 2;
    final offsetY = (canvasHeight - drawHeight) / 2;

    // 将手势坐标转换为页面坐标
    // 1. 减去偏移量
    final adjustedX = localPosition.dx - offsetX;
    final adjustedY = localPosition.dy - offsetY;

    // 2. 除以缩放比例，得到页面坐标
    final double x = adjustedX / scale;
    final double y = adjustedY / scale;

    // 3. 裁剪到页面范围内
    final double clampedX = x.clamp(0, pageWidth);
    final double clampedY = y.clamp(0, pageHeight);

    final int toolCode = switch (_selectedTool) {
      _HandwritingTool.pen => 0,
      _HandwritingTool.eraser => 1,
      _HandwritingTool.highlighter => 2,
      _HandwritingTool.selector => 3,
    };

    return {
      'x': clampedX,
      'y': clampedY,
      'pressure': 1.0, // 先用固定值，后续接入真实压感
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'tool': toolCode,
      'phase': phase,
      // 将当前选中的颜色和粗细一并写入，作为样式扩展的预留字段
      'style': {
        'color': _selectedColor.value,
        'width': _strokeWidth,
      },
    };
  }

  /// 提取当前笔迹的最后一个点（用于 onPanEnd 补一个 up 事件）
  Offset _extractLastPointOffset() {
    if (_currentStrokePoints.isEmpty) {
      return Offset.zero;
    }
    final last = _currentStrokePoints.last;
    return Offset(
      (last['x'] as num).toDouble(),
      (last['y'] as num).toDouble(),
    );
  }

  /// 渲染指定页面的缩略图并缓存
  Future<ImageProvider?> _renderThumbnail(int pageIndex) async {
    if (_thumbnails.containsKey(pageIndex)) {
      return _thumbnails[pageIndex];
    }
    try {
      final tempDir = Directory.systemTemp;
      final pngPath =
          '${tempDir.path}/handwriting_${widget.view.id}_thumb_$pageIndex.png';

      final renderedPath = await _service.renderPage(
        widget.view.id,
        pageIndex,
        pngPath,
        300,
        420,
      );
      if (renderedPath == null) {
        return null;
      }
      final file = File(renderedPath);
      if (!await file.exists()) {
        return null;
      }
      final bytes = await file.readAsBytes();
      final image = MemoryImage(bytes);
      _thumbnails[pageIndex] = image;
      return image;
    } catch (e) {
      print('⚠️ [HandwritingNativePage] render thumbnail error: $e');
      return null;
    }
  }

  /// 调用原生 render_page 渲染 PNG，并更新画布背景
  Future<void> _renderAndUpdateCanvas({int width = 1200, int height = 800}) async {
    try {
      final tempDir = Directory.systemTemp;
      final pngPath =
          '${tempDir.path}/handwriting_${widget.view.id}_page_$_currentPageIndex.png';

      final renderedPath = await _service.renderPage(
        widget.view.id,
        _currentPageIndex,
        pngPath,
        (width * _zoom).round(),
        (height * _zoom).round(),
      );

      if (renderedPath == null) {
        print('⚠️ [HandwritingNativePage] renderPage returned null');
        return;
      }

      final file = File(renderedPath);
      if (!await file.exists()) {
        print('⚠️ [HandwritingNativePage] Rendered file not exists: $renderedPath');
        return;
      }

      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _renderedImage = MemoryImage(bytes);
      });
    } catch (e) {
      print('❌ [HandwritingNativePage] _renderAndUpdateCanvas error: $e');
    }
  }
}

/// 内部使用的工具枚举
enum _HandwritingTool {
  pen,
  eraser,
  highlighter,
  selector,
}

extension _ToolMapping on _HandwritingTool {
  HandwritingTool toToolbarTool() {
    switch (this) {
      case _HandwritingTool.pen:
        return HandwritingTool.pen;
      case _HandwritingTool.eraser:
        return HandwritingTool.eraser;
      case _HandwritingTool.highlighter:
        return HandwritingTool.highlighter;
      case _HandwritingTool.selector:
        return HandwritingTool.selector;
    }
  }
}

extension _ToolbarMapping on HandwritingTool {
  _HandwritingTool toInternal() {
    switch (this) {
      case HandwritingTool.pen:
        return _HandwritingTool.pen;
      case HandwritingTool.eraser:
        return _HandwritingTool.eraser;
      case HandwritingTool.highlighter:
        return _HandwritingTool.highlighter;
      case HandwritingTool.selector:
        return _HandwritingTool.selector;
    }
  }
}

/// 仅用于 Flutter 侧的当前笔迹预览，不影响底层 Xournal++ 文档
class _HandwritingPreviewPainter extends CustomPainter {
  _HandwritingPreviewPainter({
    required this.points,
    required this.color,
    required this.strokeWidth,
  });

  final List<Offset> points;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) {
      return;
    }

    final paint = Paint()
      ..color = color.withOpacity(0.9)
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (points.length == 1) {
      // 如果只有一个点，画一个圆点
      canvas.drawCircle(points.first, strokeWidth / 2, paint);
    } else {
      // 多个点，画路径
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        final p = points[i];
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _HandwritingPreviewPainter oldDelegate) {
    // 比较点的数量和内容，而不是引用
    final pointsChanged = oldDelegate.points.length != points.length ||
        (points.isNotEmpty && oldDelegate.points.isNotEmpty &&
            (oldDelegate.points.last.dx != points.last.dx ||
                oldDelegate.points.last.dy != points.last.dy));
    final colorChanged = oldDelegate.color != color;
    final strokeWidthChanged = oldDelegate.strokeWidth != strokeWidth;
    
    final shouldRepaint = pointsChanged || colorChanged || strokeWidthChanged;
    if (shouldRepaint && points.length > 0) {
      print('🖊️ [HandwritingPreviewPainter] shouldRepaint: true, points: ${points.length}, last: ${points.last}');
    }
    return shouldRepaint;
  }
}


