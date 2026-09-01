library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/document/document.dart';
import 'package:appflowy/plugins/document/document_page.dart';
import 'package:appflowy/plugins/util.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy/workspace/application/recent/cached_recent_service.dart';
import 'package:appflowy/workspace/application/sidebar/folder/folder_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/plugins/space_hub/space_hub_selection.dart';
import 'package:appflowy/plugins/space_hub/space_hub_plugin_view.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/view_info/view_info_bloc.dart';
import 'package:appflowy/workspace/presentation/home/hotkeys.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/home/full_window_controller.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_add_button.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_item.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/more_view_actions.dart';
import 'package:appflowy/workspace/presentation/widgets/tab_bar_item.dart';
import 'package:appflowy/workspace/presentation/widgets/unified_view_top_right_actions.dart';
import 'package:appflowy/workspace/presentation/widgets/view_title_bar.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart' hide AFRolePB;
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/platform_extension.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../generated/locale_keys.g.dart';

class SpaceHubMiddlePanelController {
  SpaceHubMiddlePanelController._();

  static final ValueNotifier<String?> _revealRequest = ValueNotifier(null);

  static ValueListenable<String?> get revealRequest => _revealRequest;

  static void reveal(String spaceId) {
    _revealRequest.value = null;
    _revealRequest.value = spaceId;
  }
}

/// SpaceHubPluginBuilder 用于创建空间统一页面插件
/// 左侧显示空间下的文档/文件夹列表，右侧显示选中文档的详情
class SpaceHubPluginBuilder extends PluginBuilder {
  @override
  Plugin build(dynamic data) {
    if (data is ViewPB) {
      return SpaceHubPlugin(view: data);
    }
    throw FlowyPluginException.invalidData;
  }

  @override
  String get menuName => "空间";

  @override
  FlowySvgData get icon => FlowySvgs.folder_m;

  @override
  PluginType get pluginType => PluginType.folder; // 复用 folder 类型

  @override
  ViewLayoutPB? get layoutType => null; // 空间没有特定的 layoutType
}

class SpaceHubPlugin extends Plugin {
  SpaceHubPlugin({
    required this.view,
    ViewPB? initialSelectedView,
    this.tabView,
  })  : notifier = ViewPluginNotifier(view: view),
        _viewInfoBloc = ViewInfoBloc(view: view)
          ..add(const ViewInfoEvent.started()),
        _pageAccessLevelBloc = PageAccessLevelBloc(view: view)
          ..add(const PageAccessLevelEvent.initial()),
        _selectedViewNotifier = ValueNotifier<ViewPB?>(initialSelectedView),
        _currentViewInfoBlocNotifier = ValueNotifier<ViewInfoBloc?>(null);

  final ViewPB view;
  final ViewInfoBloc _viewInfoBloc;
  final PageAccessLevelBloc _pageAccessLevelBloc;
  final ValueNotifier<ViewPB?> _selectedViewNotifier;
  final ViewPB? tabView;
  final ValueNotifier<ViewInfoBloc?>
      _currentViewInfoBlocNotifier; // ✅ 用于跟踪当前文档的 ViewInfoBloc

  @override
  final ViewPluginNotifier notifier;

  @override
  PluginWidgetBuilder get widgetBuilder => SpaceHubPluginWidgetBuilder(
        bloc: _viewInfoBloc,
        pageAccessLevelBloc: _pageAccessLevelBloc,
        notifier: notifier,
        selectedViewNotifier: _selectedViewNotifier,
        currentViewInfoBlocNotifier: _currentViewInfoBlocNotifier,
        initialSelectedView: _selectedViewNotifier.value,
        tabView: tabView,
      );

  @override
  PluginType get pluginType => PluginType.folder;

  @override
  PluginId get id => tabView?.id ?? notifier.view.id;

  @override
  void init() {
    // Blocs are already initialized in constructor
  }

  @override
  void dispose() {
    _viewInfoBloc.close();
    _pageAccessLevelBloc.close();
    _selectedViewNotifier.dispose();
    _currentViewInfoBlocNotifier.dispose();
    notifier.dispose();
  }

  /// 清空中间栏的选中视图(用于返回操作:从 SpaceHub 内嵌的子文档
  /// 点 back 时,清空选中回到 SpaceHub 主页的子页面列表)。
  void clearSelection() {
    if (_selectedViewNotifier.value != null) {
      _selectedViewNotifier.value = null;
    }
  }

  /// 当前中间栏是否选中了某个子视图(用于 back 时判断是否在 SpaceHub 内嵌文档中)。
  bool get hasSelectedView => _selectedViewNotifier.value != null;

  /// 获取当前选中的子视图（用于返回导航时切回父文档）。
  ViewPB? get currentSelectedView => _selectedViewNotifier.value;

  /// 由 TabsBloc 在 SpaceHub 内嵌子文档中的链接点击时调用:
  /// 不替换 SpaceHub,而是在 SpaceHub 内选中目标子视图(在 rightPanel 中显示)。
  /// 这样:
  ///   - SpaceHub 整体布局保留(侧边栏 + 中间栏 + rightPanel)
  ///   - 中间栏高亮更新为目标 view
  ///   - rightPanel 切换为新的 DocumentPage
  /// 如果 view 是 space 本身或 isSpace=true,则不做任何操作(让外层 fallthrough)。
  void selectViewInSpaceHub(ViewPB view) {
    if (view.id.isEmpty) return;
    if (view.isSpace) return; // space 视图不应该在 SpaceHub 内嵌套显示
    Log.info('[SpaceHubLink] selectViewInSpaceHub: ${view.name}(${view.id}), layout=${view.layout}');
    _selectedViewNotifier.value = view;
    spaceHubSelectedViewLayoutNotifier.value = view.layout;
  }
}

/// SpaceHubPluginWidgetBuilder 实现空间统一页面的布局
/// 左侧：空间文档列表，右侧：选中文档详情
class SpaceHubPluginWidgetBuilder extends PluginWidgetBuilder
    with NavigationItem {
  SpaceHubPluginWidgetBuilder({
    required this.bloc,
    required this.notifier,
    required this.pageAccessLevelBloc,
    required this.selectedViewNotifier,
    required this.currentViewInfoBlocNotifier,
    this.initialSelectedView,
    this.tabView,
  });

  final ViewInfoBloc bloc;
  final ViewPluginNotifier notifier;
  final PageAccessLevelBloc pageAccessLevelBloc;
  final ValueNotifier<ViewPB?> selectedViewNotifier;
  final ValueNotifier<ViewInfoBloc?>
      currentViewInfoBlocNotifier; // ✅ 用于 rightBarItem 获取当前文档的 ViewInfoBloc
  final ViewPB? initialSelectedView;
  final ViewPB? tabView;

  ViewPB get view => notifier.view;

  @override
  EdgeInsets get contentPadding => EdgeInsets.zero;

  @override
  Widget? get rightBarItem => null;

  @override
  Widget? get fullWindowMoreItem {
    return ValueListenableBuilder<ViewPB?>(
      valueListenable: selectedViewNotifier,
      builder: (context, selectedView, _) {
        final effectiveView = selectedView ?? view;

        if (effectiveView.layout == ViewLayoutPB.Whiteboard) {
          return const SizedBox.shrink();
        }

        try {
          return ValueListenableBuilder<ViewInfoBloc?>(
            valueListenable: currentViewInfoBlocNotifier,
            builder: (context, currentViewInfoBloc, _) {
              final effectiveViewInfoBloc = currentViewInfoBloc ?? bloc;
              final effectiveAccessBloc =
                  pageAccessLevelBloc.view.id == effectiveView.id
                      ? pageAccessLevelBloc
                      : null;
              return MultiBlocProvider(
                providers: [
                  BlocProvider<ViewInfoBloc>.value(
                    value: effectiveViewInfoBloc,
                  ),
                  if (effectiveAccessBloc != null)
                    BlocProvider<PageAccessLevelBloc>.value(
                      value: effectiveAccessBloc,
                    ),
                ],
                child: MoreViewActions(
                  view: effectiveView,
                  viewInfoBloc: effectiveViewInfoBloc,
                  pageAccessLevelBloc: effectiveAccessBloc,
                ),
              );
            },
          );
        } catch (_) {
          return const SizedBox.shrink();
        }
      },
    );
  }

  @override
  bool get handlesFullWindowOverlayActionsInternally {
    // 白板在全屏模式下由白板页面内部渲染一个极简的退出全屏按钮，
    // 宿主(home_stack)无需再渲染全屏动作区。
    return selectedViewNotifier.value?.layout == ViewLayoutPB.Whiteboard;
  }

  @override
  bool get handlesInlineSidebarToggle => true;

  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) {
    // 使用 Builder 获取外层 context，再用 StatefulWidget 保证 SpaceBloc 只创建一次；
    // 否则每次父组件重建都会新建 SpaceBloc 并 dispatch initial()，导致一直处于未初始化状态，菜单栏一直显示 loading。
    final widget = Builder(
      builder: (outerContext) {
        return _SpaceHubBlocProvider(
          spaceView: view,
          selectedViewNotifier: selectedViewNotifier,
          onDeleted: (deletedView, index) =>
              context.onDeleted?.call(deletedView, index),
          pluginContext: context,
          bloc: bloc,
          pageAccessLevelBloc: pageAccessLevelBloc,
          currentViewInfoBlocNotifier: currentViewInfoBlocNotifier,
          initialSelectedView: initialSelectedView,
          tabView: tabView,
        );
      },
    );
    return PluginDeletionListener(
      notifier: notifier,
      onDeleted: context.onDeleted,
      child: widget,
    );
  }

  @override
  String? get viewName => notifier.view.nameOrDefault;

  @override
  Widget get leftBarItem {
    // If a specific document inside the space is selected, hide the
    // global space breadcrumb/title to avoid duplicate path UI.
    return ValueListenableBuilder<ViewPB?>(
      valueListenable: selectedViewNotifier,
      builder: (context, selectedView, _) {
        if (selectedView != null) {
          return const SizedBox.shrink();
        }

        return BlocProvider.value(
          value: pageAccessLevelBloc,
          child: ViewTitleBar(key: ValueKey(view.id), view: view),
        );
      },
    );
  }

  @override
  double get topTabsLeadingWidth => 0;

  @override
  Widget? topTabsLeadingPane(BuildContext context) => null;

  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) {
    // A SpaceHub child tab keeps the middle-pane shell, but uses the child
    // view as its tab identity/title so different documents do not collapse
    // into the single workspace tab.
    // SpaceHub 子文档 tab 保留中间栏壳，但用子文档作为 tab 身份和标题，
    // 避免多个文档都合并成同一个工作空间 tab。
    return ViewTabBarItem(
      view: tabView ?? notifier.view,
      shortForm: shortForm,
    );
  }

  @override
  List<NavigationItem> get navigationItems => [this];
}

/// 持有 SpaceBloc 的 StatefulWidget，保证同一 workspace/spaceView 只创建一次 SpaceBloc，
/// 避免每次父组件重建都新建 Bloc 导致一直处于 loading。
class _SpaceHubBlocProvider extends StatefulWidget {
  const _SpaceHubBlocProvider({
    required this.spaceView,
    required this.selectedViewNotifier,
    required this.onDeleted,
    required this.pluginContext,
    required this.bloc,
    required this.pageAccessLevelBloc,
    required this.currentViewInfoBlocNotifier,
    this.initialSelectedView,
    this.tabView,
  });

  final ViewPB spaceView;
  final ValueNotifier<ViewPB?> selectedViewNotifier;
  final Function(ViewPB, int?)? onDeleted;
  final PluginContext pluginContext;
  final ViewInfoBloc bloc;
  final PageAccessLevelBloc pageAccessLevelBloc;
  final ValueNotifier<ViewInfoBloc?>
      currentViewInfoBlocNotifier; // ✅ 用于 rightBarItem 获取当前文档的 ViewInfoBloc
  final ViewPB? initialSelectedView;
  final ViewPB? tabView;

  @override
  State<_SpaceHubBlocProvider> createState() => _SpaceHubBlocProviderState();
}

class _SpaceHubBlocProviderState extends State<_SpaceHubBlocProvider> {
  SpaceBloc? _spaceBloc;
  String _lastWorkspaceId = '';
  String _lastSpaceViewId = '';

  @override
  void dispose() {
    _spaceBloc?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String workspaceId = '';
    dynamic userProfile;
    try {
      final userWorkspaceBloc = context.read<UserWorkspaceBloc>();
      userProfile = userWorkspaceBloc.state.userProfile;
      workspaceId = userWorkspaceBloc.state.currentWorkspace?.workspaceId ?? '';
    } catch (_) {}

    final spaceViewId = widget.spaceView.id;
    final needNewBloc = _spaceBloc == null ||
        _lastWorkspaceId != workspaceId ||
        _lastSpaceViewId != spaceViewId;

    // Log.info(
    //   '[SpaceHub] _SpaceHubBlocProviderState.build: spaceView=${widget.spaceView.name}($spaceViewId), needNewBloc=$needNewBloc, lastSpaceViewId=$_lastSpaceViewId',
    // );

    if (needNewBloc && workspaceId.isNotEmpty && userProfile != null) {
      _spaceBloc?.close();
      _spaceBloc = SpaceBloc(
        userProfile: userProfile as UserProfilePB,
        workspaceId: workspaceId,
      );
      _spaceBloc!.add(const SpaceEvent.initial(openFirstPage: false));
      _lastWorkspaceId = workspaceId;
      _lastSpaceViewId = spaceViewId;
    }

    final providers = <BlocProvider>[
      BlocProvider<ViewInfoBloc>.value(value: widget.bloc),
      BlocProvider<PageAccessLevelBloc>.value(
          value: widget.pageAccessLevelBloc),
    ];
    if (_spaceBloc != null) {
      providers.add(BlocProvider<SpaceBloc>.value(value: _spaceBloc!));
    }

    return MultiBlocProvider(
      providers: providers,
      child: _SpaceHubContent(
        spaceView: widget.spaceView,
        selectedViewNotifier: widget.selectedViewNotifier,
        onDeleted: widget.onDeleted,
        currentViewInfoBlocNotifier: widget.currentViewInfoBlocNotifier,
        initialSelectedView: widget.initialSelectedView,
        tabView: widget.tabView,
      ),
    );
  }
}

/// 空间统一页面内容组件
class _SpaceHubContent extends StatefulWidget {
  const _SpaceHubContent({
    required this.spaceView,
    required this.selectedViewNotifier,
    required this.onDeleted,
    required this.currentViewInfoBlocNotifier,
    this.initialSelectedView,
    this.tabView,
  });

  final ViewPB spaceView;
  final ValueNotifier<ViewPB?> selectedViewNotifier;
  final Function(ViewPB, int?)? onDeleted;
  final ValueNotifier<ViewInfoBloc?>
      currentViewInfoBlocNotifier; // ✅ 用于 rightBarItem 获取当前文档的 ViewInfoBloc
  final ViewPB? initialSelectedView;
  final ViewPB? tabView;

  @override
  State<_SpaceHubContent> createState() => _SpaceHubContentState();
}

class _SpaceHubContentState extends State<_SpaceHubContent> {
  /// 当前选中的视图
  ViewPB? _selectedView;

  /// 左侧文档列表的宽度（使用 ValueNotifier 避免频繁 setState 导致的卡顿）
  late final ValueNotifier<double> _leftPanelWidthNotifier;

  /// 上次添加到最近访问的视图 ID（用于防抖）
  String? _lastAddedRecentViewId;

  /// 为每个子文档视图创建的 ViewInfoBloc（用于字数统计）
  final List<ViewInfoBloc> _childViewInfoBlocs = [];

  bool _isDocumentListVisible = true;

  /// 左侧文档列表的滚动控制器（用于 RawScrollbar）
  final ScrollController _scrollController = ScrollController();

  /// ✅ 分隔线是否正在拖拽（用于协调白板手势）
  bool _isDividerDragging = false;

  /// 添加视图到最近访问列表（带防抖）
  void _addToRecentViews(String viewId) {
    // 防抖：如果是同一个视图，跳过
    if (_lastAddedRecentViewId == viewId) {
      return;
    }
    _lastAddedRecentViewId = viewId;

    // 使用异步方式更新最近访问，避免阻塞UI
    Future.microtask(() async {
      try {
        final recentService = getIt<CachedRecentService>();
        await recentService.updateRecentViews([viewId], true);
      } catch (e) {
        // 静默处理错误，避免影响 UI
      }
    });
  }

  @override
  void initState() {
    super.initState();
    SpaceHubMiddlePanelController.revealRequest
        .addListener(_handleRevealDocumentList);
    // 监听外部 notifier 变化(由 SpaceHubPlugin.selectViewInSpaceHub 或
    // TabsBloc 在 SpaceHub 内嵌文档链接点击时设置),同步到本地 _selectedView,
    // 触发 rightPanel 重建,显示新的子文档而不替换整个 SpaceHub。
    widget.selectedViewNotifier.addListener(_onSelectedViewNotifierChanged);
    _leftPanelWidthNotifier = ValueNotifier<double>(
      HomeSizes.defaultSpaceHubMiddlePaneWidth,
    );
    // 若有预选文档（从新选项卡打开），直接使用，否则尝试选第一个文档
    if (widget.initialSelectedView != null) {
      _selectedView = widget.initialSelectedView;
      widget.selectedViewNotifier.value = widget.initialSelectedView;
      _addToRecentViews(widget.initialSelectedView!.id);
    } else {
      _trySelectFirstDocument();
    }
  }

  /// 响应 selectedViewNotifier 变化(由 SpaceHubPlugin.selectViewInSpaceHub
  /// 或 TabsBloc 在 SpaceHub 内嵌子文档中点击链接时设置)。
  /// 同步更新本地 _selectedView,触发 build 重建。
  /// 注意:这里只在外部 value 与本地不一致时 setState,避免自身在
  /// _selectViewInMiddlePanel 中改 notifier.value 引起的循环 rebuild。
  void _onSelectedViewNotifierChanged() {
    if (!mounted) return;
    final external = widget.selectedViewNotifier.value;
    if (external?.id != _selectedView?.id) {
      setState(() {
        _selectedView = external;
      });
    }
  }

  @override
  void didUpdateWidget(_SpaceHubContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果空间切换了，重置选中文档状态
    if (oldWidget.spaceView.id != widget.spaceView.id) {
      setState(() {
        _selectedView = null;
        _isDocumentListVisible = true;
      });
      // 重置选中状态
      // didUpdateWidget 处于 build 阶段，直接修改 ValueNotifier 会触发
      // ValueListenableBuilder.markNeedsBuild()，导致 "called during build" 错误。
      // 延迟到当前帧结束后再设置，避免在 build 阶段修改 ValueNotifier。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.selectedViewNotifier.value = null;
          // ✅ 同步更新全局 notifier，通知侧边栏分割线
          spaceHubSelectedViewLayoutNotifier.value = null;
        }
      });
      // 重新尝试选中新空间的第一个文档
      _trySelectFirstDocument();
    }
  }

  void _handleRevealDocumentList() {
    final requestedSpaceId = SpaceHubMiddlePanelController.revealRequest.value;
    if (!mounted || requestedSpaceId != widget.spaceView.id) {
      return;
    }
    if (_isDocumentListVisible) {
      return;
    }
    setState(() => _isDocumentListVisible = true);
  }

  void _selectViewInMiddlePanel(ViewPB view) {
    if (!mounted || view.id.isEmpty) {
      return;
    }

    if (!spaceHubShouldUpdateSelection(_selectedView?.id, view.id)) {
      return;
    }

    setState(() {
      _selectedView = view;
      widget.selectedViewNotifier.value = view;
      spaceHubSelectedViewLayoutNotifier.value = view.layout;
    });

    if (_selectedView != null) {
      _addToRecentViews(_selectedView!.id);
    }
  }

  void _hideDocumentList() {
    if (!_isDocumentListVisible) {
      return;
    }
    setState(() => _isDocumentListVisible = false);
  }

  /// ✅ 处理分隔线拖拽状态变化
  /// 当拖拽开始时，可以通知白板禁用手势；拖拽结束时恢复手势
  void _handleDividerDragStateChanged(bool isDragging) {
    setState(() {
      _isDividerDragging = isDragging;
    });
    // Log.debug('[SpaceHub] Divider dragging: $isDragging');
    // 如果需要，可以在这里添加通知白板的逻辑
    // 例如：通过全局通知或回调机制通知白板组件
  }

  /// 挑一个可以安全「自动打开」的文档；没有则返回 null（保持空态，由用户主动选）。
  ///
  /// database（表格/看板/日历）**不参与自动打开**。
  ///
  /// 原因：打开一个 database 视图会为它的**每一行**建立一条 WebSocket 同步通道 ——
  /// `database_editor.rs` 的 `async_load_rows` 会把该视图的全部 row_orders 按 10 个
  /// 一块并发 `init_database_row`，每行 `collab_builder.finalize()` 一次，最终走到
  /// `cloud_service_impl.rs` 的 `get_plugins()` 建一个 SyncPlugin。**行数即通道数**，
  /// 且没有上限约束（而 `finalized_rows` 缓存上限只有 50，超出还会边建边拆）。
  ///
  /// 2026-08-06 的卡顿实测：点一次空间，8 秒内建了 46 条通道（1 个空间 collab +
  /// 45 个 DatabaseRow），同期还有 90 条 database cell 处理告警，表现为界面转圈。
  /// 三次卡顿全部由「点击空间 → 自动打开第一个文档恰好是 database」引爆。
  ///
  /// 这里只是不再**替用户**打开它；用户主动点开 database 时行为不变。
  ViewPB? _firstAutoOpenableView(List<ViewPB> views) {
    for (final view in views) {
      if (!view.layout.isDatabaseView) {
        return view;
      }
    }
    return null;
  }

  void _trySelectFirstDocument() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final spaceBloc = context.read<SpaceBloc>();
        final currentSpace = spaceBloc.state.currentSpace;
        if (currentSpace?.id == widget.spaceView.id &&
            currentSpace!.childViews.isNotEmpty &&
            _selectedView == null) {
          final firstView = _firstAutoOpenableView(currentSpace.childViews);
          if (firstView == null) {
            // 全是 database，保持空态等用户主动点，避免开局就建几十条同步通道。
            return;
          }
          setState(() {
            _selectedView = firstView;
          });
          widget.selectedViewNotifier.value = firstView;
          // ✅ 同步更新全局 notifier，通知侧边栏分割线
          spaceHubSelectedViewLayoutNotifier.value = firstView.layout;
          // 添加到最近访问
          _addToRecentViews(firstView.id);
        }
      } catch (e) {
        // SpaceBloc 不存在，稍后通过 FutureBuilder 加载
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 尝试获取 SpaceBloc，如果不存在则使用 fallback 逻辑
    SpaceBloc? spaceBloc;
    try {
      spaceBloc = BlocProvider.of<SpaceBloc>(context);
    } catch (_) {
      spaceBloc = null;
    }
    final isSidebarHidden = context.select<HomeSettingBloc, bool>(
      (bloc) => bloc.isMenuHidden,
    );
    final theme = AppFlowyTheme.of(context);
    // 右侧内容区域使用本地的 _selectedView 变量
    final rightPanel = Expanded(
      child: _selectedView != null
          ? _buildSelectedViewContent(_selectedView!)
          : _buildEmptyState(),
    );

    // ✅ 全窗口模式：隐藏 SpaceHub 左侧菜单栏（文档列表）与拖拽分隔线
    Widget content = ValueListenableBuilder<bool>(
      valueListenable: FullWindowController.isFullWindow,
      builder: (context, isFullWindow, _) {
        final menuStatus = context.select<HomeSettingBloc, MenuStatus>(
          (bloc) => bloc.state.menuStatus,
        );

        final shouldApplyTopPadding =
            !isFullWindow && menuStatus != MenuStatus.expanded;
        final contentTopPadding = shouldApplyTopPadding
            ? HomeSizes.topBarHeight + HomeInsets.topBarTitleVerticalPadding
            : 0.0;
        final useFloatingDocumentList =
            !isFullWindow && menuStatus != MenuStatus.expanded;
        final availableContentWidth = MediaQuery.sizeOf(context).width;
        final maxLeftPanelWidth = (availableContentWidth -
                HomeSizes.minimumSpaceHubContentPeekWidth -
                HomeSizes.spaceHubDividerWidth)
            .clamp(HomeSizes.minimumSpaceHubMiddlePaneWidth, double.infinity);
        // 仅在 macOS 且“收起左侧边栏（浮动文档列表）”时，给中间栏（文档列表）顶部下移，
        // 避开窗口左上角的红绿灯（关闭/最小化/最大化）按钮。
        // 关键：该 inset 只作用于 documentListPanel 与分隔线，不作用于 rightPanel（白板/内容），
        // 所以白板始终贴顶、深色主题下不会出现顶部黑边。
        // Windows/Linux 或非收起态恒为 0（窗口按钮不在左上角，无需避让）。
        final floatingDocumentListTopInset =
            (useFloatingDocumentList && Platform.isMacOS)
                ? HomeSizes.macOSTrafficLightsTopInset
                : 0.0;
        final passiveFloatingDivider = Padding(
          padding: EdgeInsets.only(
            top: floatingDocumentListTopInset,
            bottom: 12,
          ),
          child: SizedBox(
            width: HomeSizes.spaceHubDividerWidth,
            child: Align(
              alignment: Alignment.center,
              child: Container(
                width: 0.8,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(0.4),
                ),
              ),
            ),
          ),
        );

        // 使用 ValueListenableBuilder 包裹需要响应宽度变化的区域
        // 这样拖拽分隔线时只会重建这个区域，而不会触发整个 build() 重建
        final documentListPanel = ValueListenableBuilder<double>(
          valueListenable: _leftPanelWidthNotifier,
          builder: (context, leftPanelWidth, child) {
            final effectiveLeftPanelWidth = leftPanelWidth.clamp(
              HomeSizes.minimumSpaceHubMiddlePaneWidth,
              maxLeftPanelWidth,
            );
            return Padding(
              padding: useFloatingDocumentList
                  ? EdgeInsets.only(
                      top: floatingDocumentListTopInset,
                      bottom: 12,
                    )
                  : EdgeInsets.zero,
              child: ClipRRect(
                borderRadius: useFloatingDocumentList
                    ? const BorderRadius.horizontal(
                        right: Radius.circular(14),
                      )
                    : BorderRadius.zero,
                child: Container(
                  color: homeContentBackgroundColor(context),
                  width: effectiveLeftPanelWidth,
                  child: Row(
                    children: [
                      Expanded(
                        child: _SpaceDocumentList(
                          spaceView: widget.spaceView,
                          selectedView: _selectedView,
                          showHeader: true,
                          onViewSelectedWithRecent: _selectViewInMiddlePanel,
                          onViewCreated: _selectViewInMiddlePanel,
                          scrollController: _scrollController,
                        ),
                      ),
                      if (_isDocumentListVisible &&
                          !isFullWindow &&
                          !useFloatingDocumentList)
                        _SpaceHubResizableDivider(
                          minLeftWidth: HomeSizes.minimumSpaceHubMiddlePaneWidth,
                          maxLeftWidth: maxLeftPanelWidth,
                          currentLeftWidth: effectiveLeftPanelWidth,
                          onResize: (newWidth) {
                            // 直接更新 ValueNotifier，避免 setState 导致的全局重建
                            _leftPanelWidthNotifier.value = newWidth.clamp(
                              HomeSizes.minimumSpaceHubMiddlePaneWidth,
                              maxLeftPanelWidth,
                            );
                          },
                          // ✅ 新增：拖拽状态变化回调，用于协调白板手势
                          onDragStateChanged: _handleDividerDragStateChanged,
                          // ✅ 新增：当当前视图是白板时，禁用分隔线拖拽
                          // 避免 MouseRegion 的 onEnter/onExit 触发 setState 导致 WKWebView 布局偏移
                          enabled: _selectedView?.layout != ViewLayoutPB.Whiteboard,
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左侧：空间文档列表
            Visibility(
              visible: _isDocumentListVisible && !isFullWindow,
              child: documentListPanel,
            ),
            Visibility(
              visible: _isDocumentListVisible &&
                  !isFullWindow &&
                  useFloatingDocumentList,
              child: passiveFloatingDivider,
            ),
            rightPanel,
          ],
        );
      },
    );

    // 如果有 SpaceBloc，使用 BlocListener 监听空间状态变化
    if (spaceBloc != null) {
      return BlocListener<SpaceBloc, SpaceState>(
        bloc: spaceBloc,
        listenWhen: (prev, curr) {
          if (!curr.isInitialized) {
            return false;
          }
          if (curr.currentSpace?.id != widget.spaceView.id) {
            return false;
          }
          final prevIds =
              prev.currentSpace?.childViews.map((v) => v.id).join(',');
          final currIds =
              curr.currentSpace?.childViews.map((v) => v.id).join(',');
          return prev.currentSpace?.id != curr.currentSpace?.id ||
              prevIds != currIds ||
              prev.isInitialized != curr.isInitialized;
        },
        listener: (context, state) {
          _syncSelectedViewWithCurrentSpace(state);
        },
        child: content,
      );
    }

    return content;
  }

  Widget _buildSelectedViewContent(ViewPB view) {
    try {
      // 获取 userProfile - AI Chat 等插件需要用户信息
      UserProfilePB? userProfile;
      try {
        final userWorkspaceBloc = context.read<UserWorkspaceBloc>();
        userProfile = userWorkspaceBloc.state.userProfile;
      } catch (e) {
        // 静默处理
      }

      // 为所有类型的视图创建 ViewInfoBloc（复用已有或创建新的）
      ViewInfoBloc? viewInfoBloc;
      try {
        for (final bloc in _childViewInfoBlocs) {
          if (bloc.view.id == view.id) {
            viewInfoBloc = bloc;
            break;
          }
        }

        if (viewInfoBloc == null) {
          viewInfoBloc = ViewInfoBloc(view: view)
            ..add(const ViewInfoEvent.started());
          _childViewInfoBlocs.add(viewInfoBloc);
        }

        // ✅ 在 build 完成后更新 currentViewInfoBlocNotifier
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            widget.currentViewInfoBlocNotifier.value = viewInfoBloc;
          }
        });
      } catch (e) {
        // 静默处理 ViewInfoBloc 创建错误
      }

      final parentView = _getParentView(view);

      final isHandwriting = isHandwritingNote(view);
      final usesDocumentPage = spaceHubUsesDocumentPage(
        view.layout,
        isHandwriting: isHandwriting,
      );

      // 文档直接使用 SpaceHub 管理的 Bloc，不创建临时 DocumentPlugin。
      if (usesDocumentPage) {
        // 将 viewInfoBloc 作为参数传给 DocumentPage。
        //
        // ⚠️ 关键修复：必须为“当前选中的子文档”单独提供一个绑定到它自己的
        // PageAccessLevelBloc，遮蔽掉祖先（_SpaceHubBlocProvider）提供的
        // “SpaceHub 主视图”的那个 bloc。
        //
        // 否则 DocumentPage / editor_page 会通过 context 读到 SpaceHub 主视图
        // 的权限（通常是 space，creator=自己 → fullAccess），导致无论子文档
        // 实际权限是不是只读，editorState.editable 都是 true：只读用户仍能输入，
        // 这些本地编辑被服务端拒绝（他人看不见），却残留在本地 CRDT，重新授权
        // 为可编辑时一次性回放到其他协作者页面。
        //
        // 用 create 形式让 BlocProvider 自动管理生命周期：ValueKey(view.id)
        // 保证切换子文档时旧 bloc 被 close、为新文档重建，零泄漏。
        return BlocProvider<PageAccessLevelBloc>(
          key: ValueKey('page_access_${view.id}'),
          create: (_) => PageAccessLevelBloc(view: view)
            ..add(const PageAccessLevelEvent.initial()),
          child: _buildContentWithToolbar(
            view: view,
            viewInfoBloc: viewInfoBloc,
            child: DocumentPage(
              key: ValueKey(view.id),
              view: view,
              onDeleted: () => _onChildViewDeleted(view, null),
              tabs: const [
                PickerTabType.emoji,
                PickerTabType.icon,
                PickerTabType.custom,
              ],
              viewInfoBloc: viewInfoBloc,
            ),
            parentView: parentView,
          ),
        );
      }

      // 其他类型的视图（如 AI Chat、白板等）
      return _buildContentWithToolbar(
        view: view,
        viewInfoBloc: viewInfoBloc,
        // ⚠️ 关键修复（白板/folder 协同不同步的总根）：为白板等非文档视图加稳定 key
        // （与上面 DocumentPage 的 ValueKey(view.id) 一致）。否则 SpaceHub 每次重建
        // rightPanel 时，Flutter 会把这里的 widget 当作新实例 —— dispose 旧的
        // WhiteboardPage、再建新的，造成 WhiteboardPage 反复 dispose+重建：
        //   · WhiteboardPage.dispose() 会 closeWhiteboard → 紧接着重建又 openWhiteboard，
        //     白板 collab 的同步流(SyncPlugin)被反复 close/重建；
        //   · close→reopen 之间的空窗会漏掉服务器广播 → 广播序列出现缺口 →
        //     collab 同步反复判定 missing update 而重启 → 永不收敛 →
        //     白板内容与 folder 文档树都同步不过来；
        //   · 同时 WebView 也被反复重建。
        // 加稳定 key 后，同一 view 在 SpaceHub 重建期间复用同一个 State（didUpdateWidget
        // 而非 dispose 重建），同步流保持单条、稳定。
        child: SpaceHubPluginView(
          key: ValueKey(
            'space_hub_plugin_${view.id}_${view.layout.value}',
          ),
          view: view,
          createPlugin: () => view.plugin(),
          builder: (context, plugin) => plugin.widgetBuilder.buildWidget(
            context: PluginContext(
              onDeleted: _onChildViewDeleted,
              userProfile: userProfile,
            ),
            shrinkWrap: false,
            data: view.layout == ViewLayoutPB.Whiteboard
                ? const {
                    'preferHostFullWindowMoreItem': true,
                    'preferHostTopRightActions': true,
                  }
                : isHandwriting
                    ? const {'preferHostTopRightActions': true}
                    : null,
          ),
        ),
        parentView: parentView,
      );
    } catch (e, stackTrace) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FlowyText.regular(
              '无法加载视图: ${view.name}',
              fontSize: 14,
              color: Theme.of(context).colorScheme.error,
            ),
            const VSpace(8),
            FlowyText.regular(
              '错误: ${e.toString()}',
              fontSize: 12,
              color: Theme.of(context).hintColor,
            ),
          ],
        ),
      );
    }
  }

  Widget _buildContentWithToolbar({
    required ViewPB view,
    ViewInfoBloc? viewInfoBloc,
    required Widget child,
    ViewPB? parentView,
  }) {
    if (viewInfoBloc == null) {
      return child;
    }
    final isWhiteboard = view.layout == ViewLayoutPB.Whiteboard;
    final isHandwriting = isHandwritingNote(view);
    final showBackButton = parentView != null;
    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          right: 0,
          child: BlocProvider<ViewInfoBloc>.value(
            value: viewInfoBloc,
            child: UnifiedViewTopRightActions(
              view: view,
              viewInfoBloc: viewInfoBloc,
              showCollaborators: FeatureFlag.syncDocument.isOn && !isWhiteboard,
              useFloatingSurface: true,
              showShareButton: !isWhiteboard && !isHandwriting,
              iconColorOverride: isWhiteboard ? const Color(0xFF111111) : null,
            ),
          ),
        ),
        if (showBackButton)
          Positioned(
            top: 8,
            left: 12,
            child: InkWell(
              onTap: () => _selectViewInMiddlePanel(parentView),
              child: FlowySvg(FlowySvgs.m_app_bar_back_s,size: Size(18, 18),),
            ),
          ),
      ],
    );
  }

  ViewPB? _getParentView(ViewPB view) {
    if (view.parentViewId.isEmpty) {
      return null;
    }

    if (view.parentViewId == widget.spaceView.id) {
      return null;
    }

    try {
      final spaceBloc = context.read<SpaceBloc>();
      final currentSpace = spaceBloc.state.currentSpace;
      if (currentSpace != null) {
        return _findParentView(currentSpace.childViews, view.parentViewId);
      }
    } catch (_) {}

    return null;
  }

  ViewPB? _findParentView(List<ViewPB> views, String parentViewId) {
    for (final view in views) {
      if (view.id == parentViewId) {
        return view;
      }
      if (view.childViews.isNotEmpty) {
        final found = _findParentView(view.childViews, parentViewId);
        if (found != null) {
          return found;
        }
      }
    }
    return null;
  }

  void _onChildViewDeleted(ViewPB deletedView, int? index) {
    // Clear current selection first, then ask SpaceBloc to reload child views.
    if (_selectedView?.id == deletedView.id) {
      setState(() {
        _selectedView = null;
      });
      widget.selectedViewNotifier.value = null;
    }

    // 清理被删除视图的 ViewInfoBloc
    final blocToRemove = _childViewInfoBlocs.where(
      (bloc) => bloc.view.id == deletedView.id,
    );
    for (final bloc in blocToRemove) {
      bloc.close();
      _childViewInfoBlocs.remove(bloc);
    }

    try {
      final spaceBloc = context.read<SpaceBloc>();
      if (!spaceBloc.isClosed) {
        spaceBloc.add(const SpaceEvent.didUpdateCurrentSpaceChildViews());
      }
    } catch (_) {
      // Ignore when SpaceBloc is unavailable in current context.
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FlowyText.regular(
            '请从左侧选择一个文档',
            fontSize: 16,
            color: Theme.of(context).hintColor,
          ),
          const VSpace(8),
          FlowyText.regular(
            '或点击左上角的 + 按钮创建新文档',
            fontSize: 14,
            color: Theme.of(context).hintColor,
          ),
        ],
      ),
    );
  }

  void _syncSelectedViewWithCurrentSpace(SpaceState state) {
    final currentSpace = state.currentSpace;
    if (currentSpace?.id != widget.spaceView.id) {
      return;
    }

    final childViews = currentSpace?.childViews ?? const <ViewPB>[];
    // SpaceBloc 只维护一级文档，刷新期间可能暂时拿不到完整列表。
    // 已从中间栏选中的文档仍属于当前 SpaceHub，不能因一级列表刷新而回退。
    if (_selectedView != null) {
      return;
    }

    if (childViews.isNotEmpty) {
      // 与 _trySelectFirstDocument 同一条规则：database 不参与自动打开，
      // 否则一次空间切换就会为它的每一行建一条同步通道（详见该方法注释）。
      final firstView = _firstAutoOpenableView(childViews);
      if (firstView == null) {
        return;
      }
      setState(() {
        _selectedView = firstView;
      });
      widget.selectedViewNotifier.value = firstView;
      // ✅ 同步更新全局 notifier，通知侧边栏分割线
      spaceHubSelectedViewLayoutNotifier.value = firstView.layout;
      _addToRecentViews(firstView.id);
    }
  }

  @override
  void dispose() {
    SpaceHubMiddlePanelController.revealRequest
        .removeListener(_handleRevealDocumentList);
    // ✅ 清理全局 notifier，通知侧边栏分割线恢复启用状态。
    // 注意：dispose 期间 widget tree 处于 locked 状态，直接修改全局
    // ValueNotifier 会触发监听者 ValueListenableBuilder 在 build 阶段
    // markNeedsBuild,从而报 "setState() or markNeedsBuild() called when
    // widget tree was locked" 异常。延迟到 frame 之后再修改，让监听者
    // 在下一帧正常 build。
    final notifier = spaceHubSelectedViewLayoutNotifier;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifier.value = null;
    });
    // ✅ 清理所有缓存的 ViewInfoBloc，防止内存泄漏
    for (final bloc in _childViewInfoBlocs) {
      bloc.close();
    }
    _childViewInfoBlocs.clear();
    _scrollController.dispose();
    _leftPanelWidthNotifier.dispose();
    widget.selectedViewNotifier.removeListener(_onSelectedViewNotifierChanged);
    super.dispose();
  }
}

/// 空间文档列表组件（左侧）
class _SpaceDocumentList extends StatefulWidget {
  const _SpaceDocumentList({
    super.key,
    required this.spaceView,
    required this.selectedView,
    required this.showHeader,
    required this.onViewCreated,
    required this.onViewSelectedWithRecent,
    required this.scrollController,
  });

  final ViewPB spaceView;
  final ViewPB? selectedView;
  final bool showHeader;
  final ValueChanged<ViewPB> onViewCreated;
  final void Function(ViewPB view) onViewSelectedWithRecent;
  final ScrollController scrollController;

  @override
  State<_SpaceDocumentList> createState() => _SpaceDocumentListState();
}

class _SpaceDocumentListState extends State<_SpaceDocumentList> {
  final _showAddNoteButton = ValueNotifier(false);
  late final SpaceHubDocumentListLoader<List<ViewPB>> _documentListLoader;

  @override
  void initState() {
    super.initState();
    _documentListLoader = SpaceHubDocumentListLoader<List<ViewPB>>(
      spaceId: widget.spaceView.id,
      load: _loadChildViews,
    );
    widget.scrollController.addListener(_checkScrollable);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScrollable();
    });
  }

  @override
  void didUpdateWidget(_SpaceDocumentList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _documentListLoader.updateSpace(widget.spaceView.id);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_checkScrollable);
    _showAddNoteButton.dispose();
    super.dispose();
  }

  void _checkScrollable() {
    if (widget.scrollController.hasClients) {
      final scrollExtent = widget.scrollController.position.maxScrollExtent;
      _showAddNoteButton.value = scrollExtent > 0;
    }
  }

  void _onExpandedChanged() {
    // 文件夹展开/收起后，延迟一帧检查滚动状态
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScrollable();
    });
  }

  void _reloadBackendDocumentList() {
    if (!mounted) {
      return;
    }
    setState(() {
      _documentListLoader.reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    // 受限成员权限检查（context.watch 实时响应权限变化）
    bool isRestrictedMember = false;
    try {
      isRestrictedMember =
          context.watch<UserWorkspaceBloc>().state.currentUserRole ==
              AFRolePB.Guest;
    } catch (_) {}

    // 尝试从 SpaceBloc 获取空间文档列表
    SpaceBloc? spaceBloc;
    try {
      spaceBloc = BlocProvider.of<SpaceBloc>(context);
    } catch (_) {
      spaceBloc = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 头部：空间名称 + 新增文档按钮
        if (widget.showHeader) ...[
          // Header stays here only in fullscreen, where HomeStack has no tabs.
          // 仅在应用内全屏保留列表头部；普通模式下由顶部预留区承载。
          _buildHeader(context, spaceBloc, isRestrictedMember),
          VSpace(4),
        ],
        // 文档列表
        Expanded(
          child: spaceBloc != null
              ? _buildListFromSpaceBloc(context, spaceBloc, isRestrictedMember)
              : _buildListFromBackend(context, isRestrictedMember),
        ),
        // 固定底部"新增笔记页"按钮（当列表超过一屏时显示）
        ValueListenableBuilder<bool>(
          valueListenable: _showAddNoteButton,
          builder: (context, show, _) {
            if (!show) {
              return const SizedBox.shrink();
            }
            return _buildBottomAddNoteButton(isRestrictedMember);
          },
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, SpaceBloc? spaceBloc, bool isRestrictedMember) {
    final theme = AppFlowyTheme.of(context);
    final isSidebarHidden = context.select<HomeSettingBloc, bool>(
      (bloc) => bloc.isMenuHidden,
    );
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 16,
        top: 10,
        bottom: 4,
      ),
      child: Row(
        children: [
          Expanded(
            child: FlowyText(
              widget.spaceView.name,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(
            width: 24,
            height: 24,
            child: ViewAddButton(
              parentViewId: widget.spaceView.id,
              onEditing: (_) {},
              enabled: !isRestrictedMember,
              onImportCompleted: (importedViews) async {
                // 导入完成后，将导入的文件移动到列表第一位（参考新建文档使用 index: 0 的逻辑）
                for (final view in importedViews.reversed) {
                  await ViewBackendService.moveViewV2(
                    viewId: view.id,
                    newParentId: widget.spaceView.id,
                    prevViewId: null,  // null 表示移动到列表开头
                  );
                }

                // 刷新列表并选中第一个导入的文件
                if (spaceBloc != null) {
                  spaceBloc.add(const SpaceEvent.didUpdateCurrentSpaceChildViews());
                } else {
                  _reloadBackendDocumentList();
                }
                if (importedViews.isNotEmpty) {
                  widget.onViewCreated(importedViews.first);
                }
              },
              onSelected: (pluginBuilder, name, initialDataBytes,
                  openAfterCreated, createNewView) async {
                final layout = pluginBuilder.layoutType;
                if (layout == null) return;

                // 准备 extra 参数
                Map<String, String> ext = {};
                String finalName = name ?? layout.defaultName;

                if (pluginBuilder.pluginType == PluginType.handwritingSaber) {
                  ext['view_type'] = 'handwriting_saber';
                  if (name == null || name.isEmpty) {
                    finalName = '未命名手记';
                  }
                }

                if (spaceBloc != null) {
                  // 使用 SpaceBloc 创建文档
                  final result = await ViewBackendService.createView(
                    name: finalName,
                    layoutType: layout,
                    parentViewId: widget.spaceView.id,
                    index: 0,
                    openAfterCreate: false, // 不自动打开新标签页
                    ext: ext,
                  );
                  await result.fold(
                    (view) async {
                      // ✅ 关键修复：强制更新 view_type，确保即使在 Space 下创建也能正确识别
                      // 某些情况下 Space 下创建 Document 可能会丢失 extra，这里二次确认
                      if (pluginBuilder.pluginType ==
                          PluginType.handwritingSaber) {
                        try {
                          await ViewBackendService.updateView(
                            viewId: view.id,
                            extra:
                                jsonEncode({'view_type': 'handwriting_saber'}),
                          );
                          // 更新本地 view 对象，确保 UI 立即渲染正确
                          if (view.extra.isEmpty ||
                              !view.extra.contains('view_type')) {
                            view.extra = '{"view_type":"handwriting_saber"}';
                          }
                        } catch (e) {
                          Log.error('Failed to force update view type: $e');
                        }
                      }

                      // 刷新空间文档列表
                      spaceBloc.add(
                          const SpaceEvent.didUpdateCurrentSpaceChildViews());
                      // 通知父组件新文档已创建，以便自动选中并显示
                      widget.onViewCreated(view);
                    },
                    (error) {
                      Log.error('Failed to create view: $error');
                    },
                  );
                } else {
                  // Fallback: 直接创建文档
                  final result = await ViewBackendService.createView(
                    layoutType: layout,
                    parentViewId: widget.spaceView.id,
                    name: finalName,
                    index: 0,
                    openAfterCreate: false, // 不自动打开新标签页
                    ext: ext,
                  );
                  await result.fold((view) async {
                    // ✅ 关键修复：强制更新 view_type (Fallback)
                    if (pluginBuilder.pluginType ==
                        PluginType.handwritingSaber) {
                      try {
                        await ViewBackendService.updateView(
                          viewId: view.id,
                          extra: jsonEncode({'view_type': 'handwriting_saber'}),
                        );
                        if (view.extra.isEmpty ||
                            !view.extra.contains('view_type')) {
                          view.extra = '{"view_type":"handwriting_saber"}';
                        }
                      } catch (e) {
                        Log.error(
                            'Failed to force update view type (fallback): $e');
                      }
                    }
                    // Fallback create success
                    _reloadBackendDocumentList();
                    widget.onViewCreated(view);
                  }, (error) {
                    Log.error('Failed to create view (fallback): $error');
                  });
                }
              },
              tooltipText: '新增文档',
            ),
          ),
          // 当侧边栏隐藏时，在加号按钮右边显示展开按钮
          if (isSidebarHidden) ...[
            const HSpace(8),
            SizedBox(
              width: 24,
              height: 24,
              child: _SpaceHubSidebarToggleButton(
                color: theme.iconColorScheme.secondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildListFromSpaceBloc(BuildContext context, SpaceBloc spaceBloc, bool isRestrictedMember) {
    final theme = AppFlowyTheme.of(context);
    return BlocListener<SpaceBloc, SpaceState>(
      bloc: spaceBloc,
      listenWhen: (prev, curr) {
        // 监听初始化完成，或者当前空间变化，或者子视图列表变化
        final initialized = !prev.isInitialized && curr.isInitialized;
        final spaceChanged = prev.currentSpace?.id != curr.currentSpace?.id;
        final childViewsChanged = prev.currentSpace?.childViews.length !=
                curr.currentSpace?.childViews.length ||
            prev.currentSpace?.childViews.map((v) => v.id).join(',') !=
                curr.currentSpace?.childViews.map((v) => v.id).join(',');
        return initialized || spaceChanged || childViewsChanged;
      },
      listener: (context, state) {
        // Log.info(
        //   '[SpaceHub] BlocListener fired: isInitialized=${state.isInitialized}, currentSpace=${state.currentSpace?.name ?? "null"}(${state.currentSpace?.id ?? "null"}), spaceView=${spaceView.name}(${spaceView.id})',
        // );
        // 当 SpaceBloc 初始化完成后，如果当前空间不是目标空间，则打开目标空间
        if (state.isInitialized) {
          final currentSpace = state.currentSpace;
          if (currentSpace?.id != widget.spaceView.id) {
            // 使用 Future.microtask 确保在下一帧执行，避免在 listener 中直接修改状态
            Future.microtask(() {
              // Log.info(
              //   '[SpaceHub] dispatching SpaceEvent.open for spaceView=${widget.spaceView.name}(${widget.spaceView.id})',
              // );
              if (!spaceBloc.isClosed) {
                final currentState = spaceBloc.state;
                // 再次检查，避免重复打开
                if (currentState.isInitialized &&
                    currentState.currentSpace?.id != widget.spaceView.id) {
                  spaceBloc.add(SpaceEvent.open(space: widget.spaceView));
                }
              }
            });
          }
        }
      },
      child: BlocBuilder<SpaceBloc, SpaceState>(
        bloc: spaceBloc,
        buildWhen: (previous, current) {
          // 检查当前空间是否匹配目标空间
          final currSpace = current.currentSpace;
          final prevSpace = previous.currentSpace;

          // 只关注与当前空间相关的变化
          if (currSpace?.id != widget.spaceView.id && prevSpace?.id != widget.spaceView.id) {
            // 两个状态都与目标空间无关，不需要重建
            return false;
          }

          // 检查空间ID是否变化
          if (prevSpace?.id != currSpace?.id) {
            return true;
          }

          // 检查子视图数量是否变化
          final prevCount = prevSpace?.childViews.length ?? 0;
          final currCount = currSpace?.childViews.length ?? 0;
          if (prevCount != currCount) {
            return true;
          }

          // 检查子视图 ID 列表是否变化，并保留当前顺序。
          if (spaceHubChildViewIdsChanged(
            prevSpace?.childViews.map((view) => view.id) ?? const <String>[],
            currSpace?.childViews.map((view) => view.id) ?? const <String>[],
          )) {
            return true;
          }

          // 检查初始化状态是否变化
          if (previous.isInitialized != current.isInitialized) {
            return true;
          }

          // 默认不重建（避免不必要的重建）
          return false;
        },
        builder: (context, state) {
          // 确保当前空间已加载，如果没有则触发加载
          final currentSpace = state.currentSpace;
          // Log.info(
          //   '[SpaceHub] BlocBuilder builder: isInitialized=${state.isInitialized}, currentSpace=${currentSpace?.name ?? "null"}(${currentSpace?.id ?? "null"}), spaceView=${spaceView.name}(${spaceView.id})',
          // );

          // 如果 SpaceBloc 还未初始化，显示加载中
          if (!state.isInitialized) {
            return const Center(
              child: CircularProgressIndicator.adaptive(),
            );
          }

          // 如果当前空间不是目标空间，显示加载中（等待 SpaceEvent.open 完成）
          if (currentSpace?.id != widget.spaceView.id) {
            return const Center(
              child: CircularProgressIndicator.adaptive(),
            );
          }

          // 当前空间匹配，使用 currentSpace（它已经包含了加载的子视图）
          final displaySpace = currentSpace!;
          final childViews = displaySpace.childViews;

          // 列表内容变化后，在下一帧检查是否需要显示底部固定按钮
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _checkScrollable();
          });

          return ListView.builder(
            controller: widget.scrollController,
            itemCount: childViews.length + 1,
            findChildIndexCallback: (key) => spaceHubDocumentListChildIndex(
              key,
              childViews.map((view) => view.id),
            ),
            itemBuilder: (context, index) {
              if (index == childViews.length) {
                return ValueListenableBuilder<bool>(
                  valueListenable: _showAddNoteButton,
                  builder: (context, showBottomButton, _) {
                    if (showBottomButton) {
                      return const SizedBox.shrink();
                    }
                    final addBtn = AFGhostIconTextButton.primary(
                      text: '新增笔记页',
                      mainAxisAlignment: MainAxisAlignment.start,
                      size: AFButtonSize.l,
                      onTap: () => _createNewNote(context),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      borderRadius: theme.borderRadius.s,
                      iconBuilder: (context, isHover, disabled) => FlowySvg(
                        FlowySvgs.view_item_add_s,
                        size: const Size.square(16.0),
                        color: Theme.of(context).textTheme.bodyMedium?.color,
                      ),
                    );
                    if (isRestrictedMember) {
                      return IgnorePointer(
                        child: Opacity(opacity: 0.3, child: addBtn),
                      );
                    }
                    return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0),
                        child: addBtn);
                  },
                );
              }
              final childView = childViews[index];
              return Padding(
                key: ValueKey('space_hub_${childView.id}'),
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: ViewItem(
                  view: childView,
                  // 拖拽排序必须知道谁是首项：DraggableViewItem 的 top 落点
                  // （插到该项之前）仅对 isFirstChild 生效，不传就永远只能
                  // 往下插，无法把条目拖到列表最前面。
                  isFirstChild: childView.id == childViews.first.id,
                  // 前一项 id 让「插到本项之前」可以表达为「插到前一项之后」，
                  // 从而支持插入到列表任意位置，而不只是首尾两端。
                  previousViewId:
                      index > 0 ? childViews[index - 1].id : null,
                  // 注意：spaceType 必须取自所在「空间」(spaceView) 的权限，
                  // 不能取自 childView。childView 是普通文档，其 extra 为空，
                  // spacePermission getter 会抛异常并回退为 private，导致在
                  // 共享空间中新建的子页面被放入「私有 section」，其他成员看不到。
                  spaceType:
                      widget.spaceView.spacePermission == SpacePermission.private
                          ? FolderSpaceType.private
                          : FolderSpaceType.public,
                  level: 0,
                  leftPadding: 10,
                  onSelected: (itemContext, clickedView) {
                    // 在空间统一页面中，点击文档只更新选中状态，不打开新 tab
                    // 直接调用回调，不更新全局状态，避免整个页面刷新
                    widget.onViewSelectedWithRecent(clickedView);
                  },
                  isFeedback: false,
                  shouldRenderChildren: true,
                  shouldLoadChildViews: true,
                  enableRightClickContext: true,
                  isHoverEnabled: true,
                  disableSelectedStatus: false,
                  isTablet: PlatformInfo.isTablet,
                  // 空字符串表示当前没有选中项，递归子项也不监听全局状态
                  externallySelectedViewId: widget.selectedView?.id ?? '',
                  onExpandedChanged: _onExpandedChanged,
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildListFromBackend(BuildContext context, bool isRestrictedMember) {
    final theme = AppFlowyTheme.of(context);
    return FutureBuilder<List<ViewPB>>(
      future: _documentListLoader.future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }

        final childViews = snapshot.data ?? const <ViewPB>[];

        // 列表内容变化后，在下一帧检查是否需要显示底部固定按钮
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _checkScrollable();
        });

        return ListView.builder(
          controller: widget.scrollController,
          itemCount: childViews.length + 1,
          findChildIndexCallback: (key) => spaceHubDocumentListChildIndex(
            key,
            childViews.map((view) => view.id),
          ),
          itemBuilder: (context, index) {
            if (index == childViews.length) {
              return ValueListenableBuilder<bool>(
                valueListenable: _showAddNoteButton,
                builder: (context, showBottomButton, _) {
                  if (showBottomButton) {
                    return const SizedBox.shrink();
                  }
                  final addBtn = AFGhostIconTextButton.primary(
                    text: '新增日记页',
                    mainAxisAlignment: MainAxisAlignment.start,
                    size: AFButtonSize.xl,
                    onTap: () => _createNewNote(context),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    borderRadius: theme.borderRadius.s,
                    iconBuilder: (context, isHover, disabled) => FlowySvg(
                      FlowySvgs.view_item_add_s,
                      size: const Size.square(16.0),
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                  );
                  if (isRestrictedMember) {
                    return IgnorePointer(
                      child: Opacity(opacity: 0.3, child: addBtn),
                    );
                  }
                  return addBtn;
                },
              );
            }
            final childView = childViews[index];
            return ViewItem(
              key: ValueKey('space_hub_${childView.id}'),
              view: childView,
              // 同上：不传 isFirstChild 就无法把条目拖到列表最前面。
              isFirstChild: childView.id == childViews.first.id,
              // 同上：有前一项 id 才能插入到列表任意位置。
              previousViewId: index > 0 ? childViews[index - 1].id : null,
              // 同上：spaceType 取自空间 spaceView，而非普通文档 childView，
              // 否则共享空间中的子页面会被错误标记为私有、其他成员不可见。
              spaceType: widget.spaceView.spacePermission == SpacePermission.private
                  ? FolderSpaceType.private
                  : FolderSpaceType.public,
              level: 0,
              leftPadding: 10,
              onSelected: (itemContext, clickedView) {
                // 在空间统一页面中，点击文档只更新选中状态，不打开新 tab
                // 直接调用回调，不更新全局状态，避免整个页面刷新
                widget.onViewSelectedWithRecent(clickedView);
              },
              isFeedback: false,
              shouldRenderChildren: true,
              shouldLoadChildViews: true,
              enableRightClickContext: true,
              isHoverEnabled: true,
              disableSelectedStatus: false,
              isTablet: PlatformInfo.isTablet,
              // 空字符串表示当前没有选中项，递归子项也不监听全局状态
              externallySelectedViewId: widget.selectedView?.id ?? '',
              onExpandedChanged: _onExpandedChanged,
            );
          },
        );
      },
    );
  }

  Widget _buildBottomAddNoteButton(bool isRestrictedMember) {
    final theme = AppFlowyTheme.of(context);
    final addBtn = AFGhostIconTextButton.primary(
      text: '新增笔记页',
      mainAxisAlignment: MainAxisAlignment.start,
      size: AFButtonSize.l,
      onTap: () => _createNewNote(context),
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      borderRadius: theme.borderRadius.s,
      iconBuilder: (context, isHover, disabled) => const FlowySvg(
        FlowySvgs.icon_add_new_s,
        size: Size.square(16.0),
      ),
    );
    if (isRestrictedMember) {
      return IgnorePointer(
        child: Opacity(opacity: 0.3, child: addBtn),
      );
    }
    return addBtn;
  }

  /// 中间栏 FutureBuilder 的数据源。
  ///
  /// 【2026-08-11 加固：中间栏无限转圈】
  /// 这里调的 getChildViews 是 FFI → Rust flowy-folder。原实现不带超时，一旦
  /// Rust 侧不返回，FutureBuilder 会永远停在 ConnectionState.waiting，中间栏
  /// 一直转圈；而且它等的是 FFI 不是网络，断网也绕不过去。
  ///
  /// 与 SpaceBloc 的 SpaceEvent.open 是同一个调用、同一个失效模式，两处都要兜。
  /// 超时后返回空列表，让中间栏渲染成「空」而不是「一直转」，并留下日志指明
  /// 卡在这里，便于下次复现时直接定位。
  Future<List<ViewPB>> _loadChildViews(String spaceId) async {
    // 注意：这里【不再】对 views 按 lastEdited 排序 —— 06308cd8d
    //（fix(space): 修复移动端文档列表状态错乱）已有意移除该排序，
    // 本次加固只加超时，不恢复它。
    try {
      final result = await ViewBackendService.getChildViews(viewId: spaceId)
          .timeout(const Duration(seconds: 10));
      return result.fold((views) => views, (_) => const <ViewPB>[]);
    } catch (e) {
      Log.error(
        '[SpaceHub] _loadChildViews 超时/失败（FFI→Rust folder）: '
        'spaceId=$spaceId, err=$e —— 以空列表降级渲染，避免中间栏无限转圈',
      );
      return const <ViewPB>[];
    }
  }

  /// 新建笔记页
  Future<void> _createNewNote(BuildContext context) async {
    final result = await ViewBackendService.createView(
      layoutType: ViewLayoutPB.Document,
      parentViewId: widget.spaceView.id,
      name: ViewLayoutPB.Document.defaultName,
      openAfterCreate: false,
      index: 0,
    );
    result.fold(
      (view) {
        // 刷新空间文档列表
        try {
          context
              .read<SpaceBloc>()
              .add(const SpaceEvent.didUpdateCurrentSpaceChildViews());
        } catch (_) {
          _reloadBackendDocumentList();
        }
        // 通知父组件新文档已创建，以便自动选中并显示
        widget.onViewCreated(view);
      },
      (error) {
        Log.error('Failed to create new note: $error');
      },
    );
  }
}

class _SpaceHubSidebarToggleButton extends StatelessWidget {
  const _SpaceHubSidebarToggleButton({
    required this.color,
  });

  final Color color;

  @override
  Widget build(BuildContext context) {
    return FlowyTooltip(
      message: LocaleKeys.sideBar_openSidebar.tr(),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => context.read<HomeSettingBloc>().collapseMenu(),
          child: FlowySvg(
            FlowySvgs.sidebar_collapse_custom_m,
            size: const Size.square(24),
            color: color,
          ),
        ),
      ),
    );
  }
}

/// SpaceHub 可拖动分隔线组件
/// 使用 Listener 直接监听 pointer 事件，避免频繁 setState 导致的卡顿
/// 拖拽时会通知父组件，以便协调白板的手势响应
class _SpaceHubResizableDivider extends StatefulWidget {
  const _SpaceHubResizableDivider({
    super.key,
    required this.minLeftWidth,
    required this.maxLeftWidth,
    required this.currentLeftWidth,
    required this.onResize,
    // ✅ 新增：拖拽状态变化回调，用于协调白板手势
    this.onDragStateChanged,
    // ✅ 新增：是否启用拖拽功能，用于白板视图时禁用
    this.enabled = true,
  });

  final double minLeftWidth;
  final double maxLeftWidth;
  final double currentLeftWidth;
  final ValueChanged<double> onResize;
  // ✅ 新增：当拖拽开始/结束时通知父组件
  final ValueChanged<bool>? onDragStateChanged;
  /// 是否启用拖拽功能。当为 false 时，分隔线不可拖拽，也不会响应 hover 事件。
  /// 用于在白板视图时禁用分隔线，避免触发 setState 导致 WKWebView 布局偏移。
  final bool enabled;

  @override
  State<_SpaceHubResizableDivider> createState() =>
      _SpaceHubResizableDividerState();
}

class _SpaceHubResizableDividerState
    extends State<_SpaceHubResizableDivider> {
  bool _isHover = false;
  bool _isDragging = false;
  double? _dragStartGlobalX;
  double? _dragStartWidth;

  @override
  void dispose() {
    super.dispose();
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.enabled) return;
    setState(() => _isDragging = true);
    _dragStartGlobalX = event.position.dx;
    _dragStartWidth = widget.currentLeftWidth;
    // ✅ 通知父组件拖拽开始
    widget.onDragStateChanged?.call(true);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!widget.enabled || !_isDragging) return;

    final dragStartGlobalX = _dragStartGlobalX ?? event.position.dx;
    final dragStartWidth = _dragStartWidth ?? widget.currentLeftWidth;
    final newWidth =
        (dragStartWidth + (event.position.dx - dragStartGlobalX))
            .clamp(widget.minLeftWidth, widget.maxLeftWidth);
    widget.onResize(newWidth);
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (!widget.enabled) return;
    setState(() => _isDragging = false);
    _dragStartGlobalX = null;
    _dragStartWidth = null;
    // ✅ 通知父组件拖拽结束
    widget.onDragStateChanged?.call(false);
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (!widget.enabled) return;
    setState(() => _isDragging = false);
    _dragStartGlobalX = null;
    _dragStartWidth = null;
    // ✅ 通知父组件拖拽取消
    widget.onDragStateChanged?.call(false);
  }

  @override
  Widget build(BuildContext context) {
    // 当禁用时，使用简单的静态分隔线，不响应任何交互事件
    // 这样可以避免 MouseRegion 的 onEnter/onExit 触发 setState
    // 从而避免 WKWebView 布局偏移
    if (!widget.enabled) {
      return Container(
        width: HomeSizes.spaceHubDividerWidth,
        color: Colors.transparent,
        child: Center(
          child: Container(
            width: 2.0,
            color: Theme.of(context).dividerColor.withValues(alpha: 0.9),
          ),
        ),
      );
    }

    // 拖拽时使用更轻量的 UI 反馈
    final showHighlight = _isHover || _isDragging;

    return Listener(
      behavior: HitTestBehavior.opaque, // ✅ 确保优先捕获指针事件
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        onEnter: (_) => setState(() => _isHover = true),
        onExit: (_) => setState(() => _isHover = false),
        child: Container(
          width: HomeSizes.spaceHubDividerWidth,
          color: Colors.transparent,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 16),
              curve: Curves.easeOut,
              width: showHighlight ? 2.0 : 1.0,
              color: showHighlight
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).dividerColor.withValues(alpha: 0.9),
            ),
          ),
        ),
      ),
    );
  }
}
