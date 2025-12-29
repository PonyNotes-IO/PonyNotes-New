import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:pdfrx/pdfrx.dart';

import '../application/handwriting_saber_data_service.dart';
import '../third_party/saber_core/components/canvas/canvas_background_pattern.dart';
import '../third_party/saber_core/components/canvas/image/pdf_editor_image.dart';
import '../third_party/saber_core/components/canvas/saber_core_canvas.dart';
import '../third_party/saber_core/data/editor/editor_core_info.dart';
import '../third_party/saber_core/data/editor/editor_history.dart'; // ✅ 导入历史记录管理器
import '../third_party/saber_core/data/editor/page.dart';
import '../third_party/saber_core/data/editor/quill_styles.dart';
import '../third_party/saber_core/data/editor/shape_strokes.dart';
import '../third_party/saber_core/data/editor/stroke_extensions.dart'; // ✅ 导入扩展方法
import '../third_party/saber_core/data/editor/text_box.dart' as saber_text; // ✅ 导入文本框（使用别名避免与Flutter的TextBox冲突）
import '../third_party/saber_core/data/tools/select_result.dart';
import '../third_party/saber_core/data/tools/tool.dart';
import 'handwriting_saber_toolbar.dart';
import '../../../util/log_utils.dart';

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

  /// ✅ 页面状态notifier列表（用于精确更新，避免全量重建）
  final List<EditorPageNotifier> _pageNotifiers = [];

  /// 当前工具（使用 ValueNotifier 以便在切换工具时避免触发父级整页重建）
  // 默认工具：钢笔，默认颜色黑色，默认粗细 2（用户要求）
  final ValueNotifier<Tool> _currentToolNotifier = ValueNotifier<Tool>(const Pen(
    toolId: ToolId.fountainPen,
    color: Colors.black,
    strokeWidth: 2,
  ));

  /// 当前背景纸模式（使用 EditorCoreInfo.empty() 的默认以保证一致）
  CanvasBackgroundPattern _currentBackgroundPattern =
      EditorCoreInfo.empty().backgroundPattern;
  
  /// ✅ 当前填充颜色（用于形状工具） - 使用 ValueNotifier 避免父级 setState 导致整页重建
  final ValueNotifier<Color?> _currentFillColorNotifier = ValueNotifier<Color?>(null);
  /// ✅ 全局当前描边颜色（保证切换工具时保留用户选择的颜色）
  final ValueNotifier<Color> _globalColorNotifier = ValueNotifier<Color>(Colors.black);
  /// ✅ 全局当前描边宽度（保证切换工具时保留用户选择的线宽）
  final ValueNotifier<double> _globalStrokeWidthNotifier = ValueNotifier<double>(2.0);
  
  /// ✅ 激光笔淡出定时器（用于管理多个激光笔笔迹的淡出）
  final Map<Stroke, Timer> _laserFadeOutTimers = {};
  /// 激光笔绘制时每点延迟记录（用于实现按绘制速度淡出）
  final Map<Stroke, List<Duration>> _laserStrokePointDelays = {};
  /// 激光笔绘制时的 Stopwatches（用于记录点间时间）
  final Map<Stroke, Stopwatch> _laserStrokeStopwatches = {};
  /// 当前是否有激光笔正在淡出（用于抑制保存等操作）
  bool _isLaserFadeInProgress = false;

  /// ✅ 选择工具状态
  SelectResult? _selectResult;
  bool _isSelecting = false; // 是否正在选择（拖拽选择区域）
  Offset? _selectStartPosition; // 选择开始位置
  
  /// ✅ 当前正在编辑的文本框ID（使用ValueNotifier避免全局setState）
  final ValueNotifier<String?> _editingTextBoxIdNotifier = ValueNotifier<String?>(null);
  
  /// ✅ 文本框编辑控制器
  final Map<String, TextEditingController> _textBoxControllers = {};
  
  // ✅ 移除有问题的页面缓存机制
  // 原因：缓存判断条件（仅检查页面数量）不够准确，导致数据更新后界面不刷新
  // ListenableBuilder已经提供了充分的优化，不需要额外的缓存
  // List<Widget>? _cachedPageWidgets;
  // int _cachedPagesCount = 0;
  
  /// ✅ 历史记录管理器
  final EditorHistory _history = EditorHistory();
  
  /// ✅ 撤销/恢复状态 notifier（用于更新工具栏按钮状态）
  final ValueNotifier<bool> _canUndoNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _canRedoNotifier = ValueNotifier<bool>(false);
  
  /// ✅ 当前虚线样式（用于直线工具）
  final ValueNotifier<DashStyle> _dashStyleNotifier = ValueNotifier<DashStyle>(DashStyle.solid);
  
  /// ✅ 当前箭头样式（用于箭头直线工具）
  final ValueNotifier<ArrowStyle> _arrowStyleNotifier = ValueNotifier<ArrowStyle>(ArrowStyle.filled);
  
  /// ✅ 文本编辑模式状态（用于切换富文本编辑模式）
  final ValueNotifier<bool> _textEditingModeNotifier = ValueNotifier<bool>(false);
  
  /// ✅ 当前焦点页面的 Quill 结构（用于在编辑模式下显示工具栏）
  final ValueNotifier<int?> _quillFocusPageIndexNotifier = ValueNotifier<int?>(null);

  @override
  void initState() {
    super.initState();
    debugPrint('🚀🚀🚀 [HandwritingSaber] ===== initState =====');
    debugPrint('🚀🚀🚀 [HandwritingSaber] ViewID: ${widget.view.id}');
    debugPrint('🚀🚀🚀 [HandwritingSaber] ViewName: ${widget.view.name}');
    _initLocalData();
    // 合并 repaint：当当前笔迹或激光笔列表变化时，更新 tick 以触发局部重绘
    _currentStrokeNotifier.addListener(() {
      _repaintTick.value++;
    });
    _laserStrokesNotifier.addListener(() {
      _repaintTick.value++;
    });
  }
  
  @override
  void didUpdateWidget(HandwritingSaberPocPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    debugPrint('🔄🔄🔄 [HandwritingSaber] ===== didUpdateWidget =====');
    debugPrint('🔄🔄🔄 [HandwritingSaber] Old ViewID: ${oldWidget.view.id}, Old ViewName: ${oldWidget.view.name}');
    debugPrint('🔄🔄🔄 [HandwritingSaber] New ViewID: ${widget.view.id}, New ViewName: ${widget.view.name}');
    // ✅ 如果视图ID发生变化，重新加载数据
    if (oldWidget.view.id != widget.view.id) {
      debugPrint('🔄🔄🔄 [HandwritingSaber] ViewID CHANGED! Reloading data...');
      // 清理旧视图的状态
      _cleanupViewState();
      // 重新初始化数据
      _initLocalData();
    } else {
      debugPrint('🔄🔄🔄 [HandwritingSaber] ViewID unchanged, skipping reload');
    }
  }
  
  /// ✅ 清理视图状态（切换视图时调用）
  void _cleanupViewState() {
    debugPrint('🦋[HandwritingSaber] _cleanupViewState called');
    // 清理当前笔迹
    _currentStrokeNotifier.value = null;
    _currentPageIndex = null;
    // 清理激光笔
    _laserStrokesNotifier.value = [];
    _coreInfo.laserStrokes.clear();
    // 清理选择状态
    _selectResult = null;
    _selectStartPosition = null;
    _isSelecting = false;
    // 清理文本框控制器
    for (final controller in _textBoxControllers.values) {
      controller.dispose();
    }
    _textBoxControllers.clear();
    // 清理历史记录
    _history.clear();  // ✅ 使用clear()方法而不是重新赋值
    _updateUndoRedoState();
    // 清理页面notifier
    for (final notifier in _pageNotifiers) {
      notifier.dispose();
    }
    _pageNotifiers.clear();
    // ✅ 清理页面缓存（已移除缓存机制）
    // _cachedPageWidgets = null;
    // _cachedPagesCount = 0;
    // 取消待保存标记
    _pendingSave = false;
    _saveDebounceTimer?.cancel();
  }
  
  /// ✅ 初始化页面状态notifier（用于精确更新，避免全量重建）
  void _initPageNotifiers() {
    // 清理旧的notifier
    for (final notifier in _pageNotifiers) {
      notifier.dispose();
    }
    _pageNotifiers.clear();

    // 为每个页面创建notifier
    for (final page in _coreInfo.pages) {
      _pageNotifiers.add(EditorPageNotifier(page));
    }
  }
  
  /// ✅ 预加载所有页面的PDF背景图（视图切换时调用，确保PDF图片能正确显示）
  void _preloadPdfBackgrounds() {
    int pdfPageCount = 0;
    for (final page in _coreInfo.pages) {
      if (page.backgroundImage != null) {
        page.backgroundImage!.preloadPdfDocument();
        pdfPageCount++;
      }
    }
    if (pdfPageCount > 0) {
      debugPrint('🦋[HandwritingSaber] _preloadPdfBackgrounds: Preloading $pdfPageCount PDF background images');
    }
  }

  /// 初始化本地数据：
  /// - 调用 HandwritingSaberDataService 打开/创建对应视图的数据文件；
  /// - 尝试从文件中加载 JSON 形式的 EditorCoreInfo；
  /// - 仅在 PoC 阶段使用 JSON 存储，后续会替换为真正的 .sbn2 二进制。
  Future<void> _initLocalData() async {
    debugPrint('🦋🦋🦋 [HandwritingSaber] ===== _initLocalData START =====');
    debugPrint('🦋🦋🦋 [HandwritingSaber] ViewID: ${widget.view.id}');
    debugPrint('🦋🦋🦋 [HandwritingSaber] ViewName: ${widget.view.name}');
    try {
      // 1. 打开或创建手写笔记数据文件（通过统一数据服务）
      await _dataService.openHandwritingSaber(viewId: widget.view.id);

      // 2. 加载已有数据（PoC 阶段按 JSON 文本解析）
      await _loadFromStorage();
      
      debugPrint('🦋🦋🦋 [HandwritingSaber] _initLocalData: Data loaded, pages=${_coreInfo.pages.length}');

      if (mounted) {
        setState(() {
          _status = '已就绪';
        });
      }
    } catch (e) {
      debugPrint('❌❌❌ [HandwritingSaber] _initLocalData ERROR: $e');
      setState(() {
        _status = '本地数据初始化失败：$e';
      });
    }
    debugPrint('🦋🦋🦋 [HandwritingSaber] ===== _initLocalData END =====');
  }

  /// 从统一数据服务加载手写笔记数据
  ///
  /// 当前 PoC 阶段约定：
  /// - 实际存储的还是 EditorCoreInfo 的 JSON 字符串；
  /// - 未来切换为 Saber 真正的 .sbn2 时，只需要替换序列化/反序列化实现。
  Future<void> _loadFromStorage() async {
    debugPrint('📖📖📖 [HandwritingSaber] ===== _loadFromStorage START =====');
    debugPrint('📖📖📖 [HandwritingSaber] 当前_coreInfo.pages.length: ${_coreInfo.pages.length}');
    
    try {
      final List<int> bytes =
          await _dataService.loadHandwritingSaberData(widget.view.id);
      
      debugPrint('📖📖📖 [HandwritingSaber] Loaded ${bytes.length} bytes from storage');

      if (bytes.isEmpty) {
        debugPrint('📖📖📖 [HandwritingSaber] Empty data, creating new EditorCoreInfo');
        _coreInfo = EditorCoreInfo.empty();
        // 保证 UI 上的当前背景纸样式与核心数据一致（避免新建时工具栏/画布不一致）
        _currentBackgroundPattern = _coreInfo.backgroundPattern;
        _status = '已就绪';
      } else {
        final String content = utf8.decode(bytes);
        debugPrint('📖📖📖 [HandwritingSaber] Decoding JSON, content length: ${content.length}');
        _coreInfo = EditorCoreInfo.fromJsonString(content);
        debugPrint('📖📖📖 [HandwritingSaber] Decoded: ${_coreInfo.pages.length} pages');
        
        // ✅ 修复无效的页面尺寸（兼容旧版本数据）
        bool needsRepair = false;
        for (int i = 0; i < _coreInfo.pages.length; i++) {
          final page = _coreInfo.pages[i];
          debugPrint('📖📖📖 [HandwritingSaber] Page $i: size=${page.size}, strokes=${page.strokes.length}');
          if (page.size.width <= 0 || page.size.height <= 0) {
            debugPrint('🔧🔧🔧 [HandwritingSaber] Repairing invalid page size at index $i: ${page.size} -> ${EditorPage.defaultSize}');
            // 创建新的页面对象with正确的尺寸
            _coreInfo.pages[i] = EditorPage(
              size: EditorPage.defaultSize,
              strokes: page.strokes,
              backgroundImage: page.backgroundImage,
              textBoxes: page.textBoxes,
              listBoxes: page.listBoxes,
              taskListBoxes: page.taskListBoxes,
            );
            needsRepair = true;
          }
        }
        
        // 如果修复了数据，保存回文件
        if (needsRepair) {
          debugPrint('🔧🔧🔧 [HandwritingSaber] Data repaired, saving...');
          await _saveToStorage(suppressStatusUpdate: true);
        }
        
        // 同步当前背景纸样式，确保工具栏与数据一致
        _currentBackgroundPattern = _coreInfo.backgroundPattern;
        _status = '已就绪';
      }

      debugPrint('📖📖📖 [HandwritingSaber] Final _coreInfo.pages.length: ${_coreInfo.pages.length}');
      
      // ✅ 初始化页面notifier（用于精确状态更新）
      _initPageNotifiers();
      debugPrint('📖📖📖 [HandwritingSaber] Page notifiers initialized: ${_pageNotifiers.length}');
      
      // ✅ 预加载所有页面的PDF背景图
      _preloadPdfBackgrounds();
      
      // ✅ 强制刷新界面，确保加载的数据能正确显示
      if (mounted) {
        setState(() {
          // 触发Widget树重建，确保页面notifier被正确使用
          debugPrint('📖📖📖 [HandwritingSaber] setState called to rebuild UI');
        });
      }
    } catch (e) {
      debugPrint('❌❌❌ [HandwritingSaber] _loadFromStorage ERROR: $e');
      _coreInfo = EditorCoreInfo.empty();
      // 如果读取失败，也同步当前背景样式为默认
      _currentBackgroundPattern = _coreInfo.backgroundPattern;
      _status = '读取本地文件失败：$e';
      
      if (mounted) {
        setState(() {
          // 触发界面更新显示错误状态
        });
      }
    }
    debugPrint('📖📖📖 [HandwritingSaber] ===== _loadFromStorage END =====');
  }

  /// 将当前 EditorCoreInfo 保存到本地数据文件
  ///
  /// PoC 阶段采用 JSON 文本保存，后续切换为 .sbn2 时只需调整序列化逻辑。
  Future<void> _saveToStorage({bool suppressStatusUpdate = false}) async {
    // 如果正在进行激光淡出，延迟保存以避免 I/O 干扰渲染
    if (_isLaserFadeInProgress) {
      _pendingSave = true;
      debugPrint('🦋[HandwritingSaber] _saveToStorage deferred due to laser fade in progress');
      return;
    }
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
    if (_currentStrokeNotifier.value != null || _isLaserFadeInProgress) {
      _pendingSave = true;
      return;
    }
    _saveDebounceTimer = Timer(_saveDebounceDuration, () {
      _saveToStorage(suppressStatusUpdate: true);
    });
  }

  /// ✅ 当前正在绘制的页面索引
  int? _currentPageIndex;
  
  /// ✅ 形状工具的起始点（用于矩形、圆形、菱形等工具）
  Offset? _shapeStartPoint;
  
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
    
    // ✅ 保存形状工具的起始点
    final toolId = _currentToolNotifier.value.toolId;
    if (toolId == ToolId.line ||
        toolId == ToolId.arrowLine ||
        toolId == ToolId.rectangle || 
        toolId == ToolId.circle || 
        toolId == ToolId.diamond) {
      _shapeStartPoint = position;
      debugPrint('🔶🔶🔶 [_startStroke] Saved shape start point: $_shapeStartPoint');
    } else {
      _shapeStartPoint = null;
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
    // 如果是激光笔，初始化点间延迟记录与计时器（参考 Saber 的实现）
    if (stroke.toolId == ToolId.laserPointer) {
      _laserStrokePointDelays[stroke] = <Duration>[Duration.zero];
      _laserStrokeStopwatches[stroke] = Stopwatch()..reset()..start();
    }
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
    
    // 删除相交的笔迹（使用notifier避免全量重建）
    if (strokesToRemove.isNotEmpty) {
      // ✅ 记录擦除操作到历史记录
      _history.recordChange(EditorHistoryItem.erase(
        pageIndex: targetPageIndex,
        deletedStrokes: List<Stroke>.from(strokesToRemove),
      ));
      _updateUndoRedoState();
      
      final pageNotifier = _pageNotifiers[targetPageIndex];
      pageNotifier.removeStrokes(strokesToRemove);
      // 重要：同步更新核心数据结构 _coreInfo.pages，确保持久化与后续的页面重建使用一致的数据源。
      // 否则在后续的工具切换（例如切换到选择工具时会使用 _coreInfo.pages 来更新页面）
      // 会把已擦除的笔迹恢复回来（因为 _coreInfo.pages 仍然包含旧笔迹）。
      try {
        _coreInfo.pages[targetPageIndex] = pageNotifier.page;
      } catch (e) {
        // 保底日志，避免抛出异常影响 UI
        debugPrint('🦋[HandwritingSaber] Warning: failed to sync _coreInfo.pages[$targetPageIndex]: $e');
      }
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
    
    // ✅ 关键修复：使用原始points而不是转换后的points
    // 对于形状工具，我们需要保存原始的起始点和当前点，而不是让它变成RectangleStroke的5个角点
    // 所以使用一个临时数组来保存原始的2个点
    List<Offset> originalPoints;
    
    final toolId = _currentToolNotifier.value.toolId;
    if (toolId == ToolId.triangle) {
      // ✅ 三角形工具：一笔绘制，像自由多边形一样添加点
      stroke.points.add(position);
      originalPoints = List<Offset>.from(stroke.points);
      // 如果是激光笔，记录点间时间
      if (stroke.toolId == ToolId.laserPointer && _laserStrokeStopwatches.containsKey(stroke)) {
        final sw = _laserStrokeStopwatches[stroke]!;
        final elapsed = sw.elapsed;
        _laserStrokePointDelays[stroke]?.add(elapsed);
        sw.reset();
      }
    } else if (toolId == ToolId.line ||
        toolId == ToolId.arrowLine ||
        toolId == ToolId.rectangle || 
        toolId == ToolId.circle || 
        toolId == ToolId.diamond) {
      // ✅ 关键修复：形状工具始终只保持2个点（起始点和当前点）
      // 不要让points数组变成转换后的角点数组
      if (stroke.points.isEmpty) {
        originalPoints = [position];
        debugPrint('🔶🔶🔶 [_updateStroke] First point: $position');
      } else if (stroke.points.length == 1) {
        originalPoints = [stroke.points.first, position];
        debugPrint('🔶🔶🔶 [_updateStroke] Second point: $position, start=${stroke.points.first}');
      } else {
        // 已经有2个点，更新第二个点
        originalPoints = [stroke.points.first, position];
        debugPrint('🔶🔶🔶 [_updateStroke] Updated end: $position, start=${stroke.points.first}');
      }
    } else if (toolId == ToolId.freePolygon) {
      // ✅ 自由多边形：添加点
      stroke.points.add(position);
      originalPoints = List<Offset>.from(stroke.points);
    } else {
      // 其他工具：正常添加点
      stroke.points.add(position);
      originalPoints = List<Offset>.from(stroke.points);
      // 如果是激光笔，记录点间时间
      if (stroke.toolId == ToolId.laserPointer && _laserStrokeStopwatches.containsKey(stroke)) {
        final sw = _laserStrokeStopwatches[stroke]!;
        final elapsed = sw.elapsed;
        _laserStrokePointDelays[stroke]?.add(elapsed);
        sw.reset();
      }
    }
    
    // ✅ 关键修复：对于形状工具，使用保存的起始点
    if (toolId == ToolId.line ||
        toolId == ToolId.arrowLine ||
        toolId == ToolId.rectangle || 
        toolId == ToolId.circle || 
        toolId == ToolId.diamond) {
      // 使用保存的起始点，如果没有则从stroke中提取
      Offset startPoint = _shapeStartPoint ?? (stroke.points.isNotEmpty ? stroke.points.first : position);
      originalPoints = [startPoint, position];
      debugPrint('🔶🔶🔶 [_updateStroke] Shape tool: start=$startPoint (saved=${_shapeStartPoint != null}), end=$position');
    }
    
    // 为确保 CustomPainter 能检测到变化，替换成新的 Stroke 实例（改变对象引用）
    final Stroke oldStrokeRef = stroke;
    Stroke newStroke;
    
    // ✅ 根据工具类型创建对应的 Stroke 对象，使用originalPoints
    if (toolId == ToolId.line) {
      // 直线工具：创建 LineStroke 用于实时预览
      if (originalPoints.length >= 2) {
        newStroke = LineStroke(
          startPoint: originalPoints.first,
          endPoint: originalPoints.last,
          color: stroke.color,
          strokeWidth: stroke.strokeWidth,
          toolId: toolId,
          dashStyle: _dashStyleNotifier.value,
        );
      } else {
        newStroke = Stroke(
          points: originalPoints,
          color: stroke.color,
          strokeWidth: stroke.strokeWidth,
          toolId: stroke.toolId,
          pressureEnabled: stroke.pressureEnabled,
        );
      }
    } else if (toolId == ToolId.arrowLine) {
      // 箭头直线工具：创建 ArrowLineStroke 用于实时预览
      if (originalPoints.length >= 2) {
        newStroke = ArrowLineStroke(
          startPoint: originalPoints.first,
          endPoint: originalPoints.last,
          color: stroke.color,
          strokeWidth: stroke.strokeWidth,
          toolId: toolId,
          dashStyle: _dashStyleNotifier.value,
          arrowStyle: _arrowStyleNotifier.value,
        );
      } else {
        newStroke = Stroke(
          points: originalPoints,
          color: stroke.color,
          strokeWidth: stroke.strokeWidth,
          toolId: stroke.toolId,
          pressureEnabled: stroke.pressureEnabled,
        );
      }
    } else if (toolId == ToolId.rectangle) {
      // 矩形工具：创建 RectangleStroke 用于实时预览
      if (originalPoints.length >= 2) {
        debugPrint('🔷🔷🔷 [_updateStroke] Creating RectangleStroke: start=${originalPoints.first}, end=${originalPoints.last}');
        newStroke = RectangleStroke(
          startPoint: originalPoints.first,
          endPoint: originalPoints.last,
          color: stroke.color,
          strokeWidth: stroke.strokeWidth,
          toolId: toolId,
          fillColor: _currentFillColorNotifier.value,
          dashStyle: _dashStyleNotifier.value, // ✅ 使用全局虚线样式
        );
        if (newStroke is RectangleStroke) {
          debugPrint('🔷🔷🔷 [_updateStroke] RectangleStroke created: rect=${newStroke.rect}, isEmpty=${newStroke.rect.isEmpty}');
        }
      } else {
        newStroke = Stroke(
          points: originalPoints,
          color: stroke.color,
          strokeWidth: stroke.strokeWidth,
          toolId: stroke.toolId,
          pressureEnabled: stroke.pressureEnabled,
        );
      }
    } else if (toolId == ToolId.circle) {
      // 圆形工具：创建 CircleStroke 用于实时预览
      if (originalPoints.length >= 2) {
        debugPrint('🔷🔷🔷 [_updateStroke] Creating CircleStroke: start=${originalPoints.first}, end=${originalPoints.last}');
        newStroke = CircleStroke(
          startPoint: originalPoints.first,
          endPoint: originalPoints.last,
          color: stroke.color,
          strokeWidth: stroke.strokeWidth,
          toolId: toolId,
          fillColor: _currentFillColorNotifier.value,
          dashStyle: _dashStyleNotifier.value, // ✅ 使用全局虚线样式
        );
      } else {
        newStroke = Stroke(
          points: originalPoints,
          color: stroke.color,
          strokeWidth: stroke.strokeWidth,
          toolId: stroke.toolId,
          pressureEnabled: stroke.pressureEnabled,
        );
      }
    } else if (toolId == ToolId.diamond) {
      // 菱形工具：创建 DiamondStroke 用于实时预览
      if (originalPoints.length >= 2) {
        debugPrint('🔷🔷🔷 [_updateStroke] Creating DiamondStroke: start=${originalPoints.first}, end=${originalPoints.last}');
        newStroke = DiamondStroke(
          startPoint: originalPoints.first,
          endPoint: originalPoints.last,
          color: stroke.color,
          strokeWidth: stroke.strokeWidth,
          toolId: toolId,
          fillColor: _currentFillColorNotifier.value,
          dashStyle: _dashStyleNotifier.value, // ✅ 使用全局虚线样式
        );
      } else {
        newStroke = Stroke(
          points: originalPoints,
          color: stroke.color,
          strokeWidth: stroke.strokeWidth,
          toolId: stroke.toolId,
          pressureEnabled: stroke.pressureEnabled,
        );
      }
    } else if (toolId == ToolId.triangle) {
      // 三角形工具：创建 TriangleStroke 用于实时预览
      if (originalPoints.length >= 2) {
        final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
        newStroke = TriangleStroke(
          points: originalPoints,
          color: stroke.color,
          strokeWidth: stroke.strokeWidth,
          toolId: toolId,
          isShiftPressed: isShiftPressed,
          fillColor: _currentFillColorNotifier.value,
          dashStyle: _dashStyleNotifier.value, // ✅ 使用全局虚线样式
        );
      } else {
        newStroke = Stroke(
          points: originalPoints,
          color: stroke.color,
          strokeWidth: stroke.strokeWidth,
          toolId: stroke.toolId,
          pressureEnabled: stroke.pressureEnabled,
        );
      }
    } else if (toolId == ToolId.freePolygon) {
      // 自由多边形工具：创建 FreePolygonStroke 用于实时预览
      if (originalPoints.length >= 2) {
        newStroke = FreePolygonStroke(
          points: originalPoints,
          color: stroke.color,
          strokeWidth: stroke.strokeWidth,
          toolId: toolId,
        );
      } else {
        newStroke = Stroke(
          points: originalPoints,
          color: stroke.color,
          strokeWidth: stroke.strokeWidth,
          toolId: stroke.toolId,
          pressureEnabled: stroke.pressureEnabled,
        );
      }
    } else {
      // 其他工具：普通笔迹
      newStroke = Stroke(
        points: originalPoints,
        color: stroke.color,
        strokeWidth: stroke.strokeWidth,
        toolId: stroke.toolId,
        pressureEnabled: stroke.pressureEnabled,
      );
    }
    
    _currentStrokeNotifier.value = newStroke;
    // 如果之前为激光笔记录了点间延迟或计时器，需要把这些临时记录从旧实例移动到新实例
    try {
      if (_laserStrokePointDelays.containsKey(oldStrokeRef)) {
        _laserStrokePointDelays[newStroke] = _laserStrokePointDelays.remove(oldStrokeRef)!;
      }
      if (_laserStrokeStopwatches.containsKey(oldStrokeRef)) {
        _laserStrokeStopwatches[newStroke] = _laserStrokeStopwatches.remove(oldStrokeRef)!;
      }
    } catch (_) {
      // 忽略意外情况，保持原有行为
    }
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
        // 只通知受影响页面的 notifier，避免触发父级全量重建导致 PDF 闪烁
        final int targetPageIndex = _selectResult!.pageIndex;
        if (targetPageIndex < _pageNotifiers.length) {
          _pageNotifiers[targetPageIndex].updatePage(_coreInfo.pages[targetPageIndex]);
        }
        // 使用防抖保存，避免频繁磁盘写入导致 UI 卡顿
        _scheduleSave();
      }
      return;
    }
    
    // ✅ 更新选择路径（拖拽选择区域）
    if (_isSelecting) {
        // 仅通知当前页面以触发局部重建（selectionPath 改变会在 SaberCoreCanvas 中生效）
        _selectResult!.selectionPath.lineTo(position.dx, position.dy);
        final int targetPageIndex = _selectResult!.pageIndex;
        if (targetPageIndex < _pageNotifiers.length) {
          _pageNotifiers[targetPageIndex].updatePage(_coreInfo.pages[targetPageIndex]);
        }
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
        // ✅ 选择区域太小，取消选择（只通知受影响页面）
        final int? prevPageIndex = _selectResult?.pageIndex;
        _selectResult = null;
        _isSelecting = false;
        _selectStartPosition = null;
        if (prevPageIndex != null && prevPageIndex < _pageNotifiers.length) {
          _pageNotifiers[prevPageIndex].updatePage(_coreInfo.pages[prevPageIndex]);
        }
        return;
      }
        final int targetPageIndex = _selectResult!.pageIndex;
        _isSelecting = false;
        if (targetPageIndex < _pageNotifiers.length) {
          _pageNotifiers[targetPageIndex].updatePage(_coreInfo.pages[targetPageIndex]);
        }
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
    debugPrint('🦋[HandwritingSaber] _createTextBox called: position=$position, pageIndex=$pageIndex');
    final pageIdx = pageIndex ?? 0;
    if (pageIdx < 0 || pageIdx >= _coreInfo.pages.length) {
      debugPrint('🦋[HandwritingSaber] _createTextBox: invalid pageIdx=$pageIdx, pages.length=${_coreInfo.pages.length}');
      return;
    }
    
    final page = _coreInfo.pages[pageIdx];
    debugPrint('🦋[HandwritingSaber] _createTextBox: page.textBoxes.length=${page.textBoxes.length}');
    
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
      id: 'textbox_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(1000)}',
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
    
    // ✅ 添加到页面并进入编辑模式（使用EditorPageNotifier避免全局setState）
    debugPrint('🦋[HandwritingSaber] _createTextBox: adding textBox id=${textBox.id} to page, position=${textBox.position}, size=${textBox.size}');
    
    // ✅ 更新页面数据（使用EditorPageNotifier，只触发该页面的局部重建）
    final updatedPage = EditorPage(
      size: page.size,
      strokes: page.strokes,
      backgroundImage: page.backgroundImage,
      textBoxes: List<saber_text.TextBox>.from(page.textBoxes)..add(textBox),
      listBoxes: page.listBoxes,
      taskListBoxes: page.taskListBoxes,
    );
    
    // ✅ 更新coreInfo中的页面数据
    final updatedPages = List<EditorPage>.from(_coreInfo.pages);
    updatedPages[pageIdx] = updatedPage;
    _coreInfo = EditorCoreInfo(
      pages: updatedPages,
      backgroundColor: _coreInfo.backgroundColor,
      backgroundPattern: _coreInfo.backgroundPattern,
      lineHeight: _coreInfo.lineHeight,
      lineThickness: _coreInfo.lineThickness,
    );
    
    // ✅ 使用EditorPageNotifier更新页面（只触发该页面的局部重建，不影响PDF）
    if (pageIdx < _pageNotifiers.length) {
      _pageNotifiers[pageIdx].updatePage(updatedPage);
    }
    
    // ✅ 使用ValueNotifier更新编辑状态（不触发全局setState）
    _editingTextBoxIdNotifier.value = textBox.id;
    debugPrint('🦋[HandwritingSaber] _createTextBox: completed, _editingTextBoxId=${_editingTextBoxIdNotifier.value}, page.textBoxes.length=${updatedPage.textBoxes.length}');
    
    // ✅ 监听文本变化（仅更新模型并使用防抖保存，避免频繁 setState）
    controller.addListener(() {
      if (_editingTextBoxIdNotifier.value == textBox.id) {
        textBox.text = controller.text;
        // ✅ 更新页面数据（使用EditorPageNotifier，只触发画布重绘，不影响PDF）
        if (pageIdx < _pageNotifiers.length) {
          final currentPage = _coreInfo.pages[pageIdx];
          final updatedPageForText = EditorPage(
            size: currentPage.size,
            strokes: currentPage.strokes,
            backgroundImage: currentPage.backgroundImage,
            textBoxes: currentPage.textBoxes,
            listBoxes: currentPage.listBoxes,
            taskListBoxes: currentPage.taskListBoxes,
          );
          _pageNotifiers[pageIdx].updatePage(updatedPageForText);
        }
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
    // ✅ 查找文本框所在的页面索引
    int? pageIndex;
    for (int i = 0; i < _coreInfo.pages.length; i++) {
      if (_coreInfo.pages[i].textBoxes.contains(textBox)) {
        pageIndex = i;
        break;
      }
    }
    if (pageIndex == null) {
      debugPrint('🦋[HandwritingSaber] _editTextBox: textBox not found in any page');
      return;
    }
    
    // ✅ 保存页面索引为final变量，避免闭包中的null检查问题
    final finalPageIndex = pageIndex;
    
    // ✅ 创建或获取文本编辑控制器
    if (!_textBoxControllers.containsKey(textBox.id)) {
      final controller = TextEditingController(text: textBox.text);
      _textBoxControllers[textBox.id] = controller;
      
      // ✅ 监听文本变化（仅更新模型并使用防抖保存，避免频繁 setState）
      controller.addListener(() {
        if (_editingTextBoxIdNotifier.value == textBox.id) {
          textBox.text = controller.text;
          // ✅ 更新页面数据（使用EditorPageNotifier，只触发画布重绘，不影响PDF）
          if (finalPageIndex < _pageNotifiers.length) {
            final currentPage = _coreInfo.pages[finalPageIndex];
            final updatedPage = EditorPage(
              size: currentPage.size,
              strokes: currentPage.strokes,
              backgroundImage: currentPage.backgroundImage,
              textBoxes: currentPage.textBoxes,
              listBoxes: currentPage.listBoxes,
              taskListBoxes: currentPage.taskListBoxes,
            );
            _pageNotifiers[finalPageIndex].updatePage(updatedPage);
          }
          _scheduleSave();
        }
      });
    } else {
      // ✅ 更新控制器文本
      _textBoxControllers[textBox.id]!.text = textBox.text;
    }
    
    // ✅ 进入编辑模式（使用ValueNotifier，不触发全局setState）
    _editingTextBoxIdNotifier.value = textBox.id;
  }
  
  /// ✅ 结束文本框编辑（使用ValueNotifier，不触发全局setState）
  void _endTextBoxEditing() {
    _editingTextBoxIdNotifier.value = null;
  }
  
  /// ✅ 构建文本框编辑器（直接在画布上显示）
  Widget _buildTextBoxEditor(
    saber_text.TextBox textBox,
    int pageIndex,
    double screenWidth,
    double pageDisplayWidth,
    double pageDisplayHeight,
  ) {
    debugPrint('🦋[HandwritingSaber] _buildTextBoxEditor called: textBox.id=${textBox.id}, pageIndex=$pageIndex');
    debugPrint('🦋[HandwritingSaber] _buildTextBoxEditor: screenWidth=$screenWidth, pageDisplayWidth=$pageDisplayWidth, pageDisplayHeight=$pageDisplayHeight');
    
    // ✅ 计算页面缩放和偏移（与 _buildSinglePageCanvas 保持一致）
    final page = _coreInfo.pages[pageIndex];
    
    // ✅ 防止无效的页面尺寸
    if (page.size.width <= 0 || page.size.height <= 0) {
      debugPrint('❌[HandwritingSaber] _buildTextBoxEditor: Invalid page size: ${page.size}');
      return const SizedBox.shrink();
    }
    
    final double scale = pageDisplayWidth / page.size.width;
    // ✅ 检查scale有效性
    if (!scale.isFinite || scale <= 0) {
      debugPrint('❌[HandwritingSaber] _buildTextBoxEditor: Invalid scale: $scale');
      return const SizedBox.shrink();
    }
    
    // 注意：offsetX 和 offsetY 应该与 _buildSinglePageCanvas 中的计算一致
    final double offsetX = (screenWidth - pageDisplayWidth) / 2;
    final double offsetY = 0;  // 页面顶部对齐，与 _buildSinglePageCanvas 一致
    debugPrint('🦋[HandwritingSaber] _buildTextBoxEditor: page.size=${page.size}, scale=$scale, offsetX=$offsetX, offsetY=$offsetY');
    
    // ✅ 计算文本框在屏幕上的位置
    final double textBoxLeft = offsetX + textBox.position.dx * scale;
    final double textBoxTop = offsetY + textBox.position.dy * scale;
    final double textBoxWidth = textBox.size.width * scale;
    final double textBoxHeight = textBox.size.height * scale;
    debugPrint('🦋[HandwritingSaber] _buildTextBoxEditor: textBoxLeft=$textBoxLeft, textBoxTop=$textBoxTop, textBoxWidth=$textBoxWidth, textBoxHeight=$textBoxHeight');
    
    // ✅ 获取或创建文本控制器
    if (!_textBoxControllers.containsKey(textBox.id)) {
      final controller = TextEditingController(text: textBox.text);
      _textBoxControllers[textBox.id] = controller;
      
      // ✅ 监听文本变化（仅更新模型并使用防抖保存，避免频繁 setState）
      controller.addListener(() {
        if (_editingTextBoxIdNotifier.value == textBox.id) {
          textBox.text = controller.text;
          // ✅ 更新页面数据（使用EditorPageNotifier，只触发画布重绘，不影响PDF）
          if (pageIndex < _pageNotifiers.length) {
            final currentPage = _coreInfo.pages[pageIndex];
            final updatedPage = EditorPage(
              size: currentPage.size,
              strokes: currentPage.strokes,
              backgroundImage: currentPage.backgroundImage,
              textBoxes: currentPage.textBoxes,
              listBoxes: currentPage.listBoxes,
              taskListBoxes: currentPage.taskListBoxes,
            );
            _pageNotifiers[pageIndex].updatePage(updatedPage);
          }
          _scheduleSave();
        }
      });
    }
    
    final controller = _textBoxControllers[textBox.id]!;
    
    // ✅ 计算缩放后的字体大小，确保最小为 12
    final double baseFontSize = textBox.textStyle?.fontSize ?? 16;
    final double scaledFontSize = (baseFontSize * scale).clamp(12.0, 72.0);
    
    // ✅ 确保文本框有最小尺寸以便正常显示和输入
    final double minWidth = 150.0;
    final double minHeight = 50.0;
    final double finalWidth = textBoxWidth < minWidth ? minWidth : textBoxWidth;
    final double finalHeight = textBoxHeight < minHeight ? minHeight : textBoxHeight;
    
    debugPrint('🦋[HandwritingSaber] _buildTextBoxEditor: scaledFontSize=$scaledFontSize, finalWidth=$finalWidth, finalHeight=$finalHeight');
    
    return Positioned(
      left: textBoxLeft,
      top: textBoxTop,
      width: finalWidth,
      height: finalHeight,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            border: Border.all(color: Colors.blue, width: 2),
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            autofocus: true,
            controller: controller,
            // ✅ 当 expands: true 时，maxLines 和 minLines 必须为 null
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: TextStyle(
              fontSize: scaledFontSize,
              color: textBox.textStyle?.color ?? Colors.black,
              fontWeight: textBox.textStyle?.fontWeight,
              fontStyle: textBox.textStyle?.fontStyle,
            ),
            decoration: InputDecoration(
              hintText: '输入文本...',
              hintStyle: TextStyle(
                fontSize: scaledFontSize,
                color: Colors.grey.withValues(alpha: 0.5),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(8),
            ),
            onSubmitted: (_) {
              _endTextBoxEditing();
            },
            onTapOutside: (_) {
              _endTextBoxEditing();
            },
          ),
        ),
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
    debugPrint('✍️✍️✍️ [HandwritingSaber] ===== _endStroke START =====');
    
    // ✅ 如果是选择工具，结束选择
    if (_currentToolNotifier.value.toolId == ToolId.select) {
      _endSelection();
      return;
    }
    
    final Stroke? stroke = _currentStrokeNotifier.value;
    debugPrint('✍️✍️✍️ [HandwritingSaber] Current stroke: ${stroke != null ? "exists, points=${stroke.points.length}" : "null"}');
    if (stroke == null || stroke.points.isEmpty) {
      _currentPageIndex = null;
      debugPrint('✍️✍️✍️ [HandwritingSaber] No valid stroke, returning');
      return;
    }
    
    debugPrint('✍️✍️✍️ [HandwritingSaber] _coreInfo.pages.length: ${_coreInfo.pages.length}');
    if (_coreInfo.pages.isEmpty) {
      debugPrint('⚠️⚠️⚠️ [HandwritingSaber] Pages empty, creating default');
      _coreInfo = EditorCoreInfo.empty();
    }
    
    // ✅ 确保页面索引有效
    final int targetPageIndex = _currentPageIndex ?? 0;
    debugPrint('✍️✍️✍️ [HandwritingSaber] Target pageIndex: $targetPageIndex, total pages: ${_coreInfo.pages.length}');
    if (targetPageIndex >= _coreInfo.pages.length) {
      debugPrint('❌❌❌ [HandwritingSaber] INVALID PAGE INDEX! pageIndex=$targetPageIndex >= pages.length=${_coreInfo.pages.length}');
      debugPrint('❌❌❌ [HandwritingSaber] Stroke LOST! Tool: ${stroke.toolId}, Points: ${stroke.points.length}');
      _currentPageIndex = null;
      return;
    }
    
    debugPrint('✍️✍️✍️ [HandwritingSaber] Valid page index, using current stroke as final stroke');
    debugPrint('✍️✍️✍️ [HandwritingSaber] Stroke type: ${stroke.runtimeType}, toolId: ${stroke.toolId}, points: ${stroke.points.length}');
    
    // ✅ 关键修复：_updateStroke 中已经创建了正确类型的Stroke对象，直接使用即可！
    // 不要重新创建，否则会从已转换的points数组中提取错误的点
    final toolId = stroke.toolId;
    Stroke? finalStroke;
    
    if (toolId == ToolId.laserPointer) {
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
      // 从记录的点延迟中获取用于淡出的 timing（参考 Saber）
      final recordedDelays = _laserStrokePointDelays[stroke];
      // 清理临时记录（不再需要）
      _laserStrokePointDelays.remove(stroke);
      final sw = _laserStrokeStopwatches.remove(stroke);
      if (sw != null) {
        try {
          sw.stop();
        } catch (_) {}
      }
      // ✅ 启动激光笔淡出动画（不使用 setState，使用 notifier 驱动局部重绘）
      _startLaserFadeOut(laserStroke, strokePointDelays: recordedDelays);
      // 使用 notifier 清空当前笔迹（避免触发整页重建）
      _currentStrokeNotifier.value = null;
      return;
    } else {
      // ✅ 其他工具：直接使用当前stroke
      // _updateStroke中已经创建了正确类型的对象，不需要重新创建
      finalStroke = stroke;
      debugPrint('✍️✍️✍️ [HandwritingSaber] Using stroke directly: type=${stroke.runtimeType}');
    }
    
    // ✅ 保存完成的笔迹到正确的页面
    if (finalStroke != null) {
      debugPrint('💾💾💾 [HandwritingSaber] Saving stroke to page $targetPageIndex, toolId=${finalStroke.toolId}, points=${finalStroke.points.length}');
      _coreInfo.pages[targetPageIndex].strokes.add(finalStroke);
      debugPrint('💾💾💾 [HandwritingSaber] Page $targetPageIndex now has ${_coreInfo.pages[targetPageIndex].strokes.length} strokes');
      
      // ✅ 记录绘制操作到历史记录
      _history.recordChange(EditorHistoryItem.draw(
        pageIndex: targetPageIndex,
        strokes: [finalStroke],
      ));
      _updateUndoRedoState();
      
      // ✅ 通知页面notifier更新（关键！触发该页面的重绘）
      if (targetPageIndex < _pageNotifiers.length) {
        // 使用updatePage方法而不是直接调用notifyListeners
        final currentPage = _coreInfo.pages[targetPageIndex];
        _pageNotifiers[targetPageIndex].updatePage(currentPage);
        debugPrint('💾💾💾 [HandwritingSaber] Page notifier $targetPageIndex updated');
      }
    } else {
      debugPrint('⚠️⚠️⚠️ [HandwritingSaber] finalStroke is null! Tool: ${stroke.toolId}');
    }
    
    // 清空 notifier 值，触发 CustomPainter 的局部重绘
    _currentStrokeNotifier.value = null;
    // 不触发父级重建，仅重置页面索引
    _currentPageIndex = null;
    // ✅ 清除形状工具的起始点
    _shapeStartPoint = null;
    debugPrint('✍️✍️✍️ [HandwritingSaber] ===== _endStroke END =====');
    
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
  
  /// ✅ 更新撤销/恢复按钮状态
  void _updateUndoRedoState() {
    _canUndoNotifier.value = _history.canUndo;
    _canRedoNotifier.value = _history.canRedo;
  }
  
  /// ✅ 撤销操作
  void _undo() {
    if (!_history.canUndo) return;
    
    final item = _history.undo();
    _updateUndoRedoState();
    
    // 根据操作类型执行撤销
    switch (item.type) {
      case EditorHistoryItemType.draw:
        // 撤销绘制：删除笔迹
        for (final stroke in item.strokes) {
          final page = _coreInfo.pages[item.pageIndex];
          page.strokes.remove(stroke);
        }
        // 更新页面 notifier
        if (item.pageIndex < _pageNotifiers.length) {
          _pageNotifiers[item.pageIndex].updatePage(_coreInfo.pages[item.pageIndex]);
        }
        break;
      case EditorHistoryItemType.erase:
        // 撤销擦除：恢复笔迹
        if (item.deletedStrokes != null) {
          for (final stroke in item.deletedStrokes!) {
            final page = _coreInfo.pages[item.pageIndex];
            page.strokes.add(stroke);
          }
          // 更新页面 notifier
          if (item.pageIndex < _pageNotifiers.length) {
            _pageNotifiers[item.pageIndex].updatePage(_coreInfo.pages[item.pageIndex]);
          }
        }
        break;
      default:
        break;
    }
    
    _scheduleSave();
  }
  
  /// ✅ 恢复操作
  void _redo() {
    if (!_history.canRedo) return;
    
    final item = _history.redo();
    _updateUndoRedoState();
    
    // 根据操作类型执行恢复
    switch (item.type) {
      case EditorHistoryItemType.draw:
        // 恢复绘制：添加笔迹
        for (final stroke in item.strokes) {
          final page = _coreInfo.pages[item.pageIndex];
          page.strokes.add(stroke);
        }
        // 更新页面 notifier
        if (item.pageIndex < _pageNotifiers.length) {
          _pageNotifiers[item.pageIndex].updatePage(_coreInfo.pages[item.pageIndex]);
        }
        break;
      case EditorHistoryItemType.erase:
        // 恢复擦除：删除笔迹
        if (item.deletedStrokes != null) {
          for (final stroke in item.deletedStrokes!) {
            final page = _coreInfo.pages[item.pageIndex];
            page.strokes.remove(stroke);
          }
          // 更新页面 notifier
          if (item.pageIndex < _pageNotifiers.length) {
            _pageNotifiers[item.pageIndex].updatePage(_coreInfo.pages[item.pageIndex]);
          }
        }
        break;
      default:
        break;
    }
    
    _scheduleSave();
  }

  void _onToolChanged(Tool tool) {
    debugPrint('🦋[HandwritingSaber] _onToolChanged: ${tool.toolId}');
    
    // ✅ 如果是文本框工具，打印日志确认
    if (tool.toolId == ToolId.textBox ||
        tool.toolId == ToolId.heading1 ||
        tool.toolId == ToolId.heading2 ||
        tool.toolId == ToolId.heading3 ||
        tool.toolId == ToolId.paragraph) {
      debugPrint('🦋[HandwritingSaber] _onToolChanged: 切换到文本工具: ${tool.toolId}');
    }
    
    // ✅ 切换工具：避免使用 setState 导致全量重建，改为仅通知受影响的页面 notifier
    if (tool.toolId == ToolId.select) {
      debugPrint('🦋[HandwritingSaber] Switching to select tool, clearing selection');
      // 记录之前选择所在页面，之后仅刷新该页面的 notifier
      final int? prevPageIndex = _selectResult?.pageIndex;
      _selectResult = null;
      _isSelecting = false;
      _selectStartPosition = null;
      if (prevPageIndex != null && prevPageIndex < _pageNotifiers.length) {
        // 触发该页面局部重建以反映选择清除
        _pageNotifiers[prevPageIndex].updatePage(_coreInfo.pages[prevPageIndex]);
      }
      // 更新当前工具（通过 notifier，不触发父级重建）
      _currentToolNotifier.value = tool;
    } else {
      // ✅ 切换到其他工具时，也清除选择状态（但只通知受影响页面）
      if (_currentToolNotifier.value.toolId == ToolId.select) {
        debugPrint('🦋[HandwritingSaber] Switching away from select tool, clearing selection');
        final int? prevPageIndex = _selectResult?.pageIndex;
        _selectResult = null;
        _isSelecting = false;
        _selectStartPosition = null;
        if (prevPageIndex != null && prevPageIndex < _pageNotifiers.length) {
          _pageNotifiers[prevPageIndex].updatePage(_coreInfo.pages[prevPageIndex]);
        }
      }
      // 更新当前工具（通过 notifier，不触发父级重建）
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
    // 更新全局颜色，保持切换工具时颜色不丢失
    _globalColorNotifier.value = color;
    // 如果当前工具是笔类（包括形状工具也使用 Pen 表示），同时更新当前工具的颜色以便立即生效
    if (_currentToolNotifier.value is Pen) {
      final updated = (_currentToolNotifier.value as Pen).copyWith(color: color);
      _currentToolNotifier.value = updated;
    }
  }

  /// ✅ 填充颜色改变回调
  void _onFillColorChanged(Color? fillColor) {
    // 仅更新 notifier 的值，避免触发父级整页重建导致 PDF 重绘闪烁
    _currentFillColorNotifier.value = fillColor;
  }

  void _onStrokeWidthChanged(double width) {
    // 更新全局线宽，保持切换工具时线宽不丢失
    _globalStrokeWidthNotifier.value = width;
    // 同步更新当前工具以便立刻生效
    if (_currentToolNotifier.value is Pen) {
      _currentToolNotifier.value = (_currentToolNotifier.value as Pen).copyWith(strokeWidth: width);
    } else if (_currentToolNotifier.value is Eraser) {
      _currentToolNotifier.value = Eraser(strokeWidth: width);
    }
  }

  /// ✅ 虚线样式改变回调
  void _onDashStyleChanged(DashStyle style) {
    debugPrint('🎨 [HandwritingSaber] Dash style changed to: $style');
    // 更新全局虚线样式，所有形状工具都将使用此样式
    _dashStyleNotifier.value = style;
  }

  /// ✅ 箭头样式改变回调
  void _onArrowStyleChanged(ArrowStyle style) {
    debugPrint('🎨 [HandwritingSaber] Arrow style changed to: $style');
    // 更新全局箭头样式，箭头直线工具将使用此样式
    _arrowStyleNotifier.value = style;
  }
  
  /// ✅ 切换文本编辑模式
  void _toggleTextEditingMode() {
    debugPrint('📝 [HandwritingSaber] Toggling text editing mode: ${!_textEditingModeNotifier.value}');
    _textEditingModeNotifier.value = !_textEditingModeNotifier.value;
    
    // 如果进入文本编辑模式，将焦点设置到第一个页面
    if (_textEditingModeNotifier.value && _coreInfo.pages.isNotEmpty) {
      _quillFocusPageIndexNotifier.value = 0;
      // 请求焦点
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_quillFocusPageIndexNotifier.value != null && 
            _quillFocusPageIndexNotifier.value! < _coreInfo.pages.length) {
          final page = _coreInfo.pages[_quillFocusPageIndexNotifier.value!];
          page.quill.focusNode.requestFocus();
        }
      });
    } else {
      // 退出文本编辑模式，取消焦点
      _quillFocusPageIndexNotifier.value = null;
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
    // ✅ 防止无效的页面尺寸导致渲染问题
    if (page.size.width <= 0 || page.size.height <= 0) {
      debugPrint('❌[HandwritingSaber] _buildSinglePageCanvas: Invalid page size: ${page.size}, pageIndex=$pageIndex');
      return Container(
        width: screenWidth,
        height: pageDisplayHeight,
        color: Colors.grey.withValues(alpha: 0.1),
        child: const Center(
          child: Text('页面尺寸无效，请重新创建'),
        ),
      );
    }
    
    // ✅ 计算页面坐标变换参数
    final double scale = pageDisplayWidth / page.size.width;
    final double offsetX = (screenWidth - pageDisplayWidth) / 2;
    final double offsetY = 0;  // 页面顶部对齐
    
    // ✅ 额外检查：确保scale有效
    if (!scale.isFinite || scale <= 0) {
      debugPrint('❌[HandwritingSaber] _buildSinglePageCanvas: Invalid scale: $scale, pageDisplayWidth=$pageDisplayWidth, page.size.width=${page.size.width}');
      return Container(
        width: screenWidth,
        height: pageDisplayHeight,
        color: Colors.grey.withValues(alpha: 0.1),
        child: const Center(
          child: Text('缩放计算错误'),
        ),
      );
    }
    
    // ✅ 将 localPosition 转换为页面坐标
    Offset toPageCoordinates(Offset localPosition) {
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
          if (_editingTextBoxIdNotifier.value != null) {
            final clickedTextBox = _findTextBoxAtPosition(pagePos, pageIndex);
            if (clickedTextBox == null || clickedTextBox.id != _editingTextBoxIdNotifier.value) {
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
                // debug: 输出当前页面与背景信息（使用受控日志，默认静默）
                Builder(builder: (context) {
                  LogUtils.debug('🦋[HandwritingSaber] _buildSinglePageCanvas: pageIndex=$pageIndex, page.backgroundImage=${page.backgroundImage != null}, coreInfo.backgroundPattern=${_coreInfo.backgroundPattern}, currentBackgroundPattern=$_currentBackgroundPattern, page.strokes=${page.strokes.length}');
                  return const SizedBox.shrink();
                }),
              // ✅ 文本框编辑层（直接在画布上编辑，使用ValueListenableBuilder避免全局重建）
              ValueListenableBuilder<String?>(
                valueListenable: _editingTextBoxIdNotifier,
                builder: (context, editingTextBoxId, _) {
                  if (editingTextBoxId != null) {
                    // ✅ 查找匹配的文本框，使用try-catch避免空列表访问错误
                    try {
                      final textBox = page.textBoxes.firstWhere(
                        (tb) => tb.id == editingTextBoxId,
                      );
                      return _buildTextBoxEditor(textBox, pageIndex, screenWidth, pageDisplayWidth, pageDisplayHeight);
                    } catch (e) {
                      // ✅ 如果找不到匹配的文本框（列表为空或没有匹配项），返回空widget
                      debugPrint('🦋[HandwritingSaber] _buildSinglePageCanvas: textBox not found for id=$editingTextBoxId, error=$e');
                      return const SizedBox.shrink();
                    }
                  }
                  return const SizedBox.shrink();
                },
              ),
              // ✅ Quill 富文本编辑层（只在文本编辑模式下显示）
              _buildQuillEditorLayer(page, pageIndex),
            ],
          ),
        ),
      ),
    );
  }
  
  /// ✅ 构建 Quill 富文本编辑层
  Widget _buildQuillEditorLayer(EditorPage page, int pageIndex) {
    return ValueListenableBuilder<bool>(
      valueListenable: _textEditingModeNotifier,
      builder: (context, textEditingMode, _) {
        return ValueListenableBuilder<int?>(
          valueListenable: _quillFocusPageIndexNotifier,
          builder: (context, quillFocusPageIndex, _) {
            // 只有在文本编辑模式且当前页面有焦点时才显示编辑器
            if (!textEditingMode || quillFocusPageIndex != pageIndex) {
              return const SizedBox.shrink();
            }
            
            final quillStruct = page.quill;
            final colorScheme = Theme.of(context).colorScheme;
            final invert = false; // 可以根据需要从设置中读取
            
            return IgnorePointer(
              ignoring: !textEditingMode,
              child: Container(
                color: Colors.white.withValues(alpha: textEditingMode ? 0.95 : 0),
                child: quill.QuillEditor.basic(
                  controller: quillStruct.controller,
                  config: quill.QuillEditorConfig(
                    customStyles: HandwritingSaberQuillStyles.get(
                      invert: invert,
                      secondary: colorScheme.secondary,
                      lineHeight: _coreInfo.lineHeight,
                    ),
                    scrollable: true,
                    autoFocus: true,
                    expands: false,
                    placeholder: '在此输入富文本...',
                    padding: EdgeInsets.only(
                      top: _coreInfo.lineHeight * 1.2,
                      left: _coreInfo.lineHeight * 0.5,
                      right: _coreInfo.lineHeight * 0.5,
                      bottom: _coreInfo.lineHeight * 0.5,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
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
  void _startLaserFadeOut(Stroke laserStroke, {List<Duration>? strokePointDelays}) {
    if (laserStroke.points.isEmpty) {
      return;
    }
    // 标记淡出进行中，抑制保存操作以避免 I/O 干扰渲染
    _isLaserFadeInProgress = true;
    
    // 如果外部传入了记录的点延迟，优先使用；否则回退到固定延迟模拟
    final List<Duration> delaysToUse;
    if (strokePointDelays != null && strokePointDelays.isNotEmpty) {
      delaysToUse = List<Duration>.from(strokePointDelays);
    } else {
      // 归一化为每点固定 50ms 的延迟（第一个点为 0）
      delaysToUse = <Duration>[];
      for (int i = 0; i < laserStroke.points.length; i++) {
        delaysToUse.add(i == 0 ? Duration.zero : const Duration(milliseconds: 50));
      }
    }

    // 打印用于诊断的延迟信息（临时调试）
    debugPrint('🦋[HandwritingSaber] _startLaserFadeOut: strokePoints=${laserStroke.points.length}, delays=${delaysToUse.map((d) => d.inMilliseconds).toList()}');

    // ✅ 启动淡出动画
    _fadeOutLaserStroke(
      stroke: laserStroke,
      strokePointDelays: delaysToUse,
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

    // 如果笔迹已被移除，直接返回
    if (!_laserStrokesNotifier.value.contains(stroke)) return;

    // 归一化每点延迟，避免零延迟导致瞬间消失（调大阈值以确保可见的淡出效果）
    final minDelay = Duration(milliseconds: 60);
    final normalizedDelays = <Duration>[];
    if (strokePointDelays.isEmpty) {
      // 如果没有记录到点间延迟，使用固定小延迟逐点淡出
      normalizedDelays.addAll(List.generate(stroke.points.length, (_) => minDelay));
    } else {
      for (final d in strokePointDelays) {
        if (d <= Duration.zero) {
          normalizedDelays.add(minDelay);
        } else if (d < minDelay) {
          normalizedDelays.add(minDelay);
        } else {
          normalizedDelays.add(d);
        }
      }
      // 如果记录的延迟少于点数，补齐最小延迟
      if (normalizedDelays.length < stroke.points.length) {
        final diff = stroke.points.length - normalizedDelays.length;
        normalizedDelays.addAll(List.generate(diff, (_) => minDelay));
      }
    }

    // 如果笔迹非常长或记录的延迟几乎全为零，使用基于透明度的淡出策略（更稳健且视觉更平滑）
    final int longStrokeThreshold = 120;
    final bool delaysMostlyZero = normalizedDelays.where((d) => d > minDelay).length < (normalizedDelays.length * 0.15);
    if (stroke.points.length > longStrokeThreshold || delaysMostlyZero) {
    debugPrint('🦋[HandwritingSaber] _fadeOutLaserStroke: using batch-removal fallback for strokePoints=${stroke.points.length}');
      // Batch removal strategy: 每个 tick 删除多个点以实现可见且平滑的淡出效果
      final int totalPoints = stroke.points.length;
      final int batchCount = math.max(1, totalPoints ~/ 15); // 每次删除的点数（对长笔迹增大以更平滑可见）
      final Duration stepDelay = const Duration(milliseconds: 120); // 每次删除间隔（放慢以便用户可见）

      final Timer timer = Timer.periodic(stepDelay, (t) async {
        // 如果笔迹已被外部移除或为空，结束定时器
        if (!_laserStrokesNotifier.value.contains(stroke) || stroke.points.isEmpty) {
          t.cancel();
          _laserFadeOutTimers.remove(stroke);
          _isLaserFadeInProgress = false;
          if (_pendingSave) {
            _pendingSave = false;
            await _saveToStorage(suppressStatusUpdate: true);
          }
          return;
        }

        // 删除 batchCount 个点
        for (int k = 0; k < batchCount; k++) {
          if (stroke.points.isEmpty) break;
          stroke.popFirstPoint();
        }
        // 通知绘制层更新
        _laserStrokesNotifier.value = List<Stroke>.from(_laserStrokesNotifier.value);

        // 如果已经删除完毕，终止定时器并移除笔迹
        if (stroke.points.isEmpty) {
          t.cancel();
          final int idx = _coreInfo.laserStrokes.indexOf(stroke);
          if (idx != -1) {
            _coreInfo.laserStrokes.removeAt(idx);
            _laserStrokesNotifier.value = List<Stroke>.from(_coreInfo.laserStrokes);
          }
          _laserFadeOutTimers.remove(stroke);
          _isLaserFadeInProgress = false;
          if (_pendingSave) {
            _pendingSave = false;
            await _saveToStorage(suppressStatusUpdate: true);
          }
        }
      });

      _laserFadeOutTimers[stroke] = timer;
      return;
    }

    // 逐点淡出（使用 notifier 驱动局部重绘）
    for (int i = 0; i < normalizedDelays.length; i++) {
      final delay = normalizedDelays[i];
      debugPrint('🦋[HandwritingSaber] _fadeOutLaserStroke: popIndex=$i delay=${delay.inMilliseconds}ms remainingPoints=${stroke.points.length}');
      await Future.delayed(delay);

      // 如果笔迹已被移除或点数不足，退出
      if (!_laserStrokesNotifier.value.contains(stroke) || stroke.points.isEmpty) break;

      // 删除第一个点并通知绘制层更新
      stroke.popFirstPoint();
      _laserStrokesNotifier.value = List<Stroke>.from(_laserStrokesNotifier.value);

      // 如果用户重新开始绘制（currentStroke 非空），暂停淡出并等待用户停止
      if (_currentStrokeNotifier.value != null) {
        const waitTime = Duration(milliseconds: 100);
        while (_currentStrokeNotifier.value != null) {
          await Future.delayed(waitTime);
        }
        // 等待一段时间再继续淡出，避免与刚结束的绘制冲突
        await Future.delayed(fadeOutDelay);
      }
    }

    // 最后删除整个笔迹并更新 notifier、持久化（抑制 UI 状态更新）
    _coreInfo.laserStrokes.remove(stroke);
    _laserStrokesNotifier.value = List<Stroke>.from(_laserStrokesNotifier.value)..remove(stroke);
    _laserFadeOutTimers.remove(stroke);
    _isLaserFadeInProgress = false;
    if (_pendingSave) {
      _pendingSave = false;
      await _saveToStorage(suppressStatusUpdate: true);
    } else {
      await _saveToStorage(suppressStatusUpdate: true);
    }
  }
  
  @override
  void dispose() {
    // ✅ 清理所有激光笔淡出定时器
    for (final timer in _laserFadeOutTimers.values) {
      timer.cancel();
    }
    _laserFadeOutTimers.clear();

    // 停止并清理激光笔绘制时使用的计时器与延迟记录
    for (final sw in _laserStrokeStopwatches.values) {
      try {
        sw.stop();
      } catch (_) {}
    }
    _laserStrokeStopwatches.clear();
    _laserStrokePointDelays.clear();

    // ✅ 清理PDF背景图片资源
    for (final page in _coreInfo.pages) {
      page.backgroundImage?.dispose();
    }

    // ✅ 清理页面notifier
    for (final notifier in _pageNotifiers) {
      notifier.dispose();
    }
    _pageNotifiers.clear();

    // ✅ 清理PDF文档缓存管理器
    PdfDocumentCacheManager().dispose();

    // ✅ 清理当前笔迹通知器
    _currentStrokeNotifier.dispose();
    _laserStrokesNotifier.dispose();
    _repaintTick.dispose();
    // ✅ 清理填充颜色 notifier
    _currentFillColorNotifier.dispose();
    // ✅ 清理全局颜色与线宽 notifier
    _globalColorNotifier.dispose();
    _globalStrokeWidthNotifier.dispose();
    
    // ✅ 清理撤销/恢复状态 notifier
    _canUndoNotifier.dispose();
    _canRedoNotifier.dispose();
    _dashStyleNotifier.dispose();
    _arrowStyleNotifier.dispose();
    _textEditingModeNotifier.dispose();
    _quillFocusPageIndexNotifier.dispose();

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
              return ValueListenableBuilder<Color?>(
                valueListenable: _currentFillColorNotifier,
                builder: (ctx, fillColor, _) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: _canUndoNotifier,
                    builder: (ctx, canUndo, _) {
                      return ValueListenableBuilder<bool>(
                        valueListenable: _canRedoNotifier,
                        builder: (ctx2, canRedo, _) {
                          return ValueListenableBuilder<bool>(
                            valueListenable: _textEditingModeNotifier,
                            builder: (ctx3, textEditingMode, _) {
                              return ValueListenableBuilder<int?>(
                                valueListenable: _quillFocusPageIndexNotifier,
                                builder: (ctx4, quillFocusPageIndex, _) {
                                  return HandwritingSaberToolbar(
                                    currentTool: currentTool,
                                    onToolChanged: _onToolChanged,
                                    currentBackgroundPattern: _currentBackgroundPattern,
                                    onBackgroundPatternChanged: _onBackgroundPatternChanged,
                                    // 使用全局颜色/线宽，确保切换工具时保持用户设置
                                    currentColor: _globalColorNotifier.value,
                                    onColorChanged: _onColorChanged,
                                    currentStrokeWidth: _globalStrokeWidthNotifier.value,
                                    onStrokeWidthChanged: _onStrokeWidthChanged,
                                    currentFillColor: fillColor, // ✅ 填充颜色（由 notifier 驱动）
                                    onFillColorChanged: _onFillColorChanged, // ✅ 填充颜色改变回调
                                    onImportPdf: _importPdf,  // ✅ PDF 导入回调
                                    canUndo: canUndo, // ✅ 撤销按钮状态
                                    canRedo: canRedo, // ✅ 恢复按钮状态
                                    onUndo: _undo, // ✅ 撤销回调
                                    onRedo: _redo, // ✅ 恢复回调
                                    currentDashStyle: _dashStyleNotifier.value, // ✅ 当前虚线样式
                                    onDashStyleChanged: _onDashStyleChanged, // ✅ 虚线样式改变回调
                                    currentArrowStyle: _arrowStyleNotifier.value, // ✅ 当前箭头样式
                                    onArrowStyleChanged: _onArrowStyleChanged, // ✅ 箭头样式改变回调
                                    textEditingMode: textEditingMode, // ✅ 文本编辑模式标志
                                    onToggleTextEditingMode: _toggleTextEditingMode, // ✅ 切换文本编辑模式回调
                                    quillFocus: quillFocusPageIndex != null && 
                                        quillFocusPageIndex < _coreInfo.pages.length
                                        ? _coreInfo.pages[quillFocusPageIndex].quill
                                        : null, // ✅ 当前焦点的 Quill 结构
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
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
                
                debugPrint('🖼️🖼️🖼️ [HandwritingSaber] Building ${_coreInfo.pages.length} pages for view: ${widget.view.name}');
                
                for (int pageIndex = 0; pageIndex < _coreInfo.pages.length; pageIndex++) {
                  // 确保 page notifier 已初始化，避免 index out of range 导致 RangeError
                  if (_pageNotifiers.length <= pageIndex) {
                    _pageNotifiers.add(EditorPageNotifier(_coreInfo.pages[pageIndex]));
                  }

                  // ✅ 使用ListenableBuilder包装页面，只在特定页面数据变化时重建
                  final pageWidget = ListenableBuilder(
                    listenable: _pageNotifiers[pageIndex],
                    builder: (context, child) {
                      final page = _pageNotifiers[pageIndex].page;

                      // 防止除零错误
                      if (page.size.width <= 0 || page.size.height <= 0) {
                        return const SizedBox.shrink();
                      }

                      // ✅ 计算页面缩放（使用屏幕宽度，保持比例）
                      // 确保页面宽度不超过屏幕宽度，高度按比例缩放
                      final double pageScale = screenWidth / page.size.width;
                      final double pageDisplayWidth = page.size.width * pageScale;
                      final double pageDisplayHeight = page.size.height * pageScale;

                      // ✅ 创建单页画布
                      return _buildSinglePageCanvas(
                        page: page,
                        pageIndex: pageIndex,
                        pageDisplayWidth: pageDisplayWidth,
                        pageDisplayHeight: pageDisplayHeight,
                        screenWidth: screenWidth,
                      );
                    },
                  );
                  pageWidgets.add(pageWidget);
                  
                  // ✅ 页面之间的间距（除了最后一页）
                  if (pageIndex < _coreInfo.pages.length - 1) {
                    pageWidgets.add(const SizedBox(height: 16));
                  }
                }
                
                // ✅ 直接使用新创建的pageWidgets，不使用缓存
                // 原因：之前的缓存机制有严重bug - 只检查页面数量，导致数据更新后界面不刷新
                // ListenableBuilder已经提供了充分的优化（每个页面只在自己的数据变化时重建）
                debugPrint('🖼️🖼️🖼️ [HandwritingSaber] Rendering ${pageWidgets.length} page widgets directly (no cache)');

                // ✅ 使用 SingleChildScrollView 支持垂直滚动
                return SingleChildScrollView(
                  child: Column(
                    children: pageWidgets,  // 直接使用最新的pageWidgets
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


