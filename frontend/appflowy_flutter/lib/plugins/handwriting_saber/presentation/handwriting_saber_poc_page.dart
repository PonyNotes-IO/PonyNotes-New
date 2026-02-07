import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'dart:math' as math;

import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy/workspace/presentation/home/full_window_controller.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:pdfrx/pdfrx.dart';

import '../application/handwriting_saber_data_service.dart';
import '../third_party/saber_core/components/canvas/canvas_background_pattern.dart';
import '../third_party/saber_core/components/canvas/image/pdf_editor_image.dart';
import '../third_party/saber_core/components/canvas/image/editor_image.dart';
import '../third_party/saber_core/components/canvas/saber_core_canvas.dart';
import '../third_party/saber_core/data/editor/editor_core_info.dart';
import '../third_party/saber_core/data/editor/editor_history.dart'; // ✅ 导入历史记录管理器
import '../third_party/saber_core/data/editor/page.dart';
import '../third_party/saber_core/data/editor/quill_styles.dart';
import '../third_party/saber_core/data/editor/quill_struct.dart'; // ✅ 导入 QuillStruct
import '../third_party/saber_core/data/editor/shape_strokes.dart';
import '../third_party/saber_core/data/editor/stroke_extensions.dart'; // ✅ 导入扩展方法
import '../third_party/saber_core/data/editor/text_box.dart'
    as saber_text; // ✅ 导入文本框（使用别名避免与Flutter的TextBox冲突）
import '../third_party/saber_core/data/tools/select_result.dart';
import '../third_party/saber_core/data/tools/tool.dart';
import 'handwriting_saber_toolbar.dart';
import 'widgets/canvas_image_widget.dart';
import 'widgets/canvas_preview.dart'; // ✅ 导入页面预览组件
import 'widgets/editor_page_manager.dart'; // ✅ 导入页面管理器组件
import '../third_party/saber_core/components/canvas/webview/webview_editor_element.dart';
import 'widgets/canvas_webview_widget.dart';
import 'dialogs/insert_webview_dialog.dart';
import '../widgets/pdf_text_selection_dialog.dart';
import '../services/pdf_text_extraction_service.dart';
import '../services/editor_exporter.dart'; // ✅ PDF导出器
import '../../../util/log_utils.dart';

/// ✅ 层级调整动作枚举
enum ReorderAction {
  bringToFront,
  bringForward,
  sendBackward,
  sendToBack,
}

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
  final HandwritingSaberDataService _dataService =
      HandwritingSaberDataService();

  String _status = '初始化中...';

  /// 简化版 Saber 核心数据
  EditorCoreInfo _coreInfo = EditorCoreInfo.empty();

  /// 当前正在绘制的一笔（使用 ValueNotifier 减少父级 setState 频繁重建）
  final ValueNotifier<Stroke?> _currentStrokeNotifier =
      ValueNotifier<Stroke?>(null);

  /// 激光笔笔迹变更 notifier（用于驱动局部重绘，避免父级 setState）
  final ValueNotifier<List<Stroke>> _laserStrokesNotifier =
      ValueNotifier<List<Stroke>>([]);

  /// 合并 repaint notifier（当 current stroke 或 laser strokes 变化时通知 painter）
  final ValueNotifier<int> _repaintTick = ValueNotifier<int>(0);

  /// ✅ 页面状态notifier列表（用于精确更新，避免全量重建）
  final List<EditorPageNotifier> _pageNotifiers = [];

  /// 当前工具（使用 ValueNotifier 以便在切换工具时避免触发父级整页重建）
  // 默认工具：钢笔，默认颜色黑色，默认粗细 2（用户要求）
  final ValueNotifier<Tool> _currentToolNotifier =
      ValueNotifier<Tool>(const Pen(
    toolId: ToolId.fountainPen,
    color: Colors.black,
    strokeWidth: 2,
  ));

  /// 当前背景纸模式（使用 EditorCoreInfo.empty() 的默认以保证一致）
  CanvasBackgroundPattern _currentBackgroundPattern =
      EditorCoreInfo.empty().backgroundPattern;

  /// ✅ 上一次布局的约束（用于在 _scrollToPage 中精确计算宽度）
  BoxConstraints? _lastCanvasConstraints;

  /// ✅ 当前填充颜色（用于形状工具） - 使用 ValueNotifier 避免父级 setState 导致整页重建
  final ValueNotifier<Color?> _currentFillColorNotifier =
      ValueNotifier<Color?>(null);

  /// ✅ 全局当前描边颜色（保证切换工具时保留用户选择的颜色）
  final ValueNotifier<Color> _globalColorNotifier =
      ValueNotifier<Color>(Colors.black);

  /// ✅ 全局当前描边宽度（保证切换工具时保留用户选择的线宽）
  final ValueNotifier<double> _globalStrokeWidthNotifier =
      ValueNotifier<double>(2.0);

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

  /// ✅ PDF文本选择状态
  Rect? _pdfTextSelectionRect;
  Offset? _pdfTextSelectionStart;
  int? _pdfTextSelectionPageIndex;
  bool _isSelecting = false; // 是否正在选择（拖拽选择区域）
  Offset? _selectStartPosition; // 选择开始位置

  /// ✅ 当前选中的图片ID（使用ValueNotifier避免全局setState）
  final ValueNotifier<String?> _selectedImageIdNotifier =
      ValueNotifier<String?>(null);

  /// ✅ 是否正在操作图片（拖动/缩放/旋转）
  bool _isImageOperationInProgress = false;

  /// ✅ 剪贴板数据（存储复制的对象）
  List<Stroke>? _clipboardStrokes;
  List<PdfEditorImage>? _clipboardImages;
  List<EditorImage>? _clipboardRegularImages; // ✅ 新增：常规图片剪贴板
  int? _clipboardSourcePageIndex;

  /// ✅ 当前正在编辑的文本框ID（使用ValueNotifier避免全局setState）
  final ValueNotifier<String?> _editingTextBoxIdNotifier =
      ValueNotifier<String?>(null);

  /// ✅ 文本框编辑控制器
  final Map<String, TextEditingController> _textBoxControllers = {};

  /// ✅ 当前视图的.sbn2文件路径（缓存，避免重复获取）
  String? _cachedSbnFilePath;

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
  final ValueNotifier<DashStyle> _dashStyleNotifier =
      ValueNotifier<DashStyle>(DashStyle.solid);

  /// ✅ 当前箭头样式（用于箭头直线工具）
  final ValueNotifier<ArrowStyle> _arrowStyleNotifier =
      ValueNotifier<ArrowStyle>(ArrowStyle.filled);

  /// ✅ 文本编辑模式状态（用于切换富文本编辑模式）
  final ValueNotifier<bool> _textEditingModeNotifier =
      ValueNotifier<bool>(false);

  /// ✅ 当前焦点页面的 Quill 结构（用于在编辑模式下显示工具栏）
  final ValueNotifier<int?> _quillFocusPageIndexNotifier =
      ValueNotifier<int?>(null);

  /// ✅ 视图缩放级别（1.0 = 100%，范围 0.2 ~ 3.0）
  final ValueNotifier<double> _zoomLevelNotifier = ValueNotifier<double>(1.0);

  /// 缩放级别常量
  static const double _minZoom = 0.2; // 20%
  static const double _maxZoom = 3.0; // 300%
  static const double _zoomStep = 0.1; // 每次缩放10%

  /// 预设缩放档位（用于快捷键和UI显示）
  static const List<double> _zoomPresets = [
    0.2,
    0.5,
    0.7,
    0.8,
    0.9,
    1.0,
    1.1,
    1.2,
    1.5,
    2.0,
    2.5,
    3.0
  ];

  /// ✅ 是否显示页面管理器侧边栏
  final ValueNotifier<bool> _showPageManagerNotifier =
      ValueNotifier<bool>(false);

  /// ✅ 当前查看的页面索引（用于页面管理器高亮显示）
  final ValueNotifier<int> _viewingPageIndexNotifier = ValueNotifier<int>(0);

  /// ✅ 滚动控制器（用于滚动到指定页面）
  final ScrollController _pageScrollController = ScrollController();

  /// ✅ 页面之间的间距
  static const double _gapBetweenPages = 16;

  /// ✅ 标记是否正在执行程序触发的滚动（防止滚动通知干扰索引更新）
  bool _isProgrammaticScrolling = false;

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
    debugPrint(
        '🔄🔄🔄 [HandwritingSaber] Old ViewID: ${oldWidget.view.id}, Old ViewName: ${oldWidget.view.name}');
    debugPrint(
        '🔄🔄🔄 [HandwritingSaber] New ViewID: ${widget.view.id}, New ViewName: ${widget.view.name}');
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
    _currentPageIndexNotifier.value = null;
    // 清理激光笔
    _laserStrokesNotifier.value = [];
    _coreInfo.laserStrokes.clear();
    // 清理选择状态
    _selectResult = null;
    _selectStartPosition = null;
    _isSelecting = false;
    // 清理缓存的文件路径
    _cachedSbnFilePath = null;
    // 清理文本框控制器
    for (final controller in _textBoxControllers.values) {
      controller.dispose();
    }
    _textBoxControllers.clear();
    // 清理历史记录
    _history.clear(); // ✅ 使用clear()方法而不是重新赋值
    _updateUndoRedoState();
    // 清理页面notifier
    for (final notifier in _pageNotifiers) {
      notifier.dispose();
    }
    _pageNotifiers.clear();
    // 取消待保存标记
    _pendingSave = false;
    _saveDebounceTimer?.cancel();

    // ✅ 清理当前页面索引
    _currentPageIndexNotifier.value = null;
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
        // ✅ 使用resetLoadStateAndPreload强制重新加载，确保视图切换后PDF能正确显示
        page.backgroundImage!.resetLoadStateAndPreload();
        pdfPageCount++;
      }
    }
    if (pdfPageCount > 0) {
      debugPrint(
          '🦋[HandwritingSaber] _preloadPdfBackgrounds: Preloading $pdfPageCount PDF background images');
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

      // 1.1 获取并缓存.sbn2文件路径（用于WebView缓存）
      _cachedSbnFilePath = await _dataService
          .getHandwritingSaberFilePathForDebug(widget.view.id);
      debugPrint('🦋🦋🦋 [HandwritingSaber] SBN文件路径: $_cachedSbnFilePath');

      // 2. 加载已有数据（PoC 阶段按 JSON 文本解析）
      await _loadFromStorage();

      debugPrint(
          '🦋🦋🦋 [HandwritingSaber] _initLocalData: Data loaded, pages=${_coreInfo.pages.length}');

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
    debugPrint(
        '📖📖📖 [HandwritingSaber] 当前_coreInfo.pages.length: ${_coreInfo.pages.length}');

    try {
      final List<int> bytes =
          await _dataService.loadHandwritingSaberData(widget.view.id);

      debugPrint(
          '📖📖📖 [HandwritingSaber] Loaded ${bytes.length} bytes from storage');

      if (bytes.isEmpty) {
        debugPrint(
            '📖📖📖 [HandwritingSaber] Empty data, creating new EditorCoreInfo');
        _coreInfo = EditorCoreInfo.empty();
        // 保证 UI 上的当前背景纸样式与核心数据一致（避免新建时工具栏/画布不一致）
        _currentBackgroundPattern = _coreInfo.backgroundPattern;
        _status = '已就绪';
      } else {
        final String content = utf8.decode(bytes);
        debugPrint(
            '📖📖📖 [HandwritingSaber] Decoding JSON, content length: ${content.length}');
        _coreInfo = EditorCoreInfo.fromJsonString(content);
        debugPrint(
            '📖📖📖 [HandwritingSaber] Decoded: ${_coreInfo.pages.length} pages');

        // ✅ 修复无效的页面尺寸（兼容旧版本数据）
        bool needsRepair = false;
        for (int i = 0; i < _coreInfo.pages.length; i++) {
          final page = _coreInfo.pages[i];
          debugPrint(
              '📖📖📖 [HandwritingSaber] Page $i: size=${page.size}, strokes=${page.strokes.length}');
          if (page.size.width <= 0 || page.size.height <= 0) {
            debugPrint(
                '🔧🔧🔧 [HandwritingSaber] Repairing invalid page size at index $i: ${page.size} -> ${EditorPage.defaultSize}');
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

      debugPrint(
          '📖📖📖 [HandwritingSaber] Final _coreInfo.pages.length: ${_coreInfo.pages.length}');

      // ✅ 初始化页面notifier（用于精确状态更新）
      _initPageNotifiers();
      debugPrint(
          '📖📖📖 [HandwritingSaber] Page notifiers initialized: ${_pageNotifiers.length}');

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
      debugPrint(
          '🦋[HandwritingSaber] _saveToStorage deferred due to laser fade in progress');
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

  // ============================================================
  // ✅ 页面管理方法（分页功能）
  // ============================================================

  /// ✅ 切换页面管理器侧边栏显示状态
  void _togglePageManager() {
    _showPageManagerNotifier.value = !_showPageManagerNotifier.value;
  }

  /// ✅ 滚动到指定页面
  /// @param pageIndex 目标页面索引
  /// @param constraints 布局约束（这里通常不需要传入，使用 _lastCanvasConstraints 更准确）
  void _scrollToPage(int pageIndex, {BoxConstraints? constraints}) async {
    debugPrint(
        '📜 [PageManager] _scrollToPage called: pageIndex=$pageIndex, currentPageIndex=${_currentPageIndexNotifier.value}, viewingPageIndex=${_viewingPageIndexNotifier.value}');

    if (pageIndex < 0 || pageIndex >= _coreInfo.pages.length) {
      debugPrint('📜 [PageManager] Invalid pageIndex, returning');
      return;
    }

    // ✅ 设置程序滚动标记，防止滚动事件更新索引
    _isProgrammaticScrolling = true;

    // ✅ 立即同步更新两个索引，确保状态一致
    _currentPageIndexNotifier.value = pageIndex;
    _viewingPageIndexNotifier.value = pageIndex;
    debugPrint(
        '📜 [PageManager] Updated both notifiers: currentPageIndex=$pageIndex, viewingPageIndex=$pageIndex');

    // 计算目标滚动位置
    double targetOffset = 0;

    // ✅ 获取实际可用宽度（优先使用上次渲染时的约束，确保一致性）
    double availableWidth;
    if (_lastCanvasConstraints != null &&
        _lastCanvasConstraints!.maxWidth.isFinite) {
      availableWidth = _lastCanvasConstraints!.maxWidth;
    } else {
      // 回退到原来的计算方式
      final mediaQueryWidth = MediaQuery.of(context).size.width;
      final pageManagerWidth = _showPageManagerNotifier.value ? 200.0 : 0.0;
      availableWidth = mediaQueryWidth - pageManagerWidth;
    }
    final zoomLevel = _zoomLevelNotifier.value;

    debugPrint(
        '📜 [PageManager] pageIndex=$pageIndex, availableWidth=$availableWidth, zoomLevel=$zoomLevel');

    for (int i = 0; i < pageIndex; i++) {
      final page = _coreInfo.pages[i];
      // ✅ 使用与页面渲染时一致的计算方式
      final baseScale = availableWidth / page.size.width;
      final effectiveScale = baseScale * zoomLevel;
      final pageHeight = page.size.height * effectiveScale;
      targetOffset += pageHeight + _gapBetweenPages;
    }

    debugPrint(
        '📜 [PageManager] targetOffset=$targetOffset, hasClients=${_pageScrollController.hasClients}');

    // 滚动到目标位置
    if (_pageScrollController.hasClients) {
      await _pageScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );

      // ✅ 动画完成后，不要立即重置滚动标记
      // 而是等待一帧，确保滚动通知处理完成
      // 这样可以避免滚动通知覆盖正确的页面索引
      await Future.delayed(const Duration(milliseconds: 50));

      // ✅ 确保最终滚动位置准确
      if ((_pageScrollController.position.pixels - targetOffset).abs() > 1) {
        debugPrint('📜 [PageManager] Adjusting scroll position');
        _pageScrollController.jumpTo(targetOffset);
      }

      // ✅ 再次确认两个索引正确
      if (_currentPageIndexNotifier.value != pageIndex) {
        debugPrint(
            '📜 [PageManager] Fixing currentPageIndex: was ${_currentPageIndexNotifier.value}, setting to $pageIndex');
        _currentPageIndexNotifier.value = pageIndex;
      }
      if (_viewingPageIndexNotifier.value != pageIndex) {
        debugPrint(
            '📜 [PageManager] Fixing viewingPageIndex: was ${_viewingPageIndexNotifier.value}, setting to $pageIndex');
        _viewingPageIndexNotifier.value = pageIndex;
      }

      // ✅ 延迟重置滚动标记，确保所有滚动通知都已处理
      await Future.delayed(const Duration(milliseconds: 50));
      _isProgrammaticScrolling = false;
      debugPrint('📜 [PageManager] Scrolling complete, pageIndex=$pageIndex');
    } else {
      // 如果控制器还没有绑定，延迟执行
      debugPrint(
          '📜 [PageManager] Controller has no clients, scheduling delayed scroll');
      Completer<void> completer = Completer<void>();
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (_pageScrollController.hasClients) {
          await _pageScrollController.animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );

          // ✅ 动画完成后延迟处理
          await Future.delayed(const Duration(milliseconds: 50));

          // ✅ 确保滚动位置准确
          if ((_pageScrollController.position.pixels - targetOffset).abs() >
              1) {
            debugPrint('📜 [PageManager] Adjusting scroll position (delayed)');
            _pageScrollController.jumpTo(targetOffset);
          }

          // ✅ 再次确认两个索引正确
          if (_currentPageIndexNotifier.value != pageIndex) {
            debugPrint(
                '📜 [PageManager] Fixing currentPageIndex (delayed): was ${_currentPageIndexNotifier.value}, setting to $pageIndex');
            _currentPageIndexNotifier.value = pageIndex;
          }
          if (_viewingPageIndexNotifier.value != pageIndex) {
            debugPrint(
                '📜 [PageManager] Fixing viewingPageIndex (delayed): was ${_viewingPageIndexNotifier.value}, setting to $pageIndex');
            _viewingPageIndexNotifier.value = pageIndex;
          }

          // ✅ 延迟重置滚动标记
          await Future.delayed(const Duration(milliseconds: 50));
          _isProgrammaticScrolling = false;
        }
        completer.complete();
      });
      await completer.future;
    }
  }

  /// ✅ 在指定页后插入新页
  void _insertPageAfter(int pageIndex) {
    debugPrint('📄 [PageManager] insertPageAfter: pageIndex=$pageIndex');

    // 创建新页面
    final newPage = EditorPage(size: EditorPage.defaultSize);

    // 插入到指定位置之后
    final insertIndex = pageIndex + 1;
    _coreInfo.pages.insert(insertIndex, newPage);

    // 更新页面notifier
    _pageNotifiers.insert(insertIndex, EditorPageNotifier(newPage));

    // 记录历史（用于撤销）
    _history.recordPageInsert(insertIndex, newPage);
    _updateUndoRedoState();

    // 保存并刷新
    _scheduleSave();
    setState(() {});
  }

  /// ✅ 复制页面
  void _duplicatePage(int pageIndex) {
    debugPrint('📄 [PageManager] duplicatePage: pageIndex=$pageIndex');

    if (pageIndex < 0 || pageIndex >= _coreInfo.pages.length) return;

    final sourcePage = _coreInfo.pages[pageIndex];

    // 深拷贝页面数据
    final newStrokes = sourcePage.strokes.map((s) {
      // 创建笔迹的副本
      return Stroke(
        points: List.from(s.points),
        color: s.color,
        strokeWidth: s.strokeWidth,
        toolId: s.toolId,
        pressureEnabled: s.pressureEnabled,
      );
    }).toList();

    // 创建新页面（带有复制的数据）
    final newPage = EditorPage(
      size: sourcePage.size,
      strokes: newStrokes,
      backgroundImage: sourcePage.backgroundImage,
      // 其他元素暂不复制（可以根据需要扩展）
    );

    // 插入到源页面之后
    final insertIndex = pageIndex + 1;
    _coreInfo.pages.insert(insertIndex, newPage);

    // 更新页面notifier
    _pageNotifiers.insert(insertIndex, EditorPageNotifier(newPage));

    // 记录历史
    _history.recordPageInsert(insertIndex, newPage);
    _updateUndoRedoState();

    // 保存并刷新
    _scheduleSave();
    setState(() {});
  }

  /// ✅ 清空页面内容
  void _clearPage(int pageIndex) {
    debugPrint('📄 [PageManager] clearPage: pageIndex=$pageIndex');

    if (pageIndex < 0 || pageIndex >= _coreInfo.pages.length) return;

    final page = _coreInfo.pages[pageIndex];

    // 记录被删除的内容（用于撤销）
    final removedStrokes = List<Stroke>.from(page.strokes);
    final removedTextBoxes = List.from(page.textBoxes);

    // 清空页面内容
    page.strokes.clear();
    page.textBoxes.clear();
    page.images.clear();
    page.webViews.clear();

    // 更新页面notifier
    if (pageIndex < _pageNotifiers.length) {
      _pageNotifiers[pageIndex].updatePage(page);
    }

    // 记录历史（清空操作记录为批量删除）
    if (removedStrokes.isNotEmpty) {
      _history.recordErase(removedStrokes);
    }
    _updateUndoRedoState();

    // 移除多余的空白页（保留至少一页）
    _removeExcessPages();

    // 保存并刷新
    _scheduleSave();
    setState(() {});
  }

  /// ✅ 删除页面
  void _deletePage(int pageIndex) {
    debugPrint('📄 [PageManager] deletePage: pageIndex=$pageIndex');

    if (pageIndex < 0 || pageIndex >= _coreInfo.pages.length) return;

    // 确保至少保留一页
    if (_coreInfo.pages.length <= 1) {
      // 如果只有一页，清空而不是删除
      _clearPage(pageIndex);
      return;
    }

    // 获取要删除的页面
    final deletedPage = _coreInfo.pages[pageIndex];

    // 删除页面
    _coreInfo.pages.removeAt(pageIndex);

    // 删除对应的notifier
    if (pageIndex < _pageNotifiers.length) {
      _pageNotifiers[pageIndex].dispose();
      _pageNotifiers.removeAt(pageIndex);
    }

    // 记录历史
    _history.recordPageDelete(pageIndex, deletedPage);
    _updateUndoRedoState();

    // 更新当前查看的页面索引
    if (_viewingPageIndexNotifier.value >= _coreInfo.pages.length) {
      _viewingPageIndexNotifier.value = _coreInfo.pages.length - 1;
    }

    // 保存并刷新
    _scheduleSave();
    setState(() {});
  }

  /// ✅ 移除多余的空白页（保留至少一页）
  void _removeExcessPages() {
    // 从后往前检查，移除连续的空白页（保留至少一页）
    while (_coreInfo.pages.length > 1) {
      final lastPage = _coreInfo.pages.last;
      final secondLastPage = _coreInfo.pages[_coreInfo.pages.length - 2];

      // 如果最后两页都是空的，删除最后一页
      if (_isPageEmpty(lastPage) && _isPageEmpty(secondLastPage)) {
        _coreInfo.pages.removeLast();
        if (_pageNotifiers.isNotEmpty) {
          _pageNotifiers.last.dispose();
          _pageNotifiers.removeLast();
        }
      } else {
        break;
      }
    }
  }

  /// ✅ 检查页面是否为空
  bool _isPageEmpty(EditorPage page) {
    return page.strokes.isEmpty &&
        page.textBoxes.isEmpty &&
        page.images.isEmpty &&
        page.webViews.isEmpty &&
        page.backgroundImage == null;
  }

  /// ✅ 重绘并保存（供页面管理器调用）
  void _redrawAndSave() {
    _scheduleSave();
    setState(() {});
  }

  /// ✅ 获取当前页面索引（基于滚动位置）
  /// 采用“最高可见度”算法：计算每个页面在视口中的重叠高度，选择可见比例最大的页面
  int _getCurrentPageIndexFromScroll() {
    if (!_pageScrollController.hasClients || _coreInfo.pages.isEmpty) return 0;

    final scrollOffset = _pageScrollController.offset;
    final viewportHeight = _pageScrollController.position.viewportDimension;

    // 视口的起止范围
    final double viewportStart = scrollOffset;
    final double viewportEnd = scrollOffset + viewportHeight;

    int bestIndex = 0;
    double maxVisibleHeight = -1.0;

    double currentPageTop = 0;

    // ✅ 获取实际可用宽度（优先使用上次渲染时的约束，确保一致性）
    double availableWidth;
    if (_lastCanvasConstraints != null &&
        _lastCanvasConstraints!.maxWidth.isFinite) {
      availableWidth = _lastCanvasConstraints!.maxWidth;
    } else {
      final mediaQueryWidth = MediaQuery.of(context).size.width;
      final pageManagerWidth = _showPageManagerNotifier.value ? 200.0 : 0.0;
      availableWidth = mediaQueryWidth - pageManagerWidth;
    }

    for (int i = 0; i < _coreInfo.pages.length; i++) {
      final page = _coreInfo.pages[i];
      // ✅ 使用与页面渲染时一致的计算方式
      final baseScale = availableWidth / page.size.width;
      final zoomLevel = _zoomLevelNotifier.value;
      final effectiveScale = baseScale * zoomLevel;
      final pageHeight = page.size.height * effectiveScale;

      final double pageBottom = currentPageTop + pageHeight;

      // 计算该页面与视口的重合高度
      final double intersectionStart = math.max(viewportStart, currentPageTop);
      final double intersectionEnd = math.min(viewportEnd, pageBottom);
      final double intersectionHeight =
          math.max(0.0, intersectionEnd - intersectionStart);

      // 如果当前页面的可见高度大于之前的最大值，则更新最佳索引
      if (intersectionHeight > maxVisibleHeight) {
        maxVisibleHeight = intersectionHeight;
        bestIndex = i;
      }
      // 如果可见高度相同（例如两个页面都完全可见，或者由于间距原因都没显示出来），
      // 且当前最佳索引就是 _viewingPageIndexNotifier 所指的索引，则保持不变以避免闪烁
      else if (intersectionHeight == maxVisibleHeight &&
          intersectionHeight > 0 &&
          i == _viewingPageIndexNotifier.value) {
        bestIndex = i;
      }

      currentPageTop = pageBottom + _gapBetweenPages;
    }

    return bestIndex;
  }

  // ============================================================
  // ✅ 结束页面管理方法
  // ============================================================

  /// ✅ 当前正在绘制的页面索引
  final ValueNotifier<int?> _currentPageIndexNotifier =
      ValueNotifier<int?>(null);

  /// ✅ 形状工具的起始点（用于矩形、圆形、菱形等工具）
  Offset? _shapeStartPoint;

  void _startStroke(Offset position, {int? pageIndex}) {
    // ✅ 设置当前页面索引
    _currentPageIndexNotifier.value = pageIndex ?? 0;
    debugPrint(
        '🦋[HandwritingSaber] _startStroke: pageIndex=$_currentPageIndexNotifier.value, position=$position, tool=${_currentToolNotifier.value.toolId}');

    // 确保页面索引有效
    if (_currentPageIndexNotifier.value! >= _coreInfo.pages.length) {
      _currentPageIndexNotifier.value = 0;
    }

    // ✅ 如果是选择工具，开始选择
    if (_currentToolNotifier.value.toolId == ToolId.select) {
      _startSelection(position, pageIndex: _currentPageIndexNotifier.value);
      return;
    }

    // ✅ 如果是PDF文本选择工具，开始PDF文本选择
    if (_currentToolNotifier.value.toolId == ToolId.pdfTextSelect) {
      _startPdfTextSelection(position,
          pageIndex: _currentPageIndexNotifier.value);
      return;
    }

    // ✅ 如果是文本框工具或标题工具，创建文本框
    if (_currentToolNotifier.value.toolId == ToolId.textBox ||
        _currentToolNotifier.value.toolId == ToolId.heading1 ||
        _currentToolNotifier.value.toolId == ToolId.heading2 ||
        _currentToolNotifier.value.toolId == ToolId.heading3 ||
        _currentToolNotifier.value.toolId == ToolId.paragraph) {
      _createTextBox(position, pageIndex: _currentPageIndexNotifier.value);
      return;
    }

    // 如果是橡皮擦，根据模式处理
    if (_currentToolNotifier.value.toolId == ToolId.eraser) {
      final eraserTool = _currentToolNotifier.value as Eraser;
      if (eraserTool.mode == EraserMode.whiteout) {
        // 涂白模式：初始化白色stroke（使用_currentStrokeNotifier以便实时显示）
        _currentStrokeNotifier.value = Stroke(
          points: [position],
          color: Colors.white,
          strokeWidth: eraserTool.strokeWidth,
          toolId: ToolId.fountainPen, // 使用普通笔工具类型
        );
      } else {
        // 标准模式和删除笔画模式：直接擦除
        _eraseStrokesAtPosition(position,
            pageIndex: _currentPageIndexNotifier.value);
      }
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
      debugPrint(
          '🔶🔶🔶 [_startStroke] Saved shape start point: $_shapeStartPoint');
    } else {
      _shapeStartPoint = null;
    }

    // ✅ 创建新笔迹，初始只包含一个点
    // 形状工具只需要起始点，在 _updateStroke 和 _endStroke 中计算形状
    final bool pressureEnabled =
        _currentToolNotifier.value.toolId == ToolId.fountainPen;
    final Stroke stroke = Stroke(
      points: <Offset>[position],
      color: _currentToolNotifier.value.color,
      strokeWidth: _currentToolNotifier.value.strokeWidth,
      toolId: _currentToolNotifier.value.toolId,
      pressureEnabled: pressureEnabled, // ✅ 设置压感支持
    );
    // 使用 notifier 更新当前笔迹，避免触发整个页面的 rebuild
    _currentStrokeNotifier.value = stroke;
    // 如果是激光笔，初始化点间延迟记录与计时器（参考 Saber 的实现）
    if (stroke.toolId == ToolId.laserPointer) {
      _laserStrokePointDelays[stroke] = <Duration>[Duration.zero];
      _laserStrokeStopwatches[stroke] = Stopwatch()
        ..reset()
        ..start();
    }
  }

  /// ✅ 开始选择
  void _startSelection(Offset position, {int? pageIndex}) {
    final pageIdx = pageIndex ?? 0;

    // ✅ 获取当前选择工具的选择模式
    final currentTool = _currentToolNotifier.value;
    SelectMode selectMode = SelectMode.click;
    if (currentTool is SelectTool) {
      selectMode = currentTool.selectMode;
    }

    // 检查是否点击在已选中的对象上
    if (_selectResult != null &&
        _selectResult!.pageIndex == pageIdx &&
        _isPointInSelection(position, _selectResult!)) {
      // 点击在已选中的对象上，准备移动
      _selectStartPosition = position;
      return;
    }

    // ✅ 点选模式：先尝试点击选择单个对象（快速点击，不拖拽）
    if (selectMode == SelectMode.click) {
      // ✅ 优先检查文本框（文本框在上层）
      final clickedTextBox = _findTextBoxAtPosition(position, pageIdx);
      if (clickedTextBox != null) {
        // 点击选中了单个文本框
        setState(() {
          _selectResult = SelectResult(
            pageIndex: pageIdx,
            strokes: [],
            images: [],
            regularImages: [],
            webViews: [],
            textBoxes: [clickedTextBox],
            selectionPath: Path(), // 点击选择不需要路径
            selectMode: selectMode,
          );
          _isSelecting = false;
          _selectStartPosition = position;
        });
        return;
      }

      // ✅ 检查图片（图片在文本框下层，笔迹上层）
      final clickedImage = _findImageAtPosition(position, pageIdx);
      if (clickedImage != null) {
        // 点击选中了单个图片
        setState(() {
          _selectResult = SelectResult(
            pageIndex: pageIdx,
            strokes: [],
            images: [],
            regularImages: [clickedImage],
            webViews: [],
            textBoxes: [],
            selectionPath: Path(), // 点击选择不需要路径
            selectMode: selectMode,
          );
          _isSelecting = false;
          _selectStartPosition = position;
          // ✅ 同步图片选中状态
          _selectedImageIdNotifier.value = clickedImage.id;
        });
        return;
      }

      final clickedStroke = _findStrokeAtPosition(position, pageIdx);
      if (clickedStroke != null) {
        // 点击选中了单个笔迹
        setState(() {
          _selectResult = SelectResult(
            pageIndex: pageIdx,
            strokes: [clickedStroke],
            images: [],
            regularImages: [],
            webViews: [],
            textBoxes: [],
            selectionPath: Path(), // 点击选择不需要路径
            selectMode: selectMode,
          );
          _isSelecting = false;
          _selectStartPosition = position;
        });
        return;
      }
    }

    // 开始新的拖拽选择区域（框选或套索）
    setState(() {
      _isSelecting = true;
      _selectStartPosition = position;
      _selectResult = SelectResult(
        pageIndex: pageIdx,
        strokes: [],
        images: [],
        regularImages: [],
        webViews: [],
        textBoxes: [],
        selectionPath: selectMode == SelectMode.lasso
            ? (Path()..moveTo(position.dx, position.dy))
            : Path(),
        selectMode: selectMode,
        selectionStartPoint:
            selectMode == SelectMode.rectangle ? position : null,
        selectionEndPoint: selectMode == SelectMode.rectangle ? position : null,
      );
    });
  }

  /// ✅ 在指定位置查找图片（用于点击选择）
  EditorImage? _findImageAtPosition(Offset position, int pageIndex) {
    if (_coreInfo.pages.isEmpty ||
        pageIndex < 0 ||
        pageIndex >= _coreInfo.pages.length) {
      return null;
    }

    final page = _coreInfo.pages[pageIndex];

    // ✅ 从后往前查找（最上层的图片优先）
    for (int i = page.images.length - 1; i >= 0; i--) {
      final image = page.images[i];
      if (image.dstRect != null && image.dstRect!.contains(position)) {
        return image;
      }
    }

    return null;
  }

  /// ✅ 在指定位置查找笔迹（用于点击选择）
  Stroke? _findStrokeAtPosition(Offset position, int pageIndex) {
    if (_coreInfo.pages.isEmpty ||
        pageIndex < 0 ||
        pageIndex >= _coreInfo.pages.length) {
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
      return _isPointNearLine(
          point, stroke.startPoint, stroke.endPoint, stroke.strokeWidth);
    } else if (stroke is RectangleStroke) {
      return stroke.rect.inflate(stroke.strokeWidth).contains(point);
    } else if (stroke is CircleStroke) {
      final center = stroke.center;
      final distance = (point - center).distance;
      return distance <= stroke.radius + stroke.strokeWidth;
    } else if (stroke is TriangleStroke) {
      // 检查点是否在三角形内
      return _isPointInTriangle(
          point, stroke.point1, stroke.point2, stroke.point3);
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
  bool _isPointNearLine(
      Offset point, Offset lineStart, Offset lineEnd, double strokeWidth) {
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
    return (p1.dx - p3.dx) * (p2.dy - p3.dy) -
        (p2.dx - p3.dx) * (p1.dy - p3.dy);
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

    // ✅ 检查是否在某个选中的文本框内
    for (final textBox in selectResult.textBoxes) {
      if (textBox.rect.contains(point)) {
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
    final eraserTool = _currentToolNotifier.value;

    // 如果不是橡皮擦工具，直接返回
    if (eraserTool.toolId != ToolId.eraser || eraserTool is! Eraser) {
      return;
    }

    final eraserSize = eraserTool.strokeWidth;
    final eraserMode = eraserTool.mode;
    final sqrEraserSize = eraserSize * eraserSize;

    // 根据橡皮擦模式执行不同的擦除行为
    switch (eraserMode) {
      case EraserMode.standard:
        // 标准模式：整体删除stroke
        _eraseStrokesStandard(page, targetPageIndex, position, sqrEraserSize);
        break;
      case EraserMode.whiteout:
        // 涂白模式：在擦除区域绘制白色覆盖层
        _eraseStrokesWhiteout(page, targetPageIndex, position, eraserSize);
        break;
      case EraserMode.deleteStrokes:
        // 删除笔画模式：精确删除stroke中被擦除的部分
        _eraseStrokesDeleteStrokes(page, targetPageIndex, position, eraserSize);
        break;
    }
  }

  /// 标准模式擦除：整体删除stroke
  void _eraseStrokesStandard(EditorPage page, int targetPageIndex,
      Offset position, double sqrEraserSize) {
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
        debugPrint(
            '🦋[HandwritingSaber] Warning: failed to sync _coreInfo.pages[$targetPageIndex]: $e');
      }
      _scheduleSave();
    }
  }

  /// 涂白模式擦除：在擦除区域绘制白色覆盖层（此方法不再使用，涂白模式的路径跟踪在_startStroke和_updateStroke中处理）
  void _eraseStrokesWhiteout(EditorPage page, int targetPageIndex,
      Offset position, double eraserSize) {
    // 涂白模式的路径跟踪在_startStroke和_updateStroke中处理
    // 这里不需要做任何事情
  }

  /// 删除笔画模式擦除：精确删除stroke中被擦除的部分，将stroke分割成多个片段
  void _eraseStrokesDeleteStrokes(EditorPage page, int targetPageIndex,
      Offset position, double eraserSize) {
    final sqrEraserSize = eraserSize * eraserSize;
    final strokesToRemove = <Stroke>[];
    final strokesToAdd = <Stroke>[];

    // 处理每个stroke
    for (int i = 0; i < page.strokes.length; i++) {
      final stroke = page.strokes[i];

      // 跳过形状stroke（LineStroke, RectangleStroke等），因为它们只有2个点，分割意义不大
      // 对于形状stroke，如果被擦除，直接删除
      if (stroke is LineStroke ||
          stroke is ArrowLineStroke ||
          stroke is RectangleStroke ||
          stroke is CircleStroke ||
          stroke is TriangleStroke ||
          stroke is DiamondStroke) {
        if (_isStrokeIntersectingEraser(position, stroke, sqrEraserSize)) {
          strokesToRemove.add(stroke);
        }
        continue;
      }

      // 对于普通stroke，检查每个点是否在橡皮擦范围内
      if (stroke.points.isEmpty) {
        continue;
      }

      final erasedPoints = List<bool>.filled(stroke.points.length, false);
      bool hasErasedPoint = false;

      // 标记被擦除的点
      for (int j = 0; j < stroke.points.length; j++) {
        final point = stroke.points[j];
        final dx = point.dx - position.dx;
        final dy = point.dy - position.dy;
        final sqrDistance = dx * dx + dy * dy;
        final adjustedSqrSize =
            sqrEraserSize + (stroke.strokeWidth * stroke.strokeWidth);

        if (sqrDistance <= adjustedSqrSize) {
          erasedPoints[j] = true;
          hasErasedPoint = true;
        }
      }

      // 如果没有被擦除的点，跳过
      if (!hasErasedPoint) {
        continue;
      }

      // 分割stroke：将未被擦除的部分提取为新的stroke片段
      final segments = <List<Offset>>[];
      List<Offset>? currentSegment;

      for (int j = 0; j < stroke.points.length; j++) {
        if (!erasedPoints[j]) {
          // 未被擦除的点，添加到当前片段
          currentSegment ??= [];
          currentSegment.add(stroke.points[j]);
        } else {
          // 被擦除的点，结束当前片段（如果存在）
          if (currentSegment != null && currentSegment.length >= 2) {
            segments.add(currentSegment);
            currentSegment = null;
          } else if (currentSegment != null) {
            // 片段太短，丢弃
            currentSegment = null;
          }
        }
      }

      // 添加最后一个片段（如果存在）
      if (currentSegment != null && currentSegment.length >= 2) {
        segments.add(currentSegment);
      }

      // 如果所有点都被擦除，或者没有有效的片段，删除整个stroke
      if (segments.isEmpty) {
        strokesToRemove.add(stroke);
      } else if (segments.length == 1 &&
          segments[0].length == stroke.points.length) {
        // 如果没有实际分割（所有点都在同一个片段中），不需要分割
        // 这种情况可能发生在边界情况，保持原样
        continue;
      } else {
        // 创建新的stroke片段
        for (final segmentPoints in segments) {
          if (segmentPoints.length >= 2) {
            final newStroke = Stroke(
              points: segmentPoints,
              color: stroke.color,
              strokeWidth: stroke.strokeWidth,
              toolId: stroke.toolId,
              pressureEnabled: stroke.pressureEnabled,
            );
            strokesToAdd.add(newStroke);
          }
        }
        strokesToRemove.add(stroke);
      }
    }

    // 执行删除和添加操作
    if (strokesToRemove.isNotEmpty || strokesToAdd.isNotEmpty) {
      // ✅ 记录擦除操作到历史记录
      _history.recordChange(EditorHistoryItem.erase(
        pageIndex: targetPageIndex,
        deletedStrokes: List<Stroke>.from(strokesToRemove),
      ));

      // 如果有新添加的stroke，记录绘制操作
      if (strokesToAdd.isNotEmpty) {
        _history.recordChange(EditorHistoryItem.draw(
          pageIndex: targetPageIndex,
          strokes: List<Stroke>.from(strokesToAdd),
        ));
      }

      _updateUndoRedoState();

      final pageNotifier = _pageNotifiers[targetPageIndex];

      // 删除被擦除的stroke
      if (strokesToRemove.isNotEmpty) {
        pageNotifier.removeStrokes(strokesToRemove);
      }

      // 添加分割后的stroke片段
      if (strokesToAdd.isNotEmpty) {
        final newStrokes = List<Stroke>.from(pageNotifier.page.strokes)
          ..addAll(strokesToAdd);
        pageNotifier.updateStrokes(newStrokes);
      }

      // 同步更新核心数据结构
      try {
        _coreInfo.pages[targetPageIndex] = pageNotifier.page;
      } catch (e) {
        debugPrint(
            '🦋[HandwritingSaber] Warning: failed to sync _coreInfo.pages[$targetPageIndex]: $e');
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
        final adjustedSqrSize =
            sqrEraserSize + (stroke.strokeWidth * stroke.strokeWidth);
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
      final adjustedSqrSize =
          sqrEraserSize + (stroke.strokeWidth * stroke.strokeWidth);
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

    // ✅ 如果是PDF文本选择工具，更新PDF文本选择
    if (_currentToolNotifier.value.toolId == ToolId.pdfTextSelect) {
      _updatePdfTextSelection(position);
      return;
    }

    // 如果是橡皮擦，根据模式处理
    if (_currentToolNotifier.value.toolId == ToolId.eraser) {
      final eraserTool = _currentToolNotifier.value as Eraser;
      if (eraserTool.mode == EraserMode.whiteout) {
        // 涂白模式：更新白色stroke路径
        final stroke = _currentStrokeNotifier.value;
        if (stroke != null) {
          stroke.points.add(position);
          _currentStrokeNotifier.value = stroke; // 触发重绘
        }
      } else {
        // 标准模式和删除笔画模式：继续检测并删除相交的笔迹
        _eraseStrokesAtPosition(position,
            pageIndex: _currentPageIndexNotifier.value);
      }
      return;
    }

    final Stroke? stroke = _currentStrokeNotifier.value;
    debugPrint(
        '🦋[HandwritingSaber] _updateStroke: position=$position, tool=${_currentToolNotifier.value.toolId}, hasCurrentStroke=${stroke != null}');
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
      // 如果是激光笔，记录点间延迟与计时器
      if (stroke.toolId == ToolId.laserPointer &&
          _laserStrokeStopwatches.containsKey(stroke)) {
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
        debugPrint(
            '🔶🔶🔶 [_updateStroke] Second point: $position, start=${stroke.points.first}');
      } else {
        // 已经有2个点，更新第二个点
        originalPoints = [stroke.points.first, position];
        debugPrint(
            '🔶🔶🔶 [_updateStroke] Updated end: $position, start=${stroke.points.first}');
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
      if (stroke.toolId == ToolId.laserPointer &&
          _laserStrokeStopwatches.containsKey(stroke)) {
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
      Offset startPoint = _shapeStartPoint ??
          (stroke.points.isNotEmpty ? stroke.points.first : position);
      originalPoints = [startPoint, position];
      debugPrint(
          '🔶🔶🔶 [_updateStroke] Shape tool: start=$startPoint (saved=${_shapeStartPoint != null}), end=$position');
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
        debugPrint(
            '🎨 [HandwritingSaber] Creating ArrowLineStroke: arrowStyle=${_arrowStyleNotifier.value}');
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
        debugPrint(
            '🔷🔷🔷 [_updateStroke] Creating RectangleStroke: start=${originalPoints.first}, end=${originalPoints.last}');
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
          debugPrint(
              '🔷🔷🔷 [_updateStroke] RectangleStroke created: rect=${newStroke.rect}, isEmpty=${newStroke.rect.isEmpty}');
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
        debugPrint(
            '🔷🔷🔷 [_updateStroke] Creating CircleStroke: start=${originalPoints.first}, end=${originalPoints.last}');
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
        debugPrint(
            '🔷🔷🔷 [_updateStroke] Creating DiamondStroke: start=${originalPoints.first}, end=${originalPoints.last}');
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
        _laserStrokePointDelays[newStroke] =
            _laserStrokePointDelays.remove(oldStrokeRef)!;
      }
      if (_laserStrokeStopwatches.containsKey(oldStrokeRef)) {
        _laserStrokeStopwatches[newStroke] =
            _laserStrokeStopwatches.remove(oldStrokeRef)!;
      }
    } catch (_) {
      // 忽略意外情况，保持原有行为
    }
  }

  /// ✅ 更新选择
  void _updateSelection(Offset position) {
    if (_selectResult == null) {
      return;
    }

    // ✅ 如果已经完成选择（点击选择或拖拽选择完成），则移动选中的对象
    if (!_isSelecting &&
        _selectResult!.pageIndex == (_currentPageIndexNotifier.value ?? 0) &&
        !_selectResult!.isEmpty) {
      // ✅ 修复移动偏移问题：如果 _selectStartPosition 为 null 或距离太远，说明是框选结束后的第一次移动
      // 应该重置为当前鼠标位置，避免瞬间偏移
      if (_selectStartPosition == null ||
          (_selectStartPosition != null &&
              (position - _selectStartPosition!).distance > 100)) {
        // 框选结束后的第一次移动，重置起始位置为当前鼠标位置
        _selectStartPosition = position;
        return; // 第一次移动不执行实际移动，只重置起始位置
      }

      final offset = position - _selectStartPosition!;
      if (offset.distance > 1.0) {
        // 只有移动距离大于1像素才移动
        final int oldPageIndex = _selectResult!.pageIndex;
        _selectResult!.move(offset);
        _selectStartPosition = position;

        // ✅ 跨页检测：检查选中对象的中心点是否已经移出当前页面
        final boundingBox = _selectResult!.getBoundingBox();
        if (boundingBox != null) {
          final center = boundingBox.center;
          // 检查是否移出了当前页面边界 (0..pageWidth, 0..pageHeight)
          final currentPage = _coreInfo.pages[oldPageIndex];
          if (center.dy < 0 ||
              center.dy > currentPage.size.height ||
              center.dx < 0 ||
              center.dx > currentPage.size.width) {
            // 中心点移出了当前页面，计算全局偏移量
            // 获取当前页面在整个滚动视图中的 top 偏移
            double oldPageTop = 0;
            for (int i = 0; i < oldPageIndex; i++) {
              oldPageTop += _coreInfo.pages[i].size.height + 16;
            }

            final globalY = oldPageTop + center.dy;

            // 寻找新页面
            int newPageIndex = -1;
            double accumulatedHeight = 0;
            for (int i = 0; i < _coreInfo.pages.length; i++) {
              final h = _coreInfo.pages[i].size.height;
              if (globalY >= accumulatedHeight &&
                  globalY <= accumulatedHeight + h) {
                newPageIndex = i;
                break;
              }
              accumulatedHeight += h + 16;
            }

            // 如果找到了新页面，且不是当前页面，则执行跨页移动
            if (newPageIndex != -1 && newPageIndex != oldPageIndex) {
              debugPrint(
                  '🦋[HandwritingSaber] Cross-page movement detected: $oldPageIndex -> $newPageIndex');

              final oldPage = _coreInfo.pages[oldPageIndex];
              final newPage = _coreInfo.pages[newPageIndex];

              // 计算从旧页面到新页面的坐标转换偏移
              double newPageTop = 0;
              for (int i = 0; i < newPageIndex; i++) {
                newPageTop += _coreInfo.pages[i].size.height + 16;
              }
              final pageToPageOffset = Offset(0, oldPageTop - newPageTop);

              // 1. 从旧页面移除对象并添加到新页面
              // 处理笔迹
              for (final stroke in _selectResult!.strokes) {
                oldPage.strokes.remove(stroke);
                // 转换坐标到新页面
                for (int i = 0; i < stroke.points.length; i++) {
                  stroke.points[i] += pageToPageOffset;
                }
                newPage.strokes.add(stroke);
              }

              // 处理常规图片
              for (final image in _selectResult!.regularImages) {
                oldPage.images.remove(image);
                if (image.dstRect != null) {
                  image.dstRect = image.dstRect!.shift(pageToPageOffset);
                }
                newPage.images.add(image);
              }

              // 处理 PDF 背景图片
              for (final image in _selectResult!.images) {
                if (oldPage.backgroundImage == image) {
                  // 背景图在 EditorPage 中通常是 final 或特有字段，
                  // 跨页移动背景图可能需要更复杂的逻辑，这里暂时支持其坐标转换
                  if (image.dstRect != null) {
                    image.dstRect = image.dstRect!.shift(pageToPageOffset);
                  }
                  // 注意：EditorPage 的 backgroundImage 可能需要特殊处理
                }
              }

              // 处理 WebView
              for (final webView in _selectResult!.webViews) {
                oldPage.webViews.remove(webView);
                webView.dstRect = webView.dstRect.shift(pageToPageOffset);
                newPage.webViews.add(webView);
              }

              // 处理文本框
              for (final textBox in _selectResult!.textBoxes) {
                oldPage.textBoxes.remove(textBox);
                textBox.move(pageToPageOffset);
                newPage.textBoxes.add(textBox);
              }

              // 2. 更新选择结果的页面索引和路径
              _selectResult!.pageIndex = newPageIndex;
              _selectResult!.selectionPath =
                  _selectResult!.selectionPath.shift(pageToPageOffset);

              // 3. 更新 notifier
              _pageNotifiers[oldPageIndex].updatePage(oldPage);
              _pageNotifiers[newPageIndex].updatePage(newPage);

              // 4. 更新 _selectStartPosition 以适应新页面的坐标系
              _selectStartPosition = _selectStartPosition! + pageToPageOffset;
            }
          }
        }

        // 只通知受影响页面的 notifier
        final int targetPageIndex = _selectResult!.pageIndex;
        if (targetPageIndex < _pageNotifiers.length) {
          _pageNotifiers[targetPageIndex]
              .updatePage(_coreInfo.pages[targetPageIndex]);
        }
        // 如果跨页了，还需要更新旧页面
        if (oldPageIndex != targetPageIndex &&
            oldPageIndex < _pageNotifiers.length) {
          _pageNotifiers[oldPageIndex]
              .updatePage(_coreInfo.pages[oldPageIndex]);
        }

        _scheduleSave();
      }
      return;
    }

    // ✅ 更新选择路径（拖拽选择区域）
    if (_isSelecting) {
      final int targetPageIndex = _selectResult!.pageIndex;

      if (_selectResult!.selectMode == SelectMode.rectangle) {
        // ✅ 矩形框选模式：只更新终点
        _selectResult!.selectionEndPoint = position;
      } else if (_selectResult!.selectMode == SelectMode.lasso) {
        // ✅ 套索选择模式：继续添加路径点
        _selectResult!.selectionPath.lineTo(position.dx, position.dy);
      }

      // 仅通知当前页面以触发局部重建
      if (targetPageIndex < _pageNotifiers.length) {
        _pageNotifiers[targetPageIndex]
            .updatePage(_coreInfo.pages[targetPageIndex]);
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
      bool shouldDetect = false;

      // ✅ 根据选择模式判断选择区域是否足够大
      if (_selectResult!.selectMode == SelectMode.rectangle) {
        // ✅ 矩形框选模式：检查起点和终点之间的距离
        final startPoint = _selectResult!.selectionStartPoint;
        final endPoint = _selectResult!.selectionEndPoint;
        if (startPoint != null && endPoint != null) {
          final rect = Rect.fromPoints(startPoint, endPoint);
          shouldDetect = rect.width.abs() > 5 || rect.height.abs() > 5;
        }
      } else if (_selectResult!.selectMode == SelectMode.lasso) {
        // ✅ 套索选择模式：检查路径边界框的大小
        final bounds = _selectResult!.selectionPath.getBounds();
        shouldDetect = bounds.width > 5 || bounds.height > 5;
        if (shouldDetect) {
          _selectResult!.selectionPath.close();
        }
      }

      if (shouldDetect) {
        // 只有选择区域足够大时才检测（避免误触）
        _detectObjectsInSelection(_selectResult!);
        final int targetPageIndex = _selectResult!.pageIndex;
        _isSelecting = false;
        // ✅ 修复移动偏移问题：框选结束后，重置 _selectStartPosition 为 null
        // 这样在第一次移动时，会重置为当前鼠标位置，避免瞬间偏移
        _selectStartPosition = null;
        if (targetPageIndex < _pageNotifiers.length) {
          _pageNotifiers[targetPageIndex]
              .updatePage(_coreInfo.pages[targetPageIndex]);
        }
        _scheduleSave();
      } else {
        // ✅ 选择区域太小，取消选择（只通知受影响页面）
        final int? prevPageIndex = _selectResult?.pageIndex;
        _selectResult = null;
        _isSelecting = false;
        _selectStartPosition = null;
        if (prevPageIndex != null && prevPageIndex < _pageNotifiers.length) {
          _pageNotifiers[prevPageIndex]
              .updatePage(_coreInfo.pages[prevPageIndex]);
        }
      }
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

  void _deleteSelectedObjects() {
    if (_selectResult == null || _selectResult!.isEmpty) {
      debugPrint('🦋[HandwritingSaber] _deleteSelectedObjects: 没有选中的对象');
      return;
    }

    final pageIndex = _selectResult!.pageIndex;
    if (pageIndex < 0 || pageIndex >= _coreInfo.pages.length) return;

    final page = _coreInfo.pages[pageIndex];
    final deletedStrokes = List<Stroke>.from(_selectResult!.strokes);
    final deletedPdfImages = List<PdfEditorImage>.from(_selectResult!.images);
    final deletedRegularImages =
        List<EditorImage>.from(_selectResult!.regularImages); // ✅ 常规图片
    final deletedTextBoxes =
        List<saber_text.TextBox>.from(_selectResult!.textBoxes); // ✅ 删除的文本框列表

    bool pageStructureChanged = false;

    // 删除笔迹
    for (final stroke in deletedStrokes) {
      page.strokes.remove(stroke);
    }

    // 删除常规图片
    for (final image in deletedRegularImages) {
      page.images.remove(image);
      pageStructureChanged = true;
    }

    // 删除 PDF 背景图片
    PdfEditorImage? newBackgroundImage = page.backgroundImage;
    for (final image in deletedPdfImages) {
      if (page.backgroundImage == image) {
        newBackgroundImage = null;
        pageStructureChanged = true;
      }
    }

    // ✅ 删除文本框
    for (final textBox in deletedTextBoxes) {
      page.textBoxes.remove(textBox);
      textBox.dispose();
      pageStructureChanged = true;
    }

    // 如果背景图片、常规图片或文本框被删除，触发页面重构（如果 EditorPage 是不可变的）
    // 这里的实现根据 EditorPage 是否允许直接修改列表而定。
    // 如果需要创建新页面对象：
    if (pageStructureChanged) {
      final updatedPage = EditorPage(
        size: page.size,
        strokes: page.strokes,
        backgroundImage: newBackgroundImage,
        images: page.images,
        textBoxes: page.textBoxes,
        listBoxes: page.listBoxes,
        taskListBoxes: page.taskListBoxes,
        quill: page.quill,
      );
      _coreInfo.pages[pageIndex] = updatedPage;
    }

    // 记录到历史（支持撤销）
    _history.recordChange(EditorHistoryItem.delete(
      pageIndex: pageIndex,
      deletedStrokes: deletedStrokes,
      deletedTextBoxes: deletedTextBoxes, // ✅ 记录删除的文本框
    ));
    _updateUndoRedoState();

    // 清除选择状态
    _selectResult = null;

    // 更新UI
    if (pageIndex < _pageNotifiers.length) {
      _pageNotifiers[pageIndex].updatePage(_coreInfo.pages[pageIndex]);
    }

    // 保存
    _scheduleSave();

    // 显示提示
    final deletedCount = deletedStrokes.length +
        deletedPdfImages.length +
        deletedRegularImages.length +
        deletedTextBoxes.length;
    if (mounted && deletedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除 $deletedCount 个对象')),
      );
    }

    debugPrint(
        '🦋[HandwritingSaber] _deleteSelectedObjects: 删除了 ${deletedStrokes.length} 笔迹, ${deletedPdfImages.length} PDF背景, ${deletedRegularImages.length} 常规图片, ${deletedTextBoxes.length} 文本框');
  }

  /// ✅ 复制选中的对象到剪贴板
  void _copySelectedObjects() {
    if (_selectResult == null || _selectResult!.isEmpty) {
      debugPrint('🦋[HandwritingSaber] _copySelectedObjects: 没有选中的对象');
      return;
    }

    // 深拷贝笔迹到剪贴板
    _clipboardStrokes = _selectResult!.strokes.map((stroke) {
      // 深拷贝笔迹的点
      final copiedPoints = List<Offset>.from(stroke.points);
      return Stroke(
        points: copiedPoints,
        color: stroke.color,
        strokeWidth: stroke.strokeWidth,
        toolId: stroke.toolId,
        pressureEnabled: stroke.pressureEnabled,
      );
    }).toList();

    // 深拷贝图片到剪贴板
    _clipboardImages = List<PdfEditorImage>.from(_selectResult!.images);
    _clipboardRegularImages =
        List<EditorImage>.from(_selectResult!.regularImages); // ✅ 复制常规图片

    // 记录源页面索引
    _clipboardSourcePageIndex = _selectResult!.pageIndex;

    // 显示提示
    final copiedCount = _clipboardStrokes!.length + _clipboardImages!.length;
    if (mounted && copiedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已复制 $copiedCount 个对象')),
      );
    }

    debugPrint(
        '🦋[HandwritingSaber] _copySelectedObjects: 复制了 ${_clipboardStrokes!.length} 个笔迹，${_clipboardImages!.length} 个图片');
  }

  /// ✅ 粘贴剪贴板中的对象
  void _pasteObjects() {
    if (_clipboardStrokes == null &&
        _clipboardImages == null &&
        _clipboardRegularImages == null) {
      debugPrint('🦋[HandwritingSaber] _pasteObjects: 剪贴板为空');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('剪贴板为空')),
        );
      }
      return;
    }

    // 默认粘贴到第一个页面（可以优化为当前可见页面）
    final targetPageIndex = 0;
    if (targetPageIndex >= _coreInfo.pages.length) return;

    final page = _coreInfo.pages[targetPageIndex];
    final pastedStrokes = <Stroke>[];

    // 粘贴偏移量（避免完全重叠）
    const pasteOffset = Offset(20, 20);

    // 粘贴笔迹
    if (_clipboardStrokes != null) {
      for (final clipboardStroke in _clipboardStrokes!) {
        // 深拷贝并偏移
        final pastedPoints =
            clipboardStroke.points.map((p) => p + pasteOffset).toList();

        final pastedStroke = Stroke(
          points: pastedPoints,
          color: clipboardStroke.color,
          strokeWidth: clipboardStroke.strokeWidth,
          toolId: clipboardStroke.toolId,
          pressureEnabled: clipboardStroke.pressureEnabled,
        );

        page.strokes.add(pastedStroke);
        pastedStrokes.add(pastedStroke);
      }
    }

    // 粘贴常规图片
    if (_clipboardRegularImages != null) {
      for (final image in _clipboardRegularImages!) {
        // 克隆图片并平移
        EditorImage? pastedImage;
        if (image is PngEditorImage) {
          pastedImage = PngEditorImage(
            id: DateTime.now().millisecondsSinceEpoch.toString() + image.id,
            imageBytes: image.imageBytes,
            extension: image.extension,
            pageIndex: targetPageIndex,
            pageSize: page.size,
            dstRect: image.dstRect?.shift(pasteOffset),
          );
        } else if (image is SvgEditorImage) {
          pastedImage = SvgEditorImage(
            id: DateTime.now().millisecondsSinceEpoch.toString() + image.id,
            svgString: image.svgString,
            pageIndex: targetPageIndex,
            pageSize: page.size,
            dstRect: image.dstRect?.shift(pasteOffset),
          );
        }

        if (pastedImage != null) {
          page.images.add(pastedImage);
        }
      }
    }

    if (pastedStrokes.isNotEmpty) {
      // 记录到历史
      _history.recordChange(EditorHistoryItem.draw(
        pageIndex: targetPageIndex,
        strokes: pastedStrokes,
      ));
      _updateUndoRedoState();

      // 更新UI
      if (targetPageIndex < _pageNotifiers.length) {
        _pageNotifiers[targetPageIndex].updatePage(page);
      }

      // 保存
      _scheduleSave();

      // 显示提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已粘贴 ${pastedStrokes.length} 个对象')),
        );
      }

      debugPrint(
          '🦋[HandwritingSaber] _pasteObjects: 粘贴了 ${pastedStrokes.length} 个笔迹');
    }
  }

  /// ✅ 显示选中对象的右键菜单
  Future<void> _showSelectionContextMenu(
      BuildContext context, Offset globalPosition) async {
    final RenderBox? overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    // 判断是否有剪贴板内容
    final hasClipboard = _clipboardStrokes != null || _clipboardImages != null;

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem<String>(
          value: 'bring_to_front',
          child: Row(
            children: [
              Icon(Icons.vertical_align_top, size: 20),
              SizedBox(width: 8),
              Text('置于顶层'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'bring_forward',
          child: Row(
            children: [
              Icon(Icons.arrow_upward, size: 20),
              SizedBox(width: 8),
              Text('上移一层'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'send_backward',
          child: Row(
            children: [
              Icon(Icons.arrow_downward, size: 20),
              SizedBox(width: 8),
              Text('下移一层'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'send_to_back',
          child: Row(
            children: [
              Icon(Icons.vertical_align_bottom, size: 20),
              SizedBox(width: 8),
              Text('置于底层'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'copy',
          child: Row(
            children: [
              Icon(Icons.copy, size: 20),
              SizedBox(width: 8),
              Text('复制'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'paste',
          enabled: hasClipboard,
          child: Row(
            children: [
              Icon(Icons.paste,
                  size: 20, color: hasClipboard ? null : Colors.grey),
              const SizedBox(width: 8),
              Text('粘贴',
                  style: TextStyle(color: hasClipboard ? null : Colors.grey)),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, size: 20),
              SizedBox(width: 8),
              Text('删除'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'cancel',
          child: Row(
            children: [
              Icon(Icons.clear, size: 20),
              SizedBox(width: 8),
              Text('取消选择'),
            ],
          ),
        ),
      ],
    );

    if (result == 'bring_to_front') {
      _reorderSelectedObjects(ReorderAction.bringToFront);
    } else if (result == 'bring_forward') {
      _reorderSelectedObjects(ReorderAction.bringForward);
    } else if (result == 'send_backward') {
      _reorderSelectedObjects(ReorderAction.sendBackward);
    } else if (result == 'send_to_back') {
      _reorderSelectedObjects(ReorderAction.sendToBack);
    } else if (result == 'copy') {
      _copySelectedObjects();
    } else if (result == 'paste') {
      _pasteObjects();
    } else if (result == 'delete') {
      _deleteSelectedObjects();
    } else if (result == 'cancel') {
      _clearSelection();
    }
  }

  /// ✅ 创建文本框（直接在画布上编辑，不弹出对话框）
  void _createTextBox(Offset position, {int? pageIndex}) {
    debugPrint(
        '🦋[HandwritingSaber] _createTextBox called: position=$position, pageIndex=$pageIndex');
    final pageIdx = pageIndex ?? 0;
    if (pageIdx < 0 || pageIdx >= _coreInfo.pages.length) {
      debugPrint(
          '🦋[HandwritingSaber] _createTextBox: invalid pageIdx=$pageIdx, pages.length=${_coreInfo.pages.length}');
      return;
    }

    final page = _coreInfo.pages[pageIdx];
    debugPrint(
        '🦋[HandwritingSaber] _createTextBox: page.textBoxes.length=${page.textBoxes.length}');

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

    // ✅ 创建新文本框（单行输入，默认宽度，高度根据字体大小自动计算）
    final textStyle = TextStyle(
      fontSize: 16,
      color: _currentToolNotifier.value.color,
    );
    final textBox = saber_text.TextBox(
      id: 'textbox_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(1000)}',
      position: position,
      size: const Size(200, 24), // ✅ 单行输入框：默认宽度200，高度24（会在编辑时自动调整）
      text: '',
      textStyle: textStyle,
      textBoxType: textBoxType, // ✅ 设置文本框类型
      quillContent: QuillStruct.createDefault(), // ✅ 创建 Quill 富文本编辑器（用于数据存储）
    );

    // ✅ 应用标题样式
    if (textBoxType != saber_text.TextBoxType.normal) {
      textBox.textStyle =
          textBox.getHeadingStyle(_currentToolNotifier.value.color);
    }

    // ✅ 关键修复：根据文本框类型和 lineHeight 计算字体大小，并显式设置到 Quill Document
    final double lineHeight = _coreInfo.lineHeight.toDouble();
    double fontSize;
    switch (textBoxType) {
      case saber_text.TextBoxType.heading1:
        fontSize = lineHeight * 1.15;
        break;
      case saber_text.TextBoxType.heading2:
        fontSize = lineHeight * 1.0;
        break;
      case saber_text.TextBoxType.heading3:
        fontSize = lineHeight * 0.9;
        break;
      case saber_text.TextBoxType.paragraph:
      case saber_text.TextBoxType.normal:
        fontSize = lineHeight * 0.7;
        break;
    }
    // ✅ 显式设置 Quill Document 的字体大小属性，确保编辑和渲染时一致
    textBox.quillContent.ensureFontSize(fontSize);

    // ✅ 添加到页面并进入编辑模式（使用EditorPageNotifier避免全局setState）
    debugPrint(
        '🦋[HandwritingSaber] _createTextBox: adding textBox id=${textBox.id} to page, position=${textBox.position}, size=${textBox.size}');

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
    debugPrint(
        '🦋[HandwritingSaber] _createTextBox: completed, _editingTextBoxId=${_editingTextBoxIdNotifier.value}, page.textBoxes.length=${updatedPage.textBoxes.length}');
  }

  /// ✅ 查找点击位置的文本框
  saber_text.TextBox? _findTextBoxAtPosition(Offset position, int pageIndex) {
    if (_coreInfo.pages.isEmpty ||
        pageIndex < 0 ||
        pageIndex >= _coreInfo.pages.length) {
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
      debugPrint(
          '🦋[HandwritingSaber] _editTextBox: textBox not found in any page');
      return;
    }

    // ✅ 确保 Quill 内容已初始化（如果为空则从 text 字段初始化）
    if (textBox.quillContent.plainText.trim().isEmpty &&
        textBox.text.isNotEmpty) {
      textBox.quillContent.clear();
      textBox.quillContent.insertText(textBox.text);
    }

    // ✅ 关键修复：确保 Quill Document 中显式设置字体大小属性
    // 根据文本框类型和 lineHeight 计算字体大小
    final double lineHeight = _coreInfo.lineHeight.toDouble();
    double fontSize;
    switch (textBox.textBoxType) {
      case saber_text.TextBoxType.heading1:
        fontSize = lineHeight * 1.15;
        break;
      case saber_text.TextBoxType.heading2:
        fontSize = lineHeight * 1.0;
        break;
      case saber_text.TextBoxType.heading3:
        fontSize = lineHeight * 0.9;
        break;
      case saber_text.TextBoxType.paragraph:
      case saber_text.TextBoxType.normal:
        fontSize = lineHeight * 0.7;
        break;
    }
    // ✅ 显式设置 Quill Document 的字体大小属性，确保编辑和渲染时一致
    textBox.quillContent.ensureFontSize(fontSize);

    // ✅ 进入编辑模式（使用ValueNotifier，不触发全局setState）
    _editingTextBoxIdNotifier.value = textBox.id;

    // ✅ 请求焦点
    textBox.quillContent.focusNode.requestFocus();
  }

  /// ✅ 结束文本框编辑（使用ValueNotifier，不触发全局setState）
  void _endTextBoxEditing() {
    _editingTextBoxIdNotifier.value = null;
  }

  /// ✅ 获取当前活动的 Quill 结构（可能来自页面的全局富文本编辑器或文本框）
  QuillStruct? _getActiveQuillStruct() {
    // ✅ 优先返回正在编辑的文本框的 Quill 结构
    final editingTextBoxId = _editingTextBoxIdNotifier.value;
    if (editingTextBoxId != null) {
      // 查找正在编辑的文本框
      for (final page in _coreInfo.pages) {
        for (final textBox in page.textBoxes) {
          if (textBox.id == editingTextBoxId) {
            return textBox.quillContent;
          }
        }
      }
    }

    // ✅ 如果没有正在编辑的文本框，返回页面的全局 Quill 结构（用于全页面富文本编辑模式）
    final quillFocusPageIndex = _quillFocusPageIndexNotifier.value;
    if (quillFocusPageIndex != null &&
        quillFocusPageIndex < _coreInfo.pages.length) {
      return _coreInfo.pages[quillFocusPageIndex].quill;
    }

    return null;
  }

  /// ✅ 构建文本框编辑器（直接在画布上显示，单行输入，透明背景）
  Widget _buildTextBoxEditor(
    saber_text.TextBox textBox,
    int pageIndex,
    double screenWidth,
    double pageDisplayWidth,
    double pageDisplayHeight,
  ) {
    debugPrint(
        '🦋[HandwritingSaber] _buildTextBoxEditor called: textBox.id=${textBox.id}, pageIndex=$pageIndex');
    debugPrint(
        '🦋[HandwritingSaber] _buildTextBoxEditor: screenWidth=$screenWidth, pageDisplayWidth=$pageDisplayWidth, pageDisplayHeight=$pageDisplayHeight');

    // ✅ 计算页面缩放和偏移（与 _buildSinglePageCanvas 保持一致）
    final page = _coreInfo.pages[pageIndex];

    // ✅ 防止无效的页面尺寸
    if (page.size.width <= 0 || page.size.height <= 0) {
      debugPrint(
          '❌[HandwritingSaber] _buildTextBoxEditor: Invalid page size: ${page.size}');
      return const SizedBox.shrink();
    }

    final double scale = pageDisplayWidth / page.size.width;
    // ✅ 检查scale有效性
    if (!scale.isFinite || scale <= 0) {
      debugPrint(
          '❌[HandwritingSaber] _buildTextBoxEditor: Invalid scale: $scale');
      return const SizedBox.shrink();
    }

    // 注意：offsetX 和 offsetY 应该与 _buildSinglePageCanvas 中的计算一致
    final double offsetX = (screenWidth - pageDisplayWidth) / 2;
    final double offsetY = 0; // 页面顶部对齐，与 _buildSinglePageCanvas 一致
    debugPrint(
        '🦋[HandwritingSaber] _buildTextBoxEditor: page.size=${page.size}, scale=$scale, offsetX=$offsetX, offsetY=$offsetY');

    // ✅ 计算文本框在屏幕上的位置
    final double textBoxLeft = offsetX + textBox.position.dx * scale;
    final double textBoxTop = offsetY + textBox.position.dy * scale;
    final double textBoxWidth = textBox.size.width * scale;

    // ✅ 单行输入框，使用固定高度（根据字体大小和缩放计算）
    // ✅ 关键修复：根据文本框类型和 lineHeight 计算字体大小，与 QuillEditor 保持一致
    final double lineHeight = _coreInfo.lineHeight.toDouble();
    double fontSize;
    switch (textBox.textBoxType) {
      case saber_text.TextBoxType.heading1:
        fontSize = lineHeight * 1.15; // 与 QuillEditor 的 displayLarge 一致
        break;
      case saber_text.TextBoxType.heading2:
        fontSize = lineHeight * 1.0; // 与 QuillEditor 的 displayMedium 一致
        break;
      case saber_text.TextBoxType.heading3:
        fontSize = lineHeight * 0.9; // 与 QuillEditor 的 displaySmall 一致
        break;
      case saber_text.TextBoxType.paragraph:
      case saber_text.TextBoxType.normal:
        fontSize = lineHeight * 0.7; // 与 QuillEditor 的 bodyLarge 一致
        break;
    }

    // ✅ 使用 textBox.textStyle 的颜色和其他属性，但覆盖字体大小
    final textStyle = (textBox.textStyle ??
            const TextStyle(
              color: Colors.black,
            ))
        .copyWith(fontSize: fontSize);

    final double scaledFontSize = fontSize * scale;
    // 单行输入框高度：字体大小 + 上下padding
    final double singleLineHeight = scaledFontSize + 8.0; // 上下各4px padding

    // ✅ 注意：不要在 build 阶段调用会修改 QuillController 状态的方法
    // 字体大小应该在 _createTextBox 或 _editTextBox 中设置
    // 在 build 阶段调用 ensureFontSize 会触发 notifyListeners
    // 导致 "setState() or markNeedsBuild() called during build" 错误

    // ✅ 监听 Quill 内容变化，同步到 TextBox 并动态调整宽度
    textBox.quillContent.controller.changes.listen((event) {
      if (_editingTextBoxIdNotifier.value == textBox.id) {
        // ✅ 同步纯文本到 text 字段（向后兼容）
        final newText = textBox.quillContent.plainText;
        textBox.text = newText;

        // ✅ 动态调整文本框宽度（根据文本内容）
        // 注意：这里使用页面坐标（未缩放），因为在数据模型中存储的是页面坐标
        final textPainter = TextPainter(
          text: TextSpan(
              text: newText, style: textStyle.copyWith(fontSize: fontSize)),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        final textWidth = textPainter.width;
        // 文本框宽度 = 文本宽度 + 左右padding（20px），最小100px，最大页面宽度
        final minWidth = 100.0;
        final maxWidth = page.size.width;
        final newWidth = (textWidth + 20.0).clamp(minWidth, maxWidth);
        // 更新 TextBox 尺寸（使用页面坐标）
        textBox.size = Size(newWidth, textBox.size.height);

        // ✅ 触发页面重建以更新编辑器显示
        if (mounted && pageIndex < _pageNotifiers.length) {
          final currentPage = _coreInfo.pages[pageIndex];
          final updatedPageForText = EditorPage(
            size: currentPage.size,
            strokes: currentPage.strokes,
            backgroundImage: currentPage.backgroundImage,
            textBoxes: currentPage.textBoxes,
            listBoxes: currentPage.listBoxes,
            taskListBoxes: currentPage.taskListBoxes,
          );
          _pageNotifiers[pageIndex].updatePage(updatedPageForText);
        }
        _scheduleSave();
      }
    });

    // ✅ 计算实际显示宽度（根据当前文本内容或文本框的尺寸）
    final currentText = textBox.quillContent.plainText;
    double displayWidth;
    if (currentText.isNotEmpty) {
      // 根据文本内容计算宽度（使用缩放后的字体大小）
      final textPainter = TextPainter(
        text: TextSpan(
            text: currentText,
            style: textStyle.copyWith(fontSize: scaledFontSize)),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      final textWidth = textPainter.width;
      final minWidth = 100.0;
      final maxWidth = page.size.width * scale;
      displayWidth = (textWidth + 20.0).clamp(minWidth, maxWidth);
    } else {
      // 使用文本框的当前宽度（已缩放）
      displayWidth = textBoxWidth.clamp(100.0, page.size.width * scale);
    }

    debugPrint(
        '🦋[HandwritingSaber] _buildTextBoxEditor: displayWidth=$displayWidth, singleLineHeight=$singleLineHeight');

    // ✅ 获取主题配置
    final colorScheme = Theme.of(context).colorScheme;
    final invert = false; // 可以根据需要从设置中读取

    return Positioned(
      left: textBoxLeft,
      top: textBoxTop,
      width: displayWidth,
      height: singleLineHeight,
      child: Material(
        color: Colors.transparent, // ✅ 透明背景
        child: ClipRect(
          // ✅ 使用 ClipRect 限制高度，防止文本超出单行高度
          child: SizedBox(
            height: singleLineHeight,
            child: quill.QuillEditor.basic(
              controller: textBox.quillContent.controller,
              config: quill.QuillEditorConfig(
                customStyles: HandwritingSaberQuillStyles.get(
                  invert: invert,
                  secondary: colorScheme.secondary,
                  lineHeight: _coreInfo.lineHeight,
                ),
                scrollable: false, // ✅ 禁用滚动（单行）
                autoFocus: true,
                expands: false, // ✅ 不扩展
                placeholder: null, // ✅ 不显示占位符
                padding: const EdgeInsets.symmetric(
                    horizontal: 2, vertical: 0), // ✅ 最小padding
              ),
              focusNode: textBox.quillContent.focusNode,
            ),
          ),
        ),
      ),
    );
  }

  /// ✅ 检测选择区域内的对象
  void _detectObjectsInSelection(SelectResult result) {
    final int pageIndex = result.pageIndex;
    if (pageIndex >= _coreInfo.pages.length) return;

    final page = _coreInfo.pages[pageIndex];
    result.strokes.clear();
    result.images.clear();
    result.webViews.clear();
    result.textBoxes.clear();

    if (result.selectMode == SelectMode.rectangle) {
      final rect = result.getSelectionRect();
      if (rect == null) return;

      // 检测笔迹
      for (final stroke in page.strokes) {
        // 检查任一点是否在矩形内
        for (final p in stroke.points) {
          if (rect.contains(p)) {
            result.strokes.add(stroke);
            break;
          }
        }
      }

      // 检测图片 (PDF背景图片)
      if (page.backgroundImage != null) {
        final image = page.backgroundImage!;
        if (image.dstRect != null && rect.overlaps(image.dstRect!)) {
          result.images.add(image);
        }
      }

      // 检测常规图片
      for (final image in page.images) {
        if (image.dstRect != null && rect.overlaps(image.dstRect!)) {
          result.regularImages.add(image);
        }
      }

      // 检测 WebView
      for (final webView in page.webViews) {
        if (rect.overlaps(webView.dstRect)) {
          result.webViews.add(webView);
        }
      }

      // 检测文本框
      for (final textBox in page.textBoxes) {
        if (rect.overlaps(textBox.rect)) {
          result.textBoxes.add(textBox);
        }
      }
    } else if (result.selectMode == SelectMode.lasso) {
      // 套索模式：使用 selectionPath 检测
      final path = result.selectionPath;

      // 检测笔迹
      for (final stroke in page.strokes) {
        for (final p in stroke.points) {
          if (path.contains(p)) {
            result.strokes.add(stroke);
            break;
          }
        }
      }

      // 检测图片 (PDF背景图片)
      if (page.backgroundImage != null) {
        final image = page.backgroundImage!;
        if (image.dstRect != null) {
          final r = image.dstRect!;
          if (path.contains(r.topLeft) ||
              path.contains(r.topRight) ||
              path.contains(r.bottomLeft) ||
              path.contains(r.bottomRight)) {
            result.images.add(image);
          }
        }
      }

      // 检测常规图片
      for (final image in page.images) {
        if (image.dstRect != null) {
          final r = image.dstRect!;
          if (path.contains(r.topLeft) ||
              path.contains(r.topRight) ||
              path.contains(r.bottomLeft) ||
              path.contains(r.bottomRight)) {
            result.regularImages.add(image);
          }
        }
      }

      // 检测 WebView
      for (final webView in page.webViews) {
        final r = webView.dstRect;
        if (path.contains(r.topLeft) ||
            path.contains(r.topRight) ||
            path.contains(r.bottomLeft) ||
            path.contains(r.bottomRight)) {
          result.webViews.add(webView);
        }
      }

      // 检测文本框
      for (final textBox in page.textBoxes) {
        final r = textBox.rect;
        if (path.contains(r.topLeft) ||
            path.contains(r.topRight) ||
            path.contains(r.bottomLeft) ||
            path.contains(r.bottomRight)) {
          result.textBoxes.add(textBox);
        }
      }
    }
  }

  /// ✅ 调整选中对象的层级
  void _reorderSelectedObjects(ReorderAction action) {
    if (_selectResult == null || _selectResult!.isEmpty) return;

    final int pageIndex = _selectResult!.pageIndex;
    if (pageIndex >= _coreInfo.pages.length) return;

    final page = _coreInfo.pages[pageIndex];

    // 分别处理笔迹和其它对象（图片、WebView、文本框）
    // 当前笔迹层在所有其它对象之上，所以只能在各自层级内调整

    // 1. 调整笔迹顺序
    if (_selectResult!.strokes.isNotEmpty) {
      final selectedStrokes = Set<Stroke>.from(_selectResult!.strokes);
      final list = List<Stroke>.from(page.strokes);

      _reorderInList(list, selectedStrokes, action);
      page.strokes.clear();
      page.strokes.addAll(list);
    }

    // 2. 调整常规图片顺序
    if (_selectResult!.regularImages.isNotEmpty) {
      final selectedImages =
          Set<EditorImage>.from(_selectResult!.regularImages);
      final list = List<EditorImage>.from(page.images);

      _reorderInList(list, selectedImages, action);
      page.images.clear();
      page.images.addAll(list);
    }

    // 3. 调整 WebView 顺序
    if (_selectResult!.webViews.isNotEmpty) {
      final selectedWebViews =
          Set<WebViewEditorElement>.from(_selectResult!.webViews);
      final list = List<WebViewEditorElement>.from(page.webViews);

      _reorderInList(list, selectedWebViews, action);
      page.webViews.clear();
      page.webViews.addAll(list);
    }

    // 4. 调整文本框顺序
    if (_selectResult!.textBoxes.isNotEmpty) {
      final selectedTextBoxes =
          Set<saber_text.TextBox>.from(_selectResult!.textBoxes);
      final list = List<saber_text.TextBox>.from(page.textBoxes);

      _reorderInList(list, selectedTextBoxes, action);
      page.textBoxes.clear();
      page.textBoxes.addAll(list);
    }

    // 更新UI
    _pageNotifiers[pageIndex].updatePage(page);
    _scheduleSave();
  }

  /// 通用的列表重排序逻辑
  void _reorderInList<T>(List<T> list, Set<T> selected, ReorderAction action) {
    if (selected.isEmpty) return;

    switch (action) {
      case ReorderAction.bringToFront:
        final selectedItems =
            list.where((item) => selected.contains(item)).toList();
        list.removeWhere((item) => selected.contains(item));
        list.addAll(selectedItems); // 移动到末尾（顶层）
        break;
      case ReorderAction.sendToBack:
        final selectedItems =
            list.where((item) => selected.contains(item)).toList();
        list.removeWhere((item) => selected.contains(item));
        list.insertAll(0, selectedItems); // 移动到开头（底层）
        break;
      case ReorderAction.bringForward:
        // 从后往前遍历，寻找可以选中的对象并上移
        for (int i = list.length - 2; i >= 0; i--) {
          if (selected.contains(list[i]) && !selected.contains(list[i + 1])) {
            final item = list.removeAt(i);
            list.insert(i + 1, item);
          }
        }
        break;
      case ReorderAction.sendBackward:
        // 从前往后遍历，下移
        for (int i = 1; i < list.length; i++) {
          if (selected.contains(list[i]) && !selected.contains(list[i - 1])) {
            final item = list.removeAt(i);
            list.insert(i - 1, item);
          }
        }
        break;
    }
  }

  Future<void> _endStroke() async {
    // ✅ 如果是PDF文本选择工具，结束PDF文本选择
    if (_currentToolNotifier.value.toolId == ToolId.pdfTextSelect) {
      await _endPdfTextSelection();
      return;
    }
    debugPrint('✍️✍️✍️ [HandwritingSaber] ===== _endStroke START =====');

    // ✅ 如果是选择工具，结束选择
    if (_currentToolNotifier.value.toolId == ToolId.select) {
      _endSelection();
      return;
    }

    // ✅ 如果是橡皮擦涂白模式，结束白色stroke
    if (_currentToolNotifier.value.toolId == ToolId.eraser) {
      final eraserTool = _currentToolNotifier.value as Eraser;
      if (eraserTool.mode == EraserMode.whiteout) {
        final whiteStroke = _currentStrokeNotifier.value;
        if (whiteStroke != null && whiteStroke.points.length >= 2) {
          final int targetPageIndex = _currentPageIndexNotifier.value ?? 0;
          if (targetPageIndex < _coreInfo.pages.length) {
            final page = _coreInfo.pages[targetPageIndex];
            page.strokes.add(whiteStroke);

            // ✅ 记录绘制操作到历史记录
            _history.recordChange(EditorHistoryItem.draw(
              pageIndex: targetPageIndex,
              strokes: [whiteStroke],
            ));
            _updateUndoRedoState();

            // 更新页面 notifier
            if (targetPageIndex < _pageNotifiers.length) {
              _pageNotifiers[targetPageIndex].updatePage(page);
            }
            _scheduleSave();
          }
        }
        _currentStrokeNotifier.value = null;
      }
      _currentPageIndexNotifier.value = null;
      return;
    }

    final Stroke? stroke = _currentStrokeNotifier.value;
    debugPrint(
        '✍️✍️✍️ [HandwritingSaber] Current stroke: ${stroke != null ? "exists, points=${stroke.points.length}" : "null"}');
    if (stroke == null || stroke.points.isEmpty) {
      _currentPageIndexNotifier.value = null;
      debugPrint('✍️✍️✍️ [HandwritingSaber] No valid stroke, returning');
      return;
    }

    debugPrint(
        '✍️✍️✍️ [HandwritingSaber] _coreInfo.pages.length: ${_coreInfo.pages.length}');
    if (_coreInfo.pages.isEmpty) {
      debugPrint('⚠️⚠️⚠️ [HandwritingSaber] Pages empty, creating default');
      _coreInfo = EditorCoreInfo.empty();
    }

    // ✅ 确保页面索引有效
    final int targetPageIndex = _currentPageIndexNotifier.value ?? 0;
    debugPrint(
        '✍️✍️✍️ [HandwritingSaber] Target pageIndex: $targetPageIndex, total pages: ${_coreInfo.pages.length}');
    if (targetPageIndex >= _coreInfo.pages.length) {
      debugPrint(
          '❌❌❌ [HandwritingSaber] INVALID PAGE INDEX! pageIndex=$targetPageIndex >= pages.length=${_coreInfo.pages.length}');
      debugPrint(
          '❌❌❌ [HandwritingSaber] Stroke LOST! Tool: ${stroke.toolId}, Points: ${stroke.points.length}');
      _currentPageIndexNotifier.value = null;
      return;
    }

    debugPrint(
        '✍️✍️✍️ [HandwritingSaber] Valid page index, using current stroke as final stroke');
    debugPrint(
        '✍️✍️✍️ [HandwritingSaber] Stroke type: ${stroke.runtimeType}, toolId: ${stroke.toolId}, points: ${stroke.points.length}');

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
      _laserStrokesNotifier.value =
          List<Stroke>.from(_laserStrokesNotifier.value)..add(laserStroke);
      // 从记录的点延迟中获取用于淡出的 timing（参考 Saber 的实现）
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
      debugPrint(
          '✍️✍️✍️ [HandwritingSaber] Using stroke directly: type=${stroke.runtimeType}');
    }

    // ✅ 保存完成的笔迹到正确的页面（finalStroke 在此处始终非空）
    debugPrint(
        '💾💾💾 [HandwritingSaber] Saving stroke to page $targetPageIndex, toolId=${finalStroke.toolId}, points=${finalStroke.points.length}');
    _coreInfo.pages[targetPageIndex].strokes.add(finalStroke);
    debugPrint(
        '💾💾💾 [HandwritingSaber] Page $targetPageIndex now has ${_coreInfo.pages[targetPageIndex].strokes.length} strokes');

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
      debugPrint(
          '💾💾💾 [HandwritingSaber] Page notifier $targetPageIndex updated');
    }

    // 清空 notifier 值，触发 CustomPainter 的局部重绘
    _currentStrokeNotifier.value = null;
    // 不触发父级重建，仅重置页面索引
    _currentPageIndexNotifier.value = null;
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

  // ==================== 视图缩放相关方法 ====================

  /// ✅ 放大视图
  void _zoomIn() {
    final currentZoom = _zoomLevelNotifier.value;
    // 找到下一个预设档位
    double newZoom = currentZoom + _zoomStep;
    // 对齐到预设档位（避免浮点数精度问题）
    for (final preset in _zoomPresets) {
      if (preset > currentZoom + 0.01) {
        newZoom = preset;
        break;
      }
    }
    _setZoomLevel(newZoom);
  }

  /// ✅ 缩小视图
  void _zoomOut() {
    final currentZoom = _zoomLevelNotifier.value;
    // 找到上一个预设档位
    double newZoom = currentZoom - _zoomStep;
    // 对齐到预设档位（从大到小查找）
    for (int i = _zoomPresets.length - 1; i >= 0; i--) {
      if (_zoomPresets[i] < currentZoom - 0.01) {
        newZoom = _zoomPresets[i];
        break;
      }
    }
    _setZoomLevel(newZoom);
  }

  /// ✅ 重置缩放到100%
  void _zoomReset() {
    _setZoomLevel(1.0);
  }

  /// ✅ 设置缩放级别（带范围限制）
  void _setZoomLevel(double zoom) {
    final clampedZoom = zoom.clamp(_minZoom, _maxZoom);
    if (_zoomLevelNotifier.value != clampedZoom) {
      _zoomLevelNotifier.value = clampedZoom;
      debugPrint(
          '🔍 [HandwritingSaber] Zoom level changed to: ${(clampedZoom * 100).toInt()}%');
    }
  }

  /// ✅ 处理鼠标滚轮缩放
  void _handleScrollZoom(double scrollDelta) {
    // scrollDelta > 0 表示向下滚动（缩小），< 0 表示向上滚动（放大）
    if (scrollDelta < 0) {
      _zoomIn();
    } else if (scrollDelta > 0) {
      _zoomOut();
    }
  }

  /// ✅ 获取缩放级别显示文本
  String _getZoomLevelText() {
    return '${(_zoomLevelNotifier.value * 100).toInt()}%';
  }

  /// ✅ 构建缩放级别指示器（右下角浮动按钮组）
  Widget _buildZoomIndicator(double zoomLevel) {
    final zoomPercent = (zoomLevel * 100).toInt();

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 缩小按钮
          IconButton(
            onPressed: zoomLevel > _minZoom ? _zoomOut : null,
            icon: const Icon(Icons.remove, size: 18),
            tooltip: '缩小 (Cmd/Ctrl + -)',
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
          ),
          // 缩放百分比显示（可点击重置）
          InkWell(
            onTap: _zoomReset,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                '$zoomPercent%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ),
          // 放大按钮
          IconButton(
            onPressed: zoomLevel < _maxZoom ? _zoomIn : null,
            icon: const Icon(Icons.add, size: 18),
            tooltip: '放大 (Cmd/Ctrl + +)',
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  // ==================== 结束视图缩放相关方法 ====================

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
          _pageNotifiers[item.pageIndex]
              .updatePage(_coreInfo.pages[item.pageIndex]);
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
            _pageNotifiers[item.pageIndex]
                .updatePage(_coreInfo.pages[item.pageIndex]);
          }
        }
        break;
      case EditorHistoryItemType.delete:
        // ✅ 撤销删除：恢复被删除的对象
        final page = _coreInfo.pages[item.pageIndex];
        bool pageUpdated = false;

        // 恢复被删除的笔迹
        if (item.deletedStrokes != null) {
          for (final stroke in item.deletedStrokes!) {
            page.strokes.add(stroke);
          }
          pageUpdated = true;
        }

        // ✅ 恢复被删除的文本框
        if (item.deletedTextBoxes != null) {
          for (final textBox in item.deletedTextBoxes!) {
            page.textBoxes.add(textBox);
          }
          pageUpdated = true;
        }

        // 更新页面 notifier
        if (pageUpdated && item.pageIndex < _pageNotifiers.length) {
          _pageNotifiers[item.pageIndex].updatePage(page);
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
          _pageNotifiers[item.pageIndex]
              .updatePage(_coreInfo.pages[item.pageIndex]);
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
            _pageNotifiers[item.pageIndex]
                .updatePage(_coreInfo.pages[item.pageIndex]);
          }
        }
        break;
      case EditorHistoryItemType.delete:
        // ✅ 恢复删除：重新删除对象
        final page = _coreInfo.pages[item.pageIndex];
        bool pageUpdated = false;

        // 重新删除笔迹
        if (item.deletedStrokes != null) {
          for (final stroke in item.deletedStrokes!) {
            page.strokes.remove(stroke);
          }
          pageUpdated = true;
        }

        // ✅ 重新删除文本框
        if (item.deletedTextBoxes != null) {
          for (final textBox in item.deletedTextBoxes!) {
            page.textBoxes.remove(textBox);
            textBox.dispose();
          }
          pageUpdated = true;
        }

        // 更新页面 notifier
        if (pageUpdated && item.pageIndex < _pageNotifiers.length) {
          _pageNotifiers[item.pageIndex].updatePage(page);
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
      debugPrint(
          '🦋[HandwritingSaber] _onToolChanged: 切换到文本工具: ${tool.toolId}');
    }

    // ✅ 切换工具：避免使用 setState 导致全量重建，改为仅通知受影响的页面 notifier
    if (tool.toolId == ToolId.select) {
      debugPrint(
          '🦋[HandwritingSaber] Switching to select tool, clearing selection');
      // 记录之前选择所在页面，之后仅刷新该页面的 notifier
      final int? prevPageIndex = _selectResult?.pageIndex;
      _selectResult = null;
      _isSelecting = false;
      _selectStartPosition = null;
      if (prevPageIndex != null && prevPageIndex < _pageNotifiers.length) {
        // 触发该页面局部重建以反映选择清除
        _pageNotifiers[prevPageIndex]
            .updatePage(_coreInfo.pages[prevPageIndex]);
      }
      // 更新当前工具（通过 notifier，不触发父级重建）
      _currentToolNotifier.value = tool;
    } else {
      // ✅ 切换到其他工具时，也清除选择状态（但只通知受影响页面）
      if (_currentToolNotifier.value.toolId == ToolId.select) {
        debugPrint(
            '🦋[HandwritingSaber] Switching away from select tool, clearing selection');
        final int? prevPageIndex = _selectResult?.pageIndex;
        _selectResult = null;
        _isSelecting = false;
        _selectStartPosition = null;
        if (prevPageIndex != null && prevPageIndex < _pageNotifiers.length) {
          _pageNotifiers[prevPageIndex]
              .updatePage(_coreInfo.pages[prevPageIndex]);
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
      final updated =
          (_currentToolNotifier.value as Pen).copyWith(color: color);
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
      _currentToolNotifier.value =
          (_currentToolNotifier.value as Pen).copyWith(strokeWidth: width);
    } else if (_currentToolNotifier.value is Eraser) {
      _currentToolNotifier.value =
          (_currentToolNotifier.value as Eraser).copyWith(strokeWidth: width);
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
    debugPrint(
        '📝 [HandwritingSaber] Toggling text editing mode: ${!_textEditingModeNotifier.value}');
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
      debugPrint(
          '❌[HandwritingSaber] _buildSinglePageCanvas: Invalid page size: ${page.size}, pageIndex=$pageIndex');
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
    final double offsetY = 0; // 页面顶部对齐

    // ✅ 额外检查：确保scale有效
    if (!scale.isFinite || scale <= 0) {
      debugPrint(
          '❌[HandwritingSaber] _buildSinglePageCanvas: Invalid scale: $scale, pageDisplayWidth=$pageDisplayWidth, page.size.width=${page.size.width}');
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
      // ✅ 添加右键菜单支持
      onSecondaryTapDown: (TapDownDetails details) {
        // 只在选择工具且有选中对象时显示菜单
        if (_currentToolNotifier.value.toolId == ToolId.select &&
            _selectResult != null &&
            !_selectResult!.isEmpty) {
          _showSelectionContextMenu(context, details.globalPosition);
        }
      },
      onPanStart: (DragStartDetails details) {
        // ✅ 如果正在操作图片，不处理
        if (_isImageOperationInProgress) {
          debugPrint('🦋[HandwritingSaber] onPanStart: 图片操作中，跳过');
          return;
        }

        // ✅ 只处理当前页面的触摸事件
        if (!isPointInPage(details.localPosition)) {
          // ✅ 点击在页面外，取消选择
          if (_currentToolNotifier.value.toolId == ToolId.select) {
            _clearSelection();
          }
          return;
        }
        final pagePos = toPageCoordinates(details.localPosition);
        debugPrint(
            '🦋[HandwritingSaber] onPanStart: local=${details.localPosition}, pagePos=$pagePos, pageIndex=$pageIndex, tool=${_currentToolNotifier.value.toolId}');

        // ✅ 检查是否点击在图片上
        final clickedImage = _findImageAtPosition(pagePos, pageIndex);
        if (clickedImage != null) {
          // ✅ 自动切换到选择工具
          if (_currentToolNotifier.value.toolId != ToolId.select) {
            _onToolChanged(const SelectTool(selectMode: SelectMode.click));
          }

          if (_selectedImageIdNotifier.value == clickedImage.id) {
            // 点击在已选中的图片上，让 CanvasImageWidget 处理拖动
            debugPrint(
                '🦋[HandwritingSaber] onPanStart: 点击已选中图片，交给 CanvasImageWidget 处理');
            _isImageOperationInProgress = true;
          } else {
            // 点击在未选中的图片上，选中该图片
            debugPrint('🦋[HandwritingSaber] onPanStart: 点击未选中图片，自动选中');
            _selectedImageIdNotifier.value = clickedImage.id;
            _isImageOperationInProgress = true;
          }
          return;
        }

        if (pagePos.dx.isFinite && pagePos.dy.isFinite) {
          // ✅ 如果点击在空白区域，结束文本框编辑
          if (_editingTextBoxIdNotifier.value != null) {
            final clickedTextBox = _findTextBoxAtPosition(pagePos, pageIndex);
            if (clickedTextBox == null ||
                clickedTextBox.id != _editingTextBoxIdNotifier.value) {
              _endTextBoxEditing();
            }
          }

          // ✅ 如果是选择工具，检查是否点击在空白区域
          if (_currentToolNotifier.value.toolId == ToolId.select) {
            debugPrint('🦋[HandwritingSaber] 选择工具点击，position=$pagePos');
            final clickedStroke = _findStrokeAtPosition(pagePos, pageIndex);
            final clickedTextBox = _findTextBoxAtPosition(pagePos, pageIndex);
            debugPrint(
                '🦋[HandwritingSaber] clickedStroke=${clickedStroke != null}, clickedTextBox=${clickedTextBox != null}, clickedTextBoxId=${clickedTextBox?.id}');

            // ✅ 修复：如果点击在空白区域且没有选中对象，取消选择
            // 文本框的选择由 _startSelection 处理，这里不阻止
            if (clickedStroke == null &&
                clickedTextBox == null &&
                (_selectResult == null ||
                    !_isPointInSelection(pagePos, _selectResult!))) {
              // ✅ 点击在空白区域，取消选择
              debugPrint('🦋[HandwritingSaber] 选择工具点击空白区域，清除选择');
              _clearSelection();
            }
            // ✅ 选择工具的操作由 _startStroke -> _startSelection 处理
          }
          // ✅ 如果是文本框工具或标题工具，检查是否点击在已存在的文本框上
          if (_currentToolNotifier.value.toolId == ToolId.textBox ||
              _currentToolNotifier.value.toolId == ToolId.heading1 ||
              _currentToolNotifier.value.toolId == ToolId.heading2 ||
              _currentToolNotifier.value.toolId == ToolId.heading3 ||
              _currentToolNotifier.value.toolId == ToolId.paragraph) {
            debugPrint('🦋[HandwritingSaber] 文本框工具点击，position=$pagePos');
            final clickedTextBox = _findTextBoxAtPosition(pagePos, pageIndex);
            if (clickedTextBox != null) {
              // ✅ 点击在已存在的文本框上，编辑它
              debugPrint(
                  '🦋[HandwritingSaber] 文本框工具点击已存在的文本框，编辑它：${clickedTextBox.id}');
              _editTextBox(clickedTextBox);
              return;
            }
            debugPrint('🦋[HandwritingSaber] 文本框工具点击空白区域，创建新文本框');
          }
          // ✅ 确保笔迹添加到正确的页面
          if (pageIndex < _coreInfo.pages.length) {
            _startStroke(pagePos, pageIndex: pageIndex);
          }
        }
      },
      onPanUpdate: (DragUpdateDetails details) {
        // ✅ 如果正在操作图片，不处理
        if (_isImageOperationInProgress) {
          return;
        }
        // ✅ 只处理当前页面的触摸事件
        if (!isPointInPage(details.localPosition)) {
          return;
        }
        final pagePos = toPageCoordinates(details.localPosition);
        debugPrint(
            '🦋[HandwritingSaber] onPanUpdate: local=${details.localPosition}, pagePos=$pagePos, pageIndex=$pageIndex, tool=${_currentToolNotifier.value.toolId}');
        if (pagePos.dx.isFinite && pagePos.dy.isFinite) {
          _updateStroke(pagePos);
        }
      },
      onPanEnd: (DragEndDetails details) {
        // ✅ 如果正在操作图片，重置状态
        if (_isImageOperationInProgress) {
          _isImageOperationInProgress = false;
          return;
        }
        _endStroke();
      },
      child: Container(
        width: screenWidth,
        height: pageDisplayHeight,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: pageDisplayWidth,
          height: pageDisplayHeight,
          child: Stack(
            children: [
              // debug: 输出当前页面与背景信息（使用受控日志，默认静默）
              Builder(builder: (context) {
                LogUtils.debug(
                    '🦋[HandwritingSaber] _buildSinglePageCanvas: pageIndex=$pageIndex, page.backgroundImage=${page.backgroundImage != null}, coreInfo.backgroundPattern=${_coreInfo.backgroundPattern}, currentBackgroundPattern=$_currentBackgroundPattern, page.strokes=${page.strokes.length}');
                return const SizedBox.shrink();
              }),

              // ✅ [第1层] 背景层 (只绘制背景色、背景纹理或PDF背景)
              SaberCoreCanvas(
                coreInfo: EditorCoreInfo(
                  pages: [page], // ✅ 只传递当前页面
                  backgroundColor: _coreInfo.backgroundColor,
                  backgroundPattern: _currentBackgroundPattern,
                  lineHeight: _coreInfo.lineHeight,
                  lineThickness: _coreInfo.lineThickness,
                  laserStrokes: [], // 背景层不需要激光笔
                ),
                drawBackground: true,
                drawStrokes: false, // ❌ 不绘制笔迹
                // 不需要监听任何变化，只显示静态背景
              ),

              // ✅ [第2层] 图片层
              if (page.images.isNotEmpty)
                ...page.images.map((image) => _buildImageWidget(
                      image,
                      pageIndex,
                      pageDisplayWidth,
                      pageDisplayHeight,
                      scale,
                    )),

              // ✅ [第3层] WebView层
              if (page.webViews.isNotEmpty)
                ...page.webViews.map((webView) => _buildWebViewWidget(
                      webView,
                      pageIndex,
                      scale,
                    )),

              // ✅ [第4层] 画布层 (笔迹层) - 移动到图片和 WebView 之上
              ValueListenableBuilder<String?>(
                valueListenable: _editingTextBoxIdNotifier,
                builder: (context, editingTextBoxId, _) {
                  return ValueListenableBuilder<int?>(
                    valueListenable: _currentPageIndexNotifier,
                    builder: (context, currentPageIndex, _) {
                      return SaberCoreCanvas(
                        coreInfo: EditorCoreInfo(
                          pages: [page], // ✅ 只传递当前页面
                          backgroundColor: _coreInfo.backgroundColor,
                          backgroundPattern: _currentBackgroundPattern,
                          lineHeight: _coreInfo.lineHeight,
                          lineThickness: _coreInfo.lineThickness,
                          laserStrokes: _coreInfo.laserStrokes, // ✅ 直接传递引用，不复制！
                        ),
                        // ✅ 关键修复：只有当绘制在当前页面时，才监听实时笔迹
                        currentStrokeListenable: currentPageIndex == pageIndex
                            ? _currentStrokeNotifier
                            : null,
                        repaintListenable: Listenable.merge(
                            [_repaintTick, _laserStrokesNotifier]),
                        selectResult: _selectResult != null &&
                                _selectResult!.pageIndex == pageIndex
                            ? _selectResult
                            : null,
                        isSelecting: _isSelecting &&
                            _selectResult != null &&
                            _selectResult!.pageIndex == pageIndex,
                        pdfTextSelectionRect: _pdfTextSelectionRect != null &&
                                _pdfTextSelectionPageIndex == pageIndex
                            ? _pdfTextSelectionRect
                            : null,
                        editingTextBoxId:
                            editingTextBoxId, // ✅ 传递正在编辑的文本框ID，避免重影
                        drawBackground: false, // ❌ 不绘制背景（已经在底层绘制了）
                        drawStrokes: true, // ✅ 绘制笔迹
                      );
                    },
                  );
                },
              ),
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
                      return _buildTextBoxEditor(textBox, pageIndex,
                          screenWidth, pageDisplayWidth, pageDisplayHeight);
                    } catch (e) {
                      // ✅ 如果找不到匹配的文本框（列表为空或没有匹配项），返回空widget
                      debugPrint(
                          '🦋[HandwritingSaber] _buildSinglePageCanvas: textBox not found for id=$editingTextBoxId, error=$e');
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
                color:
                    Colors.white.withValues(alpha: textEditingMode ? 0.95 : 0),
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

  /// ✅ 构建图片 Widget（使用可交互组件）
  Widget _buildImageWidget(
    EditorImage image,
    int pageIndex,
    double pageDisplayWidth,
    double pageDisplayHeight,
    double scale,
  ) {
    return ValueListenableBuilder<String?>(
      valueListenable: _selectedImageIdNotifier,
      builder: (context, selectedImageId, _) {
        return CanvasImageWidget(
          image: image,
          pageSize: _coreInfo.pages[pageIndex].size,
          scale: scale,
          readOnly: false,
          selected: selectedImageId == image.id,
          onImageChanged: () {
            // ✅ 自动切换到选择工具
            if (_currentToolNotifier.value.toolId != ToolId.select) {
              _onToolChanged(const SelectTool(selectMode: SelectMode.click));
            }

            // 切换选中状态
            if (_selectedImageIdNotifier.value == image.id) {
              // 如果已选中，取消选中
              _selectedImageIdNotifier.value = null;
            } else {
              // 选中这张图片
              _selectedImageIdNotifier.value = image.id;
            }
            // 保存更改
            _scheduleSave();
          },
          onImageDeleted: () {
            // 删除图片
            _deleteImage(image, pageIndex);
          },
          onDragStart: () {
            // ✅ 开始图片操作
            _isImageOperationInProgress = true;
          },
          onDragEnd: () {
            // ✅ 结束图片操作
            _isImageOperationInProgress = false;
            _scheduleSave();
          },
        );
      },
    );
  }

  /// ✅ 构建WebView Widget
  Widget _buildWebViewWidget(
    WebViewEditorElement webView,
    int pageIndex,
    double scale,
  ) {
    return CanvasWebViewWidget(
      key: ValueKey('webview_${webView.id}'),
      filePath:
          _cachedSbnFilePath ?? widget.view.id, // ✅ 使用完整的.sbn2文件路径，而不是viewId
      webView: webView,
      pageSize: _coreInfo.pages[pageIndex].size,
      readOnly: false,
      selected: _selectResult?.webViews.contains(webView) ?? false,
      onTap: () => _selectWebView(webView),
      onDelete: () => _deleteWebView(webView, pageIndex),
      onRefresh: () => _refreshWebView(webView),
    );
  }

  /// ✅ 删除图片
  void _deleteImage(EditorImage image, int pageIndex) {
    if (pageIndex < 0 || pageIndex >= _coreInfo.pages.length) return;

    final page = _coreInfo.pages[pageIndex];
    page.images.remove(image);

    // 取消选中
    if (_selectedImageIdNotifier.value == image.id) {
      _selectedImageIdNotifier.value = null;
    }

    // 记录到历史
    _history.recordChange(EditorHistoryItem.erase(
      pageIndex: pageIndex,
      deletedStrokes: [], // 图片删除不涉及笔迹
    ));
    _updateUndoRedoState();

    // 更新UI
    setState(() {});

    // 保存
    _scheduleSave();

    // 显示提示
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('图片已删除')),
      );
    }
  }

  /// ✅ 导入图片
  Future<void> _importImage() async {
    try {
      // 选择图片文件
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'jpg',
          'jpeg',
          'png',
          'gif',
          'bmp',
          'webp',
        ],
        allowMultiple: true,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      // 获取当前查看的页面索引
      final currentPageIndex = _viewingPageIndexNotifier.value;
      if (currentPageIndex >= _coreInfo.pages.length) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('没有可用的页面')),
          );
        }
        return;
      }

      final page = _coreInfo.pages[currentPageIndex];
      int imagesAdded = 0;

      for (final file in result.files) {
        if (file.bytes == null || file.extension == null) continue;

        // 生成唯一ID
        final imageId =
            'img_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(10000)}';

        // 创建图片对象
        final image = PngEditorImage(
          id: imageId,
          imageBytes: file.bytes!,
          extension: '.${file.extension}',
          pageIndex: currentPageIndex,
          pageSize: page.size,
          dstRect: Rect.fromLTWH(
            50 + (imagesAdded * 20.0), // 每个图片稍微错开
            50 + (imagesAdded * 20.0),
            200, // 默认宽度
            200, // 默认高度
          ),
        );

        // 添加到页面
        page.images.add(image);
        imagesAdded++;
      }

      if (imagesAdded > 0) {
        // 记录到历史
        _history.recordChange(EditorHistoryItem.draw(
          pageIndex: currentPageIndex,
          strokes: [],
        ));
        _updateUndoRedoState();

        // 更新UI
        setState(() {});

        // 保存
        _scheduleSave();

        // 显示提示
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已导入 $imagesAdded 张图片')),
          );
        }
      }
    } catch (e) {
      debugPrint('导入图片失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导入图片失败')),
        );
      }
    }
  }

  /// ✅ 导出为 PDF 文件（参考 Saber 的 exportAsPdf）
  Future<void> _exportPdf() async {
    try {
      debugPrint('📄[HandwritingSaber] 开始导出 PDF...');

      // 检查是否有可导出的内容
      if (_coreInfo.pages.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('没有可导出的页面')),
          );
        }
        return;
      }

      // 显示加载提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('正在生成 PDF...'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      // 使用 EditorExporter 生成 PDF
      final pdf = await EditorExporter.generatePdf(
        _coreInfo,
        context,
        pageNotifiers: _pageNotifiers,
      );

      // 保存 PDF 字节数据
      final pdfBytes = await pdf.save();

      // 让用户选择保存位置
      final fileName =
          '${widget.view.name.isNotEmpty ? widget.view.name : "手写笔记"}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: '保存 PDF',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (outputPath == null) {
        debugPrint('📄[HandwritingSaber] 用户取消保存');
        return; // 用户取消保存
      }

      // 写入文件
      final file =
          File(outputPath.endsWith('.pdf') ? outputPath : '$outputPath.pdf');
      await file.writeAsBytes(pdfBytes);

      debugPrint('📄[HandwritingSaber] PDF 导出成功: ${file.path}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF 导出成功: ${file.path}')),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [HandwritingSaber] 导出 PDF 失败: $e');
      debugPrint('❌ [HandwritingSaber] 堆栈: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出 PDF 失败: $e')),
        );
      }
    }
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
        return; // 用户取消选择
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
      debugPrint(
          '🦋[HandwritingSaber] PDF文档加载完成: ${loadTime.inMilliseconds}ms, 页面数: ${pdfDocument.pages.length}');

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
          pdfPageIndex: pdfPage.pageNumber - 1, // PDF 页面索引（从 0 开始）
          naturalSize: pdfPage.size,
          dstRect: Rect.fromLTWH(0, 0, pageSize.width, pageSize.height),
        );

        // ✅ 预加载PDF文档，避免首次显示时的闪烁
        pdfImage.preloadPdfDocument();

        // ✅ 创建新页面：仅将 existingStrokes 保留到导入前的"第一页"，其余页面不保留旧笔迹
        final page = EditorPage(
          size: pageSize,
          strokes:
              _isFirstPdfPage ? List<Stroke>.from(existingStrokes) : <Stroke>[],
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
      debugPrint(
          '🦋[HandwritingSaber] 页面创建完成: ${pageCreationTime.inMilliseconds}ms');

      // 触发UI更新（此时PDF还未完全加载，但页面结构已建立）
      setState(() {});

      // ✅ 使用智能页面管理器进行预加载优化
      final pageManager = PdfMultiPageManager();
      final visiblePageKeys = <String>[];

      // 收集所有页面键，用于智能加载
      for (final page in _coreInfo.pages) {
        if (page.backgroundImage != null) {
          final pageKey =
              '${page.backgroundImage!.pdfFilePath}|${page.backgroundImage!.pdfPageIndex}';
          visiblePageKeys.add(pageKey);
        }
      }

      // 更新可见页面，启动智能加载策略
      pageManager.updateVisiblePages(visiblePageKeys);

      debugPrint(
          '🦋[HandwritingSaber] 已启动智能PDF预加载，页面数: ${visiblePageKeys.length}');

      // 异步保存到存储（不阻塞UI）
      _saveToStorage().then((_) {
        debugPrint('🦋[HandwritingSaber] 数据保存完成');
      });

      final totalImportTime = DateTime.now().difference(importStartTime);
      debugPrint(
          '🦋[HandwritingSaber] PDF导入完成: 总用时 ${totalImportTime.inMilliseconds}ms');

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

  /// ✅ 提取PDF文本
  Future<void> _extractPdfText() async {
    try {
      // 查找当前页面或第一个有PDF背景的页面
      int targetPageIndex = _currentPageIndexNotifier.value ?? 0;
      if (targetPageIndex >= _coreInfo.pages.length) {
        targetPageIndex = 0;
      }

      // 尝试找到第一个有PDF背景的页面
      PdfEditorImage? pdfImage;
      for (int i = 0; i < _coreInfo.pages.length; i++) {
        final page = _coreInfo.pages[i];
        if (page.backgroundImage != null &&
            page.backgroundImage is PdfEditorImage) {
          pdfImage = page.backgroundImage as PdfEditorImage;
          break;
        }
      }

      if (pdfImage == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('当前没有PDF页面')),
          );
        }
        return;
      }

      // 打开PDF文本选择对话框
      if (mounted) {
        await PdfTextSelectionDialog.show(
          context: context,
          pdfFilePath: pdfImage.pdfFilePath,
          pageIndex: pdfImage.pdfPageIndex,
        );
      }
    } catch (e) {
      debugPrint('❌ [HandwritingSaberPocPage] 提取PDF文本失败：$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('提取PDF文本失败：$e')),
        );
      }
    }
  }

  /// ✅ 插入网页
  Future<void> _insertWebView() async {
    try {
      // 显示输入对话框
      final result = await showInsertWebViewDialog(context);
      if (result == null) return;

      // 获取当前页面
      final currentPageIndex = 0;
      if (currentPageIndex >= _coreInfo.pages.length) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('没有可用的页面')),
          );
        }
        return;
      }

      final page = _coreInfo.pages[currentPageIndex];

      // 生成唯一ID
      final webViewId = _getNextWebViewId();

      // 创建WebView元素
      final webView = WebViewEditorElement(
        id: webViewId,
        url: result.url,
        title: result.title,
        isInteractive: result.isInteractive,
        pageIndex: currentPageIndex,
        pageSize: page.size,
        dstRect: const Rect.fromLTWH(100, 100, 600, 400), // 默认位置和大小
      );

      // 添加到页面
      page.webViews.add(webView);

      // 记录到历史
      _history.recordChange(EditorHistoryItem.draw(
        pageIndex: currentPageIndex,
        strokes: [],
      ));
      _updateUndoRedoState();

      // 更新UI
      setState(() {});

      // 保存
      _scheduleSave();

      // 显示提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('网页已插入')),
        );
      }
    } catch (e) {
      debugPrint('插入网页失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('插入网页失败: $e')),
        );
      }
    }
  }

  /// ✅ 获取下一个WebView ID
  int _getNextWebViewId() {
    int maxId = 0;
    for (final page in _coreInfo.pages) {
      for (final webView in page.webViews) {
        if (webView.id > maxId) {
          maxId = webView.id;
        }
      }
    }
    return maxId + 1;
  }

  /// ✅ 选中WebView
  void _selectWebView(WebViewEditorElement webView) {
    setState(() {
      _selectResult = SelectResult(
        pageIndex: webView.pageIndex,
        strokes: [],
        images: [],
        regularImages: [],
        webViews: [webView],
        selectionPath: Path(),
      );
    });
  }

  /// ✅ 删除WebView
  void _deleteWebView(WebViewEditorElement webView, int pageIndex) {
    if (pageIndex < 0 || pageIndex >= _coreInfo.pages.length) return;

    final page = _coreInfo.pages[pageIndex];
    page.webViews.remove(webView);

    // 清除选中状态
    if (_selectResult?.webViews.contains(webView) ?? false) {
      setState(() {
        _selectResult = SelectResult(
          pageIndex: pageIndex,
          strokes: [],
          images: [],
          regularImages: [],
          webViews: [],
          selectionPath: Path(),
        );
      });
    }

    // 清除缓存
    final sbnPath = _cachedSbnFilePath ?? widget.view.id; // ✅ 使用完整的.sbn2文件路径
    webView.clearCache(sbnPath);

    // 记录历史
    _history.recordChange(EditorHistoryItem.erase(
      pageIndex: pageIndex,
      deletedStrokes: [],
    ));
    _updateUndoRedoState();

    // 更新UI
    setState(() {});

    // 保存
    _scheduleSave();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('网页已删除')),
      );
    }
  }

  /// ✅ 刷新WebView缓存
  Future<void> _refreshWebView(WebViewEditorElement webView) async {
    final sbnPath = _cachedSbnFilePath ?? widget.view.id; // ✅ 使用完整的.sbn2文件路径
    await webView.clearCache(sbnPath);
    setState(() {}); // 触发重新加载

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('网页缓存已清除，重新加载中...')),
      );
    }
  }

  /// ✅ 启动激光笔淡出动画（完全参考 Saber 的逻辑）
  void _startLaserFadeOut(Stroke laserStroke,
      {List<Duration>? strokePointDelays}) {
    if (laserStroke.points.isEmpty) {
      return;
    }
    // 标记淡出进行中，抑制保存操作以避免 I/O 干扰渲染
    _isLaserFadeInProgress = true;

    // ✅ 关键修复：完全按照Saber的方式，直接使用记录的延迟
    // 如果没有记录的延迟（理论上不应该发生），使用空列表也没关系，会直接跳过淡出循环
    final List<Duration> delaysToUse = strokePointDelays ?? [];

    // 打印用于诊断的延迟信息
    debugPrint(
        '🦋[HandwritingSaber] _startLaserFadeOut: strokePoints=${laserStroke.points.length}, delays=${delaysToUse.map((d) => d.inMilliseconds).toList()}');

    // ✅ 关键修复：使用 unawaited 启动异步淡出动画（参考Saber的实现）
    // 不使用 await，让淡出动画在后台异步执行
    unawaited(
      _fadeOutLaserStroke(
        stroke: laserStroke,
        strokePointDelays: delaysToUse,
      ),
    );
  }

  /// ✅ 淡出激光笔笔迹（完全参考 Saber 的 fadeOutStroke 方法实现）
  Future<void> _fadeOutLaserStroke({
    required Stroke stroke,
    required List<Duration> strokePointDelays,
  }) async {
    debugPrint(
        '🦋[HandwritingSaber] _fadeOutLaserStroke: 开始执行，等待${Duration(seconds: 2).inSeconds}秒...');

    // ✅ 等待初始延迟（2秒）- 与Saber一致
    const fadeOutDelay = Duration(seconds: 2);
    await Future.delayed(fadeOutDelay);

    debugPrint('🦋[HandwritingSaber] _fadeOutLaserStroke: 初始延迟结束，开始逐点淡出...');

    // 如果笔迹已被移除，直接返回
    if (!_laserStrokesNotifier.value.contains(stroke)) {
      debugPrint('🦋[HandwritingSaber] _fadeOutLaserStroke: 笔迹已被移除，退出');
      return;
    }

    // ✅ 关键修复：完全按照Saber的方式，直接使用记录的延迟，不做任何归一化
    // Saber的逻辑：按照绘制时的速度淡出，即使延迟为零也照用
    // 这样可以完美复现用户的绘制速度，实现真实的淡出效果
    for (int i = 0; i < strokePointDelays.length; i++) {
      final delay = strokePointDelays[i];

      // 等待这个点的延迟时间
      await Future.delayed(delay);

      // 如果笔迹已被移除或点数不足（<=1），退出循环
      if (!_laserStrokesNotifier.value.contains(stroke) ||
          stroke.points.length <= 1) {
        debugPrint(
            '🦋[HandwritingSaber] _fadeOutLaserStroke: 笔迹已移除或点数<=1，退出循环');
        break;
      }

      // 删除第一个点并通知绘制层更新
      stroke.popFirstPoint();
      _laserStrokesNotifier.value =
          List<Stroke>.from(_laserStrokesNotifier.value);

      // ✅ 关键修复：触发Canvas重绘（通过 _repaintTick）
      _repaintTick.value++;

      // 每10个点打印一次进度
      if (i % 10 == 0) {
        debugPrint(
            '🦋[HandwritingSaber] _fadeOutLaserStroke: 进度 $i/${strokePointDelays.length}, 剩余点数=${stroke.points.length}');
      }

      // ✅ 如果用户重新开始绘制（currentStroke 非空），暂停淡出并等待用户停止
      // 这是Saber的关键特性：激光笔在用户继续书写时会暂停淡出
      if (_currentStrokeNotifier.value != null) {
        const waitTime = Duration(milliseconds: 100);
        // 等待用户停止绘制
        while (_currentStrokeNotifier.value != null) {
          await Future.delayed(waitTime);
        }
        // 用户停止后，等待正常的延迟时间再继续淡出
        await Future.delayed(fadeOutDelay - waitTime);
      }
    }

    // 最后删除整个笔迹并更新 notifier
    debugPrint('🦋[HandwritingSaber] _fadeOutLaserStroke: 淡出完成，删除笔迹');
    _coreInfo.laserStrokes.remove(stroke);
    _laserStrokesNotifier.value = List<Stroke>.from(_laserStrokesNotifier.value)
      ..remove(stroke);
    _laserFadeOutTimers.remove(stroke);
    _isLaserFadeInProgress = false;

    // ✅ 关键修复：触发Canvas重绘
    _repaintTick.value++;

    // 持久化（抑制 UI 状态更新）
    debugPrint('🦋[HandwritingSaber] _fadeOutLaserStroke: 开始持久化...');
    if (_pendingSave) {
      _pendingSave = false;
      await _saveToStorage(suppressStatusUpdate: true);
    } else {
      await _saveToStorage(suppressStatusUpdate: true);
    }
    debugPrint('🦋[HandwritingSaber] _fadeOutLaserStroke: 淡出流程全部完成');
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

    // ❌ 不要清理PDF文档缓存管理器！
    // PdfDocumentCacheManager是全局单例，不应该在单个页面的dispose中清理
    // 它会自动管理缓存（定期清理过期缓存），不需要手动dispose
    // 如果在这里dispose，会导致其他页面的PDF缓存也被清空！
    // PdfDocumentCacheManager().dispose();

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
    _zoomLevelNotifier.dispose();

    // ✅ 清理页面管理器相关 notifier
    _showPageManagerNotifier.dispose();
    _viewingPageIndexNotifier.dispose();
    _pageScrollController.dispose();

    // ✅ 清理当前页面索引 notifier
    _currentPageIndexNotifier.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (FocusNode node, KeyEvent event) {
        // ✅ 监听键盘事件
        if (event is KeyDownEvent) {
          // 检查是否按下 Control (Windows/Linux) 或 Command (macOS)
          final isCtrlPressed = HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed;

          // 检查是否按下 Shift
          final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;

          // ✅ Ctrl+Z / Cmd+Z 撤销
          if (isCtrlPressed &&
              !isShiftPressed &&
              event.logicalKey == LogicalKeyboardKey.keyZ) {
            if (_history.canUndo) {
              _undo();
              return KeyEventResult.handled;
            }
          }

          // ✅ Ctrl+Shift+Z / Cmd+Shift+Z 或 Ctrl+Y / Cmd+Y 重做
          if ((isCtrlPressed &&
                  isShiftPressed &&
                  event.logicalKey == LogicalKeyboardKey.keyZ) ||
              (isCtrlPressed && event.logicalKey == LogicalKeyboardKey.keyY)) {
            if (_history.canRedo) {
              _redo();
              return KeyEventResult.handled;
            }
          }

          // Ctrl+C 复制
          if (isCtrlPressed && event.logicalKey == LogicalKeyboardKey.keyC) {
            if (_selectResult != null && !_selectResult!.isEmpty) {
              _copySelectedObjects();
              return KeyEventResult.handled;
            }
          }

          // Ctrl+V 粘贴
          if (isCtrlPressed && event.logicalKey == LogicalKeyboardKey.keyV) {
            _pasteObjects();
            return KeyEventResult.handled;
          }

          // 退格键或 Delete 键删除
          if (event.logicalKey == LogicalKeyboardKey.backspace ||
              event.logicalKey == LogicalKeyboardKey.delete) {
            // 删除选中的对象
            if (_selectResult != null && !_selectResult!.isEmpty) {
              _deleteSelectedObjects();
              return KeyEventResult.handled;
            }
          }

          // ✅ Ctrl/Cmd + Plus (+) 或 Ctrl/Cmd + Equal (=) 放大视图
          // 注意：大多数键盘上 + 需要按 Shift，所以同时支持 = 键
          if (isCtrlPressed &&
              (event.logicalKey == LogicalKeyboardKey.add ||
                  event.logicalKey == LogicalKeyboardKey.equal ||
                  event.logicalKey == LogicalKeyboardKey.numpadAdd)) {
            _zoomIn();
            return KeyEventResult.handled;
          }

          // ✅ Ctrl/Cmd + Minus (-) 缩小视图
          if (isCtrlPressed &&
              (event.logicalKey == LogicalKeyboardKey.minus ||
                  event.logicalKey == LogicalKeyboardKey.numpadSubtract)) {
            _zoomOut();
            return KeyEventResult.handled;
          }

          // ✅ Ctrl/Cmd + 0 重置缩放到100%
          if (isCtrlPressed &&
              (event.logicalKey == LogicalKeyboardKey.digit0 ||
                  event.logicalKey == LogicalKeyboardKey.numpad0)) {
            _zoomReset();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Column(
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
                              return ValueListenableBuilder<bool>(
                                valueListenable:
                                    FullWindowController.isFullWindow,
                                builder: (context, isFullWindow, __) {
                                  return ValueListenableBuilder<bool>(
                                    valueListenable: _showPageManagerNotifier,
                                    builder: (context, showPageManager, ___) {
                                      return HandwritingSaberToolbar(
                                        currentTool: currentTool,
                                        onToolChanged: _onToolChanged,
                                        currentBackgroundPattern:
                                            _currentBackgroundPattern,
                                        onBackgroundPatternChanged:
                                            _onBackgroundPatternChanged,
                                        // 使用全局颜色/线宽，确保切换工具时保持用户设置
                                        currentColor:
                                            _globalColorNotifier.value,
                                        onColorChanged: _onColorChanged,
                                        currentStrokeWidth:
                                            _globalStrokeWidthNotifier.value,
                                        onStrokeWidthChanged:
                                            _onStrokeWidthChanged,
                                        currentFillColor:
                                            fillColor, // ✅ 填充颜色（由 notifier 驱动）
                                        onFillColorChanged:
                                            _onFillColorChanged, // ✅ 填充颜色改变回调
                                        onImportPdf: _importPdf, // ✅ PDF 导入回调
                                        onImportImage: _importImage, // ✅ 图片导入回调
                                        onInsertWebView:
                                            _insertWebView, // ✅ 网页嵌入回调
                                        onExtractPdfText:
                                            _extractPdfText, // ✅ PDF文本提取回调
                                        canUndo: canUndo, // ✅ 撤销按钮状态
                                        canRedo: canRedo, // ✅ 恢复按钮状态
                                        onUndo: _undo, // ✅ 撤销回调
                                        onRedo: _redo, // ✅ 恢复回调
                                        currentDashStyle: _dashStyleNotifier
                                            .value, // ✅ 当前虚线样式
                                        onDashStyleChanged:
                                            _onDashStyleChanged, // ✅ 虚线样式改变回调
                                        currentArrowStyle: _arrowStyleNotifier
                                            .value, // ✅ 当前箭头样式
                                        onArrowStyleChanged:
                                            _onArrowStyleChanged, // ✅ 箭头样式改变回调
                                        textEditingMode:
                                            textEditingMode, // ✅ 文本编辑模式标志
                                        onToggleTextEditingMode:
                                            _toggleTextEditingMode, // ✅ 切换文本编辑模式回调
                                        quillFocus:
                                            _getActiveQuillStruct(), // ✅ 获取当前活动的 Quill 结构（可能来自页面或文本框）
                                        isFullWindow:
                                            isFullWindow, // ✅ 全窗口状态（与全局控制器同步）
                                        onToggleFullWindow: FullWindowController
                                            .toggle, // ✅ 全窗口切换回调
                                        showPageManager:
                                            showPageManager, // ✅ 页面管理器显示状态
                                        onTogglePageManager:
                                            _togglePageManager, // ✅ 切换页面管理器回调
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
              );
            },
          ),
          const Divider(height: 1),
          // ✅ 主内容区域（页面管理器 + 画布）
          Expanded(
            child: ValueListenableBuilder<bool>(
              valueListenable: _showPageManagerNotifier,
              builder: (context, showPageManager, _) {
                return Row(
                  children: [
                    // ✅ 左侧页面管理器侧边栏
                    if (showPageManager)
                      LayoutBuilder(
                        builder: (context, constraints) {
                          return ValueListenableBuilder<int>(
                            valueListenable: _viewingPageIndexNotifier,
                            builder: (context, viewingPageIndex, _) {
                              return EditorPageManager(
                                coreInfo: _coreInfo,
                                currentPageIndex: viewingPageIndex,
                                redrawAndSave: _redrawAndSave,
                                scrollToPage: _scrollToPage,
                                insertPageAfter: _insertPageAfter,
                                duplicatePage: _duplicatePage,
                                clearPage: _clearPage,
                                deletePage: _deletePage,
                                width: 200,
                                constraints: constraints,
                              );
                            },
                          );
                        },
                      ),
                    // ✅ 右侧画布区域
                    Expanded(
                      child: ValueListenableBuilder<double>(
                        valueListenable: _zoomLevelNotifier,
                        builder: (context, zoomLevel, _) {
                          return Stack(
                            children: [
                              // ✅ 主内容区域（支持鼠标滚轮缩放）
                              Listener(
                                onPointerSignal: (PointerSignalEvent event) {
                                  // 监听鼠标滚轮事件
                                  if (event is PointerScrollEvent) {
                                    // 检查是否按下 Ctrl/Cmd 键
                                    final isCtrlPressed = HardwareKeyboard
                                            .instance.isControlPressed ||
                                        HardwareKeyboard.instance.isMetaPressed;

                                    if (isCtrlPressed) {
                                      // Ctrl/Cmd + 滚轮 = 缩放
                                      _handleScrollZoom(event.scrollDelta.dy);
                                    }
                                    // 如果没有按 Ctrl/Cmd，让 SingleChildScrollView 处理滚动
                                  }
                                },
                                child: LayoutBuilder(
                                  builder: (BuildContext context,
                                      BoxConstraints constraints) {
                                    // ✅ 保存最新的布局约束，供滚动计算使用
                                    _lastCanvasConstraints = constraints;

                                    // ✅ 支持多页滚动显示
                                    if (_coreInfo.pages.isEmpty) {
                                      return const Center(
                                        child: Text('没有页面'),
                                      );
                                    }

                                    // ✅ 计算每页的显示大小（使用屏幕宽度，保持比例，并应用用户缩放）
                                    final double screenWidth =
                                        constraints.maxWidth;
                                    final List<Widget> pageWidgets = [];

                                    debugPrint(
                                        '🖼️🖼️🖼️ [HandwritingSaber] Building ${_coreInfo.pages.length} pages for view: ${widget.view.name}, zoomLevel: ${(zoomLevel * 100).toInt()}%');

                                    for (int pageIndex = 0;
                                        pageIndex < _coreInfo.pages.length;
                                        pageIndex++) {
                                      // 确保 page notifier 已初始化，避免 index out of range 导致 RangeError
                                      if (_pageNotifiers.length <= pageIndex) {
                                        _pageNotifiers.add(EditorPageNotifier(
                                            _coreInfo.pages[pageIndex]));
                                      }

                                      // ✅ 使用ListenableBuilder包装页面，只在特定页面数据变化时重建
                                      final pageWidget = ListenableBuilder(
                                        listenable: _pageNotifiers[pageIndex],
                                        builder: (context, child) {
                                          final page =
                                              _pageNotifiers[pageIndex].page;

                                          // 防止除零错误
                                          if (page.size.width <= 0 ||
                                              page.size.height <= 0) {
                                            return const SizedBox.shrink();
                                          }

                                          // ✅ 计算页面缩放（基础缩放 * 用户缩放级别）
                                          // 基础缩放：使页面宽度适应屏幕宽度
                                          // 用户缩放：在基础缩放上叠加用户选择的缩放级别
                                          final double baseScale =
                                              screenWidth / page.size.width;
                                          final double effectiveScale =
                                              baseScale * zoomLevel;
                                          final double pageDisplayWidth =
                                              page.size.width * effectiveScale;
                                          final double pageDisplayHeight =
                                              page.size.height * effectiveScale;

                                          // ✅ 创建单页画布
                                          return _buildSinglePageCanvas(
                                            page: page,
                                            pageIndex: pageIndex,
                                            pageDisplayWidth: pageDisplayWidth,
                                            pageDisplayHeight:
                                                pageDisplayHeight,
                                            screenWidth: screenWidth,
                                          );
                                        },
                                      );
                                      pageWidgets.add(pageWidget);

                                      // ✅ 页面之间的间距（除了最后一页）
                                      if (pageIndex <
                                          _coreInfo.pages.length - 1) {
                                        pageWidgets
                                            .add(const SizedBox(height: 16));
                                      }
                                    }

                                    // ✅ 直接使用新创建的pageWidgets，不使用缓存
                                    // 原因：之前的缓存机制有严重bug - 只检查页面数量，导致数据更新后界面不刷新
                                    // ListenableBuilder已经提供了充分的优化（每个页面只在自己的数据变化时重建）
                                    debugPrint(
                                        '🖼️🖼️🖼️ [HandwritingSaber] Rendering ${pageWidgets.length} page widgets directly (no cache)');

                                    // ✅ 使用 SingleChildScrollView 支持垂直和水平滚动（当放大超过100%时需要水平滚动）
                                    return NotificationListener<
                                        ScrollNotification>(
                                      onNotification: (notification) {
                                        // 更新当前查看的页面索引
                                        if (notification
                                            is ScrollUpdateNotification) {
                                          // ✅ 如果是程序锁定的滚动，不触发索引更新
                                          if (_isProgrammaticScrolling) {
                                            return false;
                                          }

                                          final newIndex =
                                              _getCurrentPageIndexFromScroll();
                                          if (_viewingPageIndexNotifier.value !=
                                              newIndex) {
                                            _viewingPageIndexNotifier.value =
                                                newIndex;
                                          }
                                        }
                                        return false;
                                      },
                                      child: SingleChildScrollView(
                                        controller:
                                            _pageScrollController, // ✅ 绑定滚动控制器
                                        scrollDirection: Axis.vertical,
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children:
                                                pageWidgets, // 直接使用最新的pageWidgets
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              // ✅ 缩放级别指示器（右下角显示当前缩放百分比）
                              Positioned(
                                right: 16,
                                bottom: 16,
                                child: _buildZoomIndicator(zoomLevel),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// ✅ 开始PDF文本选择
  void _startPdfTextSelection(Offset position, {int? pageIndex}) {
    final pageIdx = pageIndex ?? 0;

    // 检查当前页面是否有PDF背景
    if (pageIdx >= _coreInfo.pages.length) {
      return;
    }

    final page = _coreInfo.pages[pageIdx];
    if (page.backgroundImage == null ||
        !(page.backgroundImage is PdfEditorImage)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前页面没有PDF背景')),
        );
      }
      return;
    }

    _pdfTextSelectionStart = position;
    _pdfTextSelectionPageIndex = pageIdx;
    _pdfTextSelectionRect = null;

    debugPrint(
        '🦋[HandwritingSaber] 开始PDF文本选择: position=$position, pageIndex=$pageIdx');
  }

  /// ✅ 更新PDF文本选择
  void _updatePdfTextSelection(Offset position) {
    if (_pdfTextSelectionStart == null || _pdfTextSelectionPageIndex == null) {
      return;
    }

    // 计算选择矩形
    final start = _pdfTextSelectionStart!;
    _pdfTextSelectionRect = Rect.fromPoints(start, position);

    // 触发页面重绘以显示选择区域
    final pageIdx = _pdfTextSelectionPageIndex!;
    if (pageIdx < _pageNotifiers.length) {
      _pageNotifiers[pageIdx].updatePage(_coreInfo.pages[pageIdx]);
    }
  }

  /// ✅ 结束PDF文本选择并提取文本
  Future<void> _endPdfTextSelection() async {
    if (_pdfTextSelectionStart == null ||
        _pdfTextSelectionPageIndex == null ||
        _pdfTextSelectionRect == null) {
      _pdfTextSelectionStart = null;
      _pdfTextSelectionPageIndex = null;
      _pdfTextSelectionRect = null;
      return;
    }

    final pageIdx = _pdfTextSelectionPageIndex!;
    if (pageIdx >= _coreInfo.pages.length) {
      _pdfTextSelectionStart = null;
      _pdfTextSelectionPageIndex = null;
      _pdfTextSelectionRect = null;
      return;
    }

    final page = _coreInfo.pages[pageIdx];
    if (page.backgroundImage == null ||
        !(page.backgroundImage is PdfEditorImage)) {
      _pdfTextSelectionStart = null;
      _pdfTextSelectionPageIndex = null;
      _pdfTextSelectionRect = null;
      return;
    }

    final pdfImage = page.backgroundImage as PdfEditorImage;
    final selectionRect = _pdfTextSelectionRect!;

    // 检查选择区域是否足够大
    if (selectionRect.width < 5 || selectionRect.height < 5) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('选择区域太小')),
        );
      }
      _pdfTextSelectionStart = null;
      _pdfTextSelectionPageIndex = null;
      _pdfTextSelectionRect = null;
      return;
    }

    try {
      // 获取PDF在画布上的显示区域
      // 注意：这里需要根据实际的PDF渲染位置来计算
      // 简化实现：假设PDF占满整个页面
      final pageSize = page.size;
      final pdfRect = pdfImage.dstRect ??
          Rect.fromLTWH(0, 0, pageSize.width, pageSize.height);

      // 提取文本
      final extractedText =
          await PdfTextExtractionService.extractTextFromRegionFromFile(
        filePath: pdfImage.pdfFilePath,
        pageIndex: pdfImage.pdfPageIndex,
        canvasRect: selectionRect,
        pdfRect: pdfRect,
        pageSize: pdfImage.naturalSize,
      );

      if (extractedText.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('选择的区域没有文本')),
          );
        }
      } else {
        // 复制到剪贴板
        await Clipboard.setData(ClipboardData(text: extractedText));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已复制 ${extractedText.length} 个字符到剪贴板'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        debugPrint(
            '🦋[HandwritingSaber] PDF文本已复制到剪贴板: ${extractedText.length} 个字符');
      }
    } catch (e) {
      debugPrint('❌ [HandwritingSaber] 提取PDF文本失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('提取PDF文本失败: $e')),
        );
      }
    } finally {
      // 清除选择状态
      _pdfTextSelectionStart = null;
      _pdfTextSelectionPageIndex = null;
      _pdfTextSelectionRect = null;

      // 触发页面重绘以清除选择区域
      if (pageIdx < _pageNotifiers.length) {
        _pageNotifiers[pageIdx].updatePage(_coreInfo.pages[pageIdx]);
      }
    }
  }
}
