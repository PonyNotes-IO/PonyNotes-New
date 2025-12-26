library;

import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/util.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/widgets/tab_bar_item.dart';
import 'package:appflowy/workspace/presentation/widgets/view_title_bar.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_data_service.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_collab_adapter.dart';
import 'package:appflowy/plugins/whiteboard/presentation/excalidraw_webview.dart';

class WhiteboardPluginBuilder extends PluginBuilder {
  @override
  Plugin build(dynamic data) {
    // debug logs removed
    
    if (data is ViewPB) {
      // debug logs removed
      return WhiteboardPlugin(pluginType: pluginType, view: data);
    }

    Log.error('❌ [WhiteboardPluginBuilder] Invalid data type, throwing exception');
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
  late final PageAccessLevelBloc _pageAccessLevelBloc;

  @override
  PluginWidgetBuilder get widgetBuilder => WhiteboardPluginWidgetBuilder(
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
    _pageAccessLevelBloc = PageAccessLevelBloc(view: notifier.view)
      ..add(const PageAccessLevelEvent.initial());
    // debug log removed
  }

  @override
  void dispose() {
    _pageAccessLevelBloc.close();
    notifier.dispose();
  }
}

class WhiteboardPluginWidgetBuilder extends PluginWidgetBuilder {
  WhiteboardPluginWidgetBuilder({
    required this.notifier,
    required this.pageAccessLevelBloc,
  });

  final ViewPluginNotifier notifier;
  final PageAccessLevelBloc pageAccessLevelBloc;

  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) {
    // debug logs removed
    final widget = BlocProvider<PageAccessLevelBloc>.value(
      value: pageAccessLevelBloc,
      child: WhiteboardPage(
        key: ValueKey('whiteboard_page_${notifier.view.id}'),
        view: notifier.view,
        onViewChanged: (view) => notifier.view = view,
      ),
    );
    // debug log removed
    return widget;
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
  Widget tabBarItem(String pluginId, [bool shortForm = false]) =>
      ViewTabBarItem(view: notifier.view, shortForm: shortForm);
}

class WhiteboardPage extends StatefulWidget {
  WhiteboardPage({
    super.key,
    required this.view,
    required this.onViewChanged,
  }) {
    // debug log removed
  }

  final ViewPB view;
  final Function(ViewPB) onViewChanged;

  @override
  State<WhiteboardPage> createState() {
    // debug log removed
    return _WhiteboardPageState();
  }
}

// 全局WebView实例计数器，确保每个WebView的Key绝对唯一
int _globalWebViewInstanceCounter = 0;

class _WhiteboardPageState extends State<WhiteboardPage> {
  Map<String, dynamic>? _initialData;
  Map<String, dynamic>? _currentData; // 当前白板数据（实时更新）
  bool _isLoadingData = true;
  int _webViewInstanceId = 0; // 用于生成唯一的WebView Key
  bool _isDisposing = false; // 标记是否正在销毁
  
  // Collab 适配器 - 完全模仿 DocumentBloc 的 TransactionAdapter
  WhiteboardCollabAdapter? _collabAdapter;

  @override
  void initState() {
    super.initState();
    // debug logs removed
    
    // 初始化 Collab 适配器（模仿 DocumentBloc）
    _initCollabAdapter();
    
    _loadInitialData();
  }

  @override
  void dispose() {
    // debug log removed
    _isDisposing = true;
    
    // 销毁 Collab 适配器（模仿 DocumentBloc）
    _collabAdapter?.dispose();
    _collabAdapter = null;
    
    // 关闭白板以释放后端资源
    final service = WhiteboardDataService();
    service.closeWhiteboard(viewId: widget.view.id).then((result) {
      result.fold(
        (_) => null,
        (error) => Log.error('⚠️ [WhiteboardPage] Failed to close whiteboard: ${error.msg}'),
      );
    });
    
    super.dispose();
  }

  /// 初始化 Collab 适配器（完全模仿 DocumentBloc 的 TransactionAdapter）
  void _initCollabAdapter() {
    // debug log removed
    _collabAdapter = WhiteboardCollabAdapter(
      viewId: widget.view.id,
      onDataChanged: (data) {
        // 更新当前数据缓存（用于 UI 显示）
        if (mounted && !_isDisposing) {
          setState(() {
            _currentData = data;
          });
        }
      },
    );
    // debug log removed
  }

  Future<void> _loadInitialData() async {
    // debug log removed
    final service = WhiteboardDataService();
    final data = await service.loadWhiteboardData(widget.view.id);
    
    // debug log removed
    
    // 生成新的唯一实例ID
    _globalWebViewInstanceCounter++;
    final uniqueInstanceId = _globalWebViewInstanceCounter;
    
    if (mounted && !_isDisposing) {
      setState(() {
        _initialData = data.isEmpty ? null : data;
        _currentData = data.isEmpty ? null : data; // 同步当前数据
        _isLoadingData = false;
        _webViewInstanceId = uniqueInstanceId; // 使用全局唯一的实例ID
      });
    }
    
    // debug log removed
  }

  /// 白板数据变更回调 - 完全模仿 DocumentBloc 的 transactionStream 监听
  void _onWhiteboardDataChanged(String type, Map<String, dynamic> data) {
    if (_isDisposing) {
      Log.debug('⚠️ [Whiteboard] Data change ignored - widget is disposing');
      return;
    }
    
    // debug log removed
    
    // 转发给 CollabAdapter 处理（完全模仿 DocumentBloc 的 TransactionAdapter）
    _collabAdapter?.onWhiteboardDataChanged(type,data);
  }

  void _onWhiteboardExport(String format, dynamic data) {
    // 处理导出
    Log.debug('Export format: $format, data: $data');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('导出 $format 格式完成')),
    );
  }

  void _onWhiteboardError(String error) {
    if (_isDisposing) {
      Log.debug('⚠️ [Whiteboard] Error ignored - widget is disposing: $error');
      return; // 如果正在销毁，忽略错误通知
    }
    
    // 处理错误
    Log.error('❌ [Whiteboard] Error: $error');
    if (mounted && !_isDisposing) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('白板错误: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// 手动保存白板数据（现在通过 CollabAdapter 自动处理）
  Future<void> _saveWhiteboard() async {
    Log.debug('💾 [Whiteboard] Manual save triggered - forcing immediate sync (like DocumentBloc)');
    
    // 强制立即同步（模仿 DocumentBloc 的行为）
    await _collabAdapter?.forceSync();
    
    if (mounted) {
      Log.debug('✅ [Whiteboard] Manual save completed via CollabAdapter');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('白板已保存'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    Log.debug('🖼️ [WhiteboardPage] build() called, _isLoadingData: $_isLoadingData');
    
    if (_isLoadingData) {
      Log.debug('⏳ [WhiteboardPage] Showing loading indicator');
      return Scaffold(
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
    
    Log.debug('✅ [WhiteboardPage] Building whiteboard content');
    return Scaffold(
          appBar: AppBar(
            elevation: 0,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            backgroundColor: Theme.of(context).colorScheme.surface,
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            toolbarHeight: 64,
            titleSpacing: 8,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.palette_outlined,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.view.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              // 导出按钮
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.download_outlined, size: 22),
                  tooltip: '导出',
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  offset: const Offset(0, 8),
                  onSelected: (format) {
                    // 导出功能将在后续版本中实现
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('导出 $format 格式功能将在后续版本中实现'),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    );
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'png',
                      child: Row(
                        children: [
                          Icon(
                            Icons.image_outlined,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          const Text('导出为 PNG'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'svg',
                      child: Row(
                        children: [
                          Icon(
                            Icons.code,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          const Text('导出为 SVG'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'json',
                      child: Row(
                        children: [
                          Icon(
                            Icons.data_object,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          const Text('导出为 JSON'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // 保存按钮
              Container(
                margin: const EdgeInsets.only(left: 4, right: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  icon: const Icon(Icons.save_outlined, size: 22),
                  onPressed: _saveWhiteboard,
                  tooltip: '保存',
                  style: IconButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          body: _buildExcalidrawView(),
        );
  }

  Widget _buildExcalidrawView() {
    // ✅ 每次build都创建新的Widget实例，避免PlatformView重复创建错误
    // ✅ 使用全局唯一的实例ID作为key，确保绝对不会出现ID冲突
    // 📌 Key的组成：viewId（白板ID） + 全局唯一的实例编号
    // 🎯 这样即使快速切换白板视图，每个WebView的Key也是全局唯一的
    final uniqueKey = '${widget.view.id}_global_$_webViewInstanceId';
    Log.debug('🔑 [Whiteboard] Creating ExcalidrawWebView with unique key: $uniqueKey');
    
    return ExcalidrawWebView(
      key: ValueKey(uniqueKey), // 全局唯一的Key，确保PlatformView正确创建和清理
      viewId: widget.view.id,
      initialData: _initialData,
      onDataChanged: _onWhiteboardDataChanged,
      onExport: _onWhiteboardExport,
      onError: _onWhiteboardError,
    );
  }
}

