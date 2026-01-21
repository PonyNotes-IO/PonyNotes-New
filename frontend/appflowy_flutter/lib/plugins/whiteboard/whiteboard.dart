library;

import 'dart:convert';
import 'dart:io';
import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/util.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
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
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:appflowy/plugins/document/presentation/document_collaborators.dart';
import 'package:appflowy/plugins/shared/share/share_button.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/workspace/presentation/widgets/favorite_button.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/more_view_actions.dart';

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
  
  // ExcalidrawWebView的GlobalKey，用于调用其方法
  // ✅ 关键修复：为每个视图创建唯一的GlobalKey，避免视图切换时PlatformView重复创建
  // 使用view.id确保每个白板视图都有唯一的key
  late final GlobalKey<ExcalidrawWebViewState> _webViewKey;
  
  // 主题监听
  Brightness? _lastBrightness;

  @override
  void initState() {
    super.initState();
    // debug logs removed
    
    // ✅ 关键修复：为每个视图创建唯一的GlobalKey
    // 使用view.id确保每个白板视图都有唯一的key，避免视图切换时PlatformView重复创建
    _webViewKey = GlobalKey<ExcalidrawWebViewState>(debugLabel: 'whiteboard_webview_${widget.view.id}');
    
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
    
    // 监听主题变化
    final appearanceCubit = context.watch<AppearanceSettingsCubit>();
    final currentBrightness = Theme.of(context).brightness;
    
    // 如果主题发生变化，更新Excalidraw主题
    if (_lastBrightness != null && _lastBrightness != currentBrightness) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _webViewKey.currentState?.updateTheme(
          currentBrightness == Brightness.dark ? 'dark' : 'light',
        );
      });
    }
    _lastBrightness = currentBrightness;
    
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
      body: Column(
        children: [
          // 顶部按钮栏（与手写笔记和文档视图统一）
          _buildTopActionsBar(context),
          // 白板内容
          Expanded(
            child: _buildExcalidrawView(),
          ),
        ],
      ),
    );
  }

  Widget _buildTopActionsBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (FeatureFlag.syncDocument.isOn) ...[
            DocumentCollaborators(
              key: ValueKey('collaborators_${widget.view.id}'),
              width: 120,
              height: 32,
              view: widget.view,
            ),
            const SizedBox(width: 16),
          ] else
            const SizedBox(width: 8),
          ViewFavoriteButton(
            key: ValueKey('favorite_button_${widget.view.id}'),
            view: widget.view,
          ),
          const SizedBox(width: 10),
          ShareButton(
            key: ValueKey('share_button_${widget.view.id}'),
            view: widget.view,
          ),
          const SizedBox(width: 4),
          MoreViewActions(view: widget.view),
        ],
      ),
    );
  }

  Widget _buildExcalidrawView() {
    // ✅ 每次build都创建新的Widget实例，避免PlatformView重复创建错误
    // ✅ 使用基于view.id的GlobalKey，确保每个白板视图都有唯一的key
    // 📌 关键修复：GlobalKey基于view.id，确保视图切换时不会复用旧的Widget
    // 🎯 这样即使快速切换白板视图，每个WebView的Key也是唯一的，不会导致PlatformView重复创建
    Log.debug('🔑 [Whiteboard] Creating ExcalidrawWebView with key based on view.id: ${widget.view.id}');
    
    return ExcalidrawWebView(
      key: _webViewKey, // 使用基于view.id的GlobalKey，既保证唯一性又能调用方法
      viewId: widget.view.id,
      initialData: _initialData,
      onDataChanged: _onWhiteboardDataChanged,
      onExport: _onWhiteboardExport,
      onError: _onWhiteboardError,
    );
  }

  /// 导入白板文件
  Future<void> _importWhiteboard() async {
    try {
      final filePicker = getIt<FilePickerService>();
      final result = await filePicker.pickFiles(
        dialogTitle: '选择Excalidraw文件',
        type: FileType.custom,
        allowedExtensions: ['excalidraw', 'json'],
      );

      if (result == null || result.files.isEmpty) {
        return; // 用户取消了选择
      }

      final file = result.files.first;
      if (file.path == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('无法读取文件路径'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // 读取文件内容
      final fileContent = await File(file.path!).readAsString();
      final data = jsonDecode(fileContent) as Map<String, dynamic>;

      // 验证数据格式
      if (!_isValidExcalidrawData(data)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('文件格式无效，请选择有效的Excalidraw文件'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // 确认是否覆盖当前内容
      final shouldImport = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导入确认'),
          content: const Text('导入文件将替换当前白板内容，是否继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认'),
            ),
          ],
        ),
      );

      if (shouldImport == true) {
        // 加载数据到Excalidraw
        await _webViewKey.currentState?.loadData(data);
        
        // 保存到后端
        final service = WhiteboardDataService();
        await service.saveWhiteboardData(widget.view.id, data);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('导入成功'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      Log.error('❌ [Whiteboard] Import failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导入失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 导出白板
  Future<void> _exportWhiteboard(String format) async {
    try {
      if (format == 'excalidraw') {
        // 导出为源文件
        await _exportAsSourceFile();
      } else if (format == 'png' || format == 'svg') {
        // 导出为图片
        await _exportAsImage(format);
      }
    } catch (e) {
      Log.error('❌ [Whiteboard] Export failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导出失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 导出为源文件
  Future<void> _exportAsSourceFile() async {
    try {
      // 获取当前白板数据
      final service = WhiteboardDataService();
      final data = await service.loadWhiteboardData(widget.view.id);

      // 转换为JSON字符串
      final jsonString = const JsonEncoder.withIndent('  ').convert(data);

      // 选择保存位置
      final filePicker = getIt<FilePickerService>();
      final savePath = await filePicker.saveFile(
        dialogTitle: '保存Excalidraw文件',
        fileName: '${widget.view.name}.excalidraw',
        type: FileType.custom,
        allowedExtensions: ['excalidraw'],
      );

      if (savePath == null) {
        return; // 用户取消了保存
      }

      // 保存文件
      final file = File(savePath);
      await file.writeAsString(jsonString);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('导出成功'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      Log.error('❌ [Whiteboard] Export source file failed: $e');
      rethrow;
    }
  }

  /// 导出为图片
  Future<void> _exportAsImage(String format) async {
    // 通过JavaScript调用Excalidraw的导出API
    // 注意：这需要Excalidraw提供相应的API
    // 暂时显示提示
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('图片导出功能（$format）将在后续版本中实现'),
          backgroundColor: Colors.orange,
        ),
      );
    }
    
    // TODO: 实现图片导出
    // 1. 通过JavaScript调用Excalidraw的导出API
    // 2. 获取图片数据（base64或blob）
    // 3. 保存为文件
  }

  /// 验证是否为有效的Excalidraw数据格式
  bool _isValidExcalidrawData(Map<String, dynamic> data) {
    return data.containsKey('type') &&
        data['type'] == 'excalidraw' &&
        data.containsKey('elements') &&
        data['elements'] is List;
  }
}

