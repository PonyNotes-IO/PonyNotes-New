library;

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
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/view_info/view_info_bloc.dart';
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
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/platform_extension.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:appflowy/workspace/presentation/widgets/resizable_divider.dart';
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
  Widget? get rightBarItem {
    // 当有选中文档时，返回该文档的右侧工具栏
    // 注意：ValueListenableBuilder 的 builder 不能返回 null，因此这里用 SizedBox.shrink 占位
    return ValueListenableBuilder<ViewPB?>(
      valueListenable: selectedViewNotifier,
      builder: (context, selectedView, _) {
        if (selectedView == null) {
          return const SizedBox.shrink();
        }

        try {
          // ✅ 使用 currentViewInfoBlocNotifier 来获取当前文档的 ViewInfoBloc
          return ValueListenableBuilder<ViewInfoBloc?>(
            valueListenable: currentViewInfoBlocNotifier,
            builder: (context, currentViewInfoBloc, _) {
              final effectiveViewInfoBloc = currentViewInfoBloc ?? bloc;
              return MultiBlocProvider(
                providers: [
                  BlocProvider<ViewInfoBloc>.value(
                      value: effectiveViewInfoBloc),
                ],
                child: UnifiedViewTopRightActions(
                  view: selectedView,
                  viewInfoBloc: effectiveViewInfoBloc,
                  showCollaborators: FeatureFlag.syncDocument.isOn &&
                      selectedView.layout != ViewLayoutPB.Whiteboard,
                  useFloatingSurface: true,
                ),
              );
            },
          );
        } catch (e) {
          // 静默处理错误
        }

        // 没有可用的工具栏时，返回一个空占位，避免报错
        return const SizedBox.shrink();
      },
    );
  }

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
    // When Space Hub is rendering a selected whiteboard, the whiteboard page
    // owns the full-window capsule internally.
    // 当 Space Hub 右侧选中的是白板时，由白板页面内部统一承载应用内全屏动作区。
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
    return Builder(
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
  double get topTabsLeadingWidth => HomeSizes.spaceHubTopTabsLeadingWidth;

  @override
  Widget? topTabsLeadingPane(BuildContext context) {
    SpaceBloc? spaceBloc;
    try {
      spaceBloc = BlocProvider.of<SpaceBloc>(context);
    } catch (_) {
      spaceBloc = null;
    }

    // Move the SpaceHub list header into HomeStack's tab-leading slot.
    // 将 SpaceHub 列表头部放进顶部预留区，避免中间栏上方出现空白。
    return _SpaceDocumentList(
      spaceView: view,
      selectedView: null,
      showHeader: true,
      onViewCreated: (view) {
        selectedViewNotifier.value = view;
      },
      onViewSelectedWithRecent: (_) {},
    )._buildHeader(context, spaceBloc);
  }

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
  ViewPB? _selectedView;

  /// 左侧文档列表的宽度
  double _leftPanelWidth = HomeSizes.defaultSpaceHubMiddlePaneWidth;

  /// 左侧面板最小宽度
  static const double _minLeftWidth = 200.0;

  /// 左侧面板最大宽度
  static const double _maxLeftWidth = 450.0;

  /// 上次添加到最近访问的视图 ID（用于防抖）
  String? _lastAddedRecentViewId;

  /// 为每个子文档视图创建的 ViewInfoBloc（用于字数统计）
  final List<ViewInfoBloc> _childViewInfoBlocs = [];

  bool _isDocumentListVisible = true;

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
    // 若有预选文档（从新选项卡打开），直接使用，否则尝试选第一个文档
    if (widget.initialSelectedView != null) {
      _selectedView = widget.initialSelectedView;
      widget.selectedViewNotifier.value = widget.initialSelectedView;
      _addToRecentViews(widget.initialSelectedView!.id);
    } else {
      _trySelectFirstDocument();
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
      // didUpdateWidget 处于 build 阶段，直接修改 ValueNotifier 会触发
      // ValueListenableBuilder.markNeedsBuild()，导致 "called during build" 错误。
      // 延迟到当前帧结束后再设置，避免在 build 阶段修改 ValueNotifier。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.selectedViewNotifier.value = null;
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

    setState(() {
      _selectedView = view;
    });
    widget.selectedViewNotifier.value = view;
    _addToRecentViews(view.id);
    context.read<TabsBloc>().add(
          TabsEvent.openTab(
            plugin: SpaceHubPlugin(
              view: widget.spaceView,
              initialSelectedView: view,
              tabView: view,
            ),
            view: view,
          ),
        );
  }

  void _hideDocumentList() {
    if (!_isDocumentListVisible) {
      return;
    }
    setState(() => _isDocumentListVisible = false);
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
          final firstView = currentSpace.childViews.first;
          setState(() {
            _selectedView = firstView;
          });
          // 更新共享的选中视图状态
          widget.selectedViewNotifier.value = firstView;
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
            .clamp(HomeSizes.minimumSpaceHubMiddlePaneWidth, double.infinity)
            .toDouble();
        final effectiveLeftPanelWidth = _leftPanelWidth.clamp(
          HomeSizes.minimumSpaceHubMiddlePaneWidth,
          maxLeftPanelWidth,
        );
        final floatingDocumentListTopInset =
            Platform.isWindows ? 0.0 : HomeSizes.topBarHeight;
        final passiveFloatingDivider = Padding(
          padding: EdgeInsets.only(
            top: floatingDocumentListTopInset,
            bottom: 12,
          ),
          child: SizedBox(
            width: HomeSizes.spaceHubDividerWidth,
            child: Align(
              alignment: Alignment.centerLeft,
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
        final documentListPanel = Padding(
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: _SpaceDocumentList(
                      spaceView: widget.spaceView,
                      selectedView: _selectedView,
                      showHeader: isFullWindow,
                      onViewSelectedWithRecent: _selectViewInMiddlePanel,
                      onViewCreated: _selectViewInMiddlePanel,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左侧：空间文档列表
            Visibility(
              visible: _isDocumentListVisible,
              child: documentListPanel,
            ),
            // 可拖动分隔线 - 增强对比度并支持拖动调整大小
            Visibility(
              visible: _isDocumentListVisible && !useFloatingDocumentList,
              child: ResizableDivider(
                minLeftWidth: HomeSizes.minimumSpaceHubMiddlePaneWidth,
                maxLeftWidth: maxLeftPanelWidth,
                initialLeftWidth: effectiveLeftPanelWidth,
                onResize: (newWidth) {
                  setState(() {
                    _leftPanelWidth = newWidth.clamp(
                      HomeSizes.minimumSpaceHubMiddlePaneWidth,
                      maxLeftPanelWidth,
                    );
                  });
                },
              ),
            ),
            Visibility(
              visible: _isDocumentListVisible && useFloatingDocumentList,
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
    // 根据 view 的类型创建对应的插件并展示
    try {
      final plugin = view.plugin();
      // 确保插件已初始化
      plugin.init();

      // 获取 userProfile - AI Chat 等插件需要用户信息
      UserProfilePB? userProfile;
      try {
        final userWorkspaceBloc = context.read<UserWorkspaceBloc>();
        userProfile = userWorkspaceBloc.state.userProfile;
      } catch (e) {
        // 静默处理
      }

      // 为文档、文件夹和笔记本类型的视图添加 isInSpaceHub 参数
      try {
        final plugin = view.plugin();
        if (plugin.pluginType == PluginType.document ||
            plugin.pluginType == PluginType.folder ||
            plugin.pluginType == PluginType.notebook) {
          // 检查是否已经为这个 view 创建过 ViewInfoBloc
          // 如果是（用户切换视图后又切回来），复用已有的 bloc
          ViewInfoBloc? existingBloc;
          for (final bloc in _childViewInfoBlocs) {
            if (bloc.view.id == view.id) {
              existingBloc = bloc;
              break;
            }
          }

          ViewInfoBloc viewInfoBloc;
          if (existingBloc != null) {
            Log.debug(
                'SpaceHub: Reusing existing ViewInfoBloc for view: ${view.id}, hashCode: ${existingBloc.hashCode}');
            viewInfoBloc = existingBloc;
          } else {
            viewInfoBloc = ViewInfoBloc(view: view)
              ..add(const ViewInfoEvent.started());
            Log.debug(
                'SpaceHub: Created new ViewInfoBloc for view: ${view.id}, hashCode: ${viewInfoBloc.hashCode}');
            _childViewInfoBlocs.add(viewInfoBloc);
          }

          // ✅ 在 build 完成后更新 currentViewInfoBlocNotifier，避免 setState() called during build 错误
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              widget.currentViewInfoBlocNotifier.value = viewInfoBloc;
            }
          });

          // 将 viewInfoBloc 作为参数传给 DocumentPage，确保正确传递
          return DocumentPage(
            key: ValueKey(view.id),
            view: view,
            onDeleted: () => _onChildViewDeleted(view, null),
            tabs: const [
              PickerTabType.emoji,
              PickerTabType.icon,
              PickerTabType.custom,
            ],
            isInSpaceHub: true, // 在 Space Hub 中打开
            viewInfoBloc: viewInfoBloc, // ✅ 传给 DocumentPage
          );
        }
      } catch (e) {
        // 静默处理错误
      }

      return plugin.widgetBuilder.buildWidget(
        context: PluginContext(
          onDeleted: _onChildViewDeleted,
          userProfile: userProfile, // 传入用户配置
        ),
        shrinkWrap: false,
        data: view.layout == ViewLayoutPB.Whiteboard
            ? const {
                'preferHostFullWindowMoreItem': true,
                'preferHostTopRightActions': true,
              }
            : null,
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
    if (childViews.isEmpty) {
      if (_selectedView != null) {
        setState(() {
          _selectedView = null;
        });
        widget.selectedViewNotifier.value = null;
      }
      return;
    }

    if (_selectedView == null) {
      final firstView = childViews.first;
      setState(() {
        _selectedView = firstView;
      });
      widget.selectedViewNotifier.value = firstView;
      return;
    }

    final selectedId = _selectedView!.id;
    final stillExists = childViews.any((v) => v.id == selectedId);
    if (stillExists) {
      return;
    }

    // Selected view was deleted or moved out; switch right panel to first available.
    final fallbackView = childViews.first;
    setState(() {
      _selectedView = fallbackView;
    });
    widget.selectedViewNotifier.value = fallbackView;
  }

  @override
  void dispose() {
    SpaceHubMiddlePanelController.revealRequest
        .removeListener(_handleRevealDocumentList);
    // ✅ 清理所有缓存的 ViewInfoBloc，防止内存泄漏
    for (final bloc in _childViewInfoBlocs) {
      bloc.close();
    }
    _childViewInfoBlocs.clear();
    super.dispose();
  }
}

/// 空间文档列表组件（左侧）
class _SpaceDocumentList extends StatelessWidget {
  const _SpaceDocumentList({
    required this.spaceView,
    required this.selectedView,
    required this.showHeader,
    required this.onViewCreated,
    required this.onViewSelectedWithRecent,
  });

  final ViewPB spaceView;
  final ViewPB? selectedView;
  final bool showHeader;
  final ValueChanged<ViewPB> onViewCreated;
  final void Function(ViewPB view) onViewSelectedWithRecent;

  @override
  Widget build(BuildContext context) {
    // 尝试从 SpaceBloc 获取空间文档列表
    SpaceBloc? spaceBloc;
    try {
      spaceBloc = BlocProvider.of<SpaceBloc>(context);
    } catch (_) {
      spaceBloc = null;
    }

    return Container(
      // 仅保留左侧留白，避免右侧产生与分割线之间的空白带
      margin: const EdgeInsets.only(left: 12),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 头部：空间名称 + 新增文档按钮
          if (showHeader) ...[
            // Header stays here only in fullscreen, where HomeStack has no tabs.
            // 仅在应用内全屏保留列表头部；普通模式下由顶部预留区承载。
            _buildHeader(context, spaceBloc),
            VSpace(4),
          ],
          // 文档列表
          Expanded(
            child: spaceBloc != null
                ? _buildListFromSpaceBloc(context, spaceBloc)
                : _buildListFromBackend(context),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, SpaceBloc? spaceBloc) {
    final isSidebarHidden = context.select<HomeSettingBloc, bool>(
      (bloc) => bloc.isMenuHidden,
    );
    final theme = AppFlowyTheme.of(context);

    return Container(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 10, bottom: 4),
      // decoration: BoxDecoration(
      //   border: Border(
      //     bottom: BorderSide(color: Theme.of(context).dividerColor),
      //   ),
      //   color: Theme.of(context).colorScheme.surfaceContainer,
      // ),
      child: Row(
        children: [
          Expanded(
            child: FlowyText(
              spaceView.name,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(
            width: 24,
            height: 24,
            child: ViewAddButton(
              parentViewId: spaceView.id,
              onEditing: (_) {},
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
                    parentViewId: spaceView.id,
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
                      onViewCreated(view);
                    },
                    (error) {
                      Log.error('Failed to create view: $error');
                    },
                  );
                } else {
                  // Fallback: 直接创建文档
                  final result = await ViewBackendService.createView(
                    layoutType: layout,
                    parentViewId: spaceView.id,
                    name: finalName,
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
                    onViewCreated(view);
                  }, (error) {
                    Log.error('Failed to create view (fallback): $error');
                  });
                }
              },
              tooltipText: '新增文档',
            ),
          ),
          if (isSidebarHidden) ...[
            if (Platform.isMacOS)
              SizedBox(
                width: 28,
                height: 24,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      right: 0,
                      top: -18,
                      child: _SpaceHubSidebarToggleButton(
                        color: theme.iconColorScheme.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            if (Platform.isWindows) ...[
              const HSpace(4),
              SizedBox(
                width: 24,
                height: 24,
                child: _SpaceHubSidebarToggleButton(
                  color: theme.iconColorScheme.secondary,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildListFromSpaceBloc(BuildContext context, SpaceBloc spaceBloc) {
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
        // 当 SpaceBloc 初始化完成后，如果当前空间不是目标空间，则打开目标空间
        if (state.isInitialized) {
          final currentSpace = state.currentSpace;
          if (currentSpace?.id != spaceView.id) {
            // 使用 Future.microtask 确保在下一帧执行，避免在 listener 中直接修改状态
            Future.microtask(() {
              if (!spaceBloc.isClosed) {
                final currentState = spaceBloc.state;
                // 再次检查，避免重复打开
                if (currentState.isInitialized &&
                    currentState.currentSpace?.id != spaceView.id) {
                  spaceBloc.add(SpaceEvent.open(space: spaceView));
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
          if (currSpace?.id != spaceView.id && prevSpace?.id != spaceView.id) {
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

          // 检查子视图ID列表是否变化（使用 Set 比较，忽略顺序）
          final prevIds = prevSpace?.childViews.map((v) => v.id).toSet();
          final currIds = currSpace?.childViews.map((v) => v.id).toSet();
          if (prevIds != currIds) {
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

          // 如果 SpaceBloc 还未初始化，显示加载中
          if (!state.isInitialized) {
            return const Center(
              child: CircularProgressIndicator.adaptive(),
            );
          }

          // 如果当前空间不是目标空间，显示加载中（等待 SpaceEvent.open 完成）
          if (currentSpace?.id != spaceView.id) {
            return const Center(
              child: CircularProgressIndicator.adaptive(),
            );
          }

          // 当前空间匹配，使用 currentSpace（它已经包含了加载的子视图）
          final displaySpace = currentSpace!;
          final childViews = displaySpace.childViews;

          return ListView.builder(
            itemCount: childViews.length + 1,
            itemBuilder: (context, index) {
              if (index == childViews.length) {
                return AFGhostIconTextButton.primary(
                  text: '新增笔记页', // 临时使用硬编码文本
                  mainAxisAlignment: MainAxisAlignment.start,
                  size: AFButtonSize.l,
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
              }
              final childView = childViews[index];
              return ViewItem(
                key: ValueKey('space_hub_${childView.id}'),
                view: childView,
                spaceType: childView.spacePermission == SpacePermission.private
                    ? FolderSpaceType.private
                    : FolderSpaceType.public,
                level: 0,
                leftPadding: 10,
                onSelected: (itemContext, selectedView) {
                  // 在空间统一页面中，点击文档只更新选中状态，不打开新 tab
                  // 更新 MenuSharedState 以便 ViewItem 显示选中状态
                  getIt<MenuSharedState>().latestOpenView = selectedView;
                  onViewSelectedWithRecent(selectedView);
                },
                isFeedback: false,
                shouldRenderChildren: true,
                shouldLoadChildViews: true,
                enableRightClickContext: true, // 保持右键菜单功能
                isHoverEnabled: true,
                disableSelectedStatus: false, // 允许显示选中状态
                isTablet: PlatformInfo.isTablet, // 平板端始终显示按钮
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildListFromBackend(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return FutureBuilder<List<ViewPB>>(
      future: _loadChildViews(spaceView.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }

        final childViews = snapshot.data ?? const <ViewPB>[];

        return ListView.builder(
          itemCount: childViews.length + 1,
          itemBuilder: (context, index) {
            if (index == childViews.length) {
              return AFGhostIconTextButton.primary(
                text: '新增日记页', // 临时使用硬编码文本
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
            }
            final childView = childViews[index];
            return ViewItem(
              key: ValueKey('space_hub_${childView.id}'),
              view: childView,
              spaceType: childView.spacePermission == SpacePermission.private
                  ? FolderSpaceType.private
                  : FolderSpaceType.public,
              level: 0,
              leftPadding: 10,
              onSelected: (itemContext, selectedView) {
                // 更新 MenuSharedState 以便 ViewItem 显示选中状态
                getIt<MenuSharedState>().latestOpenView = selectedView;
                onViewSelectedWithRecent(selectedView);
              },
              isFeedback: false,
              shouldRenderChildren: true,
              shouldLoadChildViews: true,
              enableRightClickContext: true,
              isHoverEnabled: true,
              disableSelectedStatus: false, // 允许显示选中状态
              isTablet: PlatformInfo.isTablet, // 平板端始终显示按钮
            );
          },
        );
      },
    );
  }

  Future<List<ViewPB>> _loadChildViews(String spaceId) async {
    final result = await ViewBackendService.getChildViews(viewId: spaceId);
    return result.fold((views) => views, (_) => const <ViewPB>[]);
  }

  /// 新建笔记页
  Future<void> _createNewNote(BuildContext context) async {
    final result = await ViewBackendService.createView(
      layoutType: ViewLayoutPB.Document,
      parentViewId: spaceView.id,
      name: ViewLayoutPB.Document.defaultName,
      openAfterCreate: false,
    );
    result.fold(
      (view) {
        // 刷新空间文档列表
        context
            .read<SpaceBloc>()
            .add(const SpaceEvent.didUpdateCurrentSpaceChildViews());
        // 通知父组件新文档已创建，以便自动选中并显示
        onViewCreated(view);
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
      child: FlowyIconButton(
        width: 24,
        icon: FlowySvg(
          FlowySvgs.sidebar_collapse_custom_m,
          size: const Size.square(16),
          color: color,
        ),
        onPressed: () => context.read<HomeSettingBloc>().add(
              const HomeSettingEvent.changeMenuStatus(MenuStatus.expanded),
            ),
      ),
    );
  }
}
