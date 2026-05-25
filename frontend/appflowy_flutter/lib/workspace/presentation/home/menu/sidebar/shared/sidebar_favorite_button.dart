import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/plugins/database/calendar/application/calendar_unsaved_guard.dart';
import 'package:appflowy/workspace/application/favorite/favorite_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/folder/folder_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SidebarFavoriteButton extends StatefulWidget {
  const SidebarFavoriteButton({super.key});

  @override
  State<SidebarFavoriteButton> createState() => _SidebarFavoriteButtonState();
}

class _SidebarFavoriteButtonState extends State<SidebarFavoriteButton> {
  bool _isExpanded = false;
  bool _isDragHovering = false;

  @override
  Widget build(BuildContext context) {
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
          final newWorkspaceId = state.currentWorkspace?.workspaceId;
          context.read<FavoriteBloc>().setWorkspaceId(
                newWorkspaceId,
                userProfile: state.userProfile,
              );
        },
        child: BlocBuilder<FavoriteBloc, FavoriteState>(
          builder: (context, state) {
            if (state.isLoading) {
              return const SizedBox.shrink();
            }

            return Column(
              children: [
                _buildFavoriteHeader(context, state),
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
    final highlightColor =
        Theme.of(context).colorScheme.primary.withValues(alpha: 0.10);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: DragTarget<ViewPB>(
        onWillAcceptWithDetails: (details) {
          final canAccept = _canAcceptDraggedView(details.data);
          if (canAccept && !_isDragHovering) {
            setState(() => _isDragHovering = true);
          }
          return canAccept;
        },
        onLeave: (_) {
          if (_isDragHovering) {
            setState(() => _isDragHovering = false);
          }
        },
        onAcceptWithDetails: (details) {
          final draggedView = details.data;
          final isFavorited =
              state.views.any((item) => item.item.id == draggedView.id);
          if (!isFavorited) {
            context.read<FavoriteBloc>().add(FavoriteEvent.toggle(draggedView));
          }
          setState(() {
            _isDragHovering = false;
            _isExpanded = true;
          });
        },
        builder: (context, candidateData, rejectedData) {
          final isActive = _isDragHovering || candidateData.isNotEmpty;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              color: isActive ? highlightColor : Colors.transparent,
              borderRadius: BorderRadius.circular(theme.borderRadius.s),
            ),
            child: AFGhostIconTextButton.primary(
              text: '最爱',
              mainAxisAlignment: MainAxisAlignment.start,
              size: AFButtonSize.l,
              onTap: () {
                setState(() => _isExpanded = !_isExpanded);
              },
              padding: const EdgeInsets.symmetric(vertical: 10),
              borderRadius: theme.borderRadius.s,
              iconBuilder: (context, isHover, disabled) =>
                  const SizedBox.shrink(),
              showExpandArrow: true,
              isExpanded: _isExpanded,
            ),
          );
        },
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
        onSelected: (viewContext, selectedView) {
          CalendarUnsavedGuard.instance.maybeConfirmLeave(
            context,
            () => context.read<TabsBloc>().openPlugin(selectedView),
          );
        },
        onTertiarySelected: (viewContext, selectedView) {
          CalendarUnsavedGuard.instance.maybeConfirmLeave(
            context,
            () => context.read<TabsBloc>().openTab(selectedView),
          );
        },
      );
    }).toList();
  }

  bool _canAcceptDraggedView(ViewPB view) {
    return !view.isSpace;
  }
}
