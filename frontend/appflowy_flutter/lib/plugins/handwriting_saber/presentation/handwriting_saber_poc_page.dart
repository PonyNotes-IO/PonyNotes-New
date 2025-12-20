import 'dart:async';
import 'dart:convert';

import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../application/handwriting_saber_data_service.dart';
import '../third_party/saber_core/components/canvas/canvas_background_pattern.dart';
import '../third_party/saber_core/components/canvas/image/pdf_editor_image.dart';
import '../third_party/saber_core/components/canvas/saber_core_canvas.dart';
import '../third_party/saber_core/data/editor/editor_core_info.dart';
import '../third_party/saber_core/data/editor/page.dart';
import '../third_party/saber_core/data/editor/shape_strokes.dart';
import '../third_party/saber_core/data/tools/tool.dart';
import 'handwriting_saber_toolbar.dart';

/// PoC 页面：暂时只展示占位 UI，并在本地创建一个占位的 .sbn2 文件。
///
/// 后续会在此处嵌入从 Saber 抽取的编辑器与画布。
class HandwritingSaberPocPage extends StatefulWidget {
  const HandwritingSaberPocPage({
    super.key,
    required this.view,
    required this.onViewChanged,
  });

  final ViewPB view;
  final ValueChanged<ViewPB> onViewChanged;

  @override
  State<HandwritingSaberPocPage> createState() =>
      _HandwritingSaberPocPageState();
}

class _HandwritingSaberPocPageState extends State<HandwritingSaberPocPage> {
  final HandwritingSaberDataService _dataService = HandwritingSaberDataService();

  String _status = '初始化中...';

  /// 简化版 Saber 核心数据
  EditorCoreInfo _coreInfo = EditorCoreInfo.empty();

  /// 当前正在绘制的一笔
  Stroke? _currentStroke;

  /// 当前工具
  Tool _currentTool = const Pen(
    toolId: ToolId.fountainPen,
    color: Colors.black,
    strokeWidth: 3,
  );

  /// 当前背景纸模式
  CanvasBackgroundPattern _currentBackgroundPattern =
      CanvasBackgroundPattern.lined;
  
  /// ✅ 激光笔淡出定时器（用于管理多个激光笔笔迹的淡出）
  final Map<Stroke, Timer> _laserFadeOutTimers = {};

  @override
  void initState() {
    super.initState();
    _initLocalData();
  }

  /// 初始化本地数据：
  /// - 调用 HandwritingSaberDataService 打开/创建对应视图的数据文件；
  /// - 尝试从文件中加载 JSON 形式的 EditorCoreInfo；
  /// - 仅在 PoC 阶段使用 JSON 存储，后续会替换为真正的 .sbn2 二进制。
  Future<void> _initLocalData() async {
    try {
      // 1. 打开或创建手写笔记数据文件（通过统一数据服务）
      await _dataService.openHandwritingSaber(viewId: widget.view.id);

      // 2. 加载已有数据（PoC 阶段按 JSON 文本解析）
      await _loadFromStorage();

      if (mounted) {
        setState(() {
          _status = '已就绪';
        });
      }
    } catch (e) {
      setState(() {
        _status = '本地数据初始化失败：$e';
      });
    }
  }

  /// 从统一数据服务加载手写笔记数据
  ///
  /// 当前 PoC 阶段约定：
  /// - 实际存储的还是 EditorCoreInfo 的 JSON 字符串；
  /// - 未来切换为 Saber 真正的 .sbn2 时，只需要替换序列化/反序列化实现。
  Future<void> _loadFromStorage() async {
    try {
      final List<int> bytes =
          await _dataService.loadHandwritingSaberData(widget.view.id);

      if (bytes.isEmpty) {
        _coreInfo = EditorCoreInfo.empty();
        _status = '已就绪';
      } else {
        final String content = utf8.decode(bytes);
        _coreInfo = EditorCoreInfo.fromJsonString(content);
        _status = '已就绪';
      }
    } catch (e) {
      _coreInfo = EditorCoreInfo.empty();
      _status = '读取本地文件失败：$e';
    }
  }

  /// 将当前 EditorCoreInfo 保存到本地数据文件
  ///
  /// PoC 阶段采用 JSON 文本保存，后续切换为 .sbn2 时只需调整序列化逻辑。
  Future<void> _saveToStorage() async {
    try {
      final String json = _coreInfo.toJsonString();
      final List<int> bytes = utf8.encode(json);
      final bool ok = await _dataService.saveHandwritingSaberData(
        widget.view.id,
        bytes,
      );

      if (mounted) {
        setState(() {
          _status = ok ? '已保存' : '保存失败';
        });
      } else {
        _status = ok ? '已保存' : '保存失败';
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = '保存失败：$e';
        });
      } else {
        _status = '保存失败：$e';
      }
    }
  }

  /// ✅ 当前正在绘制的页面索引
  int? _currentPageIndex;
  
  void _startStroke(Offset position, {int? pageIndex}) {
    // ✅ 设置当前页面索引
    _currentPageIndex = pageIndex ?? 0;
    
    // 确保页面索引有效
    if (_currentPageIndex! >= _coreInfo.pages.length) {
      _currentPageIndex = 0;
    }
    
    // 如果是橡皮擦，不创建新笔迹，而是检测并删除相交的笔迹
    if (_currentTool.toolId == ToolId.eraser) {
      _eraseStrokesAtPosition(position, pageIndex: _currentPageIndex);
      return;
    }
    
    // ✅ 创建新笔迹，初始只包含一个点
    // 形状工具只需要起始点，在 _updateStroke 和 _endStroke 中计算形状
    final bool pressureEnabled = _currentTool.toolId == ToolId.fountainPen;
    final Stroke stroke = Stroke(
      points: <Offset>[position],
      color: _currentTool.color,
      strokeWidth: _currentTool.strokeWidth,
      toolId: _currentTool.toolId,
      pressureEnabled: pressureEnabled,  // ✅ 设置压感支持
    );
    setState(() {
      _currentStroke = stroke;
    });
  }
  
  /// 在指定位置擦除相交的笔迹
  void _eraseStrokesAtPosition(Offset position, {int? pageIndex}) {
    if (_coreInfo.pages.isEmpty) {
      return;
    }
    
    final int targetPageIndex = pageIndex ?? 0;
    if (targetPageIndex >= _coreInfo.pages.length) {
      return;
    }
    
    final page = _coreInfo.pages[targetPageIndex];
    final eraserSize = _currentTool.strokeWidth;
    final sqrEraserSize = eraserSize * eraserSize;
    
    // 检测与橡皮擦相交的笔迹
    final strokesToRemove = <Stroke>[];
    for (final stroke in page.strokes) {
      if (_isStrokeIntersectingEraser(position, stroke, sqrEraserSize)) {
        strokesToRemove.add(stroke);
      }
    }
    
    // 删除相交的笔迹
    if (strokesToRemove.isNotEmpty) {
      setState(() {
        page.strokes.removeWhere((s) => strokesToRemove.contains(s));
      });
      _saveToStorage();
    }
  }
  
  /// 检查笔迹是否与橡皮擦相交
  /// 参考 Saber 原版实现：使用多边形顶点检测，而不是所有点检测
  bool _isStrokeIntersectingEraser(
    Offset eraserPos,
    Stroke stroke,
    double sqrEraserSize,
  ) {
    if (stroke.points.isEmpty) {
      return false;
    }
    
    // 对于短笔迹（<=3个点），检查路径是否包含橡皮擦位置
    if (stroke.points.length <= 3) {
      // 简化检测：检查是否与任意点足够接近
      for (final point in stroke.points) {
        final dx = point.dx - eraserPos.dx;
        final dy = point.dy - eraserPos.dy;
        final sqrDistance = dx * dx + dy * dy;
        // 考虑笔迹宽度，使用更大的检测范围
        final adjustedSqrSize = sqrEraserSize + (stroke.strokeWidth * stroke.strokeWidth);
        if (sqrDistance <= adjustedSqrSize) {
          return true;
        }
      }
      return false;
    }
    
    // 对于长笔迹，使用多边形顶点检测（性能优化）
    // 跳过一些顶点以提高性能
    final int verticesToSkip = switch (stroke.points.length) {
      < 100 => 0,
      < 1000 => 1,
      _ => 2,
    };
    
    for (int i = 0; i < stroke.points.length; i += verticesToSkip + 1) {
      final Offset strokeVertex = stroke.points[i];
      final dx = strokeVertex.dx - eraserPos.dx;
      final dy = strokeVertex.dy - eraserPos.dy;
      final sqrDistance = dx * dx + dy * dy;
      // 考虑笔迹宽度，使用更大的检测范围
      final adjustedSqrSize = sqrEraserSize + (stroke.strokeWidth * stroke.strokeWidth);
      if (sqrDistance <= adjustedSqrSize) {
        return true;
      }
    }
    
    return false;
  }

  void _updateStroke(Offset position) {
    // 如果是橡皮擦，继续检测并删除相交的笔迹
    if (_currentTool.toolId == ToolId.eraser) {
      _eraseStrokesAtPosition(position, pageIndex: _currentPageIndex);
      return;
    }
    
    final Stroke? stroke = _currentStroke;
    if (stroke == null) {
      return;
    }
    
    // ✅ 对于形状工具，更新结束点并重新计算形状点
    final toolId = _currentTool.toolId;
    if (toolId == ToolId.triangle) {
      // ✅ 三角形工具：支持三个点的输入
      if (stroke.points.isEmpty) {
        stroke.points.add(position); // 第一个点
      } else if (stroke.points.length == 1) {
        stroke.points.add(position); // 第二个点
      } else if (stroke.points.length == 2) {
        stroke.points.add(position); // 第三个点
      } else {
        // 已经有三个点，更新第三个点
        stroke.points[2] = position;
      }
    } else if (toolId == ToolId.line ||
        toolId == ToolId.rectangle || 
        toolId == ToolId.circle || 
        toolId == ToolId.diamond) {
      // 其他形状工具：起始点是第一个点，结束点是当前位置
      if (stroke.points.isEmpty) {
        stroke.points.add(position);
      } else {
        // 更新结束点（第二个点）
        if (stroke.points.length == 1) {
          stroke.points.add(position);
        } else {
          stroke.points[1] = position;
        }
      }
    } else if (toolId == ToolId.freePolygon) {
      // ✅ 自由多边形：添加点
      stroke.points.add(position);
    } else {
      // 其他工具：正常添加点
      stroke.points.add(position);
    }
    
    setState(() {
      // 触发重绘
    });
  }

  Future<void> _endStroke() async {
    final Stroke? stroke = _currentStroke;
    if (stroke == null || stroke.points.isEmpty) {
      _currentPageIndex = null;
      return;
    }
    if (_coreInfo.pages.isEmpty) {
      _coreInfo = EditorCoreInfo.empty();
    }
    
    // ✅ 确保页面索引有效
    final int targetPageIndex = _currentPageIndex ?? 0;
    if (targetPageIndex >= _coreInfo.pages.length) {
      _currentPageIndex = null;
      return;
    }
    
    // ✅ 根据工具类型创建对应的形状笔迹
    final toolId = stroke.toolId;
    Stroke? finalStroke;
    
    if (toolId == ToolId.line) {
      // ✅ 直线
      if (stroke.points.length >= 2) {
        finalStroke = LineStroke(
          startPoint: stroke.points.first,
          endPoint: stroke.points[1],
          color: stroke.color,
          strokeWidth: stroke.strokeWidth,
          toolId: toolId,
        );
      }
    } else if (toolId == ToolId.rectangle) {
      // ✅ 矩形
      if (stroke.points.length >= 2) {
        finalStroke = RectangleStroke(
          startPoint: stroke.points.first,
          endPoint: stroke.points[1],
          color: stroke.color,
          strokeWidth: stroke.strokeWidth,
          toolId: toolId,
        );
      }
    } else if (toolId == ToolId.circle) {
      // ✅ 圆形
      if (stroke.points.length >= 2) {
        finalStroke = CircleStroke(
          startPoint: stroke.points.first,
          endPoint: stroke.points[1],
          color: stroke.color,
          strokeWidth: stroke.strokeWidth,
          toolId: toolId,
        );
      }
    } else if (toolId == ToolId.triangle) {
      // ✅ 三角形：需要三个点
      if (stroke.points.length >= 3) {
        finalStroke = TriangleStroke(
          point1: stroke.points[0],
          point2: stroke.points[1],
          point3: stroke.points[2],
          color: stroke.color,
          strokeWidth: stroke.strokeWidth,
          toolId: toolId,
        );
      } else if (stroke.points.length == 2) {
        // ✅ 兼容旧版本：如果只有两个点，使用fromRect构造函数
        finalStroke = TriangleStroke.fromRect(
          startPoint: stroke.points[0],
          endPoint: stroke.points[1],
          color: stroke.color,
          strokeWidth: stroke.strokeWidth,
          toolId: toolId,
        );
      }
    } else if (toolId == ToolId.diamond) {
      // ✅ 菱形
      if (stroke.points.length >= 2) {
        finalStroke = DiamondStroke(
          startPoint: stroke.points.first,
          endPoint: stroke.points[1],
          color: stroke.color,
          strokeWidth: stroke.strokeWidth,
          toolId: toolId,
        );
      }
    } else if (toolId == ToolId.freePolygon) {
      // ✅ 自由多边形
      if (stroke.points.length >= 2) {
        finalStroke = FreePolygonStroke(
          points: List<Offset>.from(stroke.points),
          color: stroke.color,
          strokeWidth: stroke.strokeWidth,
          toolId: toolId,
        );
      }
    } else if (toolId == ToolId.laserPointer) {
      // ✅ 激光笔
      final laserStroke = Stroke(
        points: List<Offset>.from(stroke.points),
        color: stroke.color,
        strokeWidth: stroke.strokeWidth,
        toolId: stroke.toolId,
        pressureEnabled: false,
      );
      _coreInfo.laserStrokes.add(laserStroke);
      // ✅ 启动激光笔淡出动画
      _startLaserFadeOut(laserStroke);
      setState(() {
        _currentStroke = null;
      });
      await _saveToStorage();
      return;
    } else {
      // ✅ 其他工具：普通笔迹
      finalStroke = Stroke(
        points: List<Offset>.from(stroke.points),
        color: stroke.color,
        strokeWidth: stroke.strokeWidth,
        toolId: stroke.toolId,
        pressureEnabled: stroke.pressureEnabled,
      );
    }
    
    // ✅ 保存完成的笔迹到正确的页面
    if (finalStroke != null) {
      _coreInfo.pages[targetPageIndex].strokes.add(finalStroke);
    }
    
    setState(() {
      _currentStroke = null;
      _currentPageIndex = null;
    });
    await _saveToStorage();
  }

  void _onToolChanged(Tool tool) {
    setState(() {
      _currentTool = tool;
    });
  }

  void _onBackgroundPatternChanged(CanvasBackgroundPattern pattern) {
    setState(() {
      _currentBackgroundPattern = pattern;
      _coreInfo = EditorCoreInfo(
        pages: _coreInfo.pages,
        backgroundColor: _coreInfo.backgroundColor,
        backgroundPattern: pattern,
        lineHeight: _coreInfo.lineHeight,
        lineThickness: _coreInfo.lineThickness,
      );
    });
    _saveToStorage();
  }

  void _onColorChanged(Color color) {
    setState(() {
      if (_currentTool is Pen) {
        _currentTool = (_currentTool as Pen).copyWith(color: color);
      }
    });
  }

  void _onStrokeWidthChanged(double width) {
    setState(() {
      if (_currentTool is Pen) {
        _currentTool = (_currentTool as Pen).copyWith(strokeWidth: width);
      } else if (_currentTool is Eraser) {
        _currentTool = Eraser(strokeWidth: width);
      }
    });
  }
  
  /// ✅ 构建单页画布（支持触摸绘制）
  Widget _buildSinglePageCanvas({
    required EditorPage page,
    required int pageIndex,
    required double pageDisplayWidth,
    required double pageDisplayHeight,
    required double screenWidth,
  }) {
    // ✅ 计算页面坐标变换参数
    final double scale = pageDisplayWidth / page.size.width;
    final double offsetX = (screenWidth - pageDisplayWidth) / 2;
    final double offsetY = 0;  // 页面顶部对齐
    
    // ✅ 将 localPosition 转换为页面坐标
    Offset toPageCoordinates(Offset localPosition) {
      // 防止除零错误
      if (scale <= 0) {
        return localPosition;
      }
      return Offset(
        (localPosition.dx - offsetX) / scale,
        (localPosition.dy - offsetY) / scale,
      );
    }
    
    // ✅ 检查触摸点是否在当前页面范围内
    bool isPointInPage(Offset localPosition) {
      return localPosition.dx >= offsetX &&
          localPosition.dx <= offsetX + pageDisplayWidth &&
          localPosition.dy >= offsetY &&
          localPosition.dy <= offsetY + pageDisplayHeight;
    }
    
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (DragStartDetails details) {
        // ✅ 只处理当前页面的触摸事件
        if (!isPointInPage(details.localPosition)) {
          return;
        }
        final pagePos = toPageCoordinates(details.localPosition);
        if (pagePos.dx.isFinite && pagePos.dy.isFinite) {
          // ✅ 确保笔迹添加到正确的页面
          if (pageIndex < _coreInfo.pages.length) {
            _startStroke(pagePos, pageIndex: pageIndex);
          }
        }
      },
      onPanUpdate: (DragUpdateDetails details) {
        // ✅ 只处理当前页面的触摸事件
        if (!isPointInPage(details.localPosition)) {
          return;
        }
        final pagePos = toPageCoordinates(details.localPosition);
        if (pagePos.dx.isFinite && pagePos.dy.isFinite) {
          _updateStroke(pagePos);
        }
      },
      onPanEnd: (DragEndDetails details) => _endStroke(),
      child: Container(
        width: screenWidth,
        height: pageDisplayHeight,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: pageDisplayWidth,
          height: pageDisplayHeight,
          child: SaberCoreCanvas(
            coreInfo: EditorCoreInfo(
              pages: [page],  // ✅ 只传递当前页面
              backgroundColor: _coreInfo.backgroundColor,
              backgroundPattern: _coreInfo.backgroundPattern,
              lineHeight: _coreInfo.lineHeight,
              lineThickness: _coreInfo.lineThickness,
            )..laserStrokes.addAll(_coreInfo.laserStrokes),
            currentStroke: _currentStroke,
          ),
        ),
      ),
    );
  }
  
  /// ✅ 导入 PDF 文件（参考 Saber 的 importPdfFromFilePath）
  Future<void> _importPdf() async {
    try {
      // 使用 file_picker 选择 PDF 文件
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      
      if (result == null || result.files.single.path == null) {
        return;  // 用户取消选择
      }
      
      final pdfFilePath = result.files.single.path!;
      await _importPdfFromFilePath(pdfFilePath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入 PDF 失败：$e')),
        );
      }
    }
  }
  
  /// ✅ 从文件路径导入 PDF（参考 Saber 的实现，支持多页）
  Future<void> _importPdfFromFilePath(String pdfFilePath) async {
    try {
      // 加载 PDF 文档
      final pdfDocument = await PdfDocument.openFile(pdfFilePath);
      
      // 检查PDF是否有页面
      if (pdfDocument.pages.isEmpty) {
        throw Exception('PDF 文件没有页面');
      }
      
      // ✅ 保存当前第一页的笔迹（如果有）
      final List<Stroke> existingStrokes = _coreInfo.pages.isNotEmpty
          ? List<Stroke>.from(_coreInfo.pages.first.strokes)
          : <Stroke>[];
      
      // ✅ 清空现有页面（除了最后一页空页面，如果有的话）
      // 参考 Saber 的实现：移除最后一页空页面，导入PDF后重新添加
      // 检查最后一页是否为空（没有笔迹、没有背景图片）
      final bool hadEmptyPage = _coreInfo.pages.isNotEmpty && 
          _coreInfo.pages.last.strokes.isEmpty &&
          _coreInfo.pages.last.backgroundImage == null;
      if (hadEmptyPage && _coreInfo.pages.length > 1) {
        _coreInfo.pages.removeLast();
      }
      _coreInfo.pages.clear();
      
      // ✅ 为每个 PDF 页面创建一个新的 EditorPage
      for (final pdfPage in pdfDocument.pages) {
        // pdfrx 页面编号从 1 开始
        assert(pdfPage.pageNumber >= 1, 'pdfrx page numbers start at 1');
        
        // ✅ 计算页面尺寸（参考 Saber 的实现）
        // resize to defaultWidth to keep pen sizes consistent
        final pageSize = Size(
          EditorPage.defaultWidth,
          EditorPage.defaultWidth * pdfPage.height / pdfPage.width,
        );
        
        // ✅ 创建 PDF 背景图片
        // dstRect 设置为填充整个页面（从 (0,0) 开始，大小为 pageSize）
        final pdfImage = PdfEditorImage(
          pdfFilePath: pdfFilePath,
          pdfPageIndex: pdfPage.pageNumber - 1,  // PDF 页面索引（从 0 开始）
          naturalSize: pdfPage.size,
          dstRect: Rect.fromLTWH(0, 0, pageSize.width, pageSize.height),
        );
        
        // ✅ 创建新页面，如果是第一页则保留原有笔迹
        final page = EditorPage(
          size: pageSize,
          strokes: _coreInfo.pages.isEmpty ? existingStrokes : <Stroke>[],
          backgroundImage: pdfImage,
        );
        _coreInfo.pages.add(page);
      }
      
      // ✅ 添加一个空页面（参考 Saber 的实现）
      _coreInfo.pages.add(EditorPage(
        size: EditorPage.defaultSize,
      ));
      
      // 更新状态
      setState(() {});
      
      // 保存更改
      await _saveToStorage();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF 导入成功（${pdfDocument.pages.length} 页）'),
          ),
        );
      }
      
      // 释放 PDF 文档资源（PdfEditorImage 会管理自己的文档）
      pdfDocument.dispose();
    } catch (e) {
      debugPrint('❌ [HandwritingSaberPocPage] 导入 PDF 失败：$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入 PDF 失败：$e')),
        );
      }
    }
  }
  
  /// ✅ 启动激光笔淡出动画（参考 Saber 的 fadeOutStroke 逻辑）
  void _startLaserFadeOut(Stroke laserStroke) {
    if (laserStroke.points.isEmpty) {
      return;
    }
    
    // ✅ 计算每个点之间的延迟时间（模拟绘制时的速度）
    final List<Duration> strokePointDelays = [];
    
    // 为每个点计算延迟（第一个点延迟为0，后续点根据时间间隔）
    for (int i = 0; i < laserStroke.points.length; i++) {
      if (i == 0) {
        strokePointDelays.add(Duration.zero);
      } else {
        // 模拟点之间的延迟（实际应该记录绘制时的时间，这里简化处理）
        strokePointDelays.add(const Duration(milliseconds: 50));
      }
    }
    
    // ✅ 启动淡出动画
    _fadeOutLaserStroke(
      stroke: laserStroke,
      strokePointDelays: strokePointDelays,
    );
  }
  
  /// ✅ 淡出激光笔笔迹（参考 Saber 的 fadeOutStroke 方法）
  Future<void> _fadeOutLaserStroke({
    required Stroke stroke,
    required List<Duration> strokePointDelays,
  }) async {
    // ✅ 等待初始延迟（2秒）
    const fadeOutDelay = Duration(seconds: 2);
    await Future.delayed(fadeOutDelay);
    
    // ✅ 如果笔迹已经被删除，直接返回
    if (!_coreInfo.laserStrokes.contains(stroke)) {
      return;
    }
    
    // ✅ 逐个删除点
    for (final delay in strokePointDelays) {
      await Future.delayed(delay);
      
      // ✅ 如果笔迹已经被删除或点数为0，退出
      if (!_coreInfo.laserStrokes.contains(stroke) || stroke.points.isEmpty) {
        break;
      }
      
      // ✅ 删除第一个点
      setState(() {
        stroke.popFirstPoint();
      });
      
      // ✅ 如果点数为0，删除整个笔迹
      if (stroke.points.isEmpty) {
        setState(() {
          _coreInfo.laserStrokes.remove(stroke);
          _laserFadeOutTimers.remove(stroke);
        });
        await _saveToStorage();
        return;
      }
    }
    
    // ✅ 删除整个笔迹
    setState(() {
      _coreInfo.laserStrokes.remove(stroke);
      _laserFadeOutTimers.remove(stroke);
    });
    await _saveToStorage();
  }
  
  @override
  void dispose() {
    // ✅ 清理所有激光笔淡出定时器
    for (final timer in _laserFadeOutTimers.values) {
      timer.cancel();
    }
    _laserFadeOutTimers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.view.name),
        // ✅ 在AppBar底部显示状态信息（更合适的位置）
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            alignment: Alignment.centerLeft,
            child: Text(
              _status,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // ✅ 工具栏（移除状态提示区域）
          HandwritingSaberToolbar(
            currentTool: _currentTool,
            onToolChanged: _onToolChanged,
            currentBackgroundPattern: _currentBackgroundPattern,
            onBackgroundPatternChanged: _onBackgroundPatternChanged,
            currentColor: _currentTool.color,
            onColorChanged: _onColorChanged,
            currentStrokeWidth: _currentTool.strokeWidth,
            onStrokeWidthChanged: _onStrokeWidthChanged,
            onImportPdf: _importPdf,  // ✅ PDF 导入回调
          ),
          const Divider(height: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                // ✅ 支持多页滚动显示
                if (_coreInfo.pages.isEmpty) {
                  return const Center(
                    child: Text('没有页面'),
                  );
                }
                
                // ✅ 计算每页的显示大小（使用屏幕宽度，保持比例）
                final double screenWidth = constraints.maxWidth;
                final List<Widget> pageWidgets = [];
                
                for (int pageIndex = 0; pageIndex < _coreInfo.pages.length; pageIndex++) {
                  final EditorPage page = _coreInfo.pages[pageIndex];
                  
                  // 防止除零错误
                  if (page.size.width <= 0 || page.size.height <= 0) {
                    continue;
                  }
                  
                  // ✅ 计算页面缩放（使用屏幕宽度，保持比例）
                  // 确保页面宽度不超过屏幕宽度，高度按比例缩放
                  final double pageScale = screenWidth / page.size.width;
                  final double pageDisplayWidth = page.size.width * pageScale;
                  final double pageDisplayHeight = page.size.height * pageScale;
                  
                  // ✅ 创建单页画布
                  final pageWidget = _buildSinglePageCanvas(
                    page: page,
                    pageIndex: pageIndex,
                    pageDisplayWidth: pageDisplayWidth,
                    pageDisplayHeight: pageDisplayHeight,
                    screenWidth: screenWidth,
                  );
                  
                  pageWidgets.add(pageWidget);
                  
                  // ✅ 页面之间的间距（除了最后一页）
                  if (pageIndex < _coreInfo.pages.length - 1) {
                    pageWidgets.add(const SizedBox(height: 16));
                  }
                }
                
                // ✅ 使用 SingleChildScrollView 支持垂直滚动
                return SingleChildScrollView(
                  child: Column(
                    children: pageWidgets,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}


