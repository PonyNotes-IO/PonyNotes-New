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
import 'package:appflowy/workspace/presentation/widgets/float_bubble/question_bubble.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart'
    show UserProfilePB, UserWorkspacePB, WorkspaceTypePB;
import 'package:appflowy_result/appflowy_result.dart';
import 'package:collection/collection.dart';
import 'package:flowy_infra_ui/style_widget/container.dart';
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
import 'menu/sidebar/slider_menu_hover_trigger.dart';
import 'menu/sidebar/space/shared_widget.dart';

class DesktopHomeScreen extends StatefulWidget {
  const DesktopHomeScreen({super.key});

  static const routeName = '/DesktopHomeScreen';

  @override
  State<DesktopHomeScreen> createState() => _DesktopHomeScreenState();
}

class _DesktopHomeScreenState extends State<DesktopHomeScreen> {
  late final Future<List<FlowyResult>> _initFuture;
  bool _hasShownRemovedDialog = false;

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
                  return HomeBloc(workspaceLatest)..add(const HomeEvent.initial());
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
              floatingActionButton: BlocBuilder<HomeSettingBloc, HomeSettingState>(
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
                      if (isMenuHidden) ...[
                        FloatingActionButton(
                          tooltip: '显示侧边栏',
                          onPressed: () {
                            context.read<HomeSettingBloc>().add(
                                  HomeSettingEvent.changeMenuStatus(MenuStatus.expanded),
                                );
                          },
                          child: const Icon(Icons.menu_open),
                        ),
                        const SizedBox(height: 50),
                      ],
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

            if (currentPageManager.plugin.pluginType == PluginType.blank) {
                      if (view.id.isEmpty) {
                        Log.error('DesktopHomeScreen: latestView.id is empty, skip opening plugin');
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
                    )..add(UserWorkspaceEvent.initialize()),
                    child: BlocListener<UserWorkspaceBloc, UserWorkspaceState>(
                      listenWhen: (previous, current) =>
                          previous.currentWorkspace != current.currentWorkspace ||
                          previous.workspaces.length != current.workspaces.length ||
                          _workspacesChanged(previous.workspaces, current.workspaces),
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
    final sliderHoverTrigger = SliderMenuHoverTrigger();

    final homeMenuResizer =
        layout.showMenu ? const SidebarResizer() : const SizedBox.shrink();
    final editPanel = _buildEditPanel(context, layout: layout);

    // 使用 BlocBuilder 监听 TabsBloc 状态变化，以便在切换标签时更新问号按钮的显示
    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (previous, current) => 
        previous.currentPageManager.plugin.pluginType != 
        current.currentPageManager.plugin.pluginType,
      builder: (context, tabsState) {
        return _layoutWidgets(
          layout: layout,
          homeStack: homeStack,
          sidebar: sidebar,
          editPanel: editPanel,
          bubble: const QuestionBubble(),
          homeMenuResizer: homeMenuResizer,
          notificationPanel: notificationPanel,
          sliderHoverTrigger: sliderHoverTrigger,
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
    required Widget bubble,
    required Widget homeMenuResizer,
    required Widget notificationPanel,
    required Widget sliderHoverTrigger,
  }) {
    final isSliderbarShowing = layout.showMenu;
    return Stack(
      children: [
        homeStack
            .constrained(minWidth: 500)
            .positioned(
              left: layout.homePageLOffset,
              right: layout.homePageROffset,
              bottom: 0,
              top: 0,
              animate: true,
            )
            .animate(layout.animDuration, Curves.easeOutQuad),
        bubble
            .positioned(right: 20, bottom: 16, animate: true)
            .animate(layout.animDuration, Curves.easeOut),
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
              left: isSliderbarShowing ? layout.menuWidth : 0,
              top: isSliderbarShowing ? 0 : 52,
              width: layout.notificationPanelWidth,
              bottom: 0,
            ),
        sidebar
            .animatedPanelX(
              closeX: -layout.menuWidth,
              isClosed: !isSliderbarShowing,
              curve: Curves.easeOutQuad,
              duration: layout.animDuration.inMilliseconds * 0.001,
            )
            .positioned(left: 0, top: 0, width: layout.menuWidth, bottom: 0),
        homeMenuResizer
            .positioned(left: layout.menuWidth)
            .animate(layout.animDuration, Curves.easeOutQuad),
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
    // 如果没有工作区，创建新工作区
    if (workspaces.isEmpty) {
      Log.info('No workspaces found, creating a new workspace');
      final workspaceBloc = context.read<UserWorkspaceBloc?>();
      if (workspaceBloc != null) {
        // 创建默认工作区
        workspaceBloc.add(
          UserWorkspaceEvent.createWorkspace(
            name: '我的工作区',
            workspaceType: WorkspaceTypePB.ServerW,
          ),
        );
      }
      return;
    }

    // 如果当前工作区不在列表中，说明被移除了
    if (currentWorkspace != null) {
      final isCurrentWorkspaceInList = workspaces.any(
        (w) => w.workspaceId == currentWorkspace.workspaceId,
      );

      if (!isCurrentWorkspaceInList && !_hasShownRemovedDialog) {
        _hasShownRemovedDialog = true;
        Log.info(
          'Current workspace ${currentWorkspace.workspaceId} not found in list, switching to first workspace',
        );

        // 切换到第一个工作区
        final firstWorkspace = workspaces.first;
        final workspaceBloc = context.read<UserWorkspaceBloc?>();
        if (workspaceBloc != null) {
          workspaceBloc.add(
            UserWorkspaceEvent.openWorkspace(
              workspaceId: firstWorkspace.workspaceId,
              workspaceType: firstWorkspace.workspaceType,
            ),
          );
        }

        // 显示提示对话框
        Future.delayed(const Duration(milliseconds: 300), () {
          if (!context.mounted) return;
          showConfirmDialog(
            context: context,
            title: '当前工作区已经移除了你，请知悉',
            description: '',
            style: ConfirmPopupStyle.onlyOk,
            confirmLabel: '确认',
            onConfirm: (_) {
              _hasShownRemovedDialog = false;
            },
          );
        });
      }
    }
  }
}

/// 监听应用生命周期，在应用回到前台时刷新工作区列表。
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 此处的 context 在 UserWorkspaceBloc 的子树中，可以安全读取 Bloc
      final workspaceBloc = context.read<UserWorkspaceBloc?>();
      if (workspaceBloc != null) {
        LogUtils.info(
          'WorkspaceLifecycleRefresher: app resumed, fetchWorkspaces',
        );
        workspaceBloc.add(UserWorkspaceEvent.fetchWorkspaces());
      } else {
        LogUtils.info(
          'WorkspaceLifecycleRefresher: UserWorkspaceBloc is null on resume',
        );
      }
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
              Log.error('DesktopHomeScreen: lastView.id is empty, skip opening plugin');
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
