import 'dart:async';
import 'dart:io' show Platform;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/features/workspace/data/repositories/rust_workspace_repository_impl.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/plugins/blank/blank.dart';
import 'package:appflowy/plugins/util.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/memory_leak_detector.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/user/application/reminder/reminder_bloc.dart';
import 'package:appflowy/util/log_utils.dart';
import 'package:appflowy/util/performance_trace.dart';
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
import 'package:appflowy_backend/protobuf/flowy-folder/notification.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/workspace.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart'
    show AuthTypePB, UserProfilePB, UserWorkspacePB;
import 'package:appflowy_backend/rust_stream.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra/size.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/container.dart';
import 'package:flowy_infra_ui/style_widget/hover.dart';
import 'package:flowy_infra/platform_extension.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sized_context/sized_context.dart';
import 'package:styled_widget/styled_widget.dart';

import '../notifications/notification_panel.dart';
import '../widgets/dialogs.dart';
import '../widgets/edit_panel/edit_panel.dart';
import '../widgets/sidebar_resizer.dart';
import 'full_window_controller.dart';
import 'home_layout.dart';
import 'home_sizes.dart';
import 'home_stack.dart';
import 'menu/sidebar/space/shared_widget.dart';
import 'upgrade_success_toast.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/mobile/application/mobile_view_migration_handoff.dart';
import 'package:appflowy/workspace/application/subscription/membership_checker_service.dart';
import 'package:appflowy/workspace/application/subscription/subscription_service.dart';
import 'package:appflowy/workspace/application/subscription_success_listenable/subscription_success_listenable.dart';

class _SharedAccessRevocationListener extends StatefulWidget {
  const _SharedAccessRevocationListener({required this.child});

  final Widget child;

  @override
  State<_SharedAccessRevocationListener> createState() =>
      _SharedAccessRevocationListenerState();
}

class _SharedAccessRevocationListenerState
    extends State<_SharedAccessRevocationListener> {
  static const String _folderObservableSource = 'Workspace';
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = RustStreamReceiver.listen((observable) {
      if (!mounted || observable.source != _folderObservableSource) {
        return;
      }
      if (observable.ty != FolderNotification.DidRemoveMySharedView.value) {
        return;
      }
      final revokedViewId = observable.id;
      if (revokedViewId.isEmpty) {
        return;
      }
      if (MobileViewMigrationHandoff.isExpectedRemoval(revokedViewId)) {
        Log.info(
          '[WhiteboardMigrationUI] 忽略桌面端迁移中的源白板删除通知: '
          'removed=$revokedViewId replacement='
          '${MobileViewMigrationHandoff.replacementViewId(revokedViewId)}',
        );
        return;
      }
      final tabsBloc = getIt<TabsBloc>();
      final pageManagers = tabsBloc.state.pageManagers;
      final isOpen = pageManagers.any((pm) => pm.plugin.id == revokedViewId);
      if (!isOpen) {
        return;
      }
      final isCurrent =
          tabsBloc.state.currentPageManager.plugin.id == revokedViewId;
      if (isCurrent) {
        // The user is viewing the revoked document. closeView refuses to close
        // the last remaining tab (and documents open by replacing the current
        // tab in place, so there is usually exactly one), which would leave the
        // doc editable. Navigate back to the home page instead.
        tabsBloc.add(
          TabsEvent.openPlugin(
            plugin: makePlugin(pluginType: PluginType.homepage),
          ),
        );
      } else {
        // The revoked view is open in a non-active tab — just drop that tab
        // without disturbing the page the user is currently on.
        tabsBloc.add(TabsEvent.closeTab(revokedViewId));
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

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

  String? _upgradeSuccessMessage;
  late final SubscriptionSuccessListenable _subscriptionSuccessListenable;
  late final VoidCallback _subscriptionSuccessListener;
  bool _homeReadyMarked = false;

  @override
  void initState() {
    super.initState();
    _initFuture = Future.wait([
      FolderEventGetCurrentWorkspaceSetting().send(),
      getIt<AuthService>().getUser(),
    ]);

    _subscriptionSuccessListenable = getIt<SubscriptionSuccessListenable>();
    _subscriptionSuccessListener = () {
      if (!mounted) {
        return;
      }
      final message = _subscriptionSuccessListenable.upgradeSuccessMessage;
      setState(() {
        _upgradeSuccessMessage = message;
      });
    };
    _subscriptionSuccessListenable.addListener(_subscriptionSuccessListener);
  }

  @override
  void dispose() {
    _subscriptionSuccessListenable.removeListener(_subscriptionSuccessListener);
    super.dispose();
  }

  void _dismissUpgradeToast() {
    setState(() {
      _upgradeSuccessMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isTablet = PlatformInfo.isTablet;

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

        if (workspaceLatest == null || userProfile == null) {
          return const WorkspaceFailedScreen();
        }

        _markHomeReady();

        return AFFocusManager(
          child: MultiBlocProvider(
            key: ValueKey(userProfile.id),
            providers: [
              BlocProvider.value(value: getIt<ReminderBloc>()),
              BlocProvider<TabsBloc>.value(value: getIt<TabsBloc>()),
              BlocProvider<HomeBloc>(
                create: (_) {
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
            child: _SharedAccessRevocationListener(
              child: Scaffold(
                resizeToAvoidBottomInset: !PlatformInfo.isTablet, // 防止全树重建
                floatingActionButton:
                    BlocBuilder<HomeSettingBloc, HomeSettingState>(
                  buildWhen: (previous, current) =>
                      previous.menuStatus != current.menuStatus,
                  builder: (context, state) {
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
                body: SafeArea(
                  top: isTablet,
                  bottom: isTablet,
                  child: Stack(
                    children: [
                      BlocListener<HomeBloc, HomeState>(
                        listenWhen: (previous, current) =>
                            previous.latestView != current.latestView,
                        listener: (context, state) {
                          final view = state.latestView;
                          if (view != null) {
                            // 总是打开最新视图，确保启动时恢复上次的视图（包括日历视图）
                            if (view.id.isEmpty) {
                              Log.error(
                                'DesktopHomeScreen: latestView.id is empty, skip opening plugin',
                              );
                            } else {
                              getIt<TabsBloc>().openPlugin(view);
                            }

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
                            child: BlocListener<UserWorkspaceBloc,
                                UserWorkspaceState>(
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
                                if (!context.mounted) {
                                  return;
                                }

                                CommandPalette.maybeOf(context)?.updateBlocs(
                                  workspaceBloc:
                                      context.read<UserWorkspaceBloc?>(),
                                  spaceBloc: context.read<SpaceBloc?>(),
                                );

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
                      if (_upgradeSuccessMessage != null)
                        UpgradeSuccessOverlay(
                          planName: _upgradeSuccessMessage!,
                          onDismiss: _dismissUpgradeToast,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _markHomeReady() {
    if (_homeReadyMarked || !PerformanceTrace.enabled) {
      return;
    }

    _homeReadyMarked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        PerformanceTrace.mark('home_ready');
      }
    });
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

    // ✅ 使用 BlocBuilder 监听 TabsState，检测当前视图是否是白板
    // 如果是白板视图，则禁用侧边栏分隔线，避免触发 setState 导致 WKWebView 布局偏移
    // ✅ 同时使用 ValueListenableBuilder 监听 SpaceHub 选中视图的布局，保持与 SpaceHub 分割线同步
    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (previous, current) =>
          previous.currentPageManager.plugin.pluginType !=
              current.currentPageManager.plugin.pluginType ||
          _getViewLayout(previous.currentPageManager) !=
              _getViewLayout(current.currentPageManager),
      builder: (context, tabsState) {
        final currentLayout = _getViewLayout(tabsState.currentPageManager);
        final isWhiteboard = currentLayout == ViewLayoutPB.Whiteboard;
        // ✅ 使用 ValueListenableBuilder 监听 SpaceHub 选中视图的布局
        // 当 SpaceHub 中选中白板视图时，侧边栏分割线也需要禁用
        return ValueListenableBuilder<ViewLayoutPB?>(
          valueListenable: spaceHubSelectedViewLayoutNotifier,
          builder: (context, spaceHubLayout, _) {
            // 任一为白板时，分割线都应该禁用
            final isSpaceHubWhiteboard =
                spaceHubLayout == ViewLayoutPB.Whiteboard;
            final shouldDisableResizer = isWhiteboard || isSpaceHubWhiteboard;
            final homeMenuResizer = layout.showMenu && !layout.menuIsDrawer
                ? SidebarResizer(enabled: !shouldDisableResizer)
                : const SizedBox.shrink();
            final editPanel = _buildEditPanel(context, layout: layout);

            return ValueListenableBuilder<bool>(
              valueListenable: FullWindowController.isFullWindow,
              builder: (context, isFullWindow, _) {
                return _layoutWidgets(
                  buildContext: context,
                  layout: layout,
                  homeStack: homeStack,
                  sidebar: sidebar,
                  editPanel: editPanel,
                  homeMenuResizer: homeMenuResizer,
                  notificationPanel: notificationPanel,
                  isFullWindow: isFullWindow,
                );
              },
            );
          },
        );
      },
    );
  }

  /// 从 PageManager 获取当前视图的布局类型
  ViewLayoutPB? _getViewLayout(PageManager pageManager) {
    final notifier = pageManager.plugin.notifier;
    if (notifier is ViewPluginNotifier) {
      return notifier.view.layout;
    }
    return null;
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
    required BuildContext buildContext,
    required HomeLayout layout,
    required Widget sidebar,
    required Widget homeStack,
    required Widget editPanel,
    required Widget homeMenuResizer,
    required Widget notificationPanel,
    bool isFullWindow = false,
  }) {
    try {
      if (!mounted) {
        return const SizedBox.shrink();
      }

      final isSliderbarShowing = layout.showMenu && !isFullWindow;
      final isDrawerMenu = isSliderbarShowing && layout.menuIsDrawer;
      final homeStackLeft = isFullWindow ? 0.0 : layout.homePageLOffset;
      final homeStackRight = isFullWindow ? 0.0 : layout.homePageROffset;

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
          if (!isFullWindow)
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
          if (!isFullWindow)
            notificationPanel
                .animatedPanelX(
                  closeX: -layout.notificationPanelWidth,
                  isClosed: !layout.showNotificationPanel,
                  curve: Curves.easeOutQuad,
                  duration: layout.animDuration.inMilliseconds * 0.001,
                )
                .positioned(
                  left: isSliderbarShowing && !isDrawerMenu
                      ? layout.menuWidth
                      : 0,
                  top: isSliderbarShowing && !isDrawerMenu ? 0 : 52,
                  width: layout.notificationPanelWidth,
                  bottom: 0,
                ),
          if (isDrawerMenu)
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) {
                  if (!mounted) return;
                  try {
                    buildContext.read<HomeSettingBloc>().add(
                          const HomeSettingEvent.changeMenuStatus(
                            MenuStatus.hidden,
                          ),
                        );
                  } catch (e) {
                    Log.warn(
                      '[DesktopHomeScreen] Error closing drawer menu: $e',
                    );
                  }
                },
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.08),
                ),
              ),
            ),
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
        ],
      );
    } catch (error, stackTrace) {
      Log.error(
        '[DesktopHomeScreen] Error building layout widgets: $error',
        error,
        stackTrace,
      );
      return homeStack;
    }
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

class _WorkspaceLifecycleRefresher extends StatefulWidget {
  const _WorkspaceLifecycleRefresher({required this.child});

  final Widget child;

  @override
  State<_WorkspaceLifecycleRefresher> createState() =>
      _WorkspaceLifecycleRefresherState();
}

class _WorkspaceLifecycleRefresherState
    extends State<_WorkspaceLifecycleRefresher> with WidgetsBindingObserver {
  static const _refreshDebounceDuration = Duration(seconds: 2);
  static const _periodicRefreshInterval = Duration(minutes: 5);

  DateTime? _lastRefreshTime;
  Timer? _periodicRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPeriodicRefresh();
  }

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

    if (!mounted) {
      return;
    }

    final now = DateTime.now();
    if (_lastRefreshTime == null ||
        now.difference(_lastRefreshTime!) > _refreshDebounceDuration) {
      _lastRefreshTime = now;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _refreshWorkspaceList();
          _checkMembershipStatus();
        }
      });
    }
  }

  Future<void> _checkMembershipStatus() async {
    try {
      final workspaceBloc = context.read<UserWorkspaceBloc?>();
      if (workspaceBloc == null) {
        return;
      }

      // 未登录（快速体验）用户没有会员/订阅数据，无需也不应做会员与存储检查：
      // 此时 getCurrentSubscription 返回 null，存储检查会把"无配额数据"误判为
      // "空间已满"，导致每次挂载/依赖变化都弹出"功能受限"提示并循环重复。
      // 未登录的引导提示由侧边栏云同步按钮在用户主动点击时展示一次即可。
      if (workspaceBloc.state.userProfile.userAuthType != AuthTypePB.Server) {
        return;
      }

      final workspaceId = workspaceBloc.state.currentWorkspace?.workspaceId;

      await context.checkMembershipStatus(workspaceId: workspaceId);
      if (!mounted) {
        return;
      }

      await context.checkAndHandleCloudSyncStorageLimit(
        workspaceId: workspaceId,
      );
    } catch (e) {
      Log.error('Failed to check membership status: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _lastRefreshTime = DateTime.now();
      _refreshWorkspaceList();
    }
  }

  void _refreshWorkspaceList() {
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
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _periodicRefreshTimer?.cancel();
    _periodicRefreshTimer = null;
    super.dispose();
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
