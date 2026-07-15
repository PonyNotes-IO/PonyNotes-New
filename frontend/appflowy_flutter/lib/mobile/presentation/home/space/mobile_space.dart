import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/application/mobile_router.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/bottom_sheet.dart';
import 'package:appflowy/mobile/presentation/home/space/mobile_space_menu.dart';
import 'package:appflowy/mobile/presentation/page_item/mobile_view_item.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/shared/list_extension.dart';
import 'package:appflowy/util/theme_extension.dart';
import 'package:appflowy/workspace/application/favorite/favorite_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/folder/folder_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class MobileSpace extends StatelessWidget {
  const MobileSpace({super.key, required this.favoriteBloc});

  final FavoriteBloc favoriteBloc;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SpaceBloc, SpaceState>(
      builder: (context, state) {
        if (state.spaces.isEmpty) {
          return const SizedBox.shrink();
        }

        final spaceBloc = context.read<SpaceBloc>();
        final privateSpaces = spaceBloc.privateSpaces;
        final publicSpaces = spaceBloc.publicSpaces;
        final isCollaborativeWorkspace =
            context.read<UserWorkspaceBloc>().state.isCollabWorkspaceOn;

        return Column(
          children: [
            if (isCollaborativeWorkspace) ...[
              // 私有空间（仅 Space）
              MobileSpaceSection(
                title: LocaleKeys.space_privateSpace.tr(),
                spaces: privateSpaces,
                isExpanded: state.isExpanded,
                onHeaderPressed: () => _showSpaceMenu(context),
                onAddPressed: () => _showCreatePageMenu(
                  context,
                  privateSpaces.isNotEmpty
                      ? privateSpaces.first
                      : publicSpaces.isNotEmpty
                          ? publicSpaces.first
                          : state.currentSpace ?? state.spaces.first,
                ),
                favoriteBloc: favoriteBloc,
              ),
              const VSpace(4.0),
              // 协作区 / 公共空间（仅 Space）
              MobileSpaceSection(
                title: LocaleKeys.sideBar_workspace.tr(),
                spaces: publicSpaces,
                isExpanded: state.isExpanded,
                onHeaderPressed: () => _showSpaceMenu(context),
                onAddPressed: () => _showCreatePageMenu(
                  context,
                  publicSpaces.isNotEmpty
                      ? publicSpaces.first
                      : state.currentSpace ?? state.spaces.first,
                ),
                favoriteBloc: favoriteBloc,
              ),
            ] else ...[
              // 非协作工作区：个人空间仅使用公共空间中的 Space
              MobileSpaceSection(
                title: LocaleKeys.space_mySpace.tr(),
                spaces: publicSpaces,
                isExpanded: state.isExpanded,
                onHeaderPressed: () => _showSpaceMenu(context),
                onAddPressed: () => _showCreatePageMenu(
                  context,
                  publicSpaces.isNotEmpty
                      ? publicSpaces.first
                      : state.currentSpace ?? state.spaces.first,
                ),
                favoriteBloc: favoriteBloc,
              ),
            ],
          ],
        );
      },
    );
  }

  void _showSpaceMenu(BuildContext context) {
    showMobileBottomSheet(
      context,
      showDivider: false,
      showHeader: true,
      showDragHandle: true,
      showCloseButton: true,
      showDoneButton: true,
      useRootNavigator: true,
      title: LocaleKeys.space_title.tr(),
      backgroundColor: Theme.of(context).colorScheme.surface,
      enableScrollable: true,
      bottomSheetPadding: context.bottomSheetPadding(),
      builder: (_) {
        return MultiBlocProvider(
          providers: [
            BlocProvider.value(value: context.read<SpaceBloc>()),
            BlocProvider.value(value: context.read<UserWorkspaceBloc>()),
          ],
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.0),
            child: MobileSpaceMenu(),
          ),
        );
      },
    );
  }

  void _showCreatePageMenu(BuildContext context, ViewPB space) {
    final title = space.name;
    showMobileBottomSheet(
      context,
      showHeader: true,
      title: title,
      showDragHandle: true,
      showCloseButton: true,
      useRootNavigator: true,
      showDivider: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) {
        return AddNewPageWidgetBottomSheet(
          view: space,
          onAction: (layout) {
            Navigator.of(sheetContext).pop();
            context.read<SpaceBloc>().add(
                  SpaceEvent.createPage(
                    name: layout.defaultName,
                    layout: layout,
                    index: 0,
                    openAfterCreate: true,
                  ),
                );
            context.read<SpaceBloc>().add(
                  SpaceEvent.expand(space, true),
                );
          },
        );
      },
    );
  }
}

class MobileSpaceSection extends StatelessWidget {
  const MobileSpaceSection({
    super.key,
    required this.title,
    required this.spaces,
    required this.isExpanded,
    required this.onHeaderPressed,
    required this.onAddPressed,
    required this.favoriteBloc,
  });

  final String title;
  final List<ViewPB> spaces;
  final bool isExpanded;
  final VoidCallback onHeaderPressed;
  final VoidCallback onAddPressed;
  final FavoriteBloc favoriteBloc;

  @override
  Widget build(BuildContext context) {
    if (spaces.isEmpty) {
      return const SizedBox.shrink();
    }

    final borderColor = Theme.of(context).isLightMode
        ? const Color(0xFFE9E9EC)
        : const Color(0x1AFFFFFF);

    return Column(
      children: [
        MobileSpaceSectionHeader(
          title: title,
          onPressed: onHeaderPressed,
          onAdded: onAddPressed,
        ),
        if (isExpanded)
          Container(
            margin: const EdgeInsets.symmetric(
              horizontal: HomeSpaceViewSizes.mHorizontalPadding,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 0.5),
            ),
            child: Column(
              children: [
                for (int i = 0; i < spaces.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 0.5,
                      thickness: 0.5,
                      color: borderColor,
                      indent: HomeSpaceViewSizes.mHorizontalPadding,
                      endIndent: HomeSpaceViewSizes.mHorizontalPadding,
                    ),
                  _SpaceItem(
                    space: spaces[i],
                    favoriteBloc: favoriteBloc,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class MobileSpaceSectionHeader extends StatefulWidget {
  const MobileSpaceSectionHeader({
    super.key,
    required this.title,
    required this.onPressed,
    required this.onAdded,
  });

  final String title;
  final VoidCallback onPressed;
  final VoidCallback onAdded;

  @override
  State<MobileSpaceSectionHeader> createState() =>
      _MobileSpaceSectionHeaderState();
}

class _MobileSpaceSectionHeaderState extends State<MobileSpaceSectionHeader> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onPressed,
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            const HSpace(HomeSpaceViewSizes.mHorizontalPadding),
            Expanded(
              child: FlowyText.medium(
                widget.title,
                lineHeight: 1.15,
                fontSize: 16.0,
              ),
            ),
            const HSpace(HomeSpaceViewSizes.mHorizontalPadding),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: widget.onAdded,
              child: Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: HomeSpaceViewSizes.mHorizontalPadding,
                  vertical: 8.0,
                ),
                child: const FlowySvg(
                  FlowySvgs.m_space_add_s,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpaceItem extends StatelessWidget {
  const _SpaceItem({required this.space, required this.favoriteBloc});

  final ViewPB space;
  final FavoriteBloc favoriteBloc;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          ViewBloc(view: space)..add(const ViewEvent.initial()),
      child: BlocBuilder<ViewBloc, ViewState>(
        builder: (context, state) {
          final spaceType =
              space.spacePermission == SpacePermission.publicToAll
                  ? FolderSpaceType.public
                  : FolderSpaceType.private;
          final childViews = state.view.childViews.unique((view) => view.id);
          if (childViews.length != state.view.childViews.length) {
            final duplicatedViews = state.view.childViews
                .where((view) => childViews.contains(view))
                .toList();
            Log.error('some view id are duplicated: $duplicatedViews');
          }
          return Column(
            children: childViews.asMap().entries.map((entry) {
              final index = entry.key;
              final view = entry.value;
              return Column(
                children: [
                  if (index > 0)
                    const Divider(
                      height: 0.5,
                      thickness: 0.5,
                      indent: HomeSpaceViewSizes.mHorizontalPadding,
                      endIndent: HomeSpaceViewSizes.mHorizontalPadding,
                    ),
                  MobileViewItem(
                    key: ValueKey(
                      '${space.id} ${view.id}',
                    ),
                    spaceType: spaceType,
                    isFirstChild: view.id == state.view.childViews.first.id,
                    view: view,
                    level: 0,
                    leftPadding: HomeSpaceViewSizes.leftPadding,
                    isFeedback: false,
                    favoriteBloc: favoriteBloc,
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
                      final actions = [
                        MobilePaneActionType.more,
                        if (view.layout == ViewLayoutPB.Document)
                          MobilePaneActionType.add,
                      ];
                      return buildEndActionPane(
                        context,
                        actions,
                        spaceType: spaceType,
                        spaceRatio: actions.length == 1 ? 3 : 4,
                      );
                    },
                  ),
                ],
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
