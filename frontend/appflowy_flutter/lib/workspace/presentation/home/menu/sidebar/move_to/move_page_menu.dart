import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/sidebar/folder/folder_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_search_bloc.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/shared_widget.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/space_icon.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

typedef MovePageMenuOnSelected = FutureOr<void> Function(
  ViewPB space,
  ViewPB view,
);

class MovePageMenu extends StatefulWidget {
  const MovePageMenu({
    super.key,
    required this.sourceView,
    required this.onSelected,
  });

  final ViewPB sourceView;
  final MovePageMenuOnSelected onSelected;

  @override
  State<MovePageMenu> createState() => _MovePageMenuState();
}

class _MovePageMenuState extends State<MovePageMenu> {
  final isExpandedNotifier = PropertyValueNotifier(true);
  final isHoveredNotifier = ValueNotifier(true);

  @override
  void dispose() {
    isExpandedNotifier.dispose();
    isHoveredNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SpaceSearchBloc()..add(const SpaceSearchEvent.initial()),
      child: BlocBuilder<SpaceBloc, SpaceState>(
        builder: (context, state) {
          final spaceBloc = context.read<SpaceBloc>();
          // 目标空间列表：协作（公共）空间 + 私有空间，支持文档在两类空间之间移动。
          final publicSpaces = spaceBloc.publicSpaces;
          final privateSpaces = spaceBloc.privateSpaces;
          if (publicSpaces.isEmpty && privateSpaces.isEmpty) {
            return const SizedBox.shrink();
          }

          // 搜索结果为扁平视图列表，无法直接推断其所属空间，
          // 回退到当前空间或第一个可用空间作为移动上下文。
          final searchFallbackSpace = state.currentSpace ??
              (publicSpaces.isNotEmpty
                  ? publicSpaces.first
                  : privateSpaces.first);

          return Column(
            children: [
              SpaceSearchField(
                width: 240,
                onSearch: (context, value) => context
                    .read<SpaceSearchBloc>()
                    .add(SpaceSearchEvent.search(value)),
              ),
              const VSpace(10),
              BlocBuilder<SpaceSearchBloc, SpaceSearchState>(
                builder: (context, searchState) {
                  if (searchState.queryResults == null) {
                    return Expanded(
                      child: _buildAllSpaces(publicSpaces, privateSpaces),
                    );
                  }
                  return Expanded(
                    child: _buildGroupedViews(
                      searchFallbackSpace,
                      searchState.queryResults!,
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGroupedViews(ViewPB space, List<ViewPB> views) {
    final groupedViews = views
        .where((v) => !_shouldIgnoreView(v, widget.sourceView) && !v.isSpace)
        .toList();
    return _MovePageGroupedViews(
      views: groupedViews,
      onSelected: (view) => widget.onSelected(space, view),
    );
  }

  /// 展示所有可作为移动目标的空间（协作空间在前，私有空间在后）。
  /// 每个空间为一组：点击空间标题移动到空间根目录，
  /// 展开可移动到空间内的具体页面，从而支持文档在私有空间↔协作空间之间移动。
  Widget _buildAllSpaces(
    List<ViewPB> publicSpaces,
    List<ViewPB> privateSpaces,
  ) {
    return CustomScrollView(
      physics: const ClampingScrollPhysics(),
      slivers: [
        if (publicSpaces.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _buildSectionHeader(LocaleKeys.space_publicPermission.tr()),
          ),
          ...publicSpaces.map(_buildSpaceGroupSliver),
        ],
        if (privateSpaces.isNotEmpty) ...[
          if (publicSpaces.isNotEmpty)
            const SliverToBoxAdapter(child: VSpace(8)),
          SliverToBoxAdapter(
            child: _buildSectionHeader(LocaleKeys.space_privatePermission.tr()),
          ),
          ...privateSpaces.map(_buildSpaceGroupSliver),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: FlowyText.medium(
        title,
        fontSize: 12.0,
        color: Theme.of(context).hintColor,
      ),
    );
  }

  Widget _buildSpaceGroupSliver(ViewPB space) {
    return _MoveSpaceGroupSliver(
      key: ValueKey(space.id),
      space: space,
      sourceView: widget.sourceView,
      isHovered: isHoveredNotifier,
      isExpandedNotifier: isExpandedNotifier,
      onSelected: widget.onSelected,
    );
  }
}

class _MovePageGroupedViews extends StatelessWidget {
  const _MovePageGroupedViews({required this.views, required this.onSelected});

  final List<ViewPB> views;
  final void Function(ViewPB view) onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const ClampingScrollPhysics(),
      itemCount: views.length,
      itemBuilder: (context, index) {
        final view = views[index];
        return ViewItem(
          key: ValueKey(view.id),
          view: view,
          spaceType: FolderSpaceType.unknown,
          level: 0,
          onSelected: (_, view) => onSelected(view),
          isFeedback: false,
          isDraggable: false,
          shouldRenderChildren: false,
          leftIconBuilder: (_, __) => const HSpace(0.0),
          rightIconsBuilder: (_, view) => [],
        );
      },
    );
  }
}

class _MoveSpaceGroupSliver extends StatelessWidget {
  const _MoveSpaceGroupSliver({
    super.key,
    required this.space,
    required this.sourceView,
    required this.isHovered,
    required this.isExpandedNotifier,
    required this.onSelected,
  });

  final ViewPB space;
  final ViewPB sourceView;
  final ValueNotifier<bool> isHovered;
  final PropertyValueNotifier<bool> isExpandedNotifier;
  final MovePageMenuOnSelected onSelected;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ViewBloc(view: space)..add(const ViewEvent.initial()),
      child: BlocBuilder<ViewBloc, ViewState>(
        builder: (context, state) {
          final childViews = state.view.childViews.where((view) {
            return !_shouldIgnoreView(view, sourceView);
          }).toList();

          return SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index == 0) {
                  return _buildSpaceRootRow(context);
                }

                final view = childViews[index - 1];
                return ViewItem(
                  key: ValueKey('${space.id} ${view.id}'),
                  spaceType:
                      space.spacePermission == SpacePermission.publicToAll
                          ? FolderSpaceType.public
                          : FolderSpaceType.private,
                  isFirstChild: index == 1,
                  view: view,
                  level: 0,
                  leftPadding: HomeSpaceViewSizes.leftPadding,
                  isFeedback: false,
                  isHovered: isHovered,
                  disableSelectedStatus: true,
                  isExpandedNotifier: isExpandedNotifier,
                  rightIconsBuilder: (_, __) => [],
                  shouldIgnoreView: (view) {
                    if (_shouldIgnoreView(view, sourceView)) {
                      return IgnoreViewType.hide;
                    }
                    return view.layout.isDatabaseView
                        ? IgnoreViewType.disable
                        : IgnoreViewType.none;
                  },
                  onSelected: (_, view) => onSelected(space, view),
                );
              },
              childCount: childViews.length + 1,
            ),
          );
        },
      ),
    );
  }

  Widget _buildSpaceRootRow(BuildContext context) {
    return SizedBox(
      height: 30,
      child: FlowyButton(
        margin: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
        text: Row(
          children: [
            SpaceIcon(
              dimension: 20,
              space: space,
              svgSize: 11,
              cornerRadius: 6.0,
            ),
            const HSpace(8),
            Flexible(
              child: FlowyText.medium(
                space.name,
                fontSize: 14.0,
                figmaLineHeight: 18.0,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        onTap: () => onSelected(space, space),
      ),
    );
  }
}

bool _shouldIgnoreView(ViewPB view, ViewPB sourceView) {
  return view.id == sourceView.id;
}
