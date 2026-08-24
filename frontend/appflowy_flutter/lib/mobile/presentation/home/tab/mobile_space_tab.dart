import 'dart:async';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/application/mobile_router.dart';
import 'package:appflowy/mobile/presentation/home/favorite_folder/favorite_space.dart';
import 'package:appflowy/mobile/presentation/home/home_space/home_space.dart';
import 'package:appflowy/mobile/presentation/home/recent_folder/recent_space.dart';
import 'package:appflowy/mobile/presentation/home/space/space_change_notifier.dart';
import 'package:appflowy/mobile/presentation/home/tab/_tab_bar.dart';
import 'package:appflowy/mobile/presentation/home/tab/space_order_bloc.dart';
import 'package:appflowy/mobile/presentation/presentation.dart';
import 'package:appflowy/mobile/presentation/setting/workspace/invite_members_screen.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/workspace/application/menu/sidebar_sections_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace/recent_access_space_service.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';

final ValueNotifier<int> mobileCreateNewAIChatNotifier = ValueNotifier(0);

class MobileHomePageTab extends StatefulWidget {
  const MobileHomePageTab({
    super.key,
    required this.userProfile,
  });

  final UserProfilePB userProfile;

  @override
  State<MobileHomePageTab> createState() => _MobileHomePageTabState();
}

class _MobileHomePageTabState extends State<MobileHomePageTab>
    with SingleTickerProviderStateMixin {
  TabController? tabController;
  bool _isCreatingQuickDocument = false;

  @override
  void initState() {
    super.initState();

    mobileCreateNewPageNotifier.addListener(_createNewDocument);
    mobileLeaveWorkspaceNotifier.addListener(_leaveWorkspace);
  }

  @override
  void dispose() {
    tabController?.removeListener(_onTabChange);
    tabController?.dispose();

    mobileCreateNewPageNotifier.removeListener(_createNewDocument);
    mobileLeaveWorkspaceNotifier.removeListener(_leaveWorkspace);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Provider.value(
      value: widget.userProfile,
      child: MultiBlocListener(
        listeners: [
          BlocListener<SpaceBloc, SpaceState>(
            listenWhen: (p, c) =>
                p.lastCreatedPage?.id != c.lastCreatedPage?.id,
            listener: (context, state) {
              final lastCreatedPage = state.lastCreatedPage;
              if (lastCreatedPage != null) {
                context.pushView(
                  lastCreatedPage,
                  tabs: [
                    PickerTabType.emoji,
                    PickerTabType.icon,
                    PickerTabType.custom,
                  ].map((e) => e.name).toList(),
                );
              }
            },
          ),
          BlocListener<SidebarSectionsBloc, SidebarSectionsState>(
            listenWhen: (p, c) =>
                p.lastCreatedRootView?.id != c.lastCreatedRootView?.id,
            listener: (context, state) {
              final lastCreatedPage = state.lastCreatedRootView;
              if (lastCreatedPage != null) {
                context.pushView(
                  lastCreatedPage,
                  tabs: [
                    PickerTabType.emoji,
                    PickerTabType.icon,
                    PickerTabType.custom,
                  ].map((e) => e.name).toList(),
                );
              }
            },
          ),
        ],
        child: BlocBuilder<SpaceOrderBloc, SpaceOrderState>(
          builder: (context, state) {
            if (state.isLoading) {
              return const SizedBox.shrink();
            }

            _initTabController(state);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MobileSpaceTabBar(
                  tabController: tabController!,
                  tabs: state.tabsOrder,
                  onReorder: (from, to) {
                    context.read<SpaceOrderBloc>().add(
                          SpaceOrderEvent.reorder(from, to),
                        );
                  },
                ),
                const HSpace(12.0),
                Expanded(
                  child: TabBarView(
                    controller: tabController,
                    children: _buildTabs(state),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _initTabController(SpaceOrderState state) {
    if (tabController != null) {
      return;
    }
    if (state.tabsOrder.isEmpty) {
      return;
    }
    final defaultIndex = state.tabsOrder.indexOf(state.defaultTab);
    tabController = TabController(
      length: state.tabsOrder.length,
      vsync: this,
      initialIndex: defaultIndex < 0 ? 0 : defaultIndex,
    );
    tabController?.addListener(_onTabChange);
  }

  void _onTabChange() {
    if (tabController == null) {
      return;
    }
    context
        .read<SpaceOrderBloc>()
        .add(SpaceOrderEvent.open(tabController!.index));
  }

  Widget _buildTab(MobileSpaceTabType tab) {
    // Defensive: every unknown/legacy enum value falls back to an empty widget
    // instead of returning null, which would crash TabBarView with
    // `Null is not a subtype of StatefulWidget` at StatefulElement.update.
    switch (tab) {
      case MobileSpaceTabType.recent:
        return const MobileRecentSpace();
      case MobileSpaceTabType.spaces:
        return MobileHomeSpace(userProfile: widget.userProfile);
      case MobileSpaceTabType.favorites:
        return MobileFavoriteSpace(userProfile: widget.userProfile);
    }
    return const SizedBox.shrink();
  }

  List<Widget> _buildTabs(SpaceOrderState state) {
    return state.tabsOrder.map(_buildTab).whereType<Widget>().toList();
  }

  // 底部导航栏“+”始终在私有的“最近访问”空间中新建文档。
  void _createNewDocument() {
    if (_isCreatingQuickDocument) {
      return;
    }
    unawaited(_createDocumentInRecentAccessSpace());
  }

  Future<void> _createDocumentInRecentAccessSpace() async {
    _isCreatingQuickDocument = true;
    try {
      final workspaceId =
          context.read<UserWorkspaceBloc>().state.currentWorkspace?.workspaceId;
      if (workspaceId == null || workspaceId.isEmpty) {
        Log.error('移动端快捷新建失败：当前工作区 ID 为空');
        _showCreateDocumentError();
        return;
      }

      final recentAccessSpaceResult = await RecentAccessSpaceService(
        workspaceId: workspaceId,
        userId: widget.userProfile.id,
      ).getOrCreate();

      if (!mounted) {
        return;
      }

      if (recentAccessSpaceResult.wasCreated) {
        SpaceChangeNotifier.instance.notifySpaceCreated(
          recentAccessSpaceResult.space,
        );
      }

      final createResult =
          await ViewBackendService.createViewWithPermissionCheck(
        parentViewId: recentAccessSpaceResult.space.id,
        name: ViewLayoutPB.Document.defaultName,
        layoutType: ViewLayoutPB.Document,
        workspaceId: workspaceId,
        userId: widget.userProfile.id.toInt(),
        index: 0,
      );

      await createResult.fold(
        (view) async {
          if (mounted) {
            await context.pushView(
              view,
              tabs: [
                PickerTabType.emoji,
                PickerTabType.icon,
                PickerTabType.custom,
              ].map((e) => e.name).toList(),
            );
          }
        },
        (error) async {
          Log.error(
            '移动端快捷新建文档失败：parent=${recentAccessSpaceResult.space.id}, '
            'error=${error.msg}',
          );
          _showCreateDocumentError();
        },
      );
    } catch (error, stackTrace) {
      Log.error('移动端快捷新建文档异常：$error\n$stackTrace');
      _showCreateDocumentError();
    } finally {
      _isCreatingQuickDocument = false;
    }
  }

  void _showCreateDocumentError() {
    if (!mounted) {
      return;
    }
    showToastNotification(
      message: LocaleKeys.document_plugins_subPage_errors_failedCreatePage.tr(),
      type: ToastificationType.error,
    );
  }

  void _leaveWorkspace() {
    final workspaceId =
        context.read<UserWorkspaceBloc>().state.currentWorkspace?.workspaceId;
    if (workspaceId == null) {
      return Log.error('Workspace ID is null');
    }
    context
        .read<UserWorkspaceBloc>()
        .add(UserWorkspaceEvent.leaveWorkspace(workspaceId: workspaceId));
  }
}
