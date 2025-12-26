import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../application/handwriting_saber_data_service.dart';
import '../third_party/saber_core/components/canvas/canvas_background_pattern.dart';
import '../third_party/saber_core/components/canvas/image/pdf_editor_image.dart';
import '../third_party/saber_core/components/canvas/saber_core_canvas.dart';
import '../third_party/saber_core/data/editor/editor_core_info.dart';
import '../third_party/saber_core/data/editor/page.dart';
import '../third_party/saber_core/data/editor/shape_strokes.dart';
import '../third_party/saber_core/data/editor/stroke_extensions.dart'; // ✅ 导入扩展方法
import '../third_party/saber_core/data/editor/text_box.dart' as saber_text; // ✅ 导入文本框（使用别名避免与Flutter的TextBox冲突）
import '../third_party/saber_core/data/tools/select_result.dart';
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

  /// 当前正在绘制的一笔（使用 ValueNotifier 减少父级 setState 频繁重建）
  final ValueNotifier<Stroke?> _currentStrokeNotifier = ValueNotifier<Stroke?>(null);
  /// 激光笔笔迹变更 notifier（用于驱动局部重绘，避免父级 setState）
  final ValueNotifier<List<Stroke>> _laserStrokesNotifier = ValueNotifier<List<Stroke>>([]);
  /// 合并 repaint notifier（当 current stroke 或 laser strokes 变化时通知 painter）
  final ValueNotifier<int> _repaintTick = ValueNotifier<int>(0);

  /// 当前工具（使用 ValueNotifier 以便在切换工具时避免触发父级整页重建）
  final ValueNotifier<Tool> _currentToolNotifier = ValueNotifier<Tool>(const Pen(
    toolId: ToolId.fountainPen,
    color: Colors.black,
    strokeWidth: 3,
  ));

  /// 当前背景纸模式（使用 EditorCoreInfo.empty() 的默认以保证一致）
  CanvasBackgroundPattern _currentBackgroundPattern =
      EditorCoreInfo.empty().backgroundPattern;
  
  /// ✅ 当前填充颜色（用于形状工具）
  Color? _currentFillColor;
  
  /// ✅ 激光笔淡出定时器（用于管理多个激光笔笔迹的淡出）
  final Map<Stroke, Timer> _laserFadeOutTimers = {};

  /// ✅ 选择工具状态
  SelectResult? _selectResult;
  bool _isSelecting = false; // 是否正在选择（拖拽选择区域）
  Offset? _selectStartPosition; // 选择开始位置
  
  /// ✅ 当前正在编辑的文本框ID
  String? _editingTextBoxId;
  
  /// ✅ 文本框编辑控制器
  final Map<String, TextEditingController> _textBoxControllers = {};

  @override
  void initState() {
    super.initState();
    _initLocalData();
    // 合并 repaint：当当前笔迹或激光笔列表变化时，更新 tick 以触发局部重绘
    _currentStrokeNotifier.addListener(() {
      _repaintTick.value++;
    });
    _laserStrokesNotifier.addListener(() {
      _repaintTick.value++;
    });
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
        // 保证 UI 上的当前背景纸样式与核心数据一致（避免新建时工具栏/画布不一致）
        _currentBackgroundPattern = _coreInfo.backgroundPattern;
        _status = '已就绪';
      } else {
        final String content = utf8.decode(bytes);
        _coreInfo = EditorCoreInfo.fromJsonString(content);
        // 同步当前背景纸样式，确保工具栏与数据一致
        _currentBackgroundPattern = _coreInfo.backgroundPattern;
        _status = '已就绪';
      }
    } catch (e) {
      _coreInfo = EditorCoreInfo.empty();
      // 如果读取失败，也同步当前背景样式为默认
      _currentBackgroundPattern = _coreInfo.backgroundPattern;
      _status = '读取本地文件失败：$e';
    }
  }

  /// 将当前 EditorCoreInfo 保存到本地数据文件
  ///
  /// PoC 阶段采用 JSON 文本保存，后续切换为 .sbn2 时只需调整序列化逻辑。
  Future<void> _saveToStorage({bool suppressStatusUpdate = false}) async {
    try {
      final String json = _coreInfo.toJsonString();
      final List<int> bytes = utf8.encode(json);
      final bool ok = await _dataService.saveHandwritingSaberData(
        widget.view.id,
        bytes,
      );

      if (!suppressStatusUpdate) {
        if (mounted) {
          setState(() {
            _status = ok ? '已保存' : '保存失败';
          });
        } else {
          _status = ok ? '已保存' : '保存失败';
        }
      } else {
        // 仅更新内部状态，不触发整页重建
        _status = ok ? '已保存' : '保存失败';
      }
    } catch (e) {
      if (!suppressStatusUpdate) {
        if (mounted) {
          setState(() {
            _status = '保存失败：$e';
          });
        } else {
          _status = '保存失败：$e';
        }
      } else {
        _status = '保存失败：$e';
      }
    }
  }

  // 延迟保存：防抖，避免在每次笔触更新时都写磁盘导致 UI 卡顿
  Timer? _saveDebounceTimer;
  static const Duration _saveDebounceDuration = Duration(milliseconds: 500);
  bool _pendingSave = false;

  /// 调度保存，如果 [immediate] 为 true 则立即保存，否则在最后一次调用后延迟 [_saveDebounceDuration] 保存
  void _scheduleSave({bool immediate = false}) {
    _saveDebounceTimer?.cancel();
    if (immediate) {
      _saveToStorage();
      return;
    }
    // 如果当前正在绘制，推迟保存，设置 pending 标记
    if (_currentStrokeNotifier.value != null) {
      _pendingSave = true;
      return;
    }
    _saveDebounceTimer = Timer(_saveDebounceDuration, () {
      _saveToStorage(suppressStatusUpdate: true);
    });
  }

  /// ✅ 当前正在绘制的页面索引
  int? _currentPageIndex;
  
  void _startStroke(Offset position, {int? pageIndex}) {
    // ✅ 设置当前页面索引
    _currentPageIndex = pageIndex ?? 0;
    debugPrint('🦋[HandwritingSaber] _startStroke: pageIndex=$_currentPageIndex, position=$position, tool=${_currentToolNotifier.value.toolId}');
    
    // 确保页面索引有效
    if (_currentPageIndex! >= _coreInfo.pages.length) {
      _currentPageIndex = 0;
    }
    
    // ✅ 如果是选择工具，开始选择
    if (_currentToolNotifier.value.toolId == ToolId.select) {
      _startSelection(position, pageIndex: _currentPageIndex);
      return;
    }
    
    // ✅ 如果是文本框工具或标题工具，创建文本框
    if (_currentToolNotifier.value.toolId == ToolId.textBox ||
        _currentToolNotifier.value.toolId == ToolId.heading1 ||
        _currentToolNotifier.value.toolId == ToolId.heading2 ||
        _currentToolNotifier.value.toolId == ToolId.heading3 ||
        _currentToolNotifier.value.toolId == ToolId.paragraph) {
      _createTextBox(position, pageIndex: _currentPageIndex);
      return;
    }
    
    // 如果是橡皮擦，不创建新笔迹，而是检测并删除相交的笔迹
    if (_currentToolNotifier.value.toolId == ToolId.eraser) {
      _eraseStrokesAtPosition(position, pageIndex: _currentPageIndex);
      return;
    }
    
    // ✅ 创建新笔迹，初始只包含一个点
    // 形状工具只需要起始点，在 _updateStroke 和 _endStroke 中计算形状
    final bool pressureEnabled = _currentToolNotifier.value.toolId == ToolId.fountainPen;
    final Stroke stroke = Stroke(
      points: <Offset>[position],
      color: _currentToolNotifier.value.color,
      strokeWidth: _currentToolNotifier.value.strokeWidth,
      toolId: _currentToolNotifier.value.toolId,
      pressureEnabled: pressureEnabled,  // ✅ 设置压感支持
    );
    // 使用 notifier 更新当前笔迹，避免触发整个页面的 rebuild
    _currentStrokeNotifier.value = stroke;
  }
  
  /// ✅ 开始选择
  void _startSelection(Offset position, {int? pageIndex}) {
    final pageIdx = pageIndex ?? 0;
    
    // 检查是否点击在已选中的对象上
    if (_selectResult != null && 
        _selectResult!.pageIndex == pageIdx &&
        _isPointInSelection(position, _selectResult!)) {
      // 点击在已选中的对象上，准备移动
      _selectStartPosition = position;
      return;
    }
    
    // ✅ 先尝试点击选择单个对象（快速点击，不拖拽）
    final clickedStroke = _findStrokeAtPosition(position, pageIdx);
    if (clickedStroke != null) {
      // 点击选中了单个笔迹
      setState(() {
        _selectResult = SelectResult(
          pageIndex: pageIdx,
          strokes: [clickedStroke],
          images: [],
          selectionPath: Path(), // 点击选择不需要路径
        );
        _isSelecting = false;
        _selectStartPosition = position;
      });
      return;
    }
    
    // 开始新的拖拽选择区域
    setState(() {
      _isSelecting = true;
      _selectStartPosition = position;
      _selectResult = SelectResult(
        pageIndex: pageIdx,
        strokes: [],
        images: [],
        selectionPath: Path()..moveTo(position.dx, position.dy),
      );
    });
  }
  
  /// ✅ 在指定位置查找笔迹（用于点击选择）
  Stroke? _findStrokeAtPosition(Offset position, int pageIndex) {
    if (_coreInfo.pages.isEmpty || pageIndex < 0 || pageIndex >= _coreInfo.pages.length) {
      return null;
    }
    
    final page = _coreInfo.pages[pageIndex];
    
    // ✅ 从后往前查找（最上层的笔迹优先）
    for (int i = page.strokes.length - 1; i >= 0; i--) {
      final stroke = page.strokes[i];
      if (_isPointInStroke(position, stroke)) {
        return stroke;
      }
    }
    
    return null;
  }
  
  /// ✅ 检查点是否在笔迹内（用于点击选择）
  bool _isPointInStroke(Offset point, Stroke stroke) {
    if (stroke.points.isEmpty) {
      return false;
    }
    
    // ✅ 使用笔迹的平滑路径进行检测（需要导入StrokeExtensions）
    // 注意：getSmoothPath是扩展方法，需要确保已导入stroke_extensions.dart
    final smoothPath = stroke.getSmoothPath(isComplete: true);
    if (smoothPath.getBounds().isEmpty) {
      // 如果路径为空，检查是否与点足够接近
      for (final strokePoint in stroke.points) {
        final distance = (point - strokePoint).distance;
        if (distance < stroke.strokeWidth * 2) {
          return true;
        }
      }
      return false;
    }
    
    // ✅ 使用路径的边界框进行快速检测
    final bounds = smoothPath.getBounds();
    final expandedBounds = bounds.inflate(stroke.strokeWidth);
    if (!expandedBounds.contains(point)) {
      return false;
    }
    
    // ✅ 对于形状笔迹，使用更精确的检测
    if (stroke is LineStroke) {
      return _isPointNearLine(point, stroke.startPoint, stroke.endPoint, stroke.strokeWidth);
    } else if (stroke is RectangleStroke) {
      return stroke.rect.inflate(stroke.strokeWidth).contains(point);
    } else if (stroke is CircleStroke) {
      final center = stroke.center;
      final distance = (point - center).distance;
      return distance <= stroke.radius + stroke.strokeWidth;
    } else if (stroke is TriangleStroke) {
      // 检查点是否在三角形内
      return _isPointInTriangle(point, stroke.point1, stroke.point2, stroke.point3);
    } else if (stroke is DiamondStroke) {
      // 检查点是否在菱形内
      return _isPointInPolygon(point, stroke.points);
    } else {
      // ✅ 对于普通笔迹，检查点是否在路径附近
      // 使用路径的边界框和点距离检测
      final tolerance = stroke.strokeWidth * 2;
      for (final strokePoint in stroke.points) {
        final distance = (point - strokePoint).distance;
        if (distance < tolerance) {
          return true;
        }
      }
      // 如果点不在任何顶点附近，检查是否在路径内（使用路径的contains方法）
      return smoothPath.contains(point);
    }
  }
  
  /// ✅ 检查点是否在直线附近
  bool _isPointNearLine(Offset point, Offset lineStart, Offset lineEnd, double strokeWidth) {
    final A = point.dx - lineStart.dx;
    final B = point.dy - lineStart.dy;
    final C = lineEnd.dx - lineStart.dx;
    final D = lineEnd.dy - lineStart.dy;
    
    final dot = A * C + B * D;
    final lenSq = C * C + D * D;
    if (lenSq == 0) {
      // 线段退化为点
      return (point - lineStart).distance < strokeWidth * 2;
    }
    
    final param = dot / lenSq;
    Offset closestPoint;
    if (param < 0) {
      closestPoint = lineStart;
    } else if (param > 1) {
      closestPoint = lineEnd;
    } else {
      closestPoint = Offset(
        lineStart.dx + param * C,
        lineStart.dy + param * D,
      );
    }
    
    final distance = (point - closestPoint).distance;
    return distance < strokeWidth * 2;
  }
  
  /// ✅ 检查点是否在三角形内
  bool _isPointInTriangle(Offset point, Offset p1, Offset p2, Offset p3) {
    // 使用重心坐标法
    final d1 = _sign(point, p1, p2);
    final d2 = _sign(point, p2, p3);
    final d3 = _sign(point, p3, p1);
    
    final hasNeg = (d1 < 0) || (d2 < 0) || (d3 < 0);
    final hasPos = (d1 > 0) || (d2 > 0) || (d3 > 0);
    
    return !(hasNeg && hasPos);
  }
  
  double _sign(Offset p1, Offset p2, Offset p3) {
    return (p1.dx - p3.dx) * (p2.dy - p3.dy) - (p2.dx - p3.dx) * (p1.dy - p3.dy);
  }
  
  /// ✅ 检查点是否在多边形内
  bool _isPointInPolygon(Offset point, List<Offset> polygon) {
    if (polygon.length < 3) {
      return false;
    }
    
    bool inside = false;
    int j = polygon.length - 1;
    for (int i = 0; i < polygon.length; i++) {
      final xi = polygon[i].dx;
      final yi = polygon[i].dy;
      final xj = polygon[j].dx;
      final yj = polygon[j].dy;
      
      final intersect = ((yi > point.dy) != (yj > point.dy)) &&
          (point.dx < (xj - xi) * (point.dy - yi) / (yj - yi) + xi);
      if (intersect) {
        inside = !inside;
      }
      j = i;
    }
    
    return inside;
  }
  
  /// ✅ 检查点是否在选择区域内
  bool _isPointInSelection(Offset point, SelectResult selectResult) {
    // 检查是否在某个选中的笔迹附近
    for (final stroke in selectResult.strokes) {
      for (final strokePoint in stroke.points) {
        final distance = (point - strokePoint).distance;
        if (distance < stroke.strokeWidth * 2) {
          return true;
        }
      }
    }
    
    // 检查是否在某个选中的图片内
    for (final image in selectResult.images) {
      if (image.dstRect != null && image.dstRect!.contains(point)) {
        return true;
      }
    }
    
    return false;
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
    final eraserSize = _currentToolNotifier.value.strokeWidth;
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
      _scheduleSave();
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
    // ✅ 如果是选择工具，更新选择
    if (_currentToolNotifier.value.toolId == ToolId.select) {
      _updateSelection(position);
      return;
    }
    
    // 如果是橡皮擦，继续检测并删除相交的笔迹
    if (_currentToolNotifier.value.toolId == ToolId.eraser) {
      _eraseStrokesAtPosition(position, pageIndex: _currentPageIndex);
      return;
    }
    
    final Stroke? stroke = _currentStrokeNotifier.value;
    debugPrint('🦋[HandwritingSaber] _updateStroke: position=$position, tool=${_currentToolNotifier.value.toolId}, hasCurrentStroke=${stroke != null}');
    if (stroke == null) {
      return;
    }
    
    // ✅ 对于形状工具，更新结束点并重新计算形状点
    final toolId = _currentToolNotifier.value.toolId;
    if (toolId == ToolId.triangle) {
      // ✅ 三角形工具：一笔绘制，像自由多边形一样添加点
      stroke.points.add(position);
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
    
    // 为确保 CustomPainter 能检测到变化，替换成新的 Stroke 实例（改变对象引用）
    _currentStrokeNotifier.value = Stroke(
      points: List<Offset>.from(stroke.points),
      color: stroke.color,
      strokeWidth: stroke.strokeWidth,
      toolId: stroke.toolId,
      pressureEnabled: stroke.pressureEnabled,
    );
  }
  
  /// ✅ 更新选择
  void _updateSelection(Offset position) {
    if (_selectResult == null || _selectStartPosition == null) {
      return;
    }
    
    // ✅ 如果已经完成选择（点击选择或拖拽选择完成），则移动选中的对象
    if (!_isSelecting && _selectResult!.pageIndex == (_currentPageIndex ?? 0) && !_selectResult!.isEmpty) {
      final offset = position - _selectStartPosition!;
      if (offset.distance > 1.0) { // 只有移动距离大于1像素才移动
        _selectResult!.move(offset);
        _selectStartPosition = position;
        setState(() {
          // 触发重绘
        });
        // 使用防抖保存，避免频繁磁盘写入导致 UI 卡顿
        _scheduleSave();
      }
      return;
    }
    
    // ✅ 更新选择路径（拖拽选择区域）
    if (_isSelecting) {
        setState(() {
          _selectResult!.selectionPath.lineTo(position.dx, position.dy);
        });
        _scheduleSave();
    }
  }

  /// ✅ 结束选择
  void _endSelection() {
    if (_selectResult == null) {
      return;
    }
    
    if (_isSelecting) {
      // ✅ 完成选择区域，检测区域内的对象
      if (_selectResult!.selectionPath.getBounds().width > 5 || 
          _selectResult!.selectionPath.getBounds().height > 5) {
        // 只有选择区域足够大时才检测（避免误触）
        _selectResult!.selectionPath.close();
        _detectObjectsInSelection(_selectResult!);
      } else {
        // ✅ 选择区域太小，取消选择
        setState(() {
          _selectResult = null;
          _isSelecting = false;
          _selectStartPosition = null;
        });
        return;
      }
        setState(() {
          _isSelecting = false;
        });
        _scheduleSave();
    } else {
      // ✅ 移动完成，保持选择状态
      _selectStartPosition = null;
    }
  }
  
  /// ✅ 取消选择（点击空白区域时调用）
  void _clearSelection() {
    setState(() {
      _selectResult = null;
      _isSelecting = false;
      _selectStartPosition = null;
    });
  }
  
  /// ✅ 创建文本框（直接在画布上编辑，不弹出对话框）
  void _createTextBox(Offset position, {int? pageIndex}) {
    final pageIdx = pageIndex ?? 0;
    if (pageIdx < 0 || pageIdx >= _coreInfo.pages.length) {
      return;
    }
    
    final page = _coreInfo.pages[pageIdx];
    
    // ✅ 根据工具类型确定文本框类型
    saber_text.TextBoxType textBoxType = saber_text.TextBoxType.normal;
    if (_currentToolNotifier.value.toolId == ToolId.heading1) {
      textBoxType = saber_text.TextBoxType.heading1;
    } else if (_currentToolNotifier.value.toolId == ToolId.heading2) {
      textBoxType = saber_text.TextBoxType.heading2;
    } else if (_currentToolNotifier.value.toolId == ToolId.heading3) {
      textBoxType = saber_text.TextBoxType.heading3;
    } else if (_currentToolNotifier.value.toolId == ToolId.paragraph) {
      textBoxType = saber_text.TextBoxType.paragraph;
    }
    
    // ✅ 创建新文本框（默认大小）
    final textBox = saber_text.TextBox(
      id: 'textbox_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}',
      position: position,
      size: const Size(200, 100), // 默认大小
      text: '',
      textStyle: TextStyle(
        fontSize: 16,
        color: _currentToolNotifier.value.color,
      ),
      textBoxType: textBoxType, // ✅ 设置文本框类型
    );
    
    // ✅ 应用标题样式
    if (textBoxType != saber_text.TextBoxType.normal) {
      textBox.textStyle = textBox.getHeadingStyle(_currentToolNotifier.value.color);
    }
    
    // ✅ 创建文本编辑控制器
    final controller = TextEditingController(text: '');
    _textBoxControllers[textBox.id] = controller;
    
    // ✅ 添加到页面并进入编辑模式
    setState(() {
      page.textBoxes.add(textBox);
      _editingTextBoxId = textBox.id;
    });
    
    // ✅ 监听文本变化（仅更新模型并使用防抖保存，避免频繁 setState）
    controller.addListener(() {
      if (_editingTextBoxId == textBox.id) {
        textBox.text = controller.text;
        _scheduleSave();
      }
    });
  }
  
  
  /// ✅ 查找点击位置的文本框
  saber_text.TextBox? _findTextBoxAtPosition(Offset position, int pageIndex) {
    if (_coreInfo.pages.isEmpty || pageIndex < 0 || pageIndex >= _coreInfo.pages.length) {
      return null;
    }
    
    final page = _coreInfo.pages[pageIndex];
    
    // ✅ 从后往前查找（最上层的文本框优先）
    for (int i = page.textBoxes.length - 1; i >= 0; i--) {
      final textBox = page.textBoxes[i];
      if (textBox.rect.contains(position)) {
        return textBox;
      }
    }
    
    return null;
  }
  
  /// ✅ 编辑文本框（点击已存在的文本框时调用，直接在画布上编辑）
  void _editTextBox(saber_text.TextBox textBox) {
    // ✅ 创建或获取文本编辑控制器
    if (!_textBoxControllers.containsKey(textBox.id)) {
      final controller = TextEditingController(text: textBox.text);
      _textBoxControllers[textBox.id] = controller;
      
      // ✅ 监听文本变化（仅更新模型并使用防抖保存，避免频繁 setState）
      controller.addListener(() {
        if (_editingTextBoxId == textBox.id) {
          textBox.text = controller.text;
          _scheduleSave();
        }
      });
    } else {
      // ✅ 更新控制器文本
      _textBoxControllers[textBox.id]!.text = textBox.text;
    }
    
    // ✅ 进入编辑模式
    setState(() {
      _editingTextBoxId = textBox.id;
    });
  }
  
  /// ✅ 结束文本框编辑
  void _endTextBoxEditing() {
    setState(() {
      _editingTextBoxId = null;
    });
  }
  
  /// ✅ 构建文本框编辑器（直接在画布上显示）
  Widget _buildTextBoxEditor(
    saber_text.TextBox textBox,
    int pageIndex,
    double screenWidth,
    double pageDisplayWidth,
    double pageDisplayHeight,
  ) {
    // ✅ 计算页面缩放和偏移
    final page = _coreInfo.pages[pageIndex];
    final double scaleX = pageDisplayWidth / page.size.width;
    final double scaleY = pageDisplayHeight / page.size.height;
    final double scale = scaleX < scaleY ? scaleX : scaleY;
    final double drawWidth = page.size.width * scale;
    final double drawHeight = page.size.height * scale;
    final double offsetX = (screenWidth - drawWidth) / 2;
    final double offsetY = (pageDisplayHeight - drawHeight) / 2;
    
    // ✅ 计算文本框在屏幕上的位置
    final double textBoxLeft = offsetX + textBox.position.dx * scale;
    final double textBoxTop = offsetY + textBox.position.dy * scale;
    final double textBoxWidth = textBox.size.width * scale;
    final double textBoxHeight = textBox.size.height * scale;
    
    // ✅ 获取或创建文本控制器
    if (!_textBoxControllers.containsKey(textBox.id)) {
      final controller = TextEditingController(text: textBox.text);
      _textBoxControllers[textBox.id] = controller;
      
      // ✅ 监听文本变化（仅更新模型并使用防抖保存，避免频繁 setState）
      controller.addListener(() {
        if (_editingTextBoxId == textBox.id) {
          textBox.text = controller.text;
          _scheduleSave();
        }
      });
    }
    
    final controller = _textBoxControllers[textBox.id]!;
    
    return Positioned(
      left: textBoxLeft,
      top: textBoxTop,
      width: textBoxWidth,
      height: textBoxHeight,
      child: TextField(
        autofocus: true,
        controller: controller,
        maxLines: null,
        minLines: 1,
        style: textBox.textStyle ?? const TextStyle(fontSize: 16),
        decoration: InputDecoration(
          hintText: '输入文本...',
          border: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.blue, width: 2),
          ),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.95),
        ),
        onSubmitted: (_) {
          _endTextBoxEditing();
        },
        onTapOutside: (_) {
          _endTextBoxEditing();
        },
      ),
    );
  }
  
  /// ✅ 检测选择区域内的对象
  void _detectObjectsInSelection(SelectResult selectResult) {
    if (_coreInfo.pages.isEmpty) {
      return;
    }
    
    final pageIndex = selectResult.pageIndex;
    if (pageIndex < 0 || pageIndex >= _coreInfo.pages.length) {
      return;
    }
    
    final page = _coreInfo.pages[pageIndex];
    final selectionPath = selectResult.selectionPath;
    
    // ✅ 检测笔迹（简化版：检查笔迹的点是否在选择区域内）
    final selectedStrokes = <Stroke>[];
    for (final stroke in page.strokes) {
      int pointsInside = 0;
      for (final point in stroke.points) {
        if (selectionPath.contains(point)) {
          pointsInside++;
        }
      }
      // 如果70%以上的点在选择区域内，则认为被选中
      if (stroke.points.isNotEmpty && 
          pointsInside / stroke.points.length >= 0.7) {
        selectedStrokes.add(stroke);
      }
    }
    
    // ✅ 检测图片
    final selectedImages = <PdfEditorImage>[];
    if (page.backgroundImage != null) {
      final image = page.backgroundImage!;
      if (image.dstRect != null) {
        final rect = image.dstRect!;
        // 检查矩形的四个角是否在选择区域内
        int cornersInside = 0;
        final corners = [
          Offset(rect.left, rect.top),
          Offset(rect.right, rect.top),
          Offset(rect.right, rect.bottom),
          Offset(rect.left, rect.bottom),
        ];
        for (final corner in corners) {
          if (selectionPath.contains(corner)) {
            cornersInside++;
          }
        }
        // 如果至少3个角在选择区域内，则认为被选中
        if (cornersInside >= 3) {
          selectedImages.add(image);
        }
      }
    }
    
    setState(() {
      selectResult.strokes.clear();
      selectResult.strokes.addAll(selectedStrokes);
      selectResult.images.clear();
      selectResult.images.addAll(selectedImages);
    });
  }

  Future<void> _endStroke() async {
    // ✅ 如果是选择工具，结束选择
    if (_currentToolNotifier.value.toolId == ToolId.select) {
      _endSelection();
      return;
    }
    
    final Stroke? stroke = _currentStrokeNotifier.value;
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
          fillColor: _currentFillColor, // ✅ 传递填充颜色
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
          fillColor: _currentFillColor, // ✅ 传递填充颜色
        );
      }
    } else if (toolId == ToolId.triangle) {
      // ✅ 三角形：一笔绘制，自动优化为三角形
      if (stroke.points.length >= 2) {
        // ✅ 检测Shift键状态
        final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
        finalStroke = TriangleStroke(
          points: List<Offset>.from(stroke.points),
          color: stroke.color,
          strokeWidth: stroke.strokeWidth,
          toolId: toolId,
          isShiftPressed: isShiftPressed, // ✅ 传递Shift键状态
          fillColor: _currentFillColor, // ✅ 传递填充颜色
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
          fillColor: _currentFillColor, // ✅ 传递填充颜色
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
      // 同步到激光笔 notifier（用于局部重绘）
      _laserStrokesNotifier.value = List<Stroke>.from(_laserStrokesNotifier.value)..add(laserStroke);
      // ✅ 启动激光笔淡出动画（不使用 setState，使用 notifier 驱动局部重绘）
      _startLaserFadeOut(laserStroke);
      // 使用 notifier 清空当前笔迹（避免触发整页重建）
      _currentStrokeNotifier.value = null;
      await _saveToStorage(suppressStatusUpdate: true);
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
    
    // 清空 notifier 值，触发 CustomPainter 的局部重绘
    _currentStrokeNotifier.value = null;
    // 不触发父级重建，仅重置页面索引
    _currentPageIndex = null;
    // 如果之前有待保存请求（在绘制期间调用过_scheduleSave），则立即保存一次
    if (_pendingSave) {
      _pendingSave = false;
      _saveDebounceTimer?.cancel();
      await _saveToStorage(suppressStatusUpdate: true);
    } else {
      // 否则安排一次延迟保存（确保最终一致性）
      _scheduleSave();
    }
  }

  void _onToolChanged(Tool tool) {
    debugPrint('🦋[HandwritingSaber] _onToolChanged: ${tool.toolId}');
    
    // ✅ 如果切换到选择工具，清除之前的选择状态
    if (tool.toolId == ToolId.select) {
      debugPrint('🦋[HandwritingSaber] Switching to select tool, clearing selection');
      setState(() {
        _selectResult = null;
        _isSelecting = false;
        _selectStartPosition = null;
      });
      // 更新当前工具（不触发父级重建）
      _currentToolNotifier.value = tool;
    } else {
      // ✅ 切换到其他工具时，也清除选择状态
      if (_currentToolNotifier.value.toolId == ToolId.select) {
        debugPrint('🦋[HandwritingSaber] Switching away from select tool, clearing selection');
        setState(() {
          _selectResult = null;
          _isSelecting = false;
          _selectStartPosition = null;
        });
      }
      // 更新当前工具（不触发父级重建）
      _currentToolNotifier.value = tool;
    }
    
    debugPrint('🦋[HandwritingSaber] _onToolChanged completed: ${tool.toolId}');
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
    _scheduleSave();
  }

  void _onColorChanged(Color color) {
    // 仅更新当前工具的颜色，不触发父级重建（toolbar 会通过 notifier 更新自身）
    if (_currentToolNotifier.value is Pen) {
      final updated = (_currentToolNotifier.value as Pen).copyWith(color: color);
      _currentToolNotifier.value = updated;
    }
  }

  /// ✅ 填充颜色改变回调
  void _onFillColorChanged(Color? fillColor) {
    setState(() {
      _currentFillColor = fillColor;
    });
  }

  void _onStrokeWidthChanged(double width) {
    // 更新当前工具的 strokeWidth，不触发父级重建
    if (_currentToolNotifier.value is Pen) {
      _currentToolNotifier.value = (_currentToolNotifier.value as Pen).copyWith(strokeWidth: width);
    } else if (_currentToolNotifier.value is Eraser) {
      _currentToolNotifier.value = Eraser(strokeWidth: width);
    }
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
          // ✅ 点击在页面外，取消选择
          if (_currentToolNotifier.value.toolId == ToolId.select) {
            _clearSelection();
          }
          return;
        }
        final pagePos = toPageCoordinates(details.localPosition);
        debugPrint('🦋[HandwritingSaber] onPanStart: local=${details.localPosition}, pagePos=$pagePos, pageIndex=$pageIndex, tool=${_currentToolNotifier.value.toolId}');
        if (pagePos.dx.isFinite && pagePos.dy.isFinite) {
          // ✅ 如果点击在空白区域，结束文本框编辑
          if (_editingTextBoxId != null) {
            final clickedTextBox = _findTextBoxAtPosition(pagePos, pageIndex);
            if (clickedTextBox == null || clickedTextBox.id != _editingTextBoxId) {
              _endTextBoxEditing();
            }
          }
          
          // ✅ 如果是选择工具，检查是否点击在空白区域或文本框
          if (_currentToolNotifier.value.toolId == ToolId.select) {
            final clickedStroke = _findStrokeAtPosition(pagePos, pageIndex);
            final clickedTextBox = _findTextBoxAtPosition(pagePos, pageIndex);
            if (clickedStroke == null && clickedTextBox == null &&
                (_selectResult == null || !_isPointInSelection(pagePos, _selectResult!))) {
              // ✅ 点击在空白区域，取消选择
              _clearSelection();
            } else if (clickedTextBox != null) {
              // ✅ 点击在文本框上，编辑文本框
              _editTextBox(clickedTextBox);
              return;
            }
          }
          // ✅ 如果是文本框工具或标题工具，检查是否点击在已存在的文本框上
          if (_currentToolNotifier.value.toolId == ToolId.textBox ||
              _currentToolNotifier.value.toolId == ToolId.heading1 ||
              _currentToolNotifier.value.toolId == ToolId.heading2 ||
              _currentToolNotifier.value.toolId == ToolId.heading3 ||
              _currentToolNotifier.value.toolId == ToolId.paragraph) {
            final clickedTextBox = _findTextBoxAtPosition(pagePos, pageIndex);
            if (clickedTextBox != null) {
              // ✅ 点击在已存在的文本框上，编辑它
              _editTextBox(clickedTextBox);
              return;
            }
          }
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
        debugPrint('🦋[HandwritingSaber] onPanUpdate: local=${details.localPosition}, pagePos=$pagePos, pageIndex=$pageIndex, tool=${_currentToolNotifier.value.toolId}');
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
          child: Stack(
            children: [
              // ✅ 画布层
                // 传递当前 UI 选择的背景样式，避免 coreInfo 未同步导致背景显示不一致
                SaberCoreCanvas(
                  coreInfo: EditorCoreInfo(
                    pages: [page], // ✅ 只传递当前页面
                    backgroundColor: _coreInfo.backgroundColor,
                    backgroundPattern: _currentBackgroundPattern,
                    lineHeight: _coreInfo.lineHeight,
                    lineThickness: _coreInfo.lineThickness,
                  )..laserStrokes.addAll(_coreInfo.laserStrokes),
                  currentStrokeListenable: _currentStrokeNotifier,
                  repaintListenable: _repaintTick,
                  selectResult: _selectResult != null &&
                      _selectResult!.pageIndex == pageIndex
                      ? _selectResult
                      : null,
                  isSelecting: _isSelecting &&
                      _selectResult != null &&
                      _selectResult!.pageIndex == pageIndex,
                ),
                // debug: 输出当前页面与背景信息，便于定位背景样式问题
                Builder(builder: (context) {
                  debugPrint('🦋[HandwritingSaber] _buildSinglePageCanvas: pageIndex=$pageIndex, page.backgroundImage=${page.backgroundImage != null}, coreInfo.backgroundPattern=${_coreInfo.backgroundPattern}, currentBackgroundPattern=$_currentBackgroundPattern, page.strokes=${page.strokes.length}');
                  return const SizedBox.shrink();
                }),
              // ✅ 文本框编辑层（直接在画布上编辑）
              if (_editingTextBoxId != null) ...[
                for (final textBox in page.textBoxes)
                  if (textBox.id == _editingTextBoxId)
                    _buildTextBoxEditor(textBox, pageIndex, screenWidth, pageDisplayWidth, pageDisplayHeight),
              ],
            ],
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
      debugPrint('🦋[HandwritingSaber] 开始导入PDF: $pdfFilePath');
      final importStartTime = DateTime.now();

      // 显示加载提示（非阻塞）
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('正在分析PDF文件...'),
            duration: Duration(seconds: 2),
          ),
        );
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

      // 异步加载PDF文档（在后台线程，避免阻塞UI）
      final pdfDocument = await PdfDocument.openFile(pdfFilePath);
      final loadTime = DateTime.now().difference(importStartTime);
      debugPrint('🦋[HandwritingSaber] PDF文档加载完成: ${loadTime.inMilliseconds}ms, 页面数: ${pdfDocument.pages.length}');

      // 检查PDF是否有页面
      if (pdfDocument.pages.isEmpty) {
        pdfDocument.dispose();
        throw Exception('PDF 文件没有页面');
      }

      // ✅ 为每个 PDF 页面创建一个新的 EditorPage（严格按照Saber的实现）
      final pageCreationStartTime = DateTime.now();
      bool _isFirstPdfPage = true;
      for (final pdfPage in pdfDocument.pages) {
        // pdfrx 页面编号从 1 开始
        assert(pdfPage.pageNumber >= 1, 'pdfrx page numbers start at 1');

        // ✅ 计算页面尺寸（参考 Saber 的实现）
        // resize to defaultWidth to keep pen sizes consistent
        final pageSize = Size(
          EditorPage.defaultWidth,
          EditorPage.defaultWidth * pdfPage.height / pdfPage.width,
        );

        // ✅ 创建 PDF 背景图片（参考Saber的PdfEditorImage.fromJson实现）
        final pdfImage = PdfEditorImage(
          pdfFilePath: pdfFilePath,
          pdfPageIndex: pdfPage.pageNumber - 1,  // PDF 页面索引（从 0 开始）
          naturalSize: pdfPage.size,
          dstRect: Rect.fromLTWH(0, 0, pageSize.width, pageSize.height),
        );

        // ✅ 预加载PDF文档，避免首次显示时的闪烁
        pdfImage.preloadPdfDocument();

        // ✅ 创建新页面：仅将 existingStrokes 保留到导入前的"第一页"，其余页面不保留旧笔迹
        final page = EditorPage(
          size: pageSize,
          strokes: _isFirstPdfPage ? List<Stroke>.from(existingStrokes) : <Stroke>[],
          backgroundImage: pdfImage,
        );
        _coreInfo.pages.add(page);
        _isFirstPdfPage = false;
      }

      // ✅ 添加一个空页面（参考 Saber 的实现）
      _coreInfo.pages.add(EditorPage(
        size: EditorPage.defaultSize,
      ));

      final pageCreationTime = DateTime.now().difference(pageCreationStartTime);
      debugPrint('🦋[HandwritingSaber] 页面创建完成: ${pageCreationTime.inMilliseconds}ms');

      // 触发UI更新（此时PDF还未完全加载，但页面结构已建立）
      setState(() {});

      // ✅ 使用智能页面管理器进行预加载优化
      final pageManager = PdfMultiPageManager();
      final visiblePageKeys = <String>[];

      // 收集所有页面键，用于智能加载
      for (final page in _coreInfo.pages) {
        if (page.backgroundImage != null) {
          final pageKey = '${page.backgroundImage!.pdfFilePath}|${page.backgroundImage!.pdfPageIndex}';
          visiblePageKeys.add(pageKey);
        }
      }

      // 更新可见页面，启动智能加载策略
      pageManager.updateVisiblePages(visiblePageKeys);

      debugPrint('🦋[HandwritingSaber] 已启动智能PDF预加载，页面数: ${visiblePageKeys.length}');

      // 异步保存到存储（不阻塞UI）
      _saveToStorage().then((_) {
        debugPrint('🦋[HandwritingSaber] 数据保存完成');
      });

      final totalImportTime = DateTime.now().difference(importStartTime);
      debugPrint('🦋[HandwritingSaber] PDF导入完成: 总用时 ${totalImportTime.inMilliseconds}ms');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF导入成功（${pdfDocument.pages.length}页），正在加载页面内容...'),
            duration: const Duration(seconds: 3),
          ),
        );
      }

      // 释放临时PDF文档（PdfEditorImage会管理自己的文档）
      pdfDocument.dispose();

    } catch (e) {
      debugPrint('❌ [HandwritingSaberPocPage] 导入 PDF 失败：$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导入 PDF 失败：$e'),
            duration: const Duration(seconds: 5),
          ),
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
    if (!_laserStrokesNotifier.value.contains(stroke)) {
      return;
    }

    // ✅ 逐个删除点（使用 notifier 驱动局部重绘，避免父级 setState）
    for (final delay in strokePointDelays) {
      await Future.delayed(delay);

      // ✅ 如果笔迹已经被删除或点数为0，退出
      if (!_laserStrokesNotifier.value.contains(stroke) || stroke.points.isEmpty) {
        break;
      }

      // 删除第一个点
      stroke.popFirstPoint();

      // 更新 notifier 触发 painter 局部重绘
      _laserStrokesNotifier.value = List<Stroke>.from(_laserStrokesNotifier.value);

      // 如果用户重新开始绘制（currentStroke 非空），等待用户停止再继续淡出
      if (_currentStrokeNotifier.value != null) {
        const waitTime = Duration(milliseconds: 100);
        while (_currentStrokeNotifier.value != null) {
          await Future.delayed(waitTime);
        }
        // 等待一个较短时间，避免立即继续导致突兀
        await Future.delayed(fadeOutDelay - waitTime);
      }
    }

    // ✅ 循环结束后删除整个笔迹并更新 notifier
    _coreInfo.laserStrokes.remove(stroke);
    _laserStrokesNotifier.value = List<Stroke>.from(_laserStrokesNotifier.value)..remove(stroke);
    _laserFadeOutTimers.remove(stroke);
    await _saveToStorage(suppressStatusUpdate: true);
  }
  
  @override
  void dispose() {
    // ✅ 清理所有激光笔淡出定时器
    for (final timer in _laserFadeOutTimers.values) {
      timer.cancel();
    }
    _laserFadeOutTimers.clear();

    // ✅ 清理PDF背景图片资源
    for (final page in _coreInfo.pages) {
      page.backgroundImage?.dispose();
    }

    // ✅ 清理PDF文档缓存管理器
    PdfDocumentCacheManager().dispose();

    // ✅ 清理当前笔迹通知器
    _currentStrokeNotifier.dispose();
    _laserStrokesNotifier.dispose();
    _repaintTick.dispose();

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
          ValueListenableBuilder<Tool>(
            valueListenable: _currentToolNotifier,
            builder: (context, currentTool, child) {
              return HandwritingSaberToolbar(
                currentTool: currentTool,
                onToolChanged: _onToolChanged,
                currentBackgroundPattern: _currentBackgroundPattern,
                onBackgroundPatternChanged: _onBackgroundPatternChanged,
                currentColor: currentTool.color,
                onColorChanged: _onColorChanged,
                currentStrokeWidth: currentTool.strokeWidth,
                onStrokeWidthChanged: _onStrokeWidthChanged,
                currentFillColor: _currentFillColor, // ✅ 填充颜色
                onFillColorChanged: _onFillColorChanged, // ✅ 填充颜色改变回调
                onImportPdf: _importPdf,  // ✅ PDF 导入回调
              );
            },
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


