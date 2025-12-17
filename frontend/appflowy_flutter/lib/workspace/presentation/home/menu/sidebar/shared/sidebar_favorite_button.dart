import 'package:appflowy/generated/flowy_svgs.g.dart';
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
    return BlocProvider(
      create: (_) => FavoriteBloc()..add(const FavoriteEvent.initial()),
      child: BlocBuilder<FavoriteBloc, FavoriteState>(
        builder: (context, state) {
          return Column(
            children: [
              // 收藏夹标题行
              _buildFavoriteHeader(context, state),
              // 收藏的页面列表
              if (_isExpanded) ..._buildFavoriteItems(context, state),
            ],
          );
        },
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
              FlowySvgs.favorite_s,
              size: const Size.square(16.0),
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
            showExpandArrow: true,
            isExpanded: _isExpanded,
            expandArrowPosition: AFExpandArrowPosition.rowEnd,
          ),
    );
  }

  List<Widget> _buildFavoriteItems(BuildContext context, FavoriteState state) {
    if (state.views.isEmpty) {
      return [
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Row(
              children: [
                const SizedBox(width: 20), // 缩进
                Icon(
                  Icons.favorite_border,
                  size: 14,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FlowyText(
                    '暂无收藏',
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    return state.views.map((sectionView) {
      final view = sectionView.item;
      return ViewItem(
        key: ValueKey('favorite_${view.id}'),
        spaceType: FolderSpaceType.public,
        view: view,
        level: 0,
        leftPadding: HomeSpaceViewSizes.leftPadding,
        height: HomeSpaceViewSizes.viewHeight,
        isFeedback: false,
        isHoverEnabled: true,
        enableRightClickContext: true,
        onSelected: (viewContext, view) {
          context.read<TabsBloc>().openPlugin(view);
        },
        onTertiarySelected: (viewContext, view) =>
            context.read<TabsBloc>().openTab(view),
      );
    }).toList();
  }
}


