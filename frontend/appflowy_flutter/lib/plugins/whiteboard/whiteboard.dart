library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/util.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/util/diagnostic_build.dart';
import 'package:appflowy/workspace/application/favorite/favorite_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view_info/view_info_bloc.dart';
import 'package:appflowy/workspace/presentation/home/full_window_controller.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/widgets/tab_bar_item.dart';
import 'package:appflowy/workspace/presentation/widgets/unified_view_top_right_actions.dart';
import 'package:appflowy/workspace/presentation/widgets/view_title_bar.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_data_service.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_collab_adapter.dart';
import 'package:appflowy/plugins/whiteboard/presentation/excalidraw_webview.dart';
import 'package:appflowy/plugins/whiteboard/presentation/remote_whiteboard_page.dart';
import 'package:appflowy/plugins/whiteboard/presentation/whiteboard_router.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/hover.dart';
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';
import 'package:appflowy/plugins/whiteboard/presentation/whiteboard_export_action.dart';
import 'package:appflowy_popover/appflowy_popover.dart' as appflowy_popover;
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra/platform_extension.dart';

const _preferHostFullWindowMoreItemKey = 'preferHostFullWindowMoreItem';
const _preferHostTopRightActionsKey = 'preferHostTopRightActions';
const _whiteboardHostActionIconColorLight = Color(0xFF111111);
const _whiteboardHostActionIconColorDark = Color(0xFFF3F4F6);
const _whiteboardCanvasLightColor = Color(0xFFFFFFFF);
const _whiteboardCanvasDarkColor = Color(0xFF121212);

class WhiteboardPluginBuilder extends PluginBuilder {
  @override
  Plugin build(dynamic data) {
    // debug logs removed

    if (data is ViewPB) {
      // debug logs removed
      return WhiteboardPlugin(pluginType: pluginType, view: data);
    }

    Log.error(
      '❌ [WhiteboardPluginBuilder] Invalid data type, throwing exception',
    );
    throw FlowyPluginException.invalidData;
  }

  @override
  String get menuName => "白板";

  @override
  FlowySvgData get icon => FlowySvgs.icon_board_s; // 暂时使用看板图标，后续可替换为专用白板图标

  @override
  PluginType get pluginType => PluginType.whiteboard;

  @override
  ViewLayoutPB? get layoutType => ViewLayoutPB.Whiteboard;
}

class WhiteboardPlugin extends Plugin {
  WhiteboardPlugin({
    required ViewPB view,
    required PluginType pluginType,
  }) : notifier = ViewPluginNotifier(view: view) {
    // debug log removed
    _pluginType = pluginType;
  }

  @override
  late final ViewPluginNotifier notifier;
  late final PluginType _pluginType;
  late final ViewInfoBloc _viewInfoBloc;
  late final PageAccessLevelBloc _pageAccessLevelBloc;

  @override
  PluginWidgetBuilder get widgetBuilder => WhiteboardPluginWidgetBuilder(
        bloc: _viewInfoBloc,
        notifier: notifier,
        pageAccessLevelBloc: _pageAccessLevelBloc,
      );

  @override
  PluginId get id => notifier.view.id;

  @override
  PluginType get pluginType => _pluginType;

  @override
  void init() {
    // debug log removed
    _viewInfoBloc = ViewInfoBloc(view: notifier.view)
      ..add(const ViewInfoEvent.started());
    _pageAccessLevelBloc = PageAccessLevelBloc(view: notifier.view)
      ..add(const PageAccessLevelEvent.initial());
    // debug log removed
  }

  @override
  void dispose() {
    _viewInfoBloc.close();
    _pageAccessLevelBloc.close();
    notifier.dispose();
  }
}

class WhiteboardPluginWidgetBuilder extends PluginWidgetBuilder {
  WhiteboardPluginWidgetBuilder({
    required this.bloc,
    required this.notifier,
    required this.pageAccessLevelBloc,
  });

  final ViewInfoBloc bloc;
  final ViewPluginNotifier notifier;
  final PageAccessLevelBloc pageAccessLevelBloc;

  ViewPB get view => notifier.view;
  @override
  EdgeInsets get contentPadding => EdgeInsets.zero;

  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) {
    final widget = MultiBlocProvider(
      providers: [
        BlocProvider<ViewInfoBloc>.value(
          value: bloc,
        ),
        BlocProvider<PageAccessLevelBloc>.value(
          value: pageAccessLevelBloc,
        ),
      ],
      child: _buildContentWithToolbar(
        view: view,
        viewInfoBloc: bloc,
        pageAccessLevelBloc: pageAccessLevelBloc,
        child: WhiteboardRouter(
          notifier: notifier,
          onViewChanged: (view) => notifier.view = view,
        ),
      ),
    );
    return widget;
  }

  Widget _buildContentWithToolbar({
    required ViewPB view,
    required ViewInfoBloc viewInfoBloc,
    required PageAccessLevelBloc pageAccessLevelBloc,
    required Widget child,
  }) {
    return _WhiteboardContentWithToolbar(
      view: view,
      viewInfoBloc: viewInfoBloc,
      pageAccessLevelBloc: pageAccessLevelBloc,
      child: child,
    );
  }

  @override
  List<NavigationItem> get navigationItems => [this];

  @override
  String? get viewName => notifier.view.nameOrDefault;

  @override
  Widget get leftBarItem => BlocProvider<PageAccessLevelBloc>.value(
        value: pageAccessLevelBloc,
        child: ViewTitleBar(
          key: ValueKey(notifier.view.id),
          view: notifier.view,
        ),
      );

  @override
  Widget? get rightBarItem => null;

  @override
  Widget? get fullWindowMoreItem => null;

  @override
  bool get handlesFullWindowOverlayActionsInternally => true;

  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) =>
      ViewTabBarItem(view: notifier.view, shortForm: shortForm);
}

class _WhiteboardContentWithToolbar extends StatelessWidget {
  const _WhiteboardContentWithToolbar({
    required this.view,
    required this.viewInfoBloc,
    required this.pageAccessLevelBloc,
    required this.child,
  });

  final ViewPB view;
  final ViewInfoBloc viewInfoBloc;
  final PageAccessLevelBloc pageAccessLevelBloc;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    // 移动端外层页面栏已提供返回、收藏、分享和更多操作，白板插件不再
    // 叠加第二层按钮；桌面端继续使用插件原有的右上角操作。
    final showPluginActions = !PlatformInfo.isMobile;
    return Stack(
      children: [
        child,
        if (showPluginActions)
          Positioned(
            top: padding.top,
            right: padding.right,
            child: UnifiedViewTopRightActions(
              view: view,
              viewInfoBloc: viewInfoBloc,
              pageAccessLevelBloc: pageAccessLevelBloc,
              useFloatingSurface: true,
              showShareButton: false,
              showFullWindowButton: !PlatformInfo.isMobile,
              iconColorOverride: const Color(0xFF111111),
            ),
          ),
      ],
    );
  }
}

class WhiteboardPage extends StatefulWidget {
  WhiteboardPage({
    super.key,
    required this.view,
    required this.onViewChanged,
    this.preferHostFullWindowMoreItem = false,
    this.preferHostTopRightActions = true,
    this.isInSpaceHub = false,
  }) {
    // debug log removed
  }

  final ViewPB view;
  final Function(ViewPB) onViewChanged;
  final bool preferHostFullWindowMoreItem;
  final bool preferHostTopRightActions;
  final bool isInSpaceHub;

  @override
  State<WhiteboardPage> createState() {
    // debug log removed
    return _WhiteboardPageState();
  }
}

// 全局WebView实例计数器，确保每个WebView的Key绝对唯一

class _WhiteboardPageState extends State<WhiteboardPage>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _initialData;
  bool _isLoadingData = true;
  bool get _showLegacyBlockingLoader => false;
  bool _isDisposing = false; // 标记是否正在销毁
  int _importReloadCounter = 0; // 每次导入递增，强制重建 WebView
  bool _isAppInBackground = false; // 标记应用是否在后台
  bool _initialDataReadyForSync = false;
  bool _webViewReadyForSync = false;
  int _whiteboardRevision = 0;

  // Collab 适配器 - 完全模仿 DocumentBloc 的 TransactionAdapter
  WhiteboardCollabAdapter? _collabAdapter;

  // ExcalidrawWebView的GlobalKey，用于调用其方法
  // ✅ 关键修复：为每个视图创建唯一的GlobalKey，避免视图切换时PlatformView重复创建
  // 使用view.id确保每个白板视图都有唯一的key
  late GlobalKey<ExcalidrawWebViewState> _webViewKey;

  // 主题监听
  Brightness? _lastBrightness;
  Brightness? _pendingBrightness;
  Timer? _brightnessPollTimer;
  Timer? _brightnessDebounceTimer;
  int _themeSyncGeneration = 0;
  late final String _sessionTraceId;
  late final String _loadTraceId;
  late final Stopwatch _loadStopwatch;

  @override
  void initState() {
    super.initState();
    // 注册应用生命周期监听
    WidgetsBinding.instance.addObserver(this);
    // iOS 的 PlatformView 场景下，系统亮度事件偶尔不会传递到 Flutter 页面。
    // 轮询只在检测到亮度变化时同步，作为原生事件监听的兜底。
    _brightnessPollTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _syncSystemBrightness(_currentSystemBrightness()),
    );

    _sessionTraceId =
        ponyNotesDiagTraceId('whiteboard-session', widget.view.id);
    _loadTraceId = ponyNotesDiagTraceId('whiteboard', widget.view.id);
    _loadStopwatch = Stopwatch()..start();
    logDiagnosticEvent(
      'WhiteboardLoad',
      'page_init',
      {
        'sessionId': _sessionTraceId,
        'traceId': _loadTraceId,
        'viewId': widget.view.id,
        'viewName': widget.view.name,
      },
    );
    // debug logs removed

    // ✅ 关键修复：为每个视图创建唯一的GlobalKey
    // 使用view.id确保每个白板视图都有唯一的key，避免视图切换时PlatformView重复创建
    _webViewKey = GlobalKey<ExcalidrawWebViewState>(
      debugLabel: 'whiteboard_webview_${widget.view.id}',
    );

    // 注册导出和导入控制器到 GetIt，供 "更多操作" 菜单中的功能使用
    _registerControllers();

    // 初始化 Collab 适配器（模仿 DocumentBloc）
    _initCollabAdapter();

    _loadInitialData();
  }

  /// 注册导出和导入控制器到 GetIt
  void _registerControllers() {
    try {
      final getIt = GetIt.instance;
      final viewId = widget.view.id;

      // 注册导出控制器
      final exportController = WhiteboardExportController(
        viewId: viewId,
        exportCallback: _performExport,
      );
      getIt.registerSingleton<WhiteboardExportController>(
        exportController,
        instanceName: '${viewId}_export',
      );
      Log.info('[Whiteboard] 注册导出控制器: $viewId');

      // 注册导入控制器
      final importController = WhiteboardImportController(
        viewId: viewId,
        importCallback: _performImport,
      );
      getIt.registerSingleton<WhiteboardImportController>(
        importController,
        instanceName: '${viewId}_import',
      );
      Log.info('[Whiteboard] 注册导入控制器: $viewId');
    } catch (e) {
      Log.warn('[Whiteboard] 注册控制器失败: $e');
    }
  }

  /// 执行导出操作
  void _performExport(String format) {
    Log.info('[Whiteboard] 执行导出: $format');
    switch (format) {
      case 'ponynotes':
        _exportAsSourceFile();
        break;
      case 'png':
      case 'svg':
        _exportAsImage(format);
        break;
      default:
        Log.warn('[Whiteboard] 未知的导出格式: $format');
    }
  }

  /// 执行导入操作
  void _performImport(String filePath) {
    Log.info('[Whiteboard] 执行导入: $filePath');
    _importFromFilePath(filePath);
  }

  /// 从文件路径导入白板数据
  Future<void> _importFromFilePath(String filePath) async {
    final importStopwatch = Stopwatch()..start();
    try {
      logDiagnosticEvent(
        'WhiteboardLoad',
        'import_start',
        {
          'sessionId': _sessionTraceId,
          'traceId': _loadTraceId,
          'viewId': widget.view.id,
          'filePath': filePath,
        },
      );
      // 读取文件内容
      final fileContent = await File(filePath).readAsString();
      final data = jsonDecode(fileContent) as Map<String, dynamic>;

      // 验证数据格式
      if (!_isValidExcalidrawData(data)) {
        Log.error('[Whiteboard] 导入失败：文件格式无效');
        _showErrorSnackBar('文件格式无效，请选择有效的白板文件');
        return;
      }

      // 从标准Excalidraw格式中提取场景数据
      final sceneData = <String, dynamic>{
        'elements': data['elements'] ?? [],
        'appState': data['appState'] ?? {},
        'files': data['files'] ?? {},
      };

      // 更新 Adapter 的全量数据缓存并保存到后端
      _collabAdapter?.onWhiteboardDataChanged('update', sceneData);
      await _collabAdapter?.forceSync();

      // 通过重建 WebView（更换 Key + 更新 initialData）确保数据立即显示，
      // 与切换 tab 后重新加载的效果一致，避免依赖 JS 调用可能失败的问题。
      if (mounted && !_isDisposing) {
        setState(() {
          _initialData = sceneData;
          _isLoadingData = false;
          _importReloadCounter++;
          _webViewKey = GlobalKey<ExcalidrawWebViewState>(
            debugLabel:
                'whiteboard_webview_${widget.view.id}_i$_importReloadCounter',
          );
        });
      }

      Log.info('[Whiteboard] 导入成功');
      logDiagnosticEvent(
        'WhiteboardLoad',
        'import_done',
        {
          'sessionId': _sessionTraceId,
          'traceId': _loadTraceId,
          'viewId': widget.view.id,
          'durationMs': importStopwatch.elapsedMilliseconds,
          'elementsCount': sceneData['elements'] is List
              ? (sceneData['elements'] as List).length
              : null,
          'filesCount': sceneData['files'] is Map
              ? (sceneData['files'] as Map).length
              : null,
          'reloadCounter': _importReloadCounter,
        },
      );
      if (mounted) _showSuccessSnackBar('导入成功');
    } catch (e, stackTrace) {
      Log.error('[Whiteboard] 导入失败: $e');
      Log.error('[Whiteboard] 堆栈: $stackTrace');
      logDiagnosticEvent(
        'WhiteboardLoad',
        'import_done',
        {
          'sessionId': _sessionTraceId,
          'traceId': _loadTraceId,
          'viewId': widget.view.id,
          'durationMs': importStopwatch.elapsedMilliseconds,
          'success': false,
          'error': '$e',
        },
        warning: true,
      );
      if (mounted) _showErrorSnackBar('导入失败: $e');
    }
  }

  /// 显示错误提示
  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    showToastNotification(
      message: message,
      type: ToastificationType.error,
    );
  }

  /// 显示成功提示
  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    showToastNotification(
      message: message,
      type: ToastificationType.success,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // 【卡顿修复 2026-07-18】Windows 上 WebView 与 Flutter 窗口互抢焦点，会让生命周期
    // 在 inactive/resumed 之间高频翻转（日志实测约每秒 1~2 次、单次会话 197 次）。
    // 原实现每次翻转都无条件打 2 条 INFO 日志（合计约 790 条），每条都经 FFI 落盘，
    // 在绘制期间挤占帧时间。改为：只在标记位真正变化时才记录，且降为 debug。
    final isBackground = state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive;

    if (state != AppLifecycleState.resumed && !isBackground) {
      // detached/hidden 等其余状态不改变前后台标记，直接忽略。
      return;
    }

    if (isBackground == _isAppInBackground) {
      // 状态未变（焦点抖动导致的重复回调），无需处理，也不记录日志。
      return;
    }

    _isAppInBackground = isBackground;
    Log.debug(
      '[WhiteboardPage] 生命周期变化: $state (isBackground=$isBackground)',
    );
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    _syncSystemBrightness(_currentSystemBrightness());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // PlatformView 场景下原生亮度回调可能晚于 MediaQuery 更新；订阅当前
    // 页面依赖可以在系统外观变化的同一帧触发主题同步。
    _syncSystemBrightness(_currentSystemBrightness());
  }

  Brightness _currentSystemBrightness() {
    // 主题模式切换（浅色/深色/跟随系统）首先更新 MaterialApp 的有效主题；
    // 仅读取 platformBrightness 会漏掉应用内手动切换，导致 WebView 只能在
    // 白板重建后才拿到新主题。
    return Theme.of(context).brightness;
  }

  void _syncSystemBrightness(Brightness brightness) {
    if (_isDisposing || _lastBrightness == brightness) return;

    // iOS 在切换系统外观的动画窗口内可能连续回调相反的亮度值。
    // 只有亮度稳定一小段时间后才提交，避免 WebView 黑白主题交替闪烁。
    _pendingBrightness = brightness;
    _brightnessDebounceTimer?.cancel();
    _brightnessDebounceTimer = Timer(const Duration(milliseconds: 260), () {
      if (!mounted || _isDisposing) return;
      final stableBrightness = _pendingBrightness;
      final currentBrightness = _currentSystemBrightness();
      if (stableBrightness == null || stableBrightness != currentBrightness) {
        return;
      }
      if (_lastBrightness == stableBrightness) return;

      final theme = stableBrightness == Brightness.dark ? 'dark' : 'light';
      Log.info('[WhiteboardPage] 系统外观变化: $theme');
      _lastBrightness = stableBrightness;
      // 不重建包含原生 PlatformView 的整页布局。主题切换由 WebView
      // 桥接直接完成，避免 Flutter 重建与 JS 更新同时发生而产生闪屏。
      _scheduleThemeSync(theme);
    });
  }

  void _scheduleThemeSync(String theme) {
    final generation = ++_themeSyncGeneration;

    void sync() {
      if (!mounted || _isDisposing || generation != _themeSyncGeneration) {
        return;
      }
      final webViewState = _webViewKey.currentState;
      if (webViewState != null) {
        unawaited(webViewState.updateTheme(theme));
      }
    }

    // 立即尝试一次，并覆盖 WebView 尚未完成初始化的几个常见时序窗口。
    sync();
    WidgetsBinding.instance.addPostFrameCallback((_) => sync());
    Future<void>.delayed(const Duration(milliseconds: 180), sync);
    Future<void>.delayed(const Duration(milliseconds: 600), sync);
  }

  @override
  void dispose() {
    // 注销应用生命周期监听
    WidgetsBinding.instance.removeObserver(this);
    _brightnessPollTimer?.cancel();
    _brightnessPollTimer = null;
    _brightnessDebounceTimer?.cancel();
    _brightnessDebounceTimer = null;
    _pendingBrightness = null;
    _themeSyncGeneration++;

    _isDisposing = true;
    logDiagnosticEvent(
      'WhiteboardLoad',
      'page_dispose_start',
      {
        'sessionId': _sessionTraceId,
        'traceId': _loadTraceId,
        'viewId': widget.view.id,
        'elapsedMs': _loadStopwatch.elapsedMilliseconds,
      },
    );

    Log.info('[WhiteboardPage] 🔄 Dispose: starting cleanup...');

    final adapter = _collabAdapter;
    _collabAdapter = null;

    // 注销所有控制器（同步操作）
    _unregisterControllers();

    // 【协作丢元素根因修复 2026-07-01】页面 dispose 时不再 closeWhiteboard。
    // 根因：白板页在协作/焦点/生命周期变化（多端来回切窗口时尤为频繁）下会被反复整页销毁重建，
    // 而 manager.close_whiteboard 会 whiteboards.remove(viewId)，丢弃内存里“已与服务器实时同步”
    // 的 collab；重建时又走 “not in cache → 从异步滞后的本地磁盘重载”，读到的是你“离开”期间其他
    // 端新增元素尚未落盘的旧态，在重新 init_sync 补齐前这些元素从画面消失 —— 多端大量绘制时就表现
    // 为“元素一点一点丢”（日志：get_whiteboard_data 同一板几秒内 136K↔126K↔36K 剧烈波动）。
    // 改为让 collab 常驻管理器缓存并保持实时同步：页面重建直接命中缓存、复用当前已同步的内存态，
    // 重开即完整、彻底消除“旧盘回退”窗口。这里仍停 listener + forceSync，把 WebView 最后一批改动
    // 落进（仍存活的）collab；后端 collab 资源随会话保留（若担心内存/连接累积，后续可在 Rust
    // manager 加 LRU 驱逐或“关闭 tab 才真正 close”的区分，见 devops-docs 记录）。
    if (adapter != null) {
      adapter.forceSyncAndDispose().then((_) {
        Log.info(
            '[WhiteboardPage] ✅ Force sync completed, adapter disposed (collab kept alive & synced)');
        logDiagnosticEvent(
          'WhiteboardLoad',
          'page_dispose_force_sync_done',
          {
            'sessionId': _sessionTraceId,
            'traceId': _loadTraceId,
            'viewId': widget.view.id,
            'elapsedMs': _loadStopwatch.elapsedMilliseconds,
            'success': true,
          },
        );
      }).catchError((e) {
        Log.error('[WhiteboardPage] ❌ Force sync failed: $e');
        logDiagnosticEvent(
          'WhiteboardLoad',
          'page_dispose_force_sync_done',
          {
            'sessionId': _sessionTraceId,
            'traceId': _loadTraceId,
            'viewId': widget.view.id,
            'elapsedMs': _loadStopwatch.elapsedMilliseconds,
            'success': false,
            'error': '$e',
          },
          warning: true,
        );
      });
    }

    super.dispose();
    Log.info('[WhiteboardPage] ✅ Dispose completed (sync part)');
  }

  /// 注销所有控制器
  void _unregisterControllers() {
    try {
      final getIt = GetIt.instance;
      final viewId = widget.view.id;

      // 注销导出控制器
      if (getIt.isRegistered<WhiteboardExportController>(
        instanceName: '${viewId}_export',
      )) {
        getIt.unregister<WhiteboardExportController>(
          instanceName: '${viewId}_export',
        );
        Log.info('[Whiteboard] 注销导出控制器: $viewId');
      }

      // 注销导入控制器
      if (getIt.isRegistered<WhiteboardImportController>(
        instanceName: '${viewId}_import',
      )) {
        getIt.unregister<WhiteboardImportController>(
          instanceName: '${viewId}_import',
        );
        Log.info('[Whiteboard] 注销导入控制器: $viewId');
      }
    } catch (e) {
      Log.warn('[Whiteboard] 注销控制器失败: $e');
    }
  }

  /// 初始化 Collab 适配器（完全模仿 DocumentBloc 的 TransactionAdapter）
  void _initCollabAdapter() {
    _collabAdapter = WhiteboardCollabAdapter(
      viewId: widget.view.id,
      traceId: _loadTraceId,
      sessionId: _sessionTraceId,
      onDataChanged: (data) {
        // ✅ 关键：当收到远程同步更新时，将其推送到 WebView
        if (!_isDisposing && mounted) {
          for (final entry in data.entries) {
            _webViewKey.currentState?.pushData(entry.key, entry.value);
          }
        }
      },
    );
  }

  Future<void> _loadInitialData() async {
    final stageStopwatch = Stopwatch()..start();
    logDiagnosticEvent(
      'WhiteboardLoad',
      'local_data_start',
      {
        'sessionId': _sessionTraceId,
        'traceId': _loadTraceId,
        'viewId': widget.view.id,
        'elapsedMs': _loadStopwatch.elapsedMilliseconds,
      },
    );
    // debug log removed
    final service = WhiteboardDataService();
    final data = await service.loadWhiteboardData(
      widget.view.id,
      traceId: _loadTraceId,
      sessionId: _sessionTraceId,
      source: 'page-load',
    );
    logDiagnosticEvent(
      'WhiteboardLoad',
      'local_data_done',
      {
        'sessionId': _sessionTraceId,
        'traceId': _loadTraceId,
        'viewId': widget.view.id,
        'durationMs': stageStopwatch.elapsedMilliseconds,
        'elapsedMs': _loadStopwatch.elapsedMilliseconds,
        'hasData': data.isNotEmpty,
        'keys': data.keys.length,
        'elements':
            data['elements'] is List ? (data['elements'] as List).length : null,
        'files': data['files'] is Map ? (data['files'] as Map).length : null,
        'slow': stageStopwatch.elapsedMilliseconds > 1000,
      },
      warning: stageStopwatch.elapsedMilliseconds > 1000,
    );

    // debug log removed

    if (mounted && !_isDisposing) {
      setState(() {
        _initialData = data.isEmpty ? null : data;
        _isLoadingData = false;
      });

      // 初始化 Collab Adapter 的全量数据缓存
      // 确保后续的增量更新能合并到完整的状态中
      if (data.isNotEmpty) {
        _collabAdapter?.setInitialData(data);
        _whiteboardRevision = _extractRevision(data);
      }

      _initialDataReadyForSync = true;
      _collabAdapter?.markInitialDataReadyForAutoSync();
    }

    // debug log removed
  }

  /// 白板数据变更回调 - 完全模仿 DocumentBloc 的 transactionStream 监听
  void _onWhiteboardDataChanged(String type, Map<String, dynamic> data) {
    if (_isDisposing) {
      Log.debug('⚠️ [Whiteboard] Data change ignored - widget is disposing');
      return;
    }

    final incomingRevision = _extractRevision(data);
    if (incomingRevision > 0 && incomingRevision < _whiteboardRevision) {
      Log.info(
        '[Whiteboard] Dropping stale data change for ${widget.view.id}: incomingRevision=$incomingRevision currentRevision=$_whiteboardRevision',
      );
      return;
    }
    if (incomingRevision > _whiteboardRevision) {
      _whiteboardRevision = incomingRevision;
    }

    // debug log removed

    // 转发给 CollabAdapter 处理（完全模仿 DocumentBloc 的 TransactionAdapter）
    _collabAdapter?.onWhiteboardDataChanged(
      type,
      {...data, 'revision': _whiteboardRevision},
    );
  }

  void _onWhiteboardInitialReady() {
    if (_isDisposing || !mounted || _webViewReadyForSync) {
      return;
    }

    _webViewReadyForSync = true;
    _collabAdapter?.markWebViewReadyForAutoSync();
    logDiagnosticEvent(
      'WhiteboardLoad',
      'webview_initial_ready',
      {
        'sessionId': _sessionTraceId,
        'traceId': _loadTraceId,
        'viewId': widget.view.id,
        'initialDataReady': _initialDataReadyForSync,
        'elapsedMs': _loadStopwatch.elapsedMilliseconds,
      },
    );
  }

  void _onWhiteboardExport(String format, dynamic data) {
    if (!mounted) return;

    if (format == 'png' && data is String) {
      // dataURL -> 保存PNG
      _savePngDataUrl(data);
      return;
    }

    if (format == 'svg' && data is String) {
      // SVG 文本 -> 保存SVG
      _saveSvgData(data);
      return;
    }

    // PonyNotes 源文件（json）
    if (format == 'ponynotes' && data is Map<String, dynamic>) {
      _savePonyNotesJson(data);
      return;
    }

    showToastNotification(
      message: '导出格式不受支持: $format',
      type: ToastificationType.error,
    );
  }

  Future<void> _savePonyNotesJson(Map<String, dynamic> data) async {
    try {
      // 确保数据符合Excalidraw标准格式（保持兼容性）
      final ponyNotesData = <String, dynamic>{
        'type': 'excalidraw',
        'version': 2,
        'source': 'https://ponynotes.io',
        'elements': data['elements'] ?? [],
        'appState': data['appState'] ?? {},
        'files': data['files'] ?? {},
      };

      final filePicker = getIt<FilePickerService>();
      final bytes = Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(ponyNotesData)),
      );
      final savePath = await filePicker.saveFile(
        dialogTitle: '保存PonyNotes白板文件',
        fileName: '${widget.view.name}.ponynotes',
        type: FileType.custom,
        allowedExtensions: ['ponynotes', 'json'],
        bytes: Platform.isAndroid || Platform.isIOS ? bytes : null,
      );
      if (savePath == null) return;

      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(savePath).writeAsBytes(bytes);
      }

      if (mounted) {
        showToastNotification(
          message: '导出成功',
          type: ToastificationType.success,
        );
      }
    } catch (e) {
      Log.error('❌ [Whiteboard] Save PonyNotes json failed: $e');
      if (mounted) {
        showToastNotification(
          message: '保存失败: $e',
          type: ToastificationType.error,
        );
      }
    }
  }

  Future<void> _savePngDataUrl(String dataUrl) async {
    try {
      final uri = Uri.parse(dataUrl);
      final data = uri.data;
      if (data == null) {
        throw Exception('PNG 数据为空');
      }
      final bytes = data.contentAsBytes();
      final filePicker = getIt<FilePickerService>();
      final savePath = await filePicker.saveFile(
        dialogTitle: '保存PNG图片',
        fileName: '${widget.view.name}.png',
        type: FileType.custom,
        allowedExtensions: ['png'],
        bytes: Platform.isAndroid || Platform.isIOS
            ? Uint8List.fromList(bytes)
            : null,
      );
      if (savePath == null) return;

      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(savePath).writeAsBytes(bytes);
      }

      if (mounted) {
        showToastNotification(
          message: '导出成功',
          type: ToastificationType.success,
        );
      }
    } catch (e) {
      Log.error('❌ [Whiteboard] Save PNG failed: $e');
      if (mounted) {
        showToastNotification(
          message: '保存失败: $e',
          type: ToastificationType.error,
        );
      }
    }
  }

  Future<void> _saveSvgData(String svgContent) async {
    try {
      final filePicker = getIt<FilePickerService>();
      final savePath = await filePicker.saveFile(
        dialogTitle: '保存SVG图片',
        fileName: '${widget.view.name}.svg',
        type: FileType.custom,
        allowedExtensions: ['svg'],
        bytes: Platform.isAndroid || Platform.isIOS
            ? Uint8List.fromList(utf8.encode(svgContent))
            : null,
      );
      if (savePath == null) return;

      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(savePath).writeAsString(svgContent);
      }

      if (mounted) {
        showToastNotification(
          message: '导出成功',
          type: ToastificationType.success,
        );
      }
    } catch (e) {
      Log.error('❌ [Whiteboard] Save SVG failed: $e');
      if (mounted) {
        showToastNotification(
          message: '保存失败: $e',
          type: ToastificationType.error,
        );
      }
    }
  }

  void _onWhiteboardError(String error) {
    if (_isDisposing) {
      Log.debug('⚠️ [Whiteboard] Error ignored - widget is disposing: $error');
      return; // 如果正在销毁，忽略错误通知
    }

    // 处理错误
    Log.error('❌ [Whiteboard] Error: $error');
    if (mounted && !_isDisposing) {
      showToastNotification(
        message: '白板错误: $error',
        type: ToastificationType.error,
      );
    }
  }

  /// 手动保存白板数据（现在通过 CollabAdapter 自动处理）
  Future<void> _saveWhiteboard() async {
    Log.debug(
      '💾 [Whiteboard] Manual save triggered - forcing immediate sync (like DocumentBloc)',
    );

    // 强制立即同步（模仿 DocumentBloc 的行为）
    await _collabAdapter?.forceSync();

    if (mounted) {
      Log.debug('✅ [Whiteboard] Manual save completed via CollabAdapter');
      showToastNotification(
        message: '白板已保存',
        type: ToastificationType.success,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 使用 Flutter 当前生效的主题亮度，覆盖系统主题和应用内手动主题设置。
    // MediaQuery/平台分发器仅作为没有 Material 主题上下文时的兜底。
    final currentBrightness = _currentSystemBrightness();
    // WebView 使用透明背景，外层兜底层也必须跟随系统，否则首屏加载或
    // Excalidraw 画布尚未绘制时会露出白色背景。
    final canvasFallbackColor = currentBrightness == Brightness.dark
        ? _whiteboardCanvasDarkColor
        : _whiteboardCanvasLightColor;

    // 主题同步由 didChangeDependencies、didChangePlatformBrightness 和轮询
    // 触发。build 期间不再排队 updateTheme，避免旧亮度延迟写回 WebView。
    if (_isLoadingData && _showLegacyBlockingLoader) {
      return Scaffold(
        resizeToAvoidBottomInset: !PlatformInfo.isTablet,
        backgroundColor: canvasFallbackColor,
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在加载白板数据...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: !PlatformInfo.isTablet,
      backgroundColor: canvasFallbackColor,
      body: ValueListenableBuilder<bool>(
        valueListenable: FullWindowController.isFullWindow,
        child: _buildExcalidrawView(),
        builder: (context, isFullWindow, excalidrawView) {
          return Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(color: canvasFallbackColor),
              ),
              excalidrawView!,
              if (_shouldRenderTopActionsBar(isFullWindow))
                Positioned.fill(
                  child: _WhiteboardFloatingActionsOverlay(
                    key: ValueKey(
                      'whiteboard_top_actions_${widget.view.id}',
                    ),
                    edgeInsets: EdgeInsets.fromLTRB(
                      12,
                      isFullWindow ? 12 : 14,
                      isFullWindow ? 12 : 18,
                      12,
                    ),
                    child: _buildTopActionsBar(
                      context,
                      isFullWindow: isFullWindow,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  bool _shouldRenderTopActionsBar(bool isFullWindow) {
    // 退出“应用内全屏”按钮已由宿主右上角操作栏(UnifiedViewTopRightActions)提供，
    // 全屏时不再额外渲染内部浮层，避免出现上下两个“退出全屏”按钮。
    // 仅当宿主不提供右上角操作时(preferHostTopRightActions=false)才渲染内部浮层。
    return !widget.preferHostTopRightActions;
  }

  Widget _buildTopActionsBar(
    BuildContext context, {
    required bool isFullWindow,
  }) {
    final hideInternalMoreButton = isFullWindow &&
        (widget.preferHostFullWindowMoreItem ||
            widget.preferHostTopRightActions);

    // 全屏模式：删除黑色方块与收藏/更多按钮，仅保留一个极简的“退出全屏”按钮，
    // 否则全屏下侧边栏/标签栏均被隐藏，用户将无法退出全屏。
    final List<Widget> children = isFullWindow
        ? [
            _buildHeaderAction(_buildFullWindowAction(context)),
          ]
        : [
            _buildHeaderAction(_buildFavoriteAction(context)),
            const SizedBox(width: 6),
            _buildHeaderAction(_buildFullWindowAction(context)),
            const SizedBox(width: 6),
            if (!hideInternalMoreButton)
              _buildHeaderAction(_buildMoreActionsButton(context)),
          ];

    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(context).colorScheme.copyWith(
              onSurface: _whiteboardActionIconColor(context),
            ),
      ),
      child: IconTheme(
        data: IconThemeData(color: _whiteboardActionIconColor(context)),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 6,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderAction(Widget child, {double width = 36}) {
    return SizedBox(
      width: width,
      height: width,
      child: Center(child: child),
    );
  }

  Color _whiteboardActionIconColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? _whiteboardHostActionIconColorDark
        : _whiteboardHostActionIconColorLight;
  }

  Widget _buildFullWindowAction(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: FullWindowController.isFullWindow,
      builder: (context, isFullWindow, _) {
        return FlowyTooltip(
          message: isFullWindow
              ? '\u9000\u51fa\u5e94\u7528\u5185\u5168\u5c4f'
              : '\u5e94\u7528\u5185\u5168\u5c4f',
          child: SizedBox.square(
            dimension: 36,
            child: FlowyButton(
              useIntrinsicWidth: true,
              margin: EdgeInsets.zero,
              text: Icon(
                isFullWindow
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                size: 20,
                color: _whiteboardActionIconColor(context),
              ),
              onTap: FullWindowController.toggle,
            ),
          ),
        );
      },
    );
  }

  Widget _buildFavoriteAction(BuildContext context) {
    return BlocBuilder<FavoriteBloc, FavoriteState>(
      builder: (context, state) {
        final isFavorite = state.views.any((v) => v.item.id == widget.view.id);
        final inactiveIconColor = _whiteboardActionIconColor(context);
        return Listener(
          onPointerDown: (_) => context
              .read<FavoriteBloc>()
              .add(FavoriteEvent.toggle(widget.view)),
          child: FlowyTooltip(
            message: isFavorite
                ? LocaleKeys.button_removeFromFavorites.tr()
                : LocaleKeys.button_addToFavorites.tr(),
            child: FlowyHover(
              resetHoverOnRebuild: false,
              child: SizedBox.square(
                dimension: 36,
                child: Center(
                  child: FlowySvg(
                    isFavorite ? FlowySvgs.favorited_s : FlowySvgs.favorite_s,
                    size: const Size.square(18),
                    color: isFavorite ? null : inactiveIconColor,
                    blendMode: isFavorite ? null : BlendMode.srcIn,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 构建导出按钮 - 直接调用 WhiteboardPage 的导出方法
  Widget _buildMoreActionsButton(BuildContext context) {
    return AppFlowyPopover(
      direction: PopoverDirection.leftWithTopAligned,
      constraints: const BoxConstraints(
        maxWidth: 200,
        maxHeight: 150,
      ),
      margin: const EdgeInsets.symmetric(
        horizontal: 14.0,
        vertical: 12.0,
      ),
      clickHandler: PopoverClickHandler.gestureDetector,
      offset: const Offset(-10, 0),
      popupBuilder: (_) => _buildExportMenu(context),
      child: FlowyTooltip(
        message: LocaleKeys.button_more.tr(),
        child: SizedBox.square(
          dimension: 36,
          child: FlowyButton(
            useIntrinsicWidth: true,
            margin: EdgeInsets.zero,
            text: FlowySvg(
              FlowySvgs.workspace_three_dots_s,
              size: const Size.square(18),
              color: _whiteboardActionIconColor(context),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建导出菜单
  Widget _buildExportMenu(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildExportOption(
          context,
          label: '导出ponynotes文件',
          icon: Icons.save_alt,
          onTap: () => _exportAsPonynotes(context),
        ),
        const VSpace(4),
        _buildExportOption(
          context,
          label: '导出为 PNG 图片',
          icon: Icons.image,
          onTap: () => _exportAsPng(context),
        ),
        const VSpace(4),
        _buildExportOption(
          context,
          label: '导出为 SVG 图片',
          icon: Icons.broken_image,
          onTap: () => _exportAsSvg(context),
        ),
      ],
    );
  }

  /// 构建导出选项
  Widget _buildExportOption(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: FlowyButton(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        onTap: () {
          // 关闭弹出菜单 - 使用 maybeOf 并添加空值检查，避免在没有 PopoverContainer 时崩溃
          appflowy_popover.PopoverContainer.maybeOf(context)?.close();
          // 执行导出
          onTap();
        },
        leftIcon: Icon(
          icon,
          size: 16,
          color: Theme.of(context).iconTheme.color,
        ),
        iconPadding: 10.0,
        text: FlowyText.regular(
          label,
          fontSize: 14.0,
          lineHeight: 1.0,
          figmaLineHeight: 18.0,
        ),
      ),
    );
  }

  /// 导出为 PonyNotes 源文件
  Future<void> _exportAsPonynotes(BuildContext context) async {
    Log.info('[Whiteboard] 导出为 ponynotes 格式');
    try {
      await _exportAsSourceFile();
    } catch (e) {
      Log.error('[Whiteboard] 导出 ponynotes 失败: $e');
    }
  }

  /// 导出为 PNG 图片
  Future<void> _exportAsPng(BuildContext context) async {
    Log.info('[Whiteboard] 导出为 PNG');
    try {
      await _exportAsImage('png');
    } catch (e) {
      Log.error('[Whiteboard] 导出 PNG 失败: $e');
    }
  }

  /// 导出为 SVG 图片
  Future<void> _exportAsSvg(BuildContext context) async {
    Log.info('[Whiteboard] 导出为 SVG');
    try {
      await _exportAsImage('svg');
    } catch (e) {
      Log.error('[Whiteboard] 导出 SVG 失败: $e');
    }
  }

  Widget _buildExcalidrawView() {
    final webView = ExcalidrawWebView(
      key: _webViewKey, // 使用基于view.id的GlobalKey，既保证唯一性又能调用方法
      viewId: widget.view.id,
      sessionTraceId: _sessionTraceId,
      loadTraceId: _loadTraceId,
      reloadToken: _importReloadCounter,
      initialData: _initialData,
      initialDataLoaded: !_isLoadingData,
      deferInitialDataLoad: true,
      onDataChanged: _onWhiteboardDataChanged,
      onExport: _onWhiteboardExport,
      onError: _onWhiteboardError,
      onInitialReady: _onWhiteboardInitialReady,
    );

    // 🚀 Pad端键盘动画优化：固定MediaQuery.viewInsets，防止键盘弹出时触发布局重建
    // 原因：iPad/Android平板走桌面端布局，但有软键盘，导致MediaQuery.viewInsets变化
    // 影响：WebView（PlatformView）布局抖动，键盘动画卡顿
    // 解决方案：在平板上固定viewInsets为零，让WebView内部处理键盘
    if (PlatformInfo.isTablet) {
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(
          viewInsets: EdgeInsets.zero,
          padding: MediaQuery.of(context).padding,
        ),
        child: webView,
      );
    }

    return webView;
  }

  /// 导出为源文件
  /// 修复：使用WebView的导出API获取标准格式的Excalidraw数据，而不是直接从服务加载
  Future<void> _exportAsSourceFile() async {
    try {
      // 触发 WebView 内的导出，通过 _onWhiteboardExport 回调处理
      await _webViewKey.currentState?.exportDrawing('ponynotes');
    } catch (e) {
      Log.error('❌ [Whiteboard] Export source file failed: $e');
      if (mounted) {
        showToastNotification(
          message: '导出失败: $e',
          type: ToastificationType.error,
        );
      }
    }
  }

  /// 导出为图片
  Future<void> _exportAsImage(String format) async {
    try {
      // 触发 WebView 内的导出
      await _webViewKey.currentState?.exportDrawing(format);
    } catch (e) {
      Log.error('❌ [Whiteboard] Export image failed: $e');
      rethrow;
    }
  }

  /// 验证是否为有效的Excalidraw数据格式
  bool _isValidExcalidrawData(Map<String, dynamic> data) {
    return data.containsKey('type') &&
        data['type'] == 'excalidraw' &&
        data.containsKey('elements') &&
        data['elements'] is List;
  }

  int _extractRevision(Map<String, dynamic> data) {
    final revision = data['revision'];
    if (revision is int) return revision;
    if (revision is num) return revision.toInt();
    if (revision is String) return int.tryParse(revision) ?? 0;
    return 0;
  }
}

class _WhiteboardFloatingActionsOverlay extends StatefulWidget {
  const _WhiteboardFloatingActionsOverlay({
    super.key,
    required this.child,
    required this.edgeInsets,
  });

  final Widget child;
  final EdgeInsets edgeInsets;

  @override
  State<_WhiteboardFloatingActionsOverlay> createState() =>
      _WhiteboardFloatingActionsOverlayState();
}

class _WhiteboardFloatingActionsOverlayState
    extends State<_WhiteboardFloatingActionsOverlay> {
  static const Size _fallbackChildSize = Size(188, 52);

  Size _childSize = _fallbackChildSize;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = constraints.biggest;
        final insets = _effectiveInsets(context);
        final resolvedTopLeft = _resolveTopLeft(
          viewportSize: viewportSize,
          insets: insets,
        );

        return Stack(
          children: [
            Positioned(
              left: resolvedTopLeft.dx,
              top: resolvedTopLeft.dy,
              child: _MeasureSize(
                onChange: _handleChildSizeChanged,
                child: widget.child,
              ),
            ),
          ],
        );
      },
    );
  }

  EdgeInsets _effectiveInsets(BuildContext context) {
    final safePadding = MediaQuery.paddingOf(context);
    return EdgeInsets.fromLTRB(
      widget.edgeInsets.left + safePadding.left,
      widget.edgeInsets.top + safePadding.top,
      widget.edgeInsets.right + safePadding.right,
      widget.edgeInsets.bottom + safePadding.bottom,
    );
  }

  void _handleChildSizeChanged(Size size) {
    if (!mounted || size == Size.zero || size == _childSize) {
      return;
    }

    setState(() {
      _childSize = size;
    });
  }

  Offset _resolveTopLeft({
    required Size viewportSize,
    required EdgeInsets insets,
  }) {
    final movementRect = _movementRect(
      viewportSize: viewportSize,
      insets: insets,
    );
    return Offset(movementRect.right, movementRect.top);
  }

  Rect _movementRect({
    required Size viewportSize,
    required EdgeInsets insets,
  }) {
    final left = insets.left;
    final top = insets.top;
    final right = (viewportSize.width - insets.right - _childSize.width)
        .clamp(left, double.infinity)
        .toDouble();
    final bottom = (viewportSize.height - insets.bottom - _childSize.height)
        .clamp(top, double.infinity)
        .toDouble();
    return Rect.fromLTRB(left, top, right, bottom);
  }
}

class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({
    required this.onChange,
    required super.child,
  });

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _MeasureSizeRenderObject(onChange);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _MeasureSizeRenderObject renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class _MeasureSizeRenderObject extends RenderProxyBox {
  _MeasureSizeRenderObject(this.onChange);

  ValueChanged<Size> onChange;
  Size? _lastSize;

  @override
  void performLayout() {
    super.performLayout();
    final nextSize = child?.size;
    if (nextSize == null || nextSize == _lastSize) {
      return;
    }

    _lastSize = nextSize;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(nextSize));
  }
}
