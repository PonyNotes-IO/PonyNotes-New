import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/application/mobile_router.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/bottom_sheet.dart';
import 'package:appflowy/mobile/presentation/home/section_folder/mobile_home_section_folder_header.dart';
import 'package:appflowy/mobile/presentation/home/space/mobile_create_space_sheet.dart';
import 'package:appflowy/mobile/presentation/page_item/mobile_view_item.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/workspace/application/menu/sidebar_sections_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/folder/folder_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class MobileSectionFolder extends StatelessWidget {
  const MobileSectionFolder({
    super.key,
    required this.title,
    required this.views,
    required this.spaceType,
  });

  final String title;
  final List<ViewPB> views;
  final FolderSpaceType spaceType;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<FolderBloc>(
      create: (context) => FolderBloc(type: spaceType)
        ..add(
          const FolderEvent.initial(),
        ),
      child: BlocBuilder<FolderBloc, FolderState>(
        builder: (context, state) {
          return Column(
            children: [
              SizedBox(
                height: HomeSpaceViewSizes.mViewHeight,
                child: MobileSectionFolderHeader(
                  title: title,
                  isExpanded: context.read<FolderBloc>().state.isExpanded,
                  onPressed: () => context
                      .read<FolderBloc>()
                      .add(const FolderEvent.expandOrUnExpand()),
                  onAdded: () => _onAddPressed(context),
                ),
              ),
              if (state.isExpanded)
                Padding(
                  padding: const EdgeInsets.only(
                    left: HomeSpaceViewSizes.leftPadding,
                  ),
                  child: _Pages(
                    views: views,
                    spaceType: spaceType,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _onAddPressed(BuildContext context) {
    final workspaceState = context.read<UserWorkspaceBloc>().state;
    final isQuickStartUser =
        workspaceState.userProfile.userAuthType != AuthTypePB.Server;
    if (isQuickStartUser ||
        (spaceType == FolderSpaceType.public &&
            workspaceState.isCollabWorkspaceOn)) {
      _showCreateSpaceBottomSheet(context);
      return;
    }
    _createNewPage(context);
  }

  void _createNewPage(BuildContext context) {
    showMobileBottomSheet(
      context,
      showHeader: true,
      title: LocaleKeys.menuAppHeader_defaultNewPageName.tr(),
      showDragHandle: true,
      showCloseButton: true,
      useRootNavigator: true,
      showDivider: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetCtx) => AddNewPageWidgetBottomSheet(
        view: context.read<ViewBloc>().state.view,
        onAction: (layout, {String? name, String? extra}) {
          Navigator.of(sheetCtx).pop();
          context.read<SidebarSectionsBloc>().add(
            SidebarSectionsEvent.createRootViewInSectionWithLayout(
              name: name ?? layout.defaultName,
              viewSection: spaceType.toViewSectionPB,
              index: 0,
              layout: layout,
              extra: extra,
            ),
          );
          context.read<FolderBloc>().add(
            const FolderEvent.expandOrUnExpand(isExpanded: true),
          );
        },
      ),
    );
  }

  void _showCreateSpaceBottomSheet(BuildContext context) {
    // 与桌面端 sidebar 的 "+" 行为对齐：调 `SpaceBloc.create` 让新 space
    // 进入 sidebar 树里的 SpaceBloc.state.spaces。
    // (这与 `_createNewPage` 调 `SidebarSectionsEvent.createRootView...`
    // 完全不同 —— 后者创建一个普通 view，而不是一个 space。)
    final spaceBloc = context.read<SpaceBloc>();
    showMobileBottomSheet(
      context,
      showDragHandle: true,
      showHeader: true,
      title: LocaleKeys.space_createSpace.tr(),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      // 让外层 sheet 用 Flexible(SingleChildScrollView) 包住我们，
      // 避免键盘弹起时外层 Column overflow。
      enableScrollable: true,
      builder: (_) => MobileCreateSpaceSheet(
        spaceBloc: spaceBloc,
        nameHint: LocaleKeys.space_spaceName.tr(),
        onCreated: () {},
      ),
    );
  }
}

class _Pages extends StatelessWidget {
  const _Pages({
    required this.views,
    required this.spaceType,
  });

  final List<ViewPB> views;
  final FolderSpaceType spaceType;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: views
          .map(
            (view) => MobileViewItem(
              key: ValueKey(
                '${FolderSpaceType.private.name} ${view.id}',
              ),
              spaceType: spaceType,
              isFirstChild: view.id == views.first.id,
              view: view,
              level: 0,
              leftPadding: HomeSpaceViewSizes.leftPadding,
              isFeedback: false,
              onSelected: (v) => context.pushView(
                v,
                tabs: [
                  PickerTabType.emoji,
                  PickerTabType.icon,
                  PickerTabType.custom,
                ].map((e) => e.name).toList(),
              ),
              endActionPane: (context) {
                final view = context.read<ViewBloc>().state.view;
                return buildEndActionPane(
                  context,
                  [
                    MobilePaneActionType.more,
                    if (view.layout == ViewLayoutPB.Document)
                      MobilePaneActionType.add,
                  ],
                  spaceType: spaceType,
                  needSpace: false,
                  spaceRatio: 5,
                );
              },
            ),
          )
          .toList(),
    );
  }
}
