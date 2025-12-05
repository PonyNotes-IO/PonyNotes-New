import 'dart:io';
import 'package:flutter/material.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy/plugins/handwriting_native/application/handwriting_native_service.dart';

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
        toolbarHeight: 56,
        titleSpacing: 8,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withOpacity(0.25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.view.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // 顶部菜单：保存 / 导出（暂为占位）
          TextButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('保存功能开发中（将调用 xopp / PNG 导出）'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('保存'),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 4),
          TextButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('导出功能开发中（计划支持 PNG / PDF）'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            icon: const Icon(Icons.ios_share_outlined, size: 18),
            label: const Text('导出'),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurface.withOpacity(0.8),
            ),
          ),
          const SizedBox(width: 12),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  theme.colorScheme.outlineVariant.withOpacity(0.3),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
      body: Row(
        children: [
          _buildLeftToolbar(theme),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTopInfoBar(theme),
                const Divider(height: 1),
                Expanded(
                  child: _buildCanvasArea(theme),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 左侧垂直工具栏（笔、橡皮擦、荧光笔、选择等）
  Widget _buildLeftToolbar(ThemeData theme) {
    final items = [
      (_HandwritingTool.pen, Icons.edit_outlined, '画笔'),
      (_HandwritingTool.eraser, Icons.cleaning_services_outlined, '橡皮擦'),
      (_HandwritingTool.highlighter, Icons.brush_outlined, '荧光笔'),
      (_HandwritingTool.selector, Icons.crop_free, '选择'),
    ];

    return Container(
      width: 72,
      color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
      child: Column(
        children: [
          const SizedBox(height: 12),
          for (final item in items)
            _HandwritingToolButton(
              icon: item.$2,
              label: item.$3,
              selected: _selectedTool == item.$1,
              onTap: () {
                setState(() {
                  _selectedTool = item.$1;
                });
              },
            ),
          const Spacer(),
          // 颜色与粗细简易控制条（占位）
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _selectedColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.colorScheme.onSurface.withOpacity(0.4),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_strokeWidth.toStringAsFixed(1)} px',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  /// 顶部信息条：显示当前工具 / 颜色等（为后续快捷操作预留）
  Widget _buildTopInfoBar(ThemeData theme) {
    String toolLabel;
    switch (_selectedTool) {
      case _HandwritingTool.pen:
        toolLabel = '画笔';
        break;
      case _HandwritingTool.eraser:
        toolLabel = '橡皮擦';
        break;
      case _HandwritingTool.highlighter:
        toolLabel = '荧光笔';
        break;
      case _HandwritingTool.selector:
        toolLabel = '选择';
        break;
    }

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Text(
            '当前工具：$toolLabel',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(width: 24),
          Text(
            '颜色：#${_selectedColor.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
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
                  // 背景：Xournal++ 渲染出来的 PNG
                  if (_renderedImage != null)
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image(
                          image: _renderedImage!,
                          fit: BoxFit.contain,
                        ),
                      ),
                    )
                  else
                    // 如果还没渲染成功，显示原来的文案占位
                    IgnorePointer(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.draw_rounded,
                              size: 72,
                              color: theme.colorScheme.primary.withOpacity(0.6),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '手写笔记（原生）',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: theme.colorScheme.onSurface.withOpacity(0.8),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '画布与笔迹渲染正在集成 Xournal++，当前为 UI 原型状态',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withOpacity(0.55),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              '视图ID: ${widget.view.id}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withOpacity(0.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // 前端即时笔迹预览层：不依赖 Xournal++ 渲染结果
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

  /// 将 Flutter 坐标转换为传给 Xournal++ 的点结构
  Map<String, dynamic> _buildPoint(
    Offset localPosition, {
    required int phase,
    required double canvasWidth,
    required double canvasHeight,
  }) {
    // 先将手势坐标裁剪到当前画布区域
    final double clampedX = localPosition.dx.clamp(0, canvasWidth);
    final double clampedY = localPosition.dy.clamp(0, canvasHeight);

    // 如果已知页面尺寸，则按比例映射到页面坐标；否则退化为直接使用画布尺寸
    final double pageWidth = _pageWidth ?? canvasWidth;
    final double pageHeight = _pageHeight ?? canvasHeight;

    final double x = clampedX / canvasWidth * pageWidth;
    final double y = clampedY / canvasHeight * pageHeight;

    final int toolCode = switch (_selectedTool) {
      _HandwritingTool.pen => 0,
      _HandwritingTool.eraser => 1,
      _HandwritingTool.highlighter => 2,
      _HandwritingTool.selector => 3,
    };

    return {
      'x': x,
      'y': y,
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
        width,
        height,
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

class _HandwritingToolButton extends StatelessWidget {
  const _HandwritingToolButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Material(
        color: selected
            ? theme.colorScheme.primary.withOpacity(0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withOpacity(0.7),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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


