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
import 'package:appflowy/plugins/whiteboard/application/whiteboard_bloc.dart';
import 'package:appflowy/plugins/whiteboard/application/drawing_models.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_data_service.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_collab_adapter.dart';
import 'package:appflowy/plugins/whiteboard/presentation/whiteboard_painter.dart';
import 'package:appflowy/plugins/whiteboard/presentation/excalidraw_webview.dart';

class WhiteboardPluginBuilder extends PluginBuilder {
  @override
  Plugin build(dynamic data) {
    print('🏗️ [WhiteboardPluginBuilder] build() called');
    print('🏗️ [WhiteboardPluginBuilder] data type: ${data.runtimeType}');
    
    if (data is ViewPB) {
      print('🏗️ [WhiteboardPluginBuilder] Creating WhiteboardPlugin for view: ${data.id}');
      print('🏗️ [WhiteboardPluginBuilder] View name: ${data.name}');
      print('🏗️ [WhiteboardPluginBuilder] View layout: ${data.layout}');
      return WhiteboardPlugin(pluginType: pluginType, view: data);
    }

    print('❌ [WhiteboardPluginBuilder] Invalid data type, throwing exception');
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
    print('🎯 [WhiteboardPlugin] Constructor called for view: ${view.id}');
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
    print('🔧 [WhiteboardPlugin] init() called for view: ${notifier.view.id}');
    _pageAccessLevelBloc = PageAccessLevelBloc(view: notifier.view)
      ..add(const PageAccessLevelEvent.initial());
    print('✅ [WhiteboardPlugin] init() completed');
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
    print('🎨 [WhiteboardPluginWidgetBuilder] buildWidget() called');
    print('🎨 [WhiteboardPluginWidgetBuilder] view: ${notifier.view.id}');
    print('🎨 [WhiteboardPluginWidgetBuilder] view name: ${notifier.view.name}');
    print('🎨 [WhiteboardPluginWidgetBuilder] PluginContext: $context');
    print('🎨 [WhiteboardPluginWidgetBuilder] shrinkWrap: $shrinkWrap');
    print('🎨 [WhiteboardPluginWidgetBuilder] data: $data');
    
    print('🎨 [WhiteboardPluginWidgetBuilder] Creating MultiBlocProvider...');
    final widget = MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (providerContext) {
            print('🎨 [WhiteboardPluginWidgetBuilder] Creating WhiteboardBloc');
            return WhiteboardBloc();
          },
        ),
        BlocProvider<PageAccessLevelBloc>.value(
          value: pageAccessLevelBloc,
        ),
      ],
      child: WhiteboardPage(
        key: ValueKey('whiteboard_page_${notifier.view.id}'),
        view: notifier.view,
        onViewChanged: (view) => notifier.view = view,
      ),
    );
    print('🎨 [WhiteboardPluginWidgetBuilder] MultiBlocProvider created, returning widget');
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
    print('🏗️ [WhiteboardPage] Constructor called for view: ${view.id} (${view.name})');
  }

  final ViewPB view;
  final Function(ViewPB) onViewChanged;

  @override
  State<WhiteboardPage> createState() {
    print('🏭 [WhiteboardPage] createState() called for view: ${view.id} (${view.name})');
    return _WhiteboardPageState();
  }
}

// 全局WebView实例计数器，确保每个WebView的Key绝对唯一
int _globalWebViewInstanceCounter = 0;

class _WhiteboardPageState extends State<WhiteboardPage> {
  bool _useExcalidraw = true; // 控制是否使用Excalidraw，可以添加切换功能
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
    print('🎨 [WhiteboardPage] initState called');
    print('🎨 [WhiteboardPage] view.id: ${widget.view.id}');
    print('🎨 [WhiteboardPage] view.name: ${widget.view.name}');
    print('🎨 [WhiteboardPage] view.layout: ${widget.view.layout}');
    print('🎨 [WhiteboardPage] view.extra: ${widget.view.extra}');
    
    // 初始化 Collab 适配器（模仿 DocumentBloc）
    _initCollabAdapter();
    
    _loadInitialData();
  }

  @override
  void dispose() {
    print('🗑️ [WhiteboardPage] dispose called for view: ${widget.view.id}');
    _isDisposing = true;
    
    // 销毁 Collab 适配器（模仿 DocumentBloc）
    _collabAdapter?.dispose();
    _collabAdapter = null;
    
    // 关闭白板以释放后端资源
    final service = WhiteboardDataService();
    service.closeWhiteboard(viewId: widget.view.id).then((result) {
      result.fold(
        (_) => print('✅ [WhiteboardPage] Whiteboard closed successfully'),
        (error) => print('⚠️ [WhiteboardPage] Failed to close whiteboard: ${error.msg}'),
      );
    });
    
    super.dispose();
  }

  /// 初始化 Collab 适配器（完全模仿 DocumentBloc 的 TransactionAdapter）
  void _initCollabAdapter() {
    print('🔧 [WhiteboardPage] Initializing Collab Adapter (like DocumentBloc)');
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
    print('✅ [WhiteboardPage] Collab Adapter initialized');
  }

  Future<void> _loadInitialData() async {
    print('🔄 [Whiteboard] Loading initial data for view: ${widget.view.id}');
    final service = WhiteboardDataService();
    final data = await service.loadWhiteboardData(widget.view.id);
    
    print('📦 [Whiteboard] Loaded data: ${data.isEmpty ? "空数据" : "有数据 (${data.keys.length} keys)"}');
    
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
    
    print('🔑 [Whiteboard] Assigned unique instance ID: $_webViewInstanceId');
  }

  /// 重新加载最新数据（用于视图切换）
  Future<void> _reloadLatestData() async {
    print('🔄 [Whiteboard] Reloading latest data for view: ${widget.view.id}');
    final service = WhiteboardDataService();
    final data = await service.loadWhiteboardData(widget.view.id);
    
    print('📦 [Whiteboard] Reloaded data: ${data.isEmpty ? "空数据" : "有数据 (${data.keys.length} keys)"}');
    
    // 生成新的唯一实例ID
    _globalWebViewInstanceCounter++;
    final uniqueInstanceId = _globalWebViewInstanceCounter;
    
    if (mounted && !_isDisposing) {
      setState(() {
        _initialData = data.isEmpty ? null : data;
        _currentData = data.isEmpty ? null : data;
        _webViewInstanceId = uniqueInstanceId; // 更新为全局唯一的实例ID
      });
    }
    
    print('🔑 [Whiteboard] Assigned unique instance ID: $_webViewInstanceId');
  }

  /// 白板数据变更回调 - 完全模仿 DocumentBloc 的 transactionStream 监听
  void _onWhiteboardDataChanged(Map<String, dynamic> data) {
    if (_isDisposing) {
      print('⚠️ [Whiteboard] Data change ignored - widget is disposing');
      return;
    }
    
    print('📝 [WhiteboardPage] =====================================================');
    print('📝 [WhiteboardPage] Data changed callback triggered (like EditorState.transactionStream)');
    print('📝 [WhiteboardPage] ViewID: ${widget.view.id}');
    print('📝 [WhiteboardPage] Data keys: ${data.keys.toList()}');
    if (data.containsKey('elements')) {
      final elements = data['elements'] as List?;
      print('📝 [WhiteboardPage] Elements count: ${elements?.length ?? 0}');
    }
    print('📝 [WhiteboardPage] Forwarding to CollabAdapter (like TransactionAdapter.apply)...');
    print('📝 [WhiteboardPage] =====================================================');
    
    // 转发给 CollabAdapter 处理（完全模仿 DocumentBloc 的 TransactionAdapter）
    _collabAdapter?.onWhiteboardDataChanged(data);
  }

  void _onWhiteboardExport(String format, dynamic data) {
    // 处理导出
    print('Export format: $format, data: $data');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('导出 $format 格式完成')),
    );
  }

  void _onWhiteboardError(String error) {
    if (_isDisposing) {
      print('⚠️ [Whiteboard] Error ignored - widget is disposing: $error');
      return; // 如果正在销毁，忽略错误通知
    }
    
    // 处理错误
    print('❌ [Whiteboard] Error: $error');
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
    print('💾 [Whiteboard] Manual save triggered - forcing immediate sync (like DocumentBloc)');
    
    // 强制立即同步（模仿 DocumentBloc 的行为）
    await _collabAdapter?.forceSync();
    
    if (mounted) {
      print('✅ [Whiteboard] Manual save completed via CollabAdapter');
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

  /// 旧的保存方法（已废弃）
  Future<void> _saveWhiteboardOld() async {
    print('💾 [Whiteboard] OLD Manual save triggered');
    
    if (_currentData == null) {
      print('⚠️ [Whiteboard] No data to save');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('没有数据需要保存'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    
    final service = WhiteboardDataService();
    final success = await service.saveWhiteboardData(widget.view.id, _currentData!);
    
    if (mounted) {
      if (success) {
        print('✅ [Whiteboard] Manual save successful');
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
      } else {
        print('❌ [Whiteboard] Manual save failed');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('保存失败，请重试'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    print('🖼️ [WhiteboardPage] build() called, _isLoadingData: $_isLoadingData');
    
    if (_isLoadingData) {
      print('⏳ [WhiteboardPage] Showing loading indicator');
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
    
    print('✅ [WhiteboardPage] Building whiteboard content');
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
              // 切换编辑器按钮
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: _useExcalidraw 
                    ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5)
                    : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  icon: Icon(
                    _useExcalidraw ? Icons.brush : Icons.draw_outlined,
                    size: 22,
                  ),
                  onPressed: () async {
                    if (_isDisposing) return; // 如果正在销毁，忽略操作
                    
                    print('🔄 [Whiteboard] Switching editor mode...');
                    
                    // 如果当前是Excalidraw且有数据，先尝试保存
                    if (_useExcalidraw && _currentData != null) {
                      print('💾 [Whiteboard] Saving current Excalidraw data before switch...');
                      final service = WhiteboardDataService();
                      await service.saveWhiteboardData(widget.view.id, _currentData!);
                    }
                    
                    // 生成新的全局唯一实例ID
                    _globalWebViewInstanceCounter++;
                    final uniqueInstanceId = _globalWebViewInstanceCounter;
                    
                    // 切换编辑器
                    if (mounted && !_isDisposing) {
                      setState(() {
                        _useExcalidraw = !_useExcalidraw;
                        // 使用全局唯一的实例ID，确保WebView完全重新创建
                        _webViewInstanceId = uniqueInstanceId;
                      });
                    }
                    
                    print('🔑 [Whiteboard] Editor switch - new instance ID: $_webViewInstanceId');
                    
                    // 如果切换到Excalidraw，重新加载最新数据
                    if (_useExcalidraw && mounted && !_isDisposing) {
                      print('🔄 [Whiteboard] Switched to Excalidraw, reloading data...');
                      await _reloadLatestData();
                    } else {
                      print('🔄 [Whiteboard] Switched to simple drawing mode');
                    }
                  },
                  tooltip: _useExcalidraw ? '切换到简单绘图' : '切换到专业白板',
                  style: IconButton.styleFrom(
                    foregroundColor: _useExcalidraw 
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              // 导出按钮
              if (_useExcalidraw) ...[  
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
              ],
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
          body: _useExcalidraw ? _buildExcalidrawView() : _buildLegacyView(),
        );
  }

  Widget _buildExcalidrawView() {
    // ✅ 每次build都创建新的Widget实例，避免PlatformView重复创建错误
    // ✅ 使用全局唯一的实例ID作为key，确保绝对不会出现ID冲突
    // 📌 Key的组成：viewId（白板ID） + 全局唯一的实例编号
    // 🎯 这样即使快速切换白板视图，每个WebView的Key也是全局唯一的
    final uniqueKey = '${widget.view.id}_global_$_webViewInstanceId';
    print('🔑 [Whiteboard] Creating ExcalidrawWebView with unique key: $uniqueKey');
    
    return ExcalidrawWebView(
      key: ValueKey(uniqueKey), // 全局唯一的Key，确保PlatformView正确创建和清理
      viewId: widget.view.id,
      initialData: _initialData,
      onDataChanged: _onWhiteboardDataChanged,
      onExport: _onWhiteboardExport,
      onError: _onWhiteboardError,
    );
  }

  Widget _buildLegacyView() {
    return BlocBuilder<WhiteboardBloc, WhiteboardState>(
      builder: (context, state) {
        final bloc = context.read<WhiteboardBloc>();
        
        return Row(
          children: [
            // 左侧工具栏
            Container(
              width: 80,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  right: BorderSide(
                    color: Colors.grey.shade300,
                  ),
                ),
              ),
              child: _buildToolbar(state, bloc),
            ),
            // 主绘图区域
            Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: ClipRect(
                    child: Builder(
                      builder: (drawingContext) {
                        return GestureDetector(
                          onPanStart: (details) {
                            final renderBox = drawingContext.findRenderObject() as RenderBox;
                            final localPosition = renderBox.globalToLocal(details.globalPosition);
                            bloc.add(StartDrawing(localPosition));
                          },
                          onPanUpdate: (details) {
                            final renderBox = drawingContext.findRenderObject() as RenderBox;
                            final localPosition = renderBox.globalToLocal(details.globalPosition);
                            bloc.add(UpdateDrawing(localPosition));
                          },
                          onPanEnd: (details) {
                            bloc.add(const EndDrawing());
                          },
                          child: Stack(
                            children: [
                              // 网格背景
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: GridPainter(),
                                ),
                              ),
                              // 绘图层
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: WhiteboardPainter(
                                    drawingData: state.drawingData,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          );
      },
    );
  }

  Widget _buildToolbar(WhiteboardState state, WhiteboardBloc bloc) {
    return Column(
      children: [
        const SizedBox(height: 16),
        // 画笔工具
        _ToolButton(
          icon: Icons.brush,
          label: '画笔',
          isSelected: state.selectedTool == DrawingTool.pen,
          onTap: () => bloc.add(const SelectTool(DrawingTool.pen)),
        ),
        // 直线工具
        _ToolButton(
          icon: Icons.timeline,
          label: '直线',
          isSelected: state.selectedTool == DrawingTool.line,
          onTap: () => bloc.add(const SelectTool(DrawingTool.line)),
        ),
        // 矩形工具
        _ToolButton(
          icon: Icons.crop_square,
          label: '矩形',
          isSelected: state.selectedTool == DrawingTool.rectangle,
          onTap: () => bloc.add(const SelectTool(DrawingTool.rectangle)),
        ),
        // 圆形工具
        _ToolButton(
          icon: Icons.circle_outlined,
          label: '圆形',
          isSelected: state.selectedTool == DrawingTool.circle,
          onTap: () => bloc.add(const SelectTool(DrawingTool.circle)),
        ),
        // 橡皮擦
        _ToolButton(
          icon: Icons.auto_fix_high,
          label: '橡皮擦',
          isSelected: state.selectedTool == DrawingTool.eraser,
          onTap: () => bloc.add(const SelectTool(DrawingTool.eraser)),
        ),
        const SizedBox(height: 24),
        // 颜色选择
        _buildColorPicker(state, bloc),
        const SizedBox(height: 16),
        // 线条粗细
        _buildStrokeWidthSlider(state, bloc),
      ],
    );
  }

  Widget _buildColorPicker(WhiteboardState state, WhiteboardBloc bloc) {
    final colors = [
      Colors.black,
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
    ];

    return Column(
      children: [
        const Text('颜色', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: colors.map((color) {
            final isSelected = state.selectedColor == color;
            return GestureDetector(
              onTap: () => bloc.add(ChangeColor(color)),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? Colors.blue : Colors.grey.shade400,
                    width: isSelected ? 2 : 1,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildStrokeWidthSlider(WhiteboardState state, WhiteboardBloc bloc) {
    return Column(
      children: [
        const Text('粗细', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 8),
        RotatedBox(
          quarterTurns: 3,
          child: Slider(
            value: state.strokeWidth,
            min: 1.0,
            max: 10.0,
            divisions: 9,
            onChanged: (value) => bloc.add(ChangeStrokeWidth(value)),
          ),
        ),
      ],
    );
  }

}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isSelected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 64,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: isSelected 
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon, 
                size: 24,
                color: isSelected 
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected 
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

