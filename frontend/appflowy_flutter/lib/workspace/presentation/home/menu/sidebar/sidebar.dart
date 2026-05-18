import 'dart:async';
import 'dart:io';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/search/view_ancestor_cache.dart';
import 'package:appflowy/plugins/blank/blank.dart';
import 'package:appflowy/plugins/database/calendar/application/calendar_unsaved_guard.dart';
import 'package:appflowy/plugins/document/presentation/editor_notification.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/shared/loading.dart';
import 'package:appflowy/startup/startup.dart';
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
import 'package:appflowy/workspace/application/home/home_bloc.dart';
import 'package:appflowy/workspace/presentation/command_palette/command_palette.dart';
import 'package:appflowy/workspace/presentation/home/full_window_controller.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/header/sidebar_top_menu.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_folder.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_entry_style.dart';
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
    this.isDrawerMenu = false,
  });

  final UserProfilePB userProfile;

  final WorkspaceLatestPB workspaceSetting;

  final bool isDrawerMenu;

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
                          'Sidebar: lastCreatedRootView.id is empty, aborting openPlugin',
                        );
                        // Open a blank page as a safe fallback to avoid passing empty id downstream.
                        context.read<TabsBloc>().add(
                              TabsEvent.openPlugin(plugin: BlankPagePlugin()),
                            );
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
                      (prev.currentSpace?.id != curr.currentSpace?.id &&
                          curr.currentSpace?.isSpace == true),
                  listener: (context, state) {
                    final page = state.lastCreatedPage;
                    final currentSpace = state.currentSpace;

                    // 濡傛灉褰撳墠绌洪棿瀛樺湪涓旀槸绌洪棿绫诲瀷瑙嗗浘
                    if (currentSpace != null && currentSpace.isSpace) {
                      // 妫€鏌ュ綋鍓嶆墦寮€鐨勬彃浠舵槸鍚︽槸绌洪棿缁熶竴椤甸潰锛圫paceHubPlugin锛?
                      final tabsBloc = context.read<TabsBloc>();
                      final currentPageManager =
                          tabsBloc.state.currentPageManager;
                      final currentPlugin = currentPageManager.plugin;

                      // SpaceHubPlugin 鐨?id 鏄┖闂寸殑 id锛宲luginType 鏄?folder
                      if (currentPlugin.id == currentSpace.id &&
                          currentPlugin.pluginType == PluginType.folder) {
                        // 褰撳墠宸茬粡鎵撳紑浜嗙┖闂寸粺涓€椤甸潰锛屼笉闇€瑕佸仛浠讳綍鎿嶄綔
                        Log.info(
                          '[SIDEBAR] Space hub is already open, skipping auto-open',
                        );
                        if (state.isDuplicatingSpace) {
                          _duplicateSpaceLoading ??= Loading(context);
                          _duplicateSpaceLoading?.start();
                        } else if (_duplicateSpaceLoading != null) {
                          _duplicateSpaceLoading?.stop();
                          _duplicateSpaceLoading = null;
                        }
                        return;
                      }

                      // 濡傛灉褰撳墠娌℃湁鎵撳紑绌洪棿缁熶竴椤甸潰锛屼笖 lastCreatedPage 鏄┖闂寸殑瀛愯鍥?
                      // 璇存槑杩欐槸閫氳繃 SpaceEvent.open 璁剧疆鐨勶紝搴旇鎵撳紑绌洪棿缁熶竴椤甸潰鑰屼笉鏄枃妗?
                      if (page != null &&
                          page.id.isNotEmpty &&
                          currentSpace.childViews.any((v) => v.id == page.id)) {
                        if (currentPlugin.pluginType == PluginType.blank) {
                          // 浠呭湪绌虹櫧椤甸樁娈佃嚜鍔ㄦ墦寮€绌洪棿缁熶竴椤甸潰锛岄伩鍏嶆姠鍗犲綋鍓嶄笟鍔￠〉闈紙濡傛枃浠跺簱/鏃ュ巻锛?
                          Log.info(
                            '[SIDEBAR] Opening space hub for space: ${currentSpace.name}',
                          );
                          context.read<TabsBloc>().openPlugin(currentSpace);
                        } else {
                          Log.info(
                            '[SIDEBAR] Skip auto-open space hub with page because current plugin is ${currentPlugin.pluginType}',
                          );
                        }
                        if (state.isDuplicatingSpace) {
                          _duplicateSpaceLoading ??= Loading(context);
                          _duplicateSpaceLoading?.start();
                        } else if (_duplicateSpaceLoading != null) {
                          _duplicateSpaceLoading?.stop();
                          _duplicateSpaceLoading = null;
                        }
                        return;
                      }

                      // 濡傛灉绌洪棿鍒氳璁剧疆涓?currentSpace锛屼絾娌℃湁 lastCreatedPage
                      // 璇存槑鏄伐浣滃尯鍒囨崲鍚庤嚜鍔ㄥ姞杞界殑绌洪棿锛屽簲璇ユ墦寮€绌洪棿缁熶竴椤甸潰
                      if (page == null || page.id.isEmpty) {
                        if (currentPlugin.pluginType == PluginType.blank) {
                          Log.info(
                            '[SIDEBAR] Opening space hub after workspace switch: ${currentSpace.name}',
                          );
                          context.read<TabsBloc>().openPlugin(currentSpace);
                        } else {
                          Log.info(
                            '[SIDEBAR] Skip auto-open space hub because current plugin is ${currentPlugin.pluginType}',
                          );
                        }
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

                    // 闈炵┖闂寸被鍨嬫垨鏅€氭枃妗ｇ殑澶勭悊
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
                    final currentWorkspace = state.currentWorkspace;
                    if (currentWorkspace != null) {
                      final workspaceId = currentWorkspace.workspaceId;
                      // Keep home data stream in sync with workspace switch.
                      context
                          .read<HomeBloc>()
                          .add(HomeEvent.switchWorkspace(workspaceId));
                      // Reset opened tabs so old workspace pages are not retained.
                      context
                          .read<TabsBloc>()
                          .add(TabsEvent.switchWorkspace(workspaceId));

                      // 褰撳伐浣滃尯鍒囨崲鏃讹紝鍒锋柊渚ц竟鏍忓尯鍩燂紙鍖呮嫭"鎴戠殑绌洪棿"锛?
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
              child: _Sidebar(
                userProfile: userProfile,
                isDrawerMenu: isDrawerMenu,
              ),
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
        // Log.info( // PonyNotes: 鍏抽棴闈炵櫧鏉挎棩蹇?
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
  const _Sidebar({
    required this.userProfile,
    required this.isDrawerMenu,
  });

  final UserProfilePB userProfile;

  final bool isDrawerMenu;

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
            !Platform.isWindows
                ? Padding(
                    padding: menuHorizontalInset,
                    child: SidebarTopMenu(
                      isSidebarOnHover: _isHovered,
                    ),
                  )
                : HSpace(12),
            // PonyNotes custom header
            Container(
              height: Platform.isWindows
                  ? HomeSizes.workspaceSectionHeight + 8
                  : HomeSizes.workspaceSectionHeight,
              padding: menuHorizontalInset - const EdgeInsets.only(right: 6),
              child: _PonyNotesHeader(
                userProfile: widget.userProfile,
                isDrawerMenu: widget.isDrawerMenu,
              ),
            ),
            if (FeatureFlag.search.isOn) ...[
              const VSpace(sidebarSearchTopGap),
              Container(
                padding: menuHorizontalInset,
                height: 34,
                child: const _SidebarSearchButton(),
              ),
            ],

            // scrollable document list
            const VSpace(sidebarSearchToEntryGroupGap),
            _renderFolderOrSpace(menuHorizontalInset),
            const VSpace(8),
            _renderUpgradeSpaceButton(menuHorizontalInset),
            _buildUpgradeApplicationButton(menuHorizontalInset),
            const VSpace(14),
            // Fixed bottom actions (trash, settings) - keep outside the scrollable area
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  // 鏂囦欢搴?
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
      // Log.debug('SpaceBloc not initialized, showing empty widget'); // PonyNotes: 鍏抽棴闈炵櫧鏉挎棩蹇?
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

    final shouldShowFolder = !containsSpace ||
        spaceState.spaces.isEmpty ||
        !workspaceState.isCollabWorkspaceOn;

    // Log.debug( // PonyNotes: 鍏抽棴闈炵櫧鏉挎棩蹇?
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
        // 妫€鏌ユ槸鍚︽湁鏂扮増鏈彲鐢?
        final isUpdateAvailable = ApplicationInfo.isUpdateAvailable;

        // 娣诲姞璋冭瘯鏃ュ織
        // Log.info('[UpdateBanner] Current: ${ApplicationInfo.applicationVersion}, Latest: $latestVersion, Available: $isUpdateAvailable');

        if (!isUpdateAvailable) {
          return const SizedBox.shrink();
        }

        // 妫€鏌ョ敤鎴锋槸鍚﹀凡缁忓叧闂繃杩欎釜鐗堟湰鐨勬洿鏂版彁绀?
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
    // 瑙﹀彂閲嶅缓浠ラ殣钘忔í骞?
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

  void _openSearch(BuildContext context) {
    EditorNotification.exitEditing().post();
    final workspaceBloc = context.read<UserWorkspaceBloc?>();
    final spaceBloc = context.read<SpaceBloc?>();
    CommandPalette.of(context).toggle(
      workspaceBloc: workspaceBloc,
      spaceBloc: spaceBloc,
    );
  }

  @override
  Widget build(BuildContext context) {
    final shortcut =
        Platform.isMacOS ? '${String.fromCharCode(0x2318)}+P' : 'Ctrl+P';
    return FlowyTooltip(
      richMessage: TextSpan(
        children: [
          TextSpan(
            text: '${LocaleKeys.search_sidebarSearchIcon.tr()}\n',
            style: context.tooltipTextStyle(),
          ),
          TextSpan(
            text: shortcut,
            style: context
                .tooltipTextStyle()
                ?.copyWith(color: Theme.of(context).hintColor),
          ),
        ],
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openSearch(context),
          child: Container(
            width: double.infinity,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: const Color(0xFFE9E9E9),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const FlowySvg(
                  FlowySvgs.search_s,
                  size: Size.square(16),
                ),
                const HSpace(8),
                Expanded(
                  child: FlowyText.regular(
                    '${LocaleKeys.search_label.tr()} ($shortcut)',
                    fontSize: 14,
                    color: Theme.of(context).hintColor,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PonyNotesHeader extends StatefulWidget {
  const _PonyNotesHeader({
    required this.userProfile,
    required this.isDrawerMenu,
  });

  final UserProfilePB userProfile;

  final bool isDrawerMenu;

  @override
  State<_PonyNotesHeader> createState() => _PonyNotesHeaderState();
}

class _PonyNotesHeaderState extends State<_PonyNotesHeader> {
  static const double _syncActionCollapseWidth =
      HomeSizes.maximumSidebarWidth - 32.0;

  final PopoverController _popoverController = PopoverController();
  final PopoverController _headerActionsPopoverController = PopoverController();

  bool _shouldCollapseSyncActions(HomeSettingState state) {
    if (widget.isDrawerMenu) {
      return true;
    }

    final currentWidth = HomeSizes.minimumSidebarWidth + state.resizeOffset;
    return currentWidth <= _syncActionCollapseWidth;
  }

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
                // 浣跨敤灏忛┈emoji浣滀负鍥炬爣
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8.0),
                    color: const Color(0xFFFBE8FB),
                    border: Border.all(
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
                // 灏忛┈绗旇鏂囧瓧鍜屽悜涓嬬澶?
                Flexible(
                  child: Tooltip(
                    message: LocaleKeys.sidebar_appName.tr(),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 28),
                            child: FlowyText.medium(
                              LocaleKeys.sidebar_appName.tr(),
                              color: Theme.of(context).colorScheme.tertiary,
                              overflow: TextOverflow.ellipsis,
                              fontSize: 15.0,
                            ),
                          ),
                        ),
                        const HSpace(2),
                        FlowySvg(
                          FlowySvgs.drop_menu_show_s,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(), // 鎺ㄩ€佹寜閽埌鍙宠竟
                // 浜戝悓姝ユ寜閽?(fill header height)
                ValueListenableBuilder<bool>(
                  valueListenable: FullWindowController.isFullWindow,
                  builder: (context, isFullWindow, _) {
                    final homeSettingState =
                        context.select<HomeSettingBloc, HomeSettingState>(
                      (bloc) => bloc.state,
                    );
                    final shouldCollapseSyncActions =
                        _shouldCollapseSyncActions(homeSettingState);
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (shouldCollapseSyncActions)
                          _buildHeaderActionsMoreButton(context)
                        else ...[
                          _buildHeaderActionSlot(
                            const SidebarCloudSyncButton(),
                          ),
                          const HSpace(4.0),
                          _buildHeaderActionSlot(
                            const SidebarUploadButton(),
                          ),
                          const HSpace(4.0),
                          _buildHeaderActionSlot(
                            NotificationButton(
                              key: ValueKey(widget.userProfile.id),
                              alwaysShow: true,
                            ),
                          ),
                        ],
                        const HSpace(8.0),
                        _buildHeaderFullWindowButton(context, isFullWindow),
                      ],
                    );
                  },
                ),
                // 鍦?Windows 涓婂皢鏀惰捣鎸夐挳鏀惧湪閫氱煡鍙充晶
                ValueListenableBuilder<bool>(
                  valueListenable: FullWindowController.isFullWindow,
                  builder: (context, isFullWindow, _) {
                    if (!Platform.isWindows ||
                        widget.isDrawerMenu ||
                        isFullWindow) {
                      return const SizedBox.shrink();
                    }
                    final homeSettingState =
                        context.select<HomeSettingBloc, HomeSettingState>(
                      (bloc) => bloc.state,
                    );
                    final shouldCollapseSyncActions =
                        _shouldCollapseSyncActions(homeSettingState);
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HSpace(shouldCollapseSyncActions ? 4.0 : 8.0),
                        SizedBox(
                          height: HomeSizes.workspaceSectionHeight + 8,
                          child: Center(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: () => context
                                  .read<HomeSettingBloc>()
                                  .collapseMenu(),
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
                    );
                  },
                ),
                const HSpace(10.0),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderActionSlot(Widget child) {
    return SizedBox(
      height: Platform.isWindows
          ? HomeSizes.workspaceSectionHeight + 8
          : HomeSizes.workspaceSectionHeight,
      child: Center(child: child),
    );
  }

  Widget _buildHeaderNotificationActionButton(
    BuildContext context, {
    Color? iconColor,
  }) {
    return SizedBox.square(
      dimension: 28,
      child: FlowyButton(
        useIntrinsicWidth: true,
        margin: EdgeInsets.zero,
        text: SvgPicture.asset(
          'assets/images/icons/sidebar_notification_custom.svg',
          width: 24,
          height: 24,
          colorFilter: ColorFilter.mode(
            iconColor ?? Theme.of(context).colorScheme.onSurface,
            BlendMode.srcIn,
          ),
        ),
        onTap: () => context.read<HomeSettingBloc>().add(
              HomeSettingEvent.collapseNotificationPanel(),
            ),
      ),
    );
  }

  Widget _buildHeaderActionsMoreButton(BuildContext context) {
    return AppFlowyPopover(
      controller: _headerActionsPopoverController,
      direction: PopoverDirection.bottomWithCenterAligned,
      triggerActions: PopoverTriggerFlags.hover | PopoverTriggerFlags.click,
      clickHandler: PopoverClickHandler.gestureDetector,
      constraints: const BoxConstraints(maxWidth: 180, maxHeight: 72),
      margin: EdgeInsets.zero,
      offset: const Offset(0, 8),
      popupBuilder: (_) {
        final colorScheme = Theme.of(context).colorScheme;
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: colorScheme.copyWith(onSurface: Colors.white),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.24),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SidebarCloudSyncButton(isHover: true),
                  const HSpace(18),
                  const SidebarUploadButton(isHover: true),
                  const HSpace(18),
                  _buildHeaderNotificationActionButton(
                    context,
                    iconColor: Colors.white,
                  ),
                ],
              ),
            ),
          ),
        );
      },
      child: FlowyTooltip(
        message: LocaleKeys.menuAppHeader_moreButtonToolTip.tr(),
        child: SizedBox.square(
          dimension: 28,
          child: FlowyButton(
            useIntrinsicWidth: true,
            margin: EdgeInsets.zero,
            text: FlowySvg(
              FlowySvgs.workspace_three_dots_s,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            onTap: () => _headerActionsPopoverController.show(),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderFullWindowButton(
    BuildContext context,
    bool isFullWindow,
  ) {
    return FlowyTooltip(
      message: isFullWindow ? 'Exit full window' : 'Full window',
      child: SizedBox.square(
        dimension: 28,
        child: FlowyButton(
          useIntrinsicWidth: true,
          margin: EdgeInsets.zero,
          text: Icon(
            isFullWindow
                ? Icons.fullscreen_exit_rounded
                : Icons.fullscreen_rounded,
            size: 20,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          onTap: () {
            if (FullWindowController.isFullWindow.value) {
              FullWindowController.exit();
              return;
            }
            FullWindowController.enter();
          },
        ),
      ),
    );
  }
}
