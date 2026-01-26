import 'dart:async';
import 'dart:io';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/search/view_ancestor_cache.dart';
import 'package:appflowy/plugins/blank/blank.dart';
import 'package:appflowy/plugins/document/presentation/editor_notification.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/shared/loading.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_file_library_button.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy/workspace/application/action_navigation/action_navigation_bloc.dart';
import 'package:appflowy/workspace/application/action_navigation/navigation_action.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_bloc.dart';
import 'package:appflowy/workspace/application/favorite/favorite_bloc.dart';
import 'package:appflowy/workspace/application/favorite/prelude.dart';
import 'package:appflowy/workspace/application/menu/sidebar_sections_bloc.dart';
import 'package:appflowy/workspace/application/recent/cached_recent_service.dart';
import 'package:appflowy/workspace/application/sidebar/billing/sidebar_plan_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/command_palette/command_palette.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/header/sidebar_top_menu.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_folder.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/sidebar_space.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/space_migration.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/workspace/_sidebar_workspace_menu.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/widgets/sidebar_cloud_sync_button.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/widgets/sidebar_upload_button.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/footer/sidebar_upgrade_application_button.dart';
import 'package:appflowy/workspace/presentation/notifications/widgets/notification_button.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_trash_item.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_settings_button.dart';
import 'package:appflowy/shared/version_checker/version_checker.dart';
import 'package:appflowy/startup/tasks/device_info_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/workspace.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart'
    show UserProfilePB;
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy_ui/appflowy_ui.dart';

import '../../../../../startup/plugin/plugin.dart';

Loading? _duplicateSpaceLoading;

/// Home Sidebar is the left side bar of the home page.
///
/// in the sidebar, we have:
///   - user icon, user name
///   - settings
///   - scrollable document list
///   - trash
class HomeSideBar extends StatelessWidget {
  const HomeSideBar({
    super.key,
    required this.userProfile,
    required this.workspaceSetting,
  });

  final UserProfilePB userProfile;

  final WorkspaceLatestPB workspaceSetting;

  @override
  Widget build(BuildContext context) {
    // Workspace Bloc: control the current workspace
    //   |
    //   +-- Workspace Menu
    //   |    |
    //   |    +-- Workspace List: control to switch workspace
    //   |    |
    //   |    +-- Workspace Settings
    //   |    |
    //   |    +-- Notification Center
    //   |
    //   +-- Favorite Section
    //   |
    //   +-- Public Or Private Section: control the sections of the workspace
    //   |
    //   +-- Trash Section
    return BlocProvider(
      create: (context) => SidebarPlanBloc()
        ..add(SidebarPlanEvent.init(workspaceSetting.workspaceId, userProfile)),
      child: BlocConsumer<UserWorkspaceBloc, UserWorkspaceState>(
        listenWhen: (prev, curr) =>
            prev.currentWorkspace?.workspaceId !=
            curr.currentWorkspace?.workspaceId,
        listener: (context, state) {
          if (FeatureFlag.search.isOn) {
            // Notify command palette that workspace has changed
            context.read<CommandPaletteBloc>().add(
                  CommandPaletteEvent.workspaceChanged(
                    workspaceId: state.currentWorkspace?.workspaceId,
                  ),
                );
          }

          if (state.currentWorkspace != null) {
            context.read<SidebarPlanBloc>().add(
                  SidebarPlanEvent.changedWorkspace(
                    workspaceId: state.currentWorkspace!.workspaceId,
                  ),
                );
          }

          // Re-initialize workspace-specific services
          getIt<CachedRecentService>().reset();
        },
        // Rebuild the whole sidebar when the current workspace changes
        buildWhen: (previous, current) =>
            previous.currentWorkspace?.workspaceId !=
            current.currentWorkspace?.workspaceId,
        builder: (context, state) {
          if (state.currentWorkspace == null) {
            return const SizedBox.shrink();
          }

          final workspaceId = state.currentWorkspace?.workspaceId ??
              workspaceSetting.workspaceId;
          return MultiBlocProvider(
            providers: [
              BlocProvider.value(value: getIt<ActionNavigationBloc>()),
              BlocProvider(
                create: (_) => SidebarSectionsBloc()
                  ..add(SidebarSectionsEvent.initial(userProfile, workspaceId)),
              ),
              BlocProvider(
                create: (_) => SpaceBloc(
                  userProfile: userProfile,
                  workspaceId: workspaceId,
                )..add(const SpaceEvent.initial(openFirstPage: false)),
              ),
            ],
            child: MultiBlocListener(
              listeners: [
                BlocListener<SidebarSectionsBloc, SidebarSectionsState>(
                  listenWhen: (p, c) =>
                      p.lastCreatedRootView?.id != c.lastCreatedRootView?.id,
                  listener: (context, state) {
                    final view = state.lastCreatedRootView;
                    if (view != null) {
                      if (view.id.isEmpty) {
                        Log.error(
                            'Sidebar: lastCreatedRootView.id is empty, aborting openPlugin');
                        // Open a blank page as a safe fallback to avoid passing empty id downstream.
                        context.read<TabsBloc>().add(
                            TabsEvent.openPlugin(plugin: BlankPagePlugin()));
                      } else {
                        context.read<TabsBloc>().openPlugin(view);
                      }
                    }
                  },
                ),
                BlocListener<SpaceBloc, SpaceState>(
                  listenWhen: (prev, curr) =>
                      prev.lastCreatedPage?.id != curr.lastCreatedPage?.id ||
                      prev.isDuplicatingSpace != curr.isDuplicatingSpace ||
                      (prev.currentSpace?.id != curr.currentSpace?.id && curr.currentSpace?.isSpace == true),
                  listener: (context, state) {
                    final page = state.lastCreatedPage;
                    final currentSpace = state.currentSpace;
                    
                    // 如果当前空间存在且是空间类型视图
                    if (currentSpace != null && currentSpace.isSpace) {
                      // 检查当前打开的插件是否是空间统一页面（SpaceHubPlugin）
                      final tabsBloc = context.read<TabsBloc>();
                      final currentPageManager = tabsBloc.state.currentPageManager;
                      final currentPlugin = currentPageManager.plugin;
                      
                      // SpaceHubPlugin 的 id 是空间的 id，pluginType 是 folder
                      if (currentPlugin.id == currentSpace.id && 
                          currentPlugin.pluginType == PluginType.folder) {
                        // 当前已经打开了空间统一页面，不需要做任何操作
                        Log.info('[SIDEBAR] Space hub is already open, skipping auto-open');
                        if (state.isDuplicatingSpace) {
                          _duplicateSpaceLoading ??= Loading(context);
                          _duplicateSpaceLoading?.start();
                        } else if (_duplicateSpaceLoading != null) {
                          _duplicateSpaceLoading?.stop();
                          _duplicateSpaceLoading = null;
                        }
                        return;
                      }
                      
                      // 如果当前没有打开空间统一页面，且 lastCreatedPage 是空间的子视图
                      // 说明这是通过 SpaceEvent.open 设置的，应该打开空间统一页面而不是文档
                      if (page != null && 
                          page.id.isNotEmpty &&
                          currentSpace.childViews.any((v) => v.id == page.id)) {
                        // 打开空间统一页面
                        Log.info('[SIDEBAR] Opening space hub for space: ${currentSpace.name}');
                        context.read<TabsBloc>().openPlugin(currentSpace);
                        if (state.isDuplicatingSpace) {
                          _duplicateSpaceLoading ??= Loading(context);
                          _duplicateSpaceLoading?.start();
                        } else if (_duplicateSpaceLoading != null) {
                          _duplicateSpaceLoading?.stop();
                          _duplicateSpaceLoading = null;
                        }
                        return;
                      }
                      
                      // 如果空间刚被设置为 currentSpace，但没有 lastCreatedPage
                      // 说明是工作区切换后自动加载的空间，应该打开空间统一页面
                      if (page == null || page.id.isEmpty) {
                        Log.info('[SIDEBAR] Opening space hub after workspace switch: ${currentSpace.name}');
                        context.read<TabsBloc>().openPlugin(currentSpace);
                        if (state.isDuplicatingSpace) {
                          _duplicateSpaceLoading ??= Loading(context);
                          _duplicateSpaceLoading?.start();
                        } else if (_duplicateSpaceLoading != null) {
                          _duplicateSpaceLoading?.stop();
                          _duplicateSpaceLoading = null;
                        }
                        return;
                      }
                    }
                    
                    // 非空间类型或普通文档的处理
                    if (page == null || page.id.isEmpty) {
                      // open the blank page
                      context
                          .read<TabsBloc>()
                          .add(TabsEvent.openPlugin(plugin: BlankPagePlugin()));
                    } else {
                      context
                          .read<TabsBloc>()
                          .openPlugin(state.lastCreatedPage!);
                    }

                    if (state.isDuplicatingSpace) {
                      _duplicateSpaceLoading ??= Loading(context);
                      _duplicateSpaceLoading?.start();
                    } else if (_duplicateSpaceLoading != null) {
                      _duplicateSpaceLoading?.stop();
                      _duplicateSpaceLoading = null;
                    }
                  },
                ),
                BlocListener<ActionNavigationBloc, ActionNavigationState>(
                  listenWhen: (_, curr) => curr.action != null,
                  listener: _onNotificationAction,
                ),
                BlocListener<UserWorkspaceBloc, UserWorkspaceState>(
                  listenWhen: (previous, current) =>
                      previous.currentWorkspace?.workspaceId !=
                      current.currentWorkspace?.workspaceId,
                  listener: (context, state) {
                    // 当工作区切换时，刷新侧边栏区域（包括"我的空间"）
                    if (state.currentWorkspace != null) {
                      final workspaceId = state.currentWorkspace!.workspaceId;
                      context.read<SidebarSectionsBloc>().add(
                            SidebarSectionsEvent.reset(
                              userProfile,
                              workspaceId,
                            ),
                          );
                    }

                    final actionType = state.actionResult?.actionType;

                    if (actionType == WorkspaceActionType.create ||
                        actionType == WorkspaceActionType.delete ||
                        actionType == WorkspaceActionType.open) {
                      if (context.read<SpaceBloc>().state.spaces.isEmpty) {
                        context.read<SidebarSectionsBloc>().add(
                              SidebarSectionsEvent.reload(
                                userProfile,
                                state.currentWorkspace?.workspaceId ??
                                    workspaceSetting.workspaceId,
                              ),
                            );
                      } else {
                        context.read<SpaceBloc>().add(
                              SpaceEvent.reset(
                                userProfile,
                                state.currentWorkspace?.workspaceId ??
                                    workspaceSetting.workspaceId,
                                true,
                              ),
                            );
                      }

                      context
                          .read<FavoriteBloc>()
                          .add(const FavoriteEvent.fetchFavorites());
                    }
                  },
                ),
              ],
              child: _Sidebar(userProfile: userProfile),
            ),
          );
        },
      ),
    );
  }

  void _onNotificationAction(
    BuildContext context,
    ActionNavigationState state,
  ) {
    final action = state.action;
    if (action?.type == ActionType.openView) {
      final view = action!.arguments?[ActionArgumentKeys.view];
      if (view != null) {
        final Map<String, dynamic> arguments = {};
        final nodePath = action.arguments?[ActionArgumentKeys.nodePath];
        if (nodePath != null) {
          arguments[PluginArgumentKeys.selection] = Selection.collapsed(
            Position(path: [nodePath]),
          );
        }

        checkForSpace(
          context.read<SpaceBloc>(),
          view,
          () => openView(action, context, view, arguments),
        );
        openView(action, context, view, arguments);
      }
    }
  }

  Future<void> checkForSpace(
    SpaceBloc spaceBloc,
    ViewPB view,
    VoidCallback afterOpen,
  ) async {
    /// open space
    final acestorCache = getIt<ViewAncestorCache>();
    final ancestor = await acestorCache.getAncestor(view.id);
    if (ancestor?.ancestors.isEmpty ?? true) return;
    final firstAncestor = ancestor!.ancestors.first;
    if (firstAncestor.id != spaceBloc.state.currentSpace?.id) {
      final space =
          (await ViewBackendService.getView(firstAncestor.id)).toNullable();
      if (space != null) {
        // Log.info( // PonyNotes: 关闭非白板日志
        //   'Switching space from (${firstAncestor.name}-${firstAncestor.id}) to (${space.name}-${space.id})',
        // );
        spaceBloc.add(SpaceEvent.open(space: space, afterOpen: afterOpen));
      }
    }
  }

  void openView(
    NavigationAction action,
    BuildContext context,
    ViewPB view,
    Map<String, dynamic> arguments,
  ) {
    final blockId = action.arguments?[ActionArgumentKeys.blockId];
    if (blockId != null) {
      arguments[PluginArgumentKeys.blockId] = blockId;
    }

    final rowId = action.arguments?[ActionArgumentKeys.rowId];
    if (rowId != null) {
      arguments[PluginArgumentKeys.rowId] = rowId;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        context.read<TabsBloc>().openPlugin(view, arguments: arguments);
      }
    });
  }
}

class _Sidebar extends StatefulWidget {
  const _Sidebar({required this.userProfile});

  final UserProfilePB userProfile;

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  final _scrollController = ScrollController();
  Timer? _scrollDebounce;
  bool _isScrolling = false;
  final _isHovered = ValueNotifier(false);
  final _scrollOffset = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScrollChanged);
  }

  @override
  void dispose() {
    _scrollDebounce?.cancel();
    _scrollController.removeListener(_onScrollChanged);
    _scrollController.dispose();
    _scrollOffset.dispose();
    _isHovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const menuHorizontalInset = EdgeInsets.symmetric(horizontal: 8);
    return MouseRegion(
      onEnter: (_) => _isHovered.value = true,
      onExit: (_) => _isHovered.value = false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: Border(
            right: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // top menu (hide on Windows)
            if (!Platform.isWindows)
              Padding(
                padding: menuHorizontalInset,
                child: SidebarTopMenu(
                  isSidebarOnHover: _isHovered,
                ),
              ),
            // PonyNotes custom header
            Container(
              height: Platform.isWindows
                  ? HomeSizes.workspaceSectionHeight + 8
                  : HomeSizes.workspaceSectionHeight,
              padding: menuHorizontalInset - const EdgeInsets.only(right: 6),
              child: _PonyNotesHeader(userProfile: widget.userProfile),
            ),
            if (FeatureFlag.search.isOn) ...[
              const VSpace(6),
              Container(
                padding: menuHorizontalInset,
                height: HomeSizes.searchSectionHeight,
                child: const _SidebarSearchButton(),
              ),
            ],

            // scrollable document list
            const VSpace(12.0),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: ValueListenableBuilder(
                valueListenable: _scrollOffset,
                builder: (_, offset, child) => Opacity(
                  opacity: offset > 0 ? 1 : 0,
                  child: child,
                ),
                child: const FlowyDivider(),
              ),
            ),
            _renderFolderOrSpace(menuHorizontalInset),
            const VSpace(8),
            _renderUpgradeSpaceButton(menuHorizontalInset),
            _buildUpgradeApplicationButton(menuHorizontalInset),
            const VSpace(14),
            // Fixed bottom actions (trash, settings) - keep outside the scrollable area
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  // 文件库
                  SidebarFileLibraryButton(),
                  VSpace(6),
                  SidebarTrashItem(),
                  VSpace(6),
                  SidebarSettingsButton(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _renderFolderOrSpace(EdgeInsets menuHorizontalInset) {
    final spaceState = context.read<SpaceBloc>().state;
    final workspaceState = context.read<UserWorkspaceBloc>().state;

    if (!spaceState.isInitialized) {
      // Log.debug('SpaceBloc not initialized, showing empty widget'); // PonyNotes: 关闭非白板日志
      return const SizedBox.shrink();
    }

    // there's no space or the workspace is not collaborative,
    // show the folder section (Workspace, Private, Personal)
    // otherwise, show the space
    final sidebarSectionBloc = context.watch<SidebarSectionsBloc>();
    final containsSpace = sidebarSectionBloc.state.containsSpace;

    if (containsSpace && spaceState.spaces.isEmpty) {
      context.read<SpaceBloc>().add(const SpaceEvent.didReceiveSpaceUpdate());
    }

    return Expanded(
      child: Padding(
        padding: menuHorizontalInset - const EdgeInsets.only(right: 6),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(right: 6),
          controller: _scrollController,
          physics: const ClampingScrollPhysics(),
          child: SidebarFolder(
            userProfile: widget.userProfile,
            isHoverEnabled: !_isScrolling,
          ),
        ),
      ),
    );

    final shouldShowFolder = !containsSpace ||
        spaceState.spaces.isEmpty ||
        !workspaceState.isCollabWorkspaceOn;

    // Log.debug( // PonyNotes: 关闭非白板日志
    //   'Sidebar render decision: containsSpace=$containsSpace, '
    //   'spaces.length=${spaceState.spaces.length}, '
    //   'isCollabWorkspaceOn=${workspaceState.isCollabWorkspaceOn}, '
    //   'shouldShowFolder=$shouldShowFolder',
    // );

    return shouldShowFolder
        ? Expanded(
            child: Padding(
              padding: menuHorizontalInset - const EdgeInsets.only(right: 6),
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(right: 6),
                controller: _scrollController,
                physics: const ClampingScrollPhysics(),
                child: SidebarFolder(
                  userProfile: widget.userProfile,
                  isHoverEnabled: !_isScrolling,
                ),
              ),
            ),
          )
        : Expanded(
            child: Padding(
              padding: menuHorizontalInset - const EdgeInsets.only(right: 6),
              child: FlowyScrollbar(
                controller: _scrollController,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(right: 6),
                  controller: _scrollController,
                  physics: const ClampingScrollPhysics(),
                  child: SidebarSpace(
                    userProfile: widget.userProfile,
                    isHoverEnabled: !_isScrolling,
                  ),
                ),
              ),
            ),
          );
  }

  Widget _renderUpgradeSpaceButton(EdgeInsets menuHorizontalInset) {
    final spaceState = context.watch<SpaceBloc>().state;
    final workspaceState = context.read<UserWorkspaceBloc>().state;
    return !spaceState.shouldShowUpgradeDialog ||
            !workspaceState.isCollabWorkspaceOn
        ? const SizedBox.shrink()
        : Padding(
            padding: menuHorizontalInset +
                const EdgeInsets.only(
                  left: 4.0,
                  right: 4.0,
                  top: 8.0,
                ),
            child: const SpaceMigration(),
          );
  }

  Widget _buildUpgradeApplicationButton(EdgeInsets menuHorizontalInset) {
    return ValueListenableBuilder(
      valueListenable: ApplicationInfo.latestVersionNotifier,
      builder: (context, latestVersion, _) {
        // 检查是否有新版本可用
        final isUpdateAvailable = ApplicationInfo.isUpdateAvailable;

        // 添加调试日志
        // Log.info('[UpdateBanner] Current: ${ApplicationInfo.applicationVersion}, Latest: $latestVersion, Available: $isUpdateAvailable');

        if (!isUpdateAvailable) {
          return const SizedBox.shrink();
        }

        // 检查用户是否已经关闭过这个版本的更新提示
        return FutureBuilder<bool>(
          future: _shouldShowUpdateBanner(latestVersion),
          builder: (context, snapshot) {
            if (!snapshot.hasData || !snapshot.data!) {
              return const SizedBox.shrink();
            }

            // Log.info('[UpdateBanner] Showing update banner for version $latestVersion');

            return Padding(
              padding: menuHorizontalInset +
                  const EdgeInsets.only(
                    left: 4.0,
                    right: 4.0,
                    top: 8.0,
                  ),
              child: SidebarUpgradeApplicationButton(
                onUpdateButtonTap: () async {
                  await versionChecker.checkForUpdate();
                },
                onCloseButtonTap: () async {
                  await _dismissUpdateBanner(latestVersion);
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> _shouldShowUpdateBanner(String version) async {
    final prefs = await SharedPreferences.getInstance();
    final dismissedVersion = prefs.getString('dismissed_update_version');
    return dismissedVersion != version;
  }

  Future<void> _dismissUpdateBanner(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dismissed_update_version', version);
    // 触发重建以隐藏横幅
    if (mounted) {
      setState(() {});
    }
  }

  void _onScrollChanged() {
    setState(() => _isScrolling = true);

    _scrollDebounce?.cancel();
    _scrollDebounce =
        Timer(const Duration(milliseconds: 300), _setScrollStopped);

    _scrollOffset.value = _scrollController.offset;
  }

  void _setScrollStopped() {
    if (mounted) {
      setState(() => _isScrolling = false);
    }
  }
}

class _SidebarSearchButton extends StatelessWidget {
  const _SidebarSearchButton();

  @override
  Widget build(BuildContext context) {
    return FlowyTooltip(
      richMessage: TextSpan(
        children: [
          TextSpan(
            text: '${LocaleKeys.search_sidebarSearchIcon.tr()}\n',
            style: context.tooltipTextStyle(),
          ),
          TextSpan(
            text: Platform.isMacOS ? '⌘+P' : 'Ctrl+P',
            style: context
                .tooltipTextStyle()
                ?.copyWith(color: Theme.of(context).hintColor),
          ),
        ],
      ),
      child: FlowyButton(
        onTap: () {
          // exit editing mode when doing search to avoid the toolbar showing up
          EditorNotification.exitEditing().post();
          final workspaceBloc = context.read<UserWorkspaceBloc?>();
          final spaceBloc = context.read<SpaceBloc?>();
          CommandPalette.of(context).toggle(
            workspaceBloc: workspaceBloc,
            spaceBloc: spaceBloc,
          );
        },
        leftIcon: const FlowySvg(FlowySvgs.search_s),
        iconPadding: 12.0,
        margin: const EdgeInsets.only(left: 8.0),
        text: FlowyText.regular(LocaleKeys.search_label.tr()),
      ),
    );
  }
}

class _PonyNotesHeader extends StatefulWidget {
  const _PonyNotesHeader({required this.userProfile});

  final UserProfilePB userProfile;

  @override
  State<_PonyNotesHeader> createState() => _PonyNotesHeaderState();
}

class _PonyNotesHeaderState extends State<_PonyNotesHeader> {
  final PopoverController _popoverController = PopoverController();

  @override
  Widget build(BuildContext context) {
    return AppFlowyPopover(
      direction: PopoverDirection.bottomWithCenterAligned,
      offset: const Offset(0, 5),
      constraints: const BoxConstraints(maxWidth: 300, maxHeight: 600),
      margin: EdgeInsets.zero,
      animationDuration: Durations.short3,
      beginScaleFactor: 1.0,
      beginOpacity: 0.8,
      controller: _popoverController,
      triggerActions: PopoverTriggerFlags.none,
      onOpen: () {
        context
            .read<UserWorkspaceBloc>()
            .add(UserWorkspaceEvent.fetchWorkspaces());
      },
      popupBuilder: (_) {
        return BlocProvider<UserWorkspaceBloc>.value(
          value: context.read<UserWorkspaceBloc>(),
          child: BlocBuilder<UserWorkspaceBloc, UserWorkspaceState>(
            builder: (context, state) {
              final currentWorkspace = state.currentWorkspace;
              final workspaces = state.workspaces;
              if (currentWorkspace == null) {
                return const SizedBox.shrink();
              }
              return WorkspacesMenu(
                userProfile: widget.userProfile,
                currentWorkspace: currentWorkspace,
                workspaces: workspaces,
              );
            },
          ),
        );
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            context.read<UserWorkspaceBloc>().add(
                  UserWorkspaceEvent.fetchWorkspaces(),
                );
            _popoverController.show();
          },
          behavior: HitTestBehavior.opaque,
          child: Container(
            margin: const EdgeInsets.only(right: 8.0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8.0),
              color: Colors.transparent,
            ),
            child: Row(
              children: [
                const HSpace(4),
                // 使用小马emoji作为图标
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8.0),
                    color: const Color(0xFFFBE8FB),
                    border: Border.all(
                      width: 1,
                      color: const Color(0x19171717),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/app_icon_m.jpg',
                      width: 25,
                      height: 25,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const HSpace(6),
                // 小马笔记文字和向下箭头
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FlowyText.medium(
                      LocaleKeys.sidebar_appName.tr(),
                      color: Theme.of(context).colorScheme.tertiary,
                      overflow: TextOverflow.ellipsis,
                      fontSize: 15.0,
                    ),
                    const HSpace(2), // 紧贴文字的小间距
                    FlowySvg(
                      FlowySvgs.drop_menu_show_s,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ],
                ),
                const Spacer(), // 推送按钮到右边
                // 云同步按钮 (fill header height)
                SizedBox(
                  height: Platform.isWindows
                      ? HomeSizes.workspaceSectionHeight + 8
                      : HomeSizes.workspaceSectionHeight,
                  child: Center(child: const SidebarCloudSyncButton()),
                ),
                const HSpace(8.0),
                // 上传按钮
                SizedBox(
                  height: Platform.isWindows
                      ? HomeSizes.workspaceSectionHeight + 8
                      : HomeSizes.workspaceSectionHeight,
                  child: Center(child: const SidebarUploadButton()),
                ),
                const HSpace(8.0),
                // 消息按钮
                SizedBox(
                  height: Platform.isWindows
                      ? HomeSizes.workspaceSectionHeight + 8
                      : HomeSizes.workspaceSectionHeight,
                  child: Center(
                      child: NotificationButton(
                          key: ValueKey(widget.userProfile.id))),
                ),
                // 在 Windows 上将收起按钮放在通知右侧
                if (Platform.isWindows) ...[
                  const HSpace(8.0),
                  SizedBox(
                    height: Platform.isWindows
                        ? HomeSizes.workspaceSectionHeight + 8
                        : HomeSizes.workspaceSectionHeight,
                    child: Center(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () =>
                            context.read<HomeSettingBloc>().collapseMenu(),
                        child: SizedBox(
                          width: 24,
                          child: FlowySvg(
                            FlowySvgs.double_back_arrow_m,
                            color: AppFlowyTheme.of(context)
                                .iconColorScheme
                                .secondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                const HSpace(10.0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
