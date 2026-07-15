import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/sidebar/folder/folder_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_search_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
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

typedef MovePageMenuOnSelected = void Function(ViewPB space, ViewPB view);

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
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (publicSpaces.isNotEmpty) ...[
            _buildSectionHeader(LocaleKeys.space_publicPermission.tr()),
            ...publicSpaces.map(_buildSpaceGroup),
          ],
          if (privateSpaces.isNotEmpty) ...[
            if (publicSpaces.isNotEmpty) const VSpace(8),
            _buildSectionHeader(LocaleKeys.space_privatePermission.tr()),
            ...privateSpaces.map(_buildSpaceGroup),
          ],
        ],
      ),
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

  Widget _buildSpaceGroup(ViewPB space) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 空间根目录行：直接可点击，移动到空间根目录
        SizedBox(
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
            onTap: () => widget.onSelected(space, space),
          ),
        ),
        SpacePages(
          key: ValueKey(space.id),
          space: space,
          isHovered: isHoveredNotifier,
          isExpandedNotifier: isExpandedNotifier,
          shouldIgnoreView: (view) {
            if (_shouldIgnoreView(view, widget.sourceView)) {
              return IgnoreViewType.hide;
            }
            // 仅禁用数据库视图（Grid/Board/Calendar），
            // 允许 Document/Folder/Notebook/Whiteboard 作为移动目标
            if (view.layout.isDatabaseView) {
              return IgnoreViewType.disable;
            }
            return IgnoreViewType.none;
          },
          // hide the hover status and disable the editing actions
          disableSelectedStatus: true,
          // hide the ... and + buttons
          rightIconsBuilder: (context, view) => [],
          onSelected: (_, view) => widget.onSelected(space, view),
        ),
      ],
    );
  }
}

class _MovePageGroupedViews extends StatelessWidget {
  const _MovePageGroupedViews({required this.views, required this.onSelected});

  final List<ViewPB> views;
  final void Function(ViewPB view) onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: views
            .map(
              (view) => ViewItem(
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
              ),
            )
            .toList(),
      ),
    );
  }
}

bool _shouldIgnoreView(ViewPB view, ViewPB sourceView) {
  return view.id == sourceView.id;
}
