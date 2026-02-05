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
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/widgets/tab_bar_item.dart';
import 'package:appflowy/workspace/presentation/widgets/view_title_bar.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:appflowy/workspace/presentation/home/full_window_controller.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_data_service.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_collab_adapter.dart';
import 'package:appflowy/plugins/whiteboard/presentation/excalidraw_webview.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';
import 'package:appflowy/plugins/document/presentation/document_collaborators.dart';
import 'package:appflowy/plugins/shared/share/share_button.dart';
import 'package:appflowy/plugins/whiteboard/presentation/whiteboard_export_action.dart';
import 'package:appflowy_popover/appflowy_popover.dart' as appflowy_popover;
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
    try {
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

      // 加载数据到 Excalidraw
        await _webViewKey.currentState?.loadData(sceneData);

        // 保存到后端
        final service = WhiteboardDataService();
        final success = await service.saveWhiteboardData(
          widget.view.id,
          sceneData,
        );

        if (success) {
          Log.info('[Whiteboard] 导入成功');
          _showSuccessSnackBar('导入成功');
        } else {
          Log.error('[Whiteboard] 保存失败');
          _showErrorSnackBar('保存失败');
        }
    } catch (e, stackTrace) {
      Log.error('[Whiteboard] 导入失败: $e');
      Log.error('[Whiteboard] 堆栈: $stackTrace');
      _showErrorSnackBar('导入失败: $e');
    }
  }

  /// 显示错误提示
  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// 显示成功提示
  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    // debug log removed
    _isDisposing = true;

    // 注销所有控制器
    _unregisterControllers();

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

  /// 注销所有控制器
  void _unregisterControllers() {
    try {
      final getIt = GetIt.instance;
      final viewId = widget.view.id;

      // 注销导出控制器
      if (getIt.isRegistered<WhiteboardExportController>(
          instanceName: '${viewId}_export')) {
        getIt.unregister<WhiteboardExportController>(
            instanceName: '${viewId}_export');
        Log.info('[Whiteboard] 注销导出控制器: $viewId');
      }

      // 注销导入控制器
      if (getIt.isRegistered<WhiteboardImportController>(
          instanceName: '${viewId}_import')) {
        getIt.unregister<WhiteboardImportController>(
            instanceName: '${viewId}_import');
        Log.info('[Whiteboard] 注销导入控制器: $viewId');
      }
    } catch (e) {
      Log.warn('[Whiteboard] 注销控制器失败: $e');
    }
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('导出格式不受支持: $format'),
        backgroundColor: Colors.red,
      ),
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
      final savePath = await filePicker.saveFile(
        dialogTitle: '保存PonyNotes白板文件',
        fileName: '${widget.view.name}.ponynotes',
        type: FileType.custom,
        allowedExtensions: ['ponynotes', 'json'],
      );
      if (savePath == null) return;

      final file = File(savePath);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(ponyNotesData),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('导出成功'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      Log.error('❌ [Whiteboard] Save PonyNotes json failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('保存失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _savePngDataUrl(String dataUrl) async {
    try {
      final filePicker = getIt<FilePickerService>();
      final savePath = await filePicker.saveFile(
        dialogTitle: '保存PNG图片',
        fileName: '${widget.view.name}.png',
        type: FileType.custom,
        allowedExtensions: ['png'],
      );
      if (savePath == null) return;

      final uri = Uri.parse(dataUrl);
      final data = uri.data;
      if (data == null) {
        throw Exception('PNG 数据为空');
      }
      final bytes = data.contentAsBytes();
      final file = File(savePath);
      await file.writeAsBytes(bytes);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('导出成功'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      Log.error('❌ [Whiteboard] Save PNG failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('保存失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
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
      );
      if (savePath == null) return;

      final file = File(savePath);
      await file.writeAsString(svgContent);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('导出成功'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      Log.error('❌ [Whiteboard] Save SVG failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('保存失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
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
        children: [
          const Spacer(),
          // 收藏、分享、更多、全窗口按钮
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
          const SizedBox(width: 8),
          // 导出按钮 - 直接调用 WhiteboardPage 的导出方法
          _buildExportButton(context),
          const SizedBox(width: 12),
          // 全窗口 / 退出全窗口按钮：通过 FullWindowController 控制全局布局
          ValueListenableBuilder<bool>(
            valueListenable: FullWindowController.isFullWindow,
            builder: (context, isFullWindow, _) {
              return Tooltip(
                message: isFullWindow ? '退出全窗口显示' : '全窗口显示',
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: IconButton(
                    iconSize: 18,
                    padding: const EdgeInsets.all(8),
                    icon: Icon(
                      isFullWindow
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                    ),
                    onPressed: FullWindowController.toggle,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 构建导出按钮 - 直接调用 WhiteboardPage 的导出方法
  Widget _buildExportButton(BuildContext context) {
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
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(vertical: 2.0),
        child: FlowyIconTextButton(
          expandText: false,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          leftIconBuilder: (_) => const Icon(
            Icons.file_download_outlined,
            size: 16,
          ),
          iconPadding: 10.0,
          textBuilder: (_) => FlowyText.regular(
            '导出'.tr(),
            fontSize: 14.0,
            lineHeight: 1.0,
            figmaLineHeight: 18.0,
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
        dialogTitle: '选择PonyNotes白板文件',
        type: FileType.custom,
        allowedExtensions: ['ponynotes', 'excalidraw', 'json'],
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
            content: Text('文件格式无效，请选择有效的白板文件'),
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
        // 从标准Excalidraw格式中提取场景数据
        final sceneData = <String, dynamic>{
          'elements': data['elements'] ?? [],
          'appState': data['appState'] ?? {},
          'files': data['files'] ?? {},
        };
        
        // 加载数据到Excalidraw（这会自动重新初始化UI）
        await _webViewKey.currentState?.loadData(sceneData);
        
        // 保存到后端（保存完整格式）
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
      if (format == 'ponynotes') {
        // 导出为源文件：使用WebView的导出API获取标准格式数据
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
  /// 修复：使用WebView的导出API获取标准格式的Excalidraw数据，而不是直接从服务加载
  Future<void> _exportAsSourceFile() async {
    try {
      // 触发 WebView 内的导出，通过 _onWhiteboardExport 回调处理
      await _webViewKey.currentState?.exportDrawing('ponynotes');
    } catch (e) {
      Log.error('❌ [Whiteboard] Export source file failed: $e');
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
}

