import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/plugins/database/calendar/application/calendar_unsaved_guard.dart';
import 'package:appflowy/plugins/space_hub/space_hub.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/menu/sidebar_sections_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/folder/folder_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/folder/_folder_header.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/create_space_popup.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_entry_style.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';

import 'package:appflowy_backend/log.dart';
import 'package:flowy_infra/platform_extension.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SectionFolder extends StatefulWidget {
  const SectionFolder({
    super.key,
    required this.title,
    required this.spaceType,
    required this.views,
    this.isHoverEnabled = true,
    required this.expandButtonTooltip,
    required this.addButtonTooltip,
    this.isTablet = false,
  });

  final String title;
  final FolderSpaceType spaceType;
  final List<ViewPB> views;
  final bool isHoverEnabled;
  final String expandButtonTooltip;
  final String addButtonTooltip;
  final bool isTablet;

  @override
  State<SectionFolder> createState() => _SectionFolderState();
}

class _SectionFolderState extends State<SectionFolder> {
  final isHovered = ValueNotifier(false);

  @override
  void dispose() {
    isHovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 自动检测平板设备，如果没有显式传递 isTablet 参数
    final bool isTablet = widget.isTablet || PlatformInfo.isTablet;

    return MouseRegion(
      onEnter: (_) => isHovered.value = true,
      onExit: (_) => isHovered.value = false,
      child: BlocProvider<FolderBloc>(
        create: (_) => FolderBloc(type: widget.spaceType)
          ..add(const FolderEvent.initial()),
        child: BlocBuilder<FolderBloc, FolderState>(
          builder: (context, state) => Column(
            children: [
              _buildHeader(context),
              ..._buildViews(context, state, isHovered),
              _buildDraggablePlaceholder(context, state, isHovered),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final parentViewId =
        context.read<UserWorkspaceBloc>().state.currentWorkspace?.workspaceId;

    final showCreateSpaceButton = widget.spaceType == FolderSpaceType.private ||
        widget.spaceType == FolderSpaceType.public;

    return FolderHeader(
      title: widget.title,
      isExpanded: context.watch<FolderBloc>().state.isExpanded,
      expandButtonTooltip: widget.expandButtonTooltip,
      addButtonTooltip: widget.addButtonTooltip,
      onPressed: () =>
          context.read<FolderBloc>().add(const FolderEvent.expandOrUnExpand()),
      onAdded: () {
        context.read<SidebarSectionsBloc>().add(
              SidebarSectionsEvent.createRootViewInSection(
                name: '',
                index: 0,
                viewSection: widget.spaceType.toViewSectionPB,
              ),
            );
        context
            .read<FolderBloc>()
            .add(const FolderEvent.expandOrUnExpand(isExpanded: true));
      },
      parentViewId: parentViewId,
      onViewSelected: _onViewSelected,
      showCreateSpaceButton: showCreateSpaceButton,
      onCreateSpace:
          showCreateSpaceButton ? () => _showCreateSpaceDialog(context) : null,
    );
  }

  void _showCreateSpaceDialog(BuildContext context) {
    final initialPermission = widget.spaceType == FolderSpaceType.private
        ? SpacePermission.private
        : SpacePermission.publicToAll;

    final spaceBloc = context.read<SpaceBloc>();
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: BlocProvider.value(
          value: spaceBloc,
          child: CreateSpacePopup(
            initialPermission: initialPermission,
            disablePermissionChange: true,
          ),
        ),
      ),
    );
  }

  void _onViewSelected(
    PluginBuilder pluginBuilder,
    String? name,
    List<int>? initialDataBytes,
    bool openAfterCreated,
    bool createNewView,
  ) async {
    final parentViewId =
        context.read<UserWorkspaceBloc>().state.currentWorkspace?.workspaceId;
    if (parentViewId == null) {
      return;
    }

    final String viewName;
    if (pluginBuilder.pluginType == PluginType.handwritingSaber) {
      viewName = '未命名手记';
    } else {
      viewName = pluginBuilder.layoutType?.defaultName ?? '';
    }

    final ext = <String, String>{};
    if (pluginBuilder.pluginType == PluginType.handwritingSaber) {
      ext['view_type'] = 'handwriting_saber';
    }

    final result = await ViewBackendService.createView(
      layoutType: pluginBuilder.layoutType!,
      parentViewId: parentViewId,
      name: viewName,
      openAfterCreate: openAfterCreated,
      initialDataBytes: initialDataBytes,
      index: 0,
      section: widget.spaceType.toViewSectionPB,
      ext: ext,
    );

    await result.fold(
      (view) async {
        if (!mounted) {
          return;
        }

        context
            .read<FolderBloc>()
            .add(const FolderEvent.expandOrUnExpand(isExpanded: true));

        if (pluginBuilder.layoutType == ViewLayoutPB.Folder) {
          await ViewBackendService.updateView(
            viewId: view.id,
            extra: '{"view_type": "folder"}',
          );
          await ViewBackendService.updateViewIcon(
            view: view,
            viewIcon: EmojiIconData.emoji('📂'),
          );
        } else if (pluginBuilder.layoutType == ViewLayoutPB.Notebook) {
          await ViewBackendService.updateView(
            viewId: view.id,
            extra: '{"view_type": "notebook"}',
          );
          await ViewBackendService.updateViewIcon(
            view: view,
            viewIcon: EmojiIconData.emoji('📓'),
          );
        }
      },
      (_) async {},
    );
  }

  Iterable<Widget> _buildViews(
    BuildContext context,
    FolderState state,
    ValueNotifier<bool> isHovered,
  ) {
    if (!state.isExpanded) {
      return const <Widget>[];
    }

    final itemLevel = 0;

    return widget.views.map((view) {
      final isSpace = view.isSpace;
      final shouldEnableTreeDrag =
          _supportsTreeDrag(widget.spaceType) && !isSpace;
      return ViewItem(
        key: ValueKey('${widget.spaceType.name} ${view.id}'),
        spaceType: widget.spaceType,
        engagedInExpanding: !isSpace,
        isFirstChild: view.id == widget.views.first.id,
        view: view,
        level: itemLevel,
        leftPadding: HomeSpaceViewSizes.leftPadding,
        isFeedback: false,
        isHovered: isHovered,
        isDraggable: shouldEnableTreeDrag,
        enableRightClickContext: true,
        shouldRenderChildren: !isSpace,
        shouldLoadChildViews: !isSpace,
        leftIconBuilder: isSpace
            ? (context, view) => SizedBox(width: HomeSpaceViewSizes.leftPadding)
            : null,
        isTablet: PlatformInfo.isTablet,
        onSelected: (viewContext, selectedView) {
          CalendarUnsavedGuard.instance.maybeConfirmLeave(
            viewContext,
            () {
              if (selectedView.isSpace) {
                final spaceBloc = context.read<SpaceBloc>();
                spaceBloc.add(SpaceEvent.open(space: selectedView));
                SpaceHubMiddlePanelController.reveal(selectedView.id);
                if (HardwareKeyboard.instance.isControlPressed) {
                  viewContext.read<TabsBloc>().openTab(selectedView);
                } else {
                  viewContext.read<TabsBloc>().openPlugin(selectedView);
                }
                return;
              }

              if (selectedView.id.isEmpty) {
                return;
              }

              // Open second-pane document items as tabs.
              viewContext.read<TabsBloc>().openTab(selectedView);
            },
          );
        },
        onTertiarySelected: (viewContext, selectedView) =>
            viewContext.read<TabsBloc>().openTab(selectedView),
        isHoverEnabled: widget.isHoverEnabled,
        style: sidebarViewItemStyle,
      );
    });
  }

  Widget _buildDraggablePlaceholder(
    BuildContext context,
    FolderState state,
    ValueNotifier<bool> isHovered,
  ) {
    if (!state.isExpanded ||
        !_supportsTreeDrag(widget.spaceType) ||
        widget.views.isNotEmpty) {
      return const SizedBox.shrink();
    }

    final parentViewId =
        context.read<UserWorkspaceBloc>().state.currentWorkspace?.workspaceId;
    if (parentViewId == null || parentViewId.isEmpty) {
      return const SizedBox.shrink();
    }

    final placeholderView = ViewPB()
      ..id = '__section_placeholder_${widget.spaceType.name}_$parentViewId'
      ..name = ''
      ..parentViewId = parentViewId
      ..layout = ViewLayoutPB.Document;

    final itemLevel = 0;

    return ViewItem(
      key: ValueKey('placeholder_${widget.spaceType.name}_$parentViewId'),
      view: placeholderView,
      parentView: null,
      spaceType: widget.spaceType,
      level: itemLevel,
      leftPadding: HomeSpaceViewSizes.leftPadding,
      isFeedback: false,
      isHovered: isHovered,
      isDraggable: false,
      isPlaceholder: true,
      enableRightClickContext: false,
      shouldRenderChildren: false,
      shouldLoadChildViews: false,
      onSelected: (_, __) {},
      isHoverEnabled: false,
      isTablet: PlatformInfo.isTablet,
    );
  }

  bool _supportsTreeDrag(FolderSpaceType spaceType) {
    return spaceType == FolderSpaceType.private ||
        spaceType == FolderSpaceType.public;
  }
}
