import 'dart:async';
import 'dart:io' show Platform;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/features/workspace/data/repositories/rust_workspace_repository_impl.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/plugins/blank/blank.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/memory_leak_detector.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/user/application/reminder/reminder_bloc.dart';
import 'package:appflowy/util/log_utils.dart';
import 'package:appflowy/workspace/application/favorite/favorite_bloc.dart';
import 'package:appflowy/workspace/application/home/home_bloc.dart';
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/user/user_workspace_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/command_palette/command_palette.dart';
import 'package:appflowy/workspace/presentation/home/af_focus_manager.dart';
import 'package:appflowy/workspace/presentation/home/errors/workspace_failed_screen.dart';
import 'package:appflowy/workspace/presentation/home/hotkeys.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/sidebar.dart';
import 'package:appflowy/workspace/presentation/widgets/edit_panel/panel_animation.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/workspace.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart'
    show UserProfilePB, UserWorkspacePB;
import 'package:appflowy_result/appflowy_result.dart';
import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/style_widget/container.dart';
import 'package:flowy_infra/size.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sized_context/sized_context.dart';
import 'package:styled_widget/styled_widget.dart';

import '../notifications/notification_panel.dart';
import '../widgets/edit_panel/edit_panel.dart';
import '../widgets/sidebar_resizer.dart';
import '../widgets/dialogs.dart';
import 'home_layout.dart';
import 'home_stack.dart';
import 'full_window_controller.dart';
import 'menu/sidebar/slider_menu_hover_trigger.dart';
import 'menu/sidebar/space/shared_widget.dart';
import 'package:appflowy/workspace/application/subscription/membership_checker_service.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/subscription/subscription_service.dart';

class DesktopHomeScreen extends StatefulWidget {
  const DesktopHomeScreen({super.key});

  static const routeName = '/DesktopHomeScreen';

  @override
  State<DesktopHomeScreen> createState() => _DesktopHomeScreenState();
}

class _DesktopHomeScreenState extends State<DesktopHomeScreen> {
  static const double _minContentWidth = 760;
  static const double _minContentHeight = 420;

  late final Future<List<FlowyResult>> _initFuture;

  @override
  void initState() {
    super.initState();
    // 在 initState 中创建 future，避免在每次 rebuild 时重新创建
    _initFuture = Future.wait([
      FolderEventGetCurrentWorkspaceSetting().send(),
      getIt<AuthService>().getUser(),
    ]);
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FlowyResult>>(
      future: _initFuture,
      builder: (context, snapshots) {
        if (!snapshots.hasData) {
          return _buildLoading();
        }

        final workspaceLatest = snapshots.data?[0].fold(
          (workspaceLatestPB) => workspaceLatestPB as WorkspaceLatestPB,
          (error) => null,
        );

        final userProfile = snapshots.data?[1].fold(
          (userProfilePB) => userProfilePB as UserProfilePB,
          (error) => null,
        );

        // In the unlikely case either of the above is null, eg.
        // when a workspace is already open this can happen.
        if (workspaceLatest == null || userProfile == null) {
          return const WorkspaceFailedScreen();
        }

        return AFFocusManager(
          child: MultiBlocProvider(
            key: ValueKey(userProfile.id),
            providers: [
              BlocProvider.value(
                value: getIt<ReminderBloc>(),
              ),
              BlocProvider<TabsBloc>.value(value: getIt<TabsBloc>()),
              BlocProvider<HomeBloc>(
                create: (_) {
                  // 触发 TabsBloc 初始化，确保当前页面被添加到最近访问
                  getIt<TabsBloc>().add(const TabsEvent.initial());
                  return HomeBloc(workspaceLatest)
                    ..add(const HomeEvent.initial());
                },
              ),
              BlocProvider<HomeSettingBloc>(
                create: (_) => HomeSettingBloc(
                  workspaceLatest,
                  context.read<AppearanceSettingsCubit>(),
                  context.widthPx,
                )..add(const HomeSettingEvent.initial()),
              ),
              BlocProvider<FavoriteBloc>(
                create: (context) =>
                    FavoriteBloc()..add(const FavoriteEvent.initial()),
              ),
            ],
            child: Scaffold(
              floatingActionButton:
                  BlocBuilder<HomeSettingBloc, HomeSettingState>(
                buildWhen: (p, c) => p.menuStatus != c.menuStatus,
                builder: (context, state) {
                  final isMenuHidden = state.menuStatus == MenuStatus.hidden;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (enableMemoryLeakDetect)
                        const FloatingActionButton(
                          onPressed: dumpMemoryLeak,
                          child: Icon(Icons.memory),
                        ),
                      const SizedBox(height: 12),
                    ],
                  );
                },
              ),
              body: BlocListener<HomeBloc, HomeState>(
                listenWhen: (p, c) => p.latestView != c.latestView,
                listener: (context, state) {
                  final view = state.latestView;
                  if (view != null) {
                    // Only open the last opened view if the [TabsState.currentPageManager] current opened plugin is blank and the last opened view is not null.
                    // All opened widgets that display on the home screen are in the form of plugins. There is a list of built-in plugins defined in the [PluginType] enum, including board, grid and trash.
                    final currentPageManager =
                        context.read<TabsBloc>().state.currentPageManager;

                    if (currentPageManager.plugin.pluginType ==
                        PluginType.blank) {
                      if (view.id.isEmpty) {
                        Log.error(
                          'DesktopHomeScreen: latestView.id is empty, skip opening plugin',
                        );
                      } else {
                        getIt<TabsBloc>().openPlugin(view);
                      }
                    }

                    // switch to the space that contains the last opened view
                    _switchToSpace(view);
                  }
                },
                child: BlocBuilder<HomeSettingBloc, HomeSettingState>(
                  buildWhen: (previous, current) => previous != current,
                  builder: (context, state) => BlocProvider(
                    create: (_) => UserWorkspaceBloc(
                      userProfile: userProfile,
                      repository: RustWorkspaceRepositoryImpl(
                        userId: userProfile.id,
                      ),
                    )
                      ..add(UserWorkspaceEvent.initialize())
                      ..add(UserWorkspaceEvent.fetchWorkspaces()),
                    child: BlocListener<UserWorkspaceBloc, UserWorkspaceState>(
                      listenWhen: (previous, current) =>
                          previous.currentWorkspace !=
                              current.currentWorkspace ||
                          previous.workspaces.length !=
                              current.workspaces.length ||
                          _workspacesChanged(
                            previous.workspaces,
                            current.workspaces,
                          ) ||
                          (previous.actionResult?.actionType ==
                                  WorkspaceActionType.create &&
                              current.actionResult?.actionType ==
                                  WorkspaceActionType.create &&
                              previous.actionResult?.isLoading !=
                                  current.actionResult?.isLoading),
                      listener: (context, state) {
                        if (!context.mounted) return;
                        final workspaceBloc =
                            context.read<UserWorkspaceBloc?>();
                        final spaceBloc = context.read<SpaceBloc?>();
                        CommandPalette.maybeOf(context)?.updateBlocs(
                          workspaceBloc: workspaceBloc,
                          spaceBloc: spaceBloc,
                        );

                        // 检查当前工作区是否还在列表中
                        _checkAndHandleWorkspaceRemoved(context, state);
                      },
                      child: _WorkspaceLifecycleRefresher(
                        child: HomeHotKeys(
                          userProfile: userProfile,
                          child: FlowyContainer(
                            Theme.of(context).colorScheme.surface,
                            child: _buildBody(
                              context,
                              userProfile,
                              workspaceLatest,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoading() =>
      const Center(child: CircularProgressIndicator.adaptive());

  Widget _buildBody(
    BuildContext context,
    UserProfilePB userProfile,
    WorkspaceLatestPB workspaceSetting,
  ) {
    final layout = HomeLayout(context);
    final homeStack = HomeStack(
      layout: layout,
      delegate: DesktopHomeScreenStackAdaptor(context),
      userProfile: userProfile,
    );
    final sidebar = _buildHomeSidebar(
      context,
      layout: layout,
      userProfile: userProfile,
      workspaceSetting: workspaceSetting,
    );
    final notificationPanel = NotificationPanel();
    final sliderHoverTrigger = SliderMenuHoverTrigger(
      touchOptimized: context.widthPx < PageBreaks.tabletLandscape,
      onOpen: () => context.read<HomeSettingBloc>().add(
            const HomeSettingEvent.changeMenuStatus(MenuStatus.expanded),
          ),
    );

    final homeMenuResizer = layout.showMenu && !layout.menuIsDrawer
        ? const SidebarResizer()
        : const SizedBox.shrink();
    final editPanel = _buildEditPanel(context, layout: layout);

    // 使用 BlocBuilder 监听 TabsBloc 状态变化，以便在切换标签时更新问号按钮的显示
    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (previous, current) =>
          previous.currentPageManager.plugin.pluginType !=
          current.currentPageManager.plugin.pluginType,
      builder: (context, tabsState) {
        // 全窗口模式：不切换布局，仅用 Visibility 控制左侧菜单显隐，避免重新绘制
        return ValueListenableBuilder<bool>(
          valueListenable: FullWindowController.isFullWindow,
          builder: (context, isFullWindow, _) {
            return _layoutWidgets(
              layout: layout,
              homeStack: homeStack,
              sidebar: sidebar,
              editPanel: editPanel,
              homeMenuResizer: homeMenuResizer,
              notificationPanel: notificationPanel,
              sliderHoverTrigger: sliderHoverTrigger,
              isFullWindow: isFullWindow,
            );
          },
        );
      },
    );
  }

  Widget _buildHomeSidebar(
    BuildContext context, {
    required HomeLayout layout,
    required UserProfilePB userProfile,
    required WorkspaceLatestPB workspaceSetting,
  }) {
    final homeMenu = HomeSideBar(
      userProfile: userProfile,
      workspaceSetting: workspaceSetting,
      isDrawerMenu: layout.menuIsDrawer,
    );
    return FocusTraversalGroup(child: RepaintBoundary(child: homeMenu));
  }

  Widget _buildEditPanel(
    BuildContext context, {
    required HomeLayout layout,
  }) {
    final homeBloc = context.read<HomeSettingBloc>();
    return BlocBuilder<HomeSettingBloc, HomeSettingState>(
      buildWhen: (previous, current) =>
          previous.panelContext != current.panelContext,
      builder: (context, state) {
        final panelContext = state.panelContext;
        if (panelContext == null) {
          return const SizedBox.shrink();
        }

        return FocusTraversalGroup(
          child: RepaintBoundary(
            child: EditPanel(
              panelContext: panelContext,
              onEndEdit: () => homeBloc.add(
                const HomeSettingEvent.dismissEditPanel(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _layoutWidgets({
    required HomeLayout layout,
    required Widget sidebar,
    required Widget homeStack,
    required Widget editPanel,
    required Widget homeMenuResizer,
    required Widget notificationPanel,
    required Widget sliderHoverTrigger,
    bool isFullWindow = false,
  }) {
    final isSliderbarShowing = layout.showMenu;
    final isDrawerMenu =
        isSliderbarShowing && (layout.menuIsDrawer || isFullWindow);
    // 全窗口时主内容区铺满；非全窗口时为主内容区留出左侧偏移
    final homeStackLeft = isFullWindow ? 0.0 : layout.homePageLOffset;
    final homeStackRight = layout.homePageROffset;
    return Stack(
      children: [
        homeStack
            .constrained(
              minWidth: _minContentWidth,
              minHeight: _minContentHeight,
            )
            .positioned(
              left: homeStackLeft,
              right: homeStackRight,
              bottom: 0,
              top: 0,
              animate: true,
            )
            .animate(layout.animDuration, Curves.easeOutQuad),
        editPanel
            .animatedPanelX(
              duration: layout.animDuration.inMilliseconds * 0.001,
              closeX: layout.editPanelWidth,
              isClosed: !layout.showEditPanel,
              curve: Curves.easeOutQuad,
            )
            .positioned(
              top: 0,
              right: 0,
              bottom: 0,
              width: layout.editPanelWidth,
            ),
        notificationPanel
            .animatedPanelX(
              closeX: -layout.notificationPanelWidth,
              isClosed: !layout.showNotificationPanel,
              curve: Curves.easeOutQuad,
              duration: layout.animDuration.inMilliseconds * 0.001,
            )
            .positioned(
              left: isFullWindow
                  ? 0
                  : (isSliderbarShowing && !isDrawerMenu
                      ? layout.menuWidth
                      : 0),
              top: isSliderbarShowing && !isDrawerMenu ? 0 : 52,
              width: layout.notificationPanelWidth,
              bottom: 0,
            ),
        if (isDrawerMenu)
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => context.read<HomeSettingBloc>().add(
                    const HomeSettingEvent.changeMenuStatus(MenuStatus.hidden),
                  ),
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.08),
              ),
            ),
          ),
        // 左侧菜单：Positioned 必须是 Stack 直接子组件才能正确布局；全屏时宽度为 0 不占位
        Positioned(
          left: 0,
          top: isDrawerMenu ? 12 : 0,
          bottom: isDrawerMenu ? 12 : 0,
          width: layout.menuWidth,
          child: Visibility(
            visible: isSliderbarShowing,
            maintainState: true,
            child: (isDrawerMenu
                    ? ClipRRect(
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(14),
                        ),
                        child: sidebar,
                      )
                    : sidebar)
                .animatedPanelX(
              closeX: -layout.menuWidth,
              isClosed: !isSliderbarShowing,
              curve: Curves.easeOutQuad,
              duration: layout.animDuration.inMilliseconds * 0.001,
            ),
          ),
        ),
        // 左侧与主内容之间的 resizer，全屏时宽度为 0 不占位
        Positioned(
          left: isFullWindow ? 0 : layout.menuWidth,
          top: 0,
          bottom: 0,
          width: isFullWindow ? 0 : null,
          child: Visibility(
            visible: !isFullWindow && !isDrawerMenu,
            maintainState: true,
            child: homeMenuResizer.animate(
              layout.animDuration,
              Curves.easeOutQuad,
            ),
          ),
        ),
        if (!isSliderbarShowing)
          Positioned(
            left: 6,
            top: Platform.isWindows ? 56 : 12,
            child: sliderHoverTrigger,
          ),
      ],
    );
  }

  Future<void> _switchToSpace(ViewPB view) async {
    final ancestors = await ViewBackendService.getViewAncestors(view.id);
    final space = ancestors.fold(
      (ancestors) =>
          ancestors.items.firstWhereOrNull((ancestor) => ancestor.isSpace),
      (error) => null,
    );
    if (space?.id != switchToSpaceNotifier.value?.id) {
      switchToSpaceNotifier.value = space;
    }
  }

  bool _workspacesChanged(
    List<UserWorkspacePB> previous,
    List<UserWorkspacePB> current,
  ) {
    if (previous.length != current.length) {
      return true;
    }
    final previousIds = previous.map((w) => w.workspaceId).toSet();
    final currentIds = current.map((w) => w.workspaceId).toSet();
    return previousIds != currentIds;
  }

  void _checkAndHandleWorkspaceRemoved(
    BuildContext context,
    UserWorkspaceState state,
  ) {
    final currentWorkspace = state.currentWorkspace;
    final workspaces = state.workspaces;

    // 如果当前工作区不在列表中，说明被移除了
    if (currentWorkspace != null) {
      final isCurrentWorkspaceInList = workspaces.any(
        (w) => w.workspaceId == currentWorkspace.workspaceId,
      );

      if (!isCurrentWorkspaceInList) {
        Log.info(
          'Current workspace ${currentWorkspace.workspaceId} not found in list, switching to an available workspace',
        );

        final workspaceBloc = context.read<UserWorkspaceBloc?>();
        if (workspaceBloc != null) {
          // 优先切换到用户自己的工作区（Owner），找不到再退回第一个可用工作区。
          // 这样被移出协作区时，会自动回到用户自己的工作区。
          UserWorkspacePB? targetWorkspace = workspaces.firstWhereOrNull(
            (w) => w.role == AFRolePB.Owner,
          );
          targetWorkspace ??= workspaces.firstOrNull;

          if (targetWorkspace != null) {
            Log.info(
              'Switching workspace to ${targetWorkspace.workspaceId} (role: ${targetWorkspace.role}) after removal',
            );
            workspaceBloc.add(
              UserWorkspaceEvent.openWorkspace(
                workspaceId: targetWorkspace.workspaceId,
                workspaceType: targetWorkspace.workspaceType,
              ),
            );
          }
        }

        showToastNotification(
          message:
              LocaleKeys.settings_appearance_members_removeFromWorkspace.tr(),
          type: ToastificationType.warning,
        );
      }
    }
  }
}

/// 监听应用生命周期和页面可见性，在首页可见时刷新工作区列表。
/// 放在 `UserWorkspaceBloc` 的子树中，确保能拿到正确的 Bloc。
class _WorkspaceLifecycleRefresher extends StatefulWidget {
  const _WorkspaceLifecycleRefresher({required this.child});

  final Widget child;

  @override
  State<_WorkspaceLifecycleRefresher> createState() =>
      _WorkspaceLifecycleRefresherState();
}

class _WorkspaceLifecycleRefresherState
    extends State<_WorkspaceLifecycleRefresher> with WidgetsBindingObserver {
  DateTime? _lastRefreshTime;
  static const _refreshDebounceDuration = Duration(seconds: 2);

  /// 定期刷新定时器，用于检测用户是否被踢出工作区
  /// 间隔设置为 5 分钟，作为 WebSocket 实时通知的后备机制
  /// WebSocket 连接断开时，此定时器可以确保用户最终会被踢出
  Timer? _periodicRefreshTimer;
  static const _periodicRefreshInterval = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 启动定期刷新定时器，用于检测用户是否被踢出工作区
    _startPeriodicRefresh();
  }

  /// 启动定期刷新定时器
  void _startPeriodicRefresh() {
    _periodicRefreshTimer?.cancel();
    _periodicRefreshTimer = Timer.periodic(
      _periodicRefreshInterval,
      (_) {
        if (mounted) {
          _refreshWorkspaceList();
        }
      },
    );
    LogUtils.info(
      'WorkspaceLifecycleRefresher: started periodic refresh timer',
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 每次首页可见时刷新工作区列表（使用防抖避免过于频繁）
    if (mounted) {
      final now = DateTime.now();
      if (_lastRefreshTime == null ||
          now.difference(_lastRefreshTime!) > _refreshDebounceDuration) {
        _lastRefreshTime = now;
        // 延迟一小段时间，确保 Bloc 已经初始化
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _refreshWorkspaceList();
            _checkMembershipStatus();
          }
        });
      }
    }
  }

  /// 检查会员状态和存储限制，如果过期或存储不足则打开会员订阅页面
  Future<void> _checkMembershipStatus() async {
    try {
      // 获取当前工作区ID
      final workspaceId = context
          .read<UserWorkspaceBloc?>()
          ?.state
          .currentWorkspace
          ?.workspaceId;
      // 检查会员状态
      await context.checkMembershipStatus(workspaceId: workspaceId);
      if (!mounted) {
        return;
      }

      // 检查存储限制
      await context.checkAndHandleCloudSyncStorageLimit(
        workspaceId: workspaceId,
      );
    } catch (e) {
      Log.error('Failed to check membership status: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _periodicRefreshTimer?.cancel();
    _periodicRefreshTimer = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 应用恢复时刷新工作区列表
      _lastRefreshTime = DateTime.now();
      _refreshWorkspaceList();
    }
  }

  void _refreshWorkspaceList() {
    // 此处的 context 在 UserWorkspaceBloc 的子树中，可以安全读取 Bloc
    final workspaceBloc = context.read<UserWorkspaceBloc?>();
    if (workspaceBloc != null) {
      LogUtils.info(
        'WorkspaceLifecycleRefresher: page visible, fetchWorkspaces',
      );
      workspaceBloc.add(UserWorkspaceEvent.fetchWorkspaces());
    } else {
      LogUtils.info(
        'WorkspaceLifecycleRefresher: UserWorkspaceBloc is null',
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class DesktopHomeScreenStackAdaptor extends HomeStackDelegate {
  DesktopHomeScreenStackAdaptor(this.buildContext);

  final BuildContext buildContext;

  @override
  void didDeleteStackWidget(ViewPB view, int? index) {
    ViewBackendService.getView(view.parentViewId).then(
      (result) => result.fold(
        (parentView) {
          final List<ViewPB> views = parentView.childViews;
          if (views.isNotEmpty) {
            ViewPB lastView = views.last;
            if (index != null && index != 0 && views.length > index - 1) {
              lastView = views[index - 1];
            }

            if (lastView.id.isEmpty) {
              Log.error(
                'DesktopHomeScreen: lastView.id is empty, skip opening plugin',
              );
              return;
            }
            return getIt<TabsBloc>().openPlugin(lastView);
          }

          getIt<TabsBloc>()
              .add(TabsEvent.openPlugin(plugin: BlankPagePlugin()));
        },
        (err) => Log.error(err),
      ),
    );
  }
}
