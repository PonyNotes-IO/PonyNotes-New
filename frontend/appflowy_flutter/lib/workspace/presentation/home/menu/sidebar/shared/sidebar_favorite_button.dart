import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/database/calendar/application/calendar_unsaved_guard.dart';
import 'package:appflowy/workspace/application/favorite/favorite_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_item.dart';
import 'package:appflowy/workspace/application/sidebar/folder/folder_bloc.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:appflowy_ui/appflowy_ui.dart';

class SidebarFavoriteButton extends StatefulWidget {
  const SidebarFavoriteButton({super.key});

  @override
  State<SidebarFavoriteButton> createState() => _SidebarFavoriteButtonState();
}

class _SidebarFavoriteButtonState extends State<SidebarFavoriteButton> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    // 获取当前工作区ID和用户信息
    final userWorkspaceBloc = context.read<UserWorkspaceBloc>();
    final currentWorkspace = userWorkspaceBloc.state.currentWorkspace;
    final workspaceId = currentWorkspace?.workspaceId;
    final userProfile = userWorkspaceBloc.state.userProfile;

    return BlocProvider(
      create: (_) => FavoriteBloc(
        workspaceId: workspaceId,
        userProfile: userProfile,
      )..add(const FavoriteEvent.initial()),
      child: BlocListener<UserWorkspaceBloc, UserWorkspaceState>(
        listenWhen: (previous, current) =>
            previous.currentWorkspace?.workspaceId !=
            current.currentWorkspace?.workspaceId,
        listener: (context, state) {
          // 工作区切换时，更新 FavoriteBloc 的工作区ID
          final newWorkspaceId = state.currentWorkspace?.workspaceId;
          context.read<FavoriteBloc>().setWorkspaceId(
                newWorkspaceId,
                userProfile: state.userProfile,
              );
        },
        child: BlocBuilder<FavoriteBloc, FavoriteState>(
          builder: (context, state) {
            // 如果正在加载，显示空组件（避免闪烁）
            if (state.isLoading) {
              return const SizedBox.shrink();
            }

            // 始终显示最爱菜单项，有收藏时可展开列表
            return Column(
              children: [
                // 收藏夹标题行
                _buildFavoriteHeader(context, state),
                // 收藏的页面列表（仅在展开且有内容时显示）
                if (_isExpanded && state.views.isNotEmpty)
                  ..._buildFavoriteItems(context, state),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFavoriteHeader(BuildContext context, FavoriteState state) {
    final theme = AppFlowyTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: AFGhostIconTextButton.primary(
        text: '最爱',
        mainAxisAlignment: MainAxisAlignment.start,
        size: AFButtonSize.l,
        onTap: () {
          setState(() => _isExpanded = !_isExpanded);
        },
        padding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 10,
        ),
        borderRadius: theme.borderRadius.s,
        iconBuilder: (context, isHover, disabled) => FlowySvg(
          FlowySvgs.icon_favorite_s,
          size: const Size.square(18.0),
          color: Theme.of(context).textTheme.bodyMedium?.color,
        ),
        showExpandArrow: true,
        isExpanded: _isExpanded,
        expandArrowPosition: AFExpandArrowPosition.rowEnd,
      ),
    );
  }

  List<Widget> _buildFavoriteItems(BuildContext context, FavoriteState state) {
    return state.views.map((sectionView) {
      final view = sectionView.item;
      return ViewItem(
        key: ValueKey('favorite_${view.id}'),
        spaceType: FolderSpaceType.public,
        view: view,
        level: 0,
        isDraggable: false,
        leftPadding: HomeSpaceViewSizes.leftPadding,
        height: HomeSpaceViewSizes.viewHeight,
        isFeedback: false,
        isHoverEnabled: true,
        enableRightClickContext: true,
        onSelected: (viewContext, view) {
          CalendarUnsavedGuard.instance.maybeConfirmLeave(
            context,
            () => context.read<TabsBloc>().openPlugin(view),
          );
        },
        onTertiarySelected: (viewContext, view) {
          CalendarUnsavedGuard.instance.maybeConfirmLeave(
            context,
            () => context.read<TabsBloc>().openTab(view),
          );
        },
      );
    }).toList();
  }
}
