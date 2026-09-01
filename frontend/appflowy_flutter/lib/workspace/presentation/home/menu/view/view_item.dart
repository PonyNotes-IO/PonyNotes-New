import 'dart:async';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/mobile/presentation/home/space/mobile_space_list_refresh.dart';
import 'package:appflowy/workspace/application/favorite/favorite_bloc.dart';
import 'package:appflowy/workspace/application/menu/sidebar_sections_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/folder/folder_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/rename_view/rename_view_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/prelude.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/cross_space_move.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/draggable_view_item.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_action_type.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_add_button.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_more_action_button.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/manage_space_popup.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_entry_style.dart';
import 'package:appflowy/plugins/handwriting_saber/handwriting_saber.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/workspace/presentation/widgets/dialog_v2.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/widgets/lock_page_action.dart';
import 'package:appflowy/workspace/presentation/widgets/rename_view_popover.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart'
    hide AFRolePB;
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart'
    hide AFRolePB;
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/platform_extension.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/hover.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

typedef ViewItemOnSelected = void Function(BuildContext context, ViewPB view);
typedef ViewItemLeftIconBuilder = Widget Function(
  BuildContext context,
  ViewPB view,
);
typedef ViewItemRightIconsBuilder = List<Widget> Function(
  BuildContext context,
  ViewPB view,
);

enum IgnoreViewType { none, hide, disable }

class ViewItemStyle {
  final Color? selectedTextColor;
  final Color? selectedBackgroundColor;
  final Color? hoverColor;
  final Color? focusColor;

  const ViewItemStyle({
    this.selectedTextColor,
    this.selectedBackgroundColor,
    this.hoverColor,
    this.focusColor,
  });

  static ViewItemStyle defaultStyle(BuildContext context) {
    return ViewItemStyle(
      selectedTextColor: Theme.of(context).brightness == Brightness.light
          ? Theme.of(context).colorScheme.primary
          : const Color(0xFFFFFFFF),
      selectedBackgroundColor: Theme.of(context).brightness == Brightness.light
          ? Theme.of(context).colorScheme.secondary
          : const Color(0xFF383838),
      hoverColor: Theme.of(context).brightness == Brightness.light
          ? const Color(0xFFF1F0EF)
          : const Color(0xFF383838),
      focusColor: Theme.of(context).brightness == Brightness.light
          ? Color(0xFFF1F0EF)
          : Color(0xFF2C2C2C),
    );
  }

  ViewItemStyle copyWith({
    Color? selectedTextColor,
    Color? selectedBackgroundColor,
    Color? hoverColor,
    Color? focusColor,
  }) {
    return ViewItemStyle(
      selectedTextColor: selectedTextColor ?? this.selectedTextColor,
      selectedBackgroundColor:
          selectedBackgroundColor ?? this.selectedBackgroundColor,
      hoverColor: hoverColor ?? this.hoverColor,
      focusColor: focusColor ?? this.focusColor,
    );
  }
}

class ViewItem extends StatelessWidget {
  const ViewItem({
    super.key,
    required this.view,
    this.parentView,
    required this.spaceType,
    required this.level,
    this.leftPadding = 10,
    required this.onSelected,
    this.onTertiarySelected,
    this.isFirstChild = false,
    this.previousViewId,
    this.isDraggable = true,
    required this.isFeedback,
    this.height,
    this.isHoverEnabled = false,
    this.isPlaceholder = false,
    this.isHovered,
    this.shouldRenderChildren = true,
    this.leftIconBuilder,
    this.rightIconsBuilder,
    this.shouldLoadChildViews = true,
    this.isExpandedNotifier,
    this.extendBuilder,
    this.disableSelectedStatus,
    this.shouldIgnoreView,
    this.engagedInExpanding = false,
    this.enableRightClickContext = false,
    this.isTablet = false,

    /// 外部传入的选中状态，用于在局部列表中独立管理选中状态，避免监听全局状态
    this.isExternallySelected,
    this.externallySelectedViewId,
    this.onExpandedChanged,
    this.style,
  });

  final ViewPB view;
  final ViewPB? parentView;

  final FolderSpaceType spaceType;

  // indicate the level of the view item
  // used to calculate the left padding
  final int level;

  // the left padding of the view item for each level
  // the left padding of the each level = level * leftPadding
  final double leftPadding;

  // Selected by normal conventions
  final ViewItemOnSelected onSelected;

  // Selected by middle mouse button
  final ViewItemOnSelected? onTertiarySelected;

  // used for indicating the first child of the parent view, so that we can
  // add top border to the first child
  final bool isFirstChild;

  /// 同级列表中前一项的 id（首项为 null）。
  ///
  /// 拖拽排序时，「插到本项之前」在 folder 接口里表达为「插到前一项之后」
  /// （`prevViewId` 语义）。没有这个值就只能给出 `prevViewId = null`，
  /// 即永远插到列表最前面 —— 这正是此前只能拖到两端、无法插入任意位置的原因。
  final String? previousViewId;

  // it should be false when it's rendered as feedback widget inside DraggableItem
  final bool isDraggable;

  // identify if the view item is rendered as feedback widget inside DraggableItem
  final bool isFeedback;

  final double? height;

  final bool isHoverEnabled;

  // all the view movement depends on the [ViewItem] widget, so we have to add a
  // placeholder widget to receive the drop event when moving view across sections.
  final bool isPlaceholder;

  // used for control the expand/collapse icon
  final ValueNotifier<bool>? isHovered;

  // render the child views of the view
  final bool shouldRenderChildren;

  // custom the left icon widget, if it's null, the default expand/collapse icon will be used
  final ViewItemLeftIconBuilder? leftIconBuilder;

  // custom the right icon widget, if it's null, the default ... and + button will be used
  final ViewItemRightIconsBuilder? rightIconsBuilder;

  final bool shouldLoadChildViews;
  final PropertyValueNotifier<bool>? isExpandedNotifier;

  final List<Widget> Function(ViewPB view)? extendBuilder;

  // disable the selected status of the view item
  final bool? disableSelectedStatus;

  // ignore the views when rendering the child views
  final IgnoreViewType Function(ViewPB view)? shouldIgnoreView;

  /// Whether to add right-click to show the view action context menu
  ///
  final bool enableRightClickContext;

  /// to record the ViewBlock which is expanded or collapsed
  final bool engagedInExpanding;

  /// Whether the device is a tablet (no hover effect)
  final bool isTablet;

  /// 外部传入的选中状态，用于在局部列表中独立管理选中状态，避免监听全局状态
  /// 当此参数不为 null 时，将使用此值作为选中状态，而不是监听 MenuSharedState
  final bool? isExternallySelected;

  /// 递归列表使用同一个 ID 判断选中项，避免子项回退到全局选中状态。
  final String? externallySelectedViewId;

  final VoidCallback? onExpandedChanged;

  final ViewItemStyle? style;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ViewBloc(
        view: view,
        shouldLoadChildViews: shouldLoadChildViews,
        engagedInExpanding: engagedInExpanding,
      )..add(const ViewEvent.initial()),
      child: BlocConsumer<ViewBloc, ViewState>(
        listenWhen: (p, c) {
          final newView = c.lastCreatedView;
          final oldId = p.lastCreatedView?.id;
          return newView != null && oldId != newView.id;
        },
        listener: (context, state) {
          final created = state.lastCreatedView;
          if (created == null) return;
          // Guard: only open plugin automatically when view has been annotated as handwriting_saber
          // to avoid opening a plugin too early before extra metadata is set.
          final extra = created.extra;
          final bool isHandwriting = extra.contains('handwriting_saber');
          if (isHandwriting) {
            context.read<TabsBloc>().openPlugin(created);
          } else {
            Log.info(
                '🔵 [VIEW_ITEM] Skipping auto-open for created view ${created.id}, extra=$extra');
          }
        },
        builder: (context, state) {
          // filter the child views that should be ignored
          List<ViewPB> childViews = state.view.childViews;
          if (shouldIgnoreView != null) {
            childViews = childViews
                .where((v) => shouldIgnoreView!(v) != IgnoreViewType.hide)
                .toList();
          }

          final itemHeight = height ?? HomeSpaceViewSizes.viewHeight;
          final Widget child = InnerViewItem(
            view: state.view,
            parentView: parentView,
            childViews: childViews,
            spaceType: spaceType,
            level: level,
            leftPadding: leftPadding,
            showActions: state.isEditing,
            enableRightClickContext: enableRightClickContext,
            isExpanded: state.isExpanded,
            disableSelectedStatus: disableSelectedStatus,
            onSelected: onSelected,
            onTertiarySelected: onTertiarySelected,
            isFirstChild: isFirstChild,
            previousViewId: previousViewId,
            isDraggable: isDraggable,
            isFeedback: isFeedback,
            height: itemHeight,
            isHoverEnabled: isHoverEnabled,
            isPlaceholder: isPlaceholder,
            isHovered: isHovered,
            shouldRenderChildren: shouldRenderChildren,
            leftIconBuilder: leftIconBuilder,
            rightIconsBuilder: rightIconsBuilder,
            isExpandedNotifier: isExpandedNotifier,
            extendBuilder: extendBuilder,
            shouldIgnoreView: shouldIgnoreView,
            engagedInExpanding: engagedInExpanding,
            isTablet: isTablet,
            isExternallySelected: isExternallySelected,
            externallySelectedViewId: externallySelectedViewId,
            onExpandedChanged: onExpandedChanged,
            style: style,
          );

          if (shouldIgnoreView?.call(view) == IgnoreViewType.disable) {
            return Opacity(
              opacity: 0.5,
              child: FlowyTooltip(
                message: LocaleKeys.space_cannotMovePageToDatabase.tr(),
                child: MouseRegion(
                  cursor: SystemMouseCursors.forbidden,
                  child: IgnorePointer(child: child),
                ),
              ),
            );
          }

          return child;
        },
      ),
    );
  }
}

// TODO: We shouldn't have local global variables
bool _isDragging = false;

class InnerViewItem extends StatefulWidget {
  const InnerViewItem({
    super.key,
    required this.view,
    required this.parentView,
    required this.childViews,
    required this.spaceType,
    this.isDraggable = true,
    this.isExpanded = true,
    required this.level,
    required this.leftPadding,
    required this.showActions,
    this.enableRightClickContext = false,
    required this.onSelected,
    this.onTertiarySelected,
    this.isFirstChild = false,
    this.previousViewId,
    required this.isFeedback,
    required this.height,
    this.isHoverEnabled = true,
    this.isPlaceholder = false,
    this.isHovered,
    this.shouldRenderChildren = true,
    required this.leftIconBuilder,
    required this.rightIconsBuilder,
    this.isExpandedNotifier,
    required this.extendBuilder,
    this.disableSelectedStatus,
    this.engagedInExpanding = false,
    required this.shouldIgnoreView,
    this.isTablet = false,
    this.isExternallySelected,
    this.externallySelectedViewId,
    this.onExpandedChanged,
    this.style,
  });

  final ViewPB view;
  final ViewPB? parentView;
  final List<ViewPB> childViews;
  final FolderSpaceType spaceType;

  final bool isDraggable;
  final bool isExpanded;
  final bool isFirstChild;
  final String? previousViewId;

  // identify if the view item is rendered as feedback widget inside DraggableItem
  final bool isFeedback;

  final int level;
  final double leftPadding;

  final bool showActions;
  final bool enableRightClickContext;
  final ViewItemOnSelected onSelected;
  final ViewItemOnSelected? onTertiarySelected;
  final double height;

  final bool isHoverEnabled;
  final bool isPlaceholder;
  final bool? disableSelectedStatus;
  final ValueNotifier<bool>? isHovered;
  final bool shouldRenderChildren;
  final ViewItemLeftIconBuilder? leftIconBuilder;
  final ViewItemRightIconsBuilder? rightIconsBuilder;

  final PropertyValueNotifier<bool>? isExpandedNotifier;
  final List<Widget> Function(ViewPB view)? extendBuilder;
  final IgnoreViewType Function(ViewPB view)? shouldIgnoreView;
  final bool engagedInExpanding;

  /// Whether the device is a tablet (no hover effect)
  final bool isTablet;

  /// 外部传入的选中状态，用于在局部列表中独立管理选中状态，避免监听全局状态
  /// 当此参数不为 null 时，将使用此值作为选中状态，而不是监听 MenuSharedState
  final bool? isExternallySelected;

  final String? externallySelectedViewId;

  final VoidCallback? onExpandedChanged;

  final ViewItemStyle? style;

  @override
  State<InnerViewItem> createState() => _InnerViewItemState();
}

class _InnerViewItemState extends State<InnerViewItem> {
  @override
  Widget build(BuildContext context) {
    final externallySelected = widget.externallySelectedViewId != null
        ? widget.externallySelectedViewId == widget.view.id
        : widget.isExternallySelected;

    // 如果外部传入了选中状态，则直接使用，不监听全局状态
    Widget child;
    if (externallySelected != null) {
      child = SingleInnerViewItem(
        view: widget.view,
        parentView: widget.parentView,
        level: widget.level,
        showActions: widget.showActions,
        enableRightClickContext: widget.enableRightClickContext,
        spaceType: widget.spaceType,
        onSelected: widget.onSelected,
        onTertiarySelected: widget.onTertiarySelected,
        isExpanded: widget.isExpanded,
        isDraggable: widget.isDraggable,
        leftPadding: widget.leftPadding,
        isFeedback: widget.isFeedback,
        height: widget.height,
        isPlaceholder: widget.isPlaceholder,
        isHovered: widget.isHovered,
        leftIconBuilder: widget.leftIconBuilder,
        rightIconsBuilder: widget.rightIconsBuilder,
        extendBuilder: widget.extendBuilder,
        disableSelectedStatus: widget.disableSelectedStatus,
        shouldIgnoreView: widget.shouldIgnoreView,
        isSelected: externallySelected,
        isTablet: widget.isTablet,
        onExpandedChanged: widget.onExpandedChanged,
        style: widget.style,
      );
    } else {
      // 否则监听全局状态
      child = ValueListenableBuilder(
        valueListenable: getIt<MenuSharedState>().notifier,
        builder: (context, value, _) {
          final isSelected = value?.id == widget.view.id;
          return SingleInnerViewItem(
            view: widget.view,
            parentView: widget.parentView,
            level: widget.level,
            showActions: widget.showActions,
            enableRightClickContext: widget.enableRightClickContext,
            spaceType: widget.spaceType,
            onSelected: widget.onSelected,
            onTertiarySelected: widget.onTertiarySelected,
            isExpanded: widget.isExpanded,
            isDraggable: widget.isDraggable,
            leftPadding: widget.leftPadding,
            isFeedback: widget.isFeedback,
            height: widget.height,
            isPlaceholder: widget.isPlaceholder,
            isHovered: widget.isHovered,
            leftIconBuilder: widget.leftIconBuilder,
            rightIconsBuilder: widget.rightIconsBuilder,
            extendBuilder: widget.extendBuilder,
            disableSelectedStatus: widget.disableSelectedStatus,
            shouldIgnoreView: widget.shouldIgnoreView,
            isSelected: isSelected,
            isTablet: widget.isTablet,
            onExpandedChanged: widget.onExpandedChanged,
            style: widget.style,
          );
        },
      );
    }

    // if the view is expanded and has child views, render its child views
    if (widget.isExpanded &&
        widget.shouldRenderChildren &&
        widget.childViews.isNotEmpty) {
      final children = widget.childViews.asMap().entries.map((entry) {
        final index = entry.key;
        final childView = entry.value;
        return ViewItem(
          key: ValueKey('${widget.spaceType.name} ${childView.id}'),
          parentView: widget.view,
          spaceType: widget.spaceType,
          isFirstChild: index == 0,
          previousViewId: index > 0 ? widget.childViews[index - 1].id : null,
          view: childView,
          level: widget.level + 1,
          enableRightClickContext: widget.enableRightClickContext,
          onSelected: widget.onSelected,
          onTertiarySelected: widget.onTertiarySelected,
          isDraggable: widget.isDraggable,
          disableSelectedStatus: widget.disableSelectedStatus,
          leftPadding: widget.leftPadding,
          isFeedback: widget.isFeedback,
          isPlaceholder: widget.isPlaceholder,
          isHovered: widget.isHovered,
          leftIconBuilder: widget.leftIconBuilder,
          rightIconsBuilder: widget.rightIconsBuilder,
          extendBuilder: widget.extendBuilder,
          shouldIgnoreView: widget.shouldIgnoreView,
          engagedInExpanding: widget.engagedInExpanding,
          isTablet: widget.isTablet,
          externallySelectedViewId: widget.externallySelectedViewId,
          onExpandedChanged: widget.onExpandedChanged,
          style: widget.style,
        );
      }).toList();

      child = Column(
        mainAxisSize: MainAxisSize.min,
        children: [child, ...children],
      );
    }

    // wrap the child with DraggableItem if isDraggable is true
    if ((widget.isDraggable || widget.isPlaceholder) &&
        !isReferencedDatabaseView(widget.view, widget.parentView)) {
      child = DraggableViewItem(
        isFirstChild: widget.isFirstChild,
        previousViewId: widget.previousViewId,
        view: widget.view,
        onDragging: (isDragging) => _isDragging = isDragging,
        onMove: widget.isPlaceholder
            ? (from, to) => moveViewToSectionPlaceholder(
                  context,
                  widget.spaceType,
                  from,
                  to.parentViewId,
                )
            : null,
        feedback: (context) => Container(
          width: 250,
          decoration: BoxDecoration(
            color: Brightness.light == Theme.of(context).brightness
                ? Colors.white
                : Colors.black54,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ViewItem(
            view: widget.view,
            parentView: widget.parentView,
            spaceType: widget.spaceType,
            level: widget.level,
            onSelected: widget.onSelected,
            onTertiarySelected: widget.onTertiarySelected,
            isDraggable: false,
            leftPadding: widget.leftPadding,
            isFeedback: true,
            enableRightClickContext: widget.enableRightClickContext,
            leftIconBuilder: widget.leftIconBuilder,
            rightIconsBuilder: widget.rightIconsBuilder,
            extendBuilder: widget.extendBuilder,
            shouldIgnoreView: widget.shouldIgnoreView,
          ),
        ),
        child: child,
      );
    } else {
      // keep the same height of the DraggableItem
      child = Padding(
        padding: const EdgeInsets.only(top: kDraggableViewItemDividerHeight),
        child: child,
      );
    }

    return child;
  }
}

class SingleInnerViewItem extends StatefulWidget {
  const SingleInnerViewItem({
    super.key,
    required this.view,
    required this.parentView,
    required this.isExpanded,
    required this.level,
    required this.leftPadding,
    this.isDraggable = true,
    required this.spaceType,
    required this.showActions,
    this.enableRightClickContext = false,
    required this.onSelected,
    this.onTertiarySelected,
    required this.isFeedback,
    required this.height,
    this.isHoverEnabled = true,
    this.isPlaceholder = false,
    this.isHovered,
    required this.leftIconBuilder,
    required this.rightIconsBuilder,
    required this.extendBuilder,
    required this.disableSelectedStatus,
    required this.shouldIgnoreView,
    required this.isSelected,
    this.isTablet = false,
    this.onExpandedChanged,
    this.style,
  });

  final ViewPB view;
  final ViewPB? parentView;
  final bool isExpanded;

  // identify if the view item is rendered as feedback widget inside DraggableItem
  final bool isFeedback;

  final int level;
  final double leftPadding;

  final bool isDraggable;
  final bool showActions;
  final bool enableRightClickContext;
  final ViewItemOnSelected onSelected;
  final ViewItemOnSelected? onTertiarySelected;
  final FolderSpaceType spaceType;
  final double height;

  final bool isHoverEnabled;
  final bool isPlaceholder;
  final bool? disableSelectedStatus;
  final ValueNotifier<bool>? isHovered;
  final ViewItemLeftIconBuilder? leftIconBuilder;
  final ViewItemRightIconsBuilder? rightIconsBuilder;

  final List<Widget> Function(ViewPB view)? extendBuilder;
  final IgnoreViewType Function(ViewPB view)? shouldIgnoreView;
  final bool isSelected;

  /// Whether the device is a tablet (no hover effect)
  final bool isTablet;

  final VoidCallback? onExpandedChanged;

  final ViewItemStyle? style;

  @override
  State<SingleInnerViewItem> createState() => _SingleInnerViewItemState();
}

class _SingleInnerViewItemState extends State<SingleInnerViewItem> {
  final controller = PopoverController();
  final viewMoreActionController = PopoverController();
  final TextEditingController _renameController = TextEditingController();
  final FocusNode _renameFocusNode = FocusNode();

  bool isIconPickerOpened = false;
  bool isRenaming = false;

  /// 当前用户是否为受限成员（Guest）
  /// 由 build() 中 context.watch 驱动重建，确保 role 变化时 UI 实时更新
  late bool _isRestrictedMember;

  late final ViewListener _viewListener;
  late ViewPB _view;

  @override
  void initState() {
    super.initState();
    _view = widget.view;
    _viewListener = ViewListener(viewId: widget.view.id);
    _viewListener.start(
      onViewUpdated: (updatedView) {
        if (mounted) {
          setState(() => _view = updatedView);
        }
      },
    );
  }

  @override
  void dispose() {
    _viewListener.stop();
    _renameController.dispose();
    _renameFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // context.watch 确保 role 变化时 widget 重建，实时更新权限状态
    try {
      _isRestrictedMember =
          context.watch<UserWorkspaceBloc>().state.currentUserRole ==
              AFRolePB.Guest;
    } catch (_) {
      _isRestrictedMember = false;
    }

    bool isSelected = widget.isSelected;

    if (widget.disableSelectedStatus == true) {
      isSelected = false;
    }

    if (widget.isPlaceholder) {
      return const SizedBox(height: 4, width: double.infinity);
    }

    if (widget.isFeedback || !widget.isHoverEnabled) {
      return _buildViewItem(
        false,
        !widget.isHoverEnabled ? isSelected : false,
      );
    }

    final style = widget.style ?? ViewItemStyle.defaultStyle(context);
    return FlowyHover(
      style: HoverStyle(
        hoverColor:
            isSelected ? style.selectedBackgroundColor : style.hoverColor,
        foregroundColorOnHover: isSelected ? style.selectedTextColor : null,
      ),
      resetHoverOnRebuild: widget.showActions || !isIconPickerOpened,
      buildWhenOnHover: () =>
          !widget.showActions &&
          !_isDragging &&
          !isIconPickerOpened &&
          !isRenaming,
      isSelected: () => widget.showActions || isSelected,
      builder: (_, onHover) => _buildViewItem(onHover, isSelected),
    );
  }

  Widget _buildViewItem(bool onHover, [bool isSelected = false]) {
    final style = widget.style ?? ViewItemStyle.defaultStyle(context);
    final nameWidget =
        isRenaming ? _buildInlineRenameField() : _buildNameText();

    final children = [
      widget.leftIconBuilder?.call(context, _view) ?? _buildLeftIcon(),
      _buildViewIconButton(),
      const HSpace(4),
      Expanded(
        child: widget.extendBuilder != null
            ? Row(
                children: [
                  Flexible(child: nameWidget),
                  ...widget.extendBuilder!(_view),
                ],
              )
            : nameWidget,
      ),
    ];

    if (widget.showActions || onHover || widget.isTablet) {
      if (widget.rightIconsBuilder != null) {
        children.addAll(widget.rightIconsBuilder!(context, _view));
      } else {
        if (!_isRestrictedMember) {
          children.add(
            _buildViewMoreActionButton(
              context,
              viewMoreActionController,
              (_) => FlowyTooltip(
                message: LocaleKeys.menuAppHeader_moreButtonToolTip.tr(),
                child: FlowyIconButton(
                  width: 24,
                  icon: const FlowySvg(FlowySvgs.workspace_three_dots_s),
                  onPressed: viewMoreActionController.show,
                ),
              ),
            ),
          );
        }
        if (_view.layout == ViewLayoutPB.Document ||
            _view.layout == ViewLayoutPB.Folder ||
            _view.layout == ViewLayoutPB.Notebook) {
          children.add(const HSpace(8.0));
          children.add(_buildViewAddButton(context));
        }
        children.add(const HSpace(4.0));
      }
    }

    final rowChild = SizedBox(
      height: widget.height,
      child: Padding(
        padding: EdgeInsets.only(left: widget.level * widget.leftPadding),
        child: Listener(
          onPointerDown: (event) {
            if (event.buttons == kSecondaryMouseButton &&
                widget.enableRightClickContext) {
              if (_isRestrictedMember) {
                showToastNotification(
                  message: '无权限',
                  type: ToastificationType.warning,
                );
                return;
              }
              viewMoreActionController.showAt(
                event.position + const Offset(4, 0),
              );
            }
          },
          behavior: HitTestBehavior.opaque,
          child: Row(children: children),
        ),
      ),
    );

    // 鼠标悬停时在行的左外侧显示拖拽手柄，提示该条目可以拖动排序。
    //
    // 用 Positioned + Clip.none 叠在布局之外，而不是塞进 Row 的第一位：
    // 手柄只在 hover 时出现，若参与布局会让整行在鼠标移入/移出时横向跳动。
    // 手柄本身不接收命中测试，拖拽仍由外层 DraggableViewItem 对整行负责 ——
    // 它只是可拖动的视觉提示，不改变任何交互范围。
    final rowWithDragHandle =
        !widget.isDraggable || widget.isFeedback || widget.isPlaceholder
            ? rowChild
            : Stack(
                clipBehavior: Clip.none,
                children: [
                  rowChild,
                  if (onHover)
                    Positioned(
                      left: -13,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: FlowyTooltip(
                          message: LocaleKeys.blockActions_dragTooltip.tr(),
                          child: Opacity(
                            opacity: 0.55,
                            child: const FlowySvg(
                              FlowySvgs.drag_element_s,
                              size: Size.square(12),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );

    Widget child = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => widget.onSelected(context, _view),
      onTertiaryTapDown: (_) => widget.onTertiarySelected?.call(context, _view),
      child: rowWithDragHandle,
    );

    if (isSelected) {
      final popoverController = getIt<RenameViewBloc>().state.controller;
      child = AppFlowyPopover(
        controller: popoverController,
        triggerActions: PopoverTriggerFlags.none,
        offset: const Offset(0, 5),
        direction: PopoverDirection.bottomWithLeftAligned,
        popupBuilder: (_) => RenameViewPopover(
          view: _view,
          name: _view.name,
          emoji: _view.icon.toEmojiIconData(),
          popoverController: popoverController,
          showIconChanger: false,
        ),
        child: child,
      );
    }

    return child;
  }

  Widget _buildViewIconButton() {
    final iconData = _view.icon.toEmojiIconData();
    final icon = iconData.isNotEmpty
        ? RawEmojiIconWidget(
            emoji: iconData,
            emojiSize: 16.0,
            lineHeight: 18.0 / 16.0,
          )
        : Opacity(opacity: 0.6, child: _view.defaultIcon());

    final Widget child = AppFlowyPopover(
      offset: const Offset(20, 0),
      controller: controller,
      direction: PopoverDirection.rightWithCenterAligned,
      constraints: BoxConstraints.loose(const Size(364, 356)),
      margin: const EdgeInsets.all(0),
      onClose: () => setState(() => isIconPickerOpened = false),
      child: GestureDetector(
        // prevent the tap event from being passed to the parent widget
        onTap: () {},
        child: FlowyTooltip(
          message: LocaleKeys.document_plugins_cover_changeIcon.tr(),
          child: SizedBox(width: 16.0, child: icon),
        ),
      ),
      popupBuilder: (context) {
        isIconPickerOpened = true;
        return FlowyIconEmojiPicker(
          initialType: iconData.type.toPickerTabType(),
          tabs: const [
            PickerTabType.emoji,
            PickerTabType.icon,
            PickerTabType.custom,
          ],
          documentId: _view.id,
          onSelectedEmoji: (r) {
            ViewBackendService.updateViewIcon(
              view: _view,
              viewIcon: r.data,
            );
            if (!r.keepOpen) controller.close();
          },
        );
      },
    );

    if (_view.isLocked) {
      return LockPageButtonWrapper(
        child: child,
      );
    }

    return child;
  }

  Widget _buildNameText() {
    bool isSelected = widget.isSelected;
    if (widget.disableSelectedStatus == true) {
      isSelected = false;
    }

    final style = widget.style ?? ViewItemStyle.defaultStyle(context);
    final textStyle = sidebarEntryTextStyle(context).copyWith(
      color: isSelected ? style.selectedTextColor : null,
    );

    return GestureDetector(
      onDoubleTap: () {
        _startRenaming();
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 28),
        child: Text(
          _view.nameOrDefault,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: textStyle,
          strutStyle: StrutStyle.fromTextStyle(
            textStyle,
            forceStrutHeight: true,
            height: 1.35,
            leadingDistribution: TextLeadingDistribution.even,
          ),
        ),
      ),
    );
  }

  Widget _buildInlineRenameField() {
    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _cancelRenaming();
        }
      },
      child: SizedBox(
        height: 24.0,
        child: TextField(
          controller: _renameController,
          focusNode: _renameFocusNode,
          style: const TextStyle(
            fontSize: 12.0,
            height: 1.35,
            fontWeight: FontWeight.w800,
            leadingDistribution: TextLeadingDistribution.even,
          ),
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4.0),
              borderSide:
                  BorderSide(color: Theme.of(context).colorScheme.primary),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4.0),
              borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary, width: 2.0),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 6.0),
            isDense: true,
            counterText: '',
          ),
          maxLength: 256,
          onSubmitted: _finishRenaming,
        ),
      ),
    );
  }

  void _startRenaming() {
    setState(() {
      isRenaming = true;
      _renameController.text = _view.nameOrDefault;
      _renameController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _view.nameOrDefault.length,
      );
    });
    // 延迟聚焦以确保TextField已经构建
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _renameFocusNode.requestFocus();
    });

    // 监听焦点丢失事件
    _renameFocusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_renameFocusNode.hasFocus && isRenaming) {
      _finishRenaming(_renameController.text);
      _renameFocusNode.removeListener(_onFocusChange);
    }
  }

  Future<void> _finishRenaming(String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      showToastNotification(
        message: LocaleKeys.web_error_pageNameCannotBeEmpty.tr(),
      );
    } else if (trimmed != _view.nameOrDefault) {
      await ViewBackendService.updateView(
        viewId: _view.id,
        name: trimmed,
      );
      if (mounted) {
        _refreshSpaceBlocIfNeeded(context);
      }
    }
    if (mounted) {
      setState(() {
        isRenaming = false;
      });
    }
  }

  void _cancelRenaming() {
    setState(() {
      isRenaming = false;
    });
  }

  // > button or · button
  // show > if the view is expandable.
  // show · if the view can't contain child views.
  Widget _buildLeftIcon() {
    return ViewItemDefaultLeftIcon(
      view: _view,
      parentView: widget.parentView,
      isExpanded: widget.isExpanded,
      leftPadding: widget.leftPadding,
      isHovered: widget.isHovered,
      onExpandedChanged: widget.onExpandedChanged,
    );
  }

  // + button
  Widget _buildViewAddButton(BuildContext context) {
    // 受限成员按钮禁用（保留在 tree 中，context.watch 实时响应权限变化）
    return FlowyTooltip(
      message: _isRestrictedMember
          ? '无权限'
          : LocaleKeys.menuAppHeader_addPageTooltip.tr(),
      child: ViewAddButton(
        parentViewId: _view.id,
        onEditing: (value) =>
            context.read<ViewBloc>().add(ViewEvent.setIsEditing(value)),
        onSelected: _onSelected,
        enabled: !_isRestrictedMember,
      ),
    );
  }

  void _onSelected(
    PluginBuilder pluginBuilder,
    String? name,
    List<int>? initialDataBytes,
    bool openAfterCreated,
    bool createNewView,
  ) async {
    // debug logs removed
    final viewBloc = context.read<ViewBloc>();
    // 如果是 HandwritingSaberPluginBuilder，使用"未命名手记"作为默认名称
    final isHandwritingSaber =
        pluginBuilder.pluginType == PluginType.handwritingSaber;
    final viewName = isHandwritingSaber
        ? '未命名手记'
        : (pluginBuilder.layoutType?.defaultName ?? '');

    // debug logs removed

    // 如果是 Saber 手写视图，需要先创建视图，然后立即更新 extra 字段
    // 否则，直接通过 ViewBloc 创建视图
    if (isHandwritingSaber) {
      // Saber 手写视图：直接调用 ViewBackendService.createView 创建文档，
      // 然后通过 updateView 把 view_type 写入 extra，供 ViewExtension.plugin() 识别
      final parentViewId = _view.id;
      Log.info(
        '🔵 [VIEW_ITEM] Creating handwriting_saber view via ViewBackendService.createView, parentViewId: $parentViewId',
      );

      final result = await ViewBackendService.createView(
        parentViewId: parentViewId,
        name: viewName,
        layoutType: pluginBuilder.layoutType!,
        openAfterCreate: openAfterCreated,
        section: widget.spaceType.toViewSectionPB,
        index: 0,
        // Ensure the backend receives view_type at creation time to avoid race where
        // the view is opened before extra metadata (view_type) is set.
        ext: const {'view_type': 'handwriting_saber'},
      );

      // If the widget has been unmounted while waiting for createView, skip further UI actions.
      if (!context.mounted) {
        Log.error(
            '🔵 [VIEW_ITEM] Widget unmounted after createView returned, skipping UI open actions');
        // Still ensure ViewBloc state is updated with created view if possible
        await result.fold(
          (createdView) async {
            viewBloc.add(
              ViewEvent.viewDidUpdate(FlowyResult.success(createdView)),
            );
          },
          (error) async {
            viewBloc.add(ViewEvent.viewDidUpdate(FlowyResult.failure(error)));
          },
        );
        return;
      }

      await result.fold(
        (createdView) async {
          // debug log removed

          const extraJson = '{"view_type": "handwriting_saber"}';
          final updateResult = await ViewBackendService.updateView(
            viewId: createdView.id,
            extra: extraJson,
          );

          updateResult.fold(
            (_) {
              // Note: FolderEventUpdateView returns void on success. Use the createdView
              // object (which contains the real id) when opening the plugin.
              // debug log removed
              // ensure the local createdView carries the extra so plugin selection
              // will pick HandwritingSaber immediately (avoid race where backend
              // hasn't yet propagated extra to returned view)
              try {
                createdView.extra = extraJson;
              } catch (_) {}
              viewBloc.add(
                ViewEvent.viewDidUpdate(FlowyResult.success(createdView)),
              );
              if (openAfterCreated) {
                // debug log removed
                try {
                  getIt<TabsBloc>().openPlugin(createdView);
                } catch (e) {
                  Log.error(
                      '🔵 [VIEW_ITEM] Failed to open plugin globally for ${createdView.id}: $e');
                }
              }
            },
            (error) {
              Log.error(
                '❌ [VIEW_ITEM] Failed to set extra for handwriting_saber view: ${createdView.id}, error=${error.msg}',
              );
              // even if update failed, set extra locally so the client will render
              // HandwritingSaber instead of DocumentPlugin
              try {
                createdView.extra = extraJson;
              } catch (_) {}
              viewBloc.add(
                ViewEvent.viewDidUpdate(FlowyResult.success(createdView)),
              );
              if (openAfterCreated) {
                try {
                  getIt<TabsBloc>().openPlugin(createdView);
                } catch (e) {
                  Log.warn(
                      '🔵 [VIEW_ITEM] Failed to open plugin globally for ${createdView.id}: $e');
                }
              }
            },
          );
        },
        (error) async {
          Log.error(
            '❌ [VIEW_ITEM] Failed to create handwriting_saber view: ${error.msg}',
          );
          viewBloc.add(ViewEvent.viewDidUpdate(FlowyResult.failure(error)));
        },
      );
    } else {
      // 非 Saber 视图，直接通过 ViewBloc 创建
      viewBloc.add(
        ViewEvent.createView(
          viewName,
          pluginBuilder.layoutType!,
          openAfterCreated: openAfterCreated,
          section: widget.spaceType.toViewSectionPB,
        ),
      );
    }

    viewBloc.add(const ViewEvent.setIsExpanded(true));
  }

  /// 刷新 SpaceBloc 的列表（如果存在）
  /// 用于在删除、重命名、复制等操作后更新空间文档列表
  void _refreshSpaceBlocIfNeeded(BuildContext context) {
    try {
      // 尝试从外层 context 获取 SpaceBloc
      SpaceBloc? spaceBloc;

      // 方法1: 尝试从当前 context 读取（可能是外层提供的）
      try {
        spaceBloc = context.read<SpaceBloc>();
      } catch (_) {
        // 方法2: 通过 Navigator 获取根 context
        try {
          final navigator = Navigator.of(context, rootNavigator: false);
          final rootContext = navigator.context;
          spaceBloc = rootContext.read<SpaceBloc>();
        } catch (_) {
          // 根 context 也没有 SpaceBloc，忽略
        }
      }

      if (spaceBloc != null && !spaceBloc.isClosed) {
        spaceBloc.add(const SpaceEvent.didReceiveSpaceUpdate());
      }
    } catch (_) {
      // SpaceBloc 不存在，忽略
    }
  }

  // ··· more action button
  Widget _buildViewMoreActionButton(
    BuildContext context,
    PopoverController controller,
    Widget Function(PopoverController) buildChild,
  ) {
    // 尝试获取外层的 SpaceBloc，如果不存在则创建新的
    SpaceBloc? outerSpaceBloc;
    try {
      outerSpaceBloc = context.read<SpaceBloc>();
    } catch (_) {
      // 外层没有 SpaceBloc，需要创建新的
      try {
        final userWorkspaceBloc = context.read<UserWorkspaceBloc>();
        final userProfile = userWorkspaceBloc.state.userProfile;
        final workspaceId =
            userWorkspaceBloc.state.currentWorkspace?.workspaceId ?? '';
        if (workspaceId.isNotEmpty) {
          outerSpaceBloc = SpaceBloc(
            userProfile: userProfile,
            workspaceId: workspaceId,
          )..add(const SpaceEvent.initial(openFirstPage: false));
        }
      } catch (_) {
        // 无法创建 SpaceBloc
      }
    }

    Widget child = BlocListener<ViewBloc, ViewState>(
      listenWhen: (prev, curr) {
        // 只在删除状态变化或操作成功时触发
        return prev.isDeleted != curr.isDeleted ||
            (prev.successOrFailure.isFailure &&
                curr.successOrFailure.isSuccess);
      },
      listener: (context, state) {
        // 监听删除成功状态，刷新 SpaceBloc
        if (state.isDeleted) {
          // 延迟一下，确保后端删除操作完成
          // 增加延迟时间，确保最后一条文档删除后也能刷新
          Future.delayed(const Duration(milliseconds: 500), () {
            if (context.mounted) {
              _refreshSpaceBlocIfNeeded(context);
            }
          });
        }
        // 监听视图更新（重命名、复制等），刷新 SpaceBloc
        // 使用 fold 检查操作是否成功
        state.successOrFailure.fold(
          (success) {
            // 操作成功，刷新列表
            // 延迟一下，确保后端操作完成
            Future.delayed(const Duration(milliseconds: 300), () {
              if (context.mounted) {
                _refreshSpaceBlocIfNeeded(context);
              }
            });
          },
          (error) {
            // 操作失败，不刷新
          },
        );
      },
      child: ViewMoreActionPopover(
        view: _view,
        controller: controller,
        isExpanded: widget.isExpanded,
        spaceType: widget.spaceType,
        onEditing: (value) =>
            context.read<ViewBloc>().add(ViewEvent.setIsEditing(value)),
        buildChild: buildChild,
        onAction: (action, data) async {
          switch (action) {
            case ViewMoreActionType.favorite:
            case ViewMoreActionType.unFavorite:
              context.read<FavoriteBloc>().add(FavoriteEvent.toggle(_view));
              break;
            case ViewMoreActionType.rename:
              // 如果是 Space 类型，显示弹框重命名
              if (_view.isSpace) {
                await showAFTextFieldDialog(
                  context: context,
                  title: LocaleKeys.space_rename.tr(),
                  initialValue: _view.name,
                  hintText: LocaleKeys.space_spaceName.tr(),
                  onConfirm: (name) {
                    if (context.mounted) {
                      context.read<SpaceBloc>().add(
                            SpaceEvent.rename(
                              space: _view,
                              name: name,
                            ),
                          );
                      // 重命名后刷新列表
                      _refreshSpaceBlocIfNeeded(context);
                    }
                  },
                );
              } else {
                // 非 Space 类型使用内联编辑
                _startRenaming();
                // 重命名后刷新列表（内联编辑完成后会触发 ViewBloc 更新）
              }
              break;
            case ViewMoreActionType.leaveWorkspace:
              // 离开工作区
              if (context.mounted) {
                final workspaceId = context
                    .read<UserWorkspaceBloc>()
                    .state
                    .currentWorkspace
                    ?.workspaceId;
                if (workspaceId != null) {
                  context.read<UserWorkspaceBloc>().add(
                        UserWorkspaceEvent.leaveWorkspace(
                            workspaceId: workspaceId),
                      );
                }
              }
              break;
            case ViewMoreActionType.delete:
              // 如果是 Space 类型，使用 SpaceBloc 删除
              if (_view.isSpace) {
                if (context.mounted) {
                  context.read<SpaceBloc>().add(
                        SpaceEvent.delete(_view),
                      );
                  // 删除空间后刷新列表
                  _refreshSpaceBlocIfNeeded(context);
                }
              } else {
                // 保存父视图ID，用于删除后刷新
                final parentViewId = _view.parentViewId;
                // get if current page contains published child views
                final (containPublishedPage, _) =
                    await ViewBackendService.containPublishedPage(_view);
                if (containPublishedPage && context.mounted) {
                  await showConfirmDeletionDialog(
                    context: context,
                    name: _view.name,
                    description: LocaleKeys.publish_containsPublishedPage.tr(),
                    onConfirm: () {
                      context.read<ViewBloc>().add(const ViewEvent.delete());
                      // 删除后立即刷新列表（不等待监听，确保最后一条也能刷新）
                      Future.delayed(const Duration(milliseconds: 500), () {
                        if (context.mounted) {
                          _refreshSpaceBlocIfNeeded(context);
                        }
                      });
                    },
                  );
                } else if (context.mounted) {
                  await showDeleteViewToTrashConfirmDialog(
                    context: context,
                    name: _view.nameOrDefault,
                    onConfirm: () {
                      context.read<ViewBloc>().add(const ViewEvent.delete());
                      Future.delayed(const Duration(milliseconds: 500), () {
                        if (context.mounted) {
                          _refreshSpaceBlocIfNeeded(context);
                        }
                      });
                    },
                  );
                }
              }
              break;
            case ViewMoreActionType.duplicate:
              // 如果是 Space 类型，使用 SpaceBloc 复制空间
              if (_view.isSpace) {
                if (context.mounted) {
                  context.read<SpaceBloc>().add(
                        SpaceEvent.duplicate(space: _view),
                      );
                  // 复制后刷新列表
                  _refreshSpaceBlocIfNeeded(context);
                }
              } else {
                context.read<ViewBloc>().add(const ViewEvent.duplicate());
                // 复制后刷新列表（通过 BlocListener 监听成功）
              }
              break;
            case ViewMoreActionType.duplicateToMySpace:
              // 触发复制到我的空间操作
              context
                  .read<ViewBloc>()
                  .add(const ViewEvent.duplicateToMySpace());
              // 复制后刷新列表（通过 BlocListener 监听成功）
              // 使用 addPostFrameCallback 延迟显示成功提示，确保在状态更新后执行
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  Future.delayed(const Duration(milliseconds: 500), () {
                    if (mounted) {
                      showToastNotification(
                        message: '已复制到我的空间',
                        type: ToastificationType.success,
                      );
                    }
                  });
                }
              });
              break;
            case ViewMoreActionType.openInNewTab:
              // 使用addPostFrameCallback延迟执行，避免在渲染周期中触发UI状态变化
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) {
                  context.read<TabsBloc>().openTab(_view);
                }
              });
              break;
            case ViewMoreActionType.changeIcon:
              if (data is! SelectedEmojiIconResult) {
                return;
              }
              // Space 与文档统一走 view.icon（FolderEventUpdateViewIcon）。
              // 旧逻辑仅在 FlowyIconType.icon 时 dispatch SpaceBloc（写 extra），
              // Emojis / Upload 分支为空，导致菜单里选表情「无反应」。
              if (context.mounted) {
                await ViewBackendService.updateViewIcon(
                  view: _view,
                  viewIcon: data.data,
                );
                _refreshSpaceBlocIfNeeded(context);
              }
              break;
            case ViewMoreActionType.manageSpace:
              // 显示管理空间弹窗，传入当前点击的 Space
              if (context.mounted) {
                await showDialog(
                  context: context,
                  builder: (_) => Dialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    child: BlocProvider.value(
                      value: context.read<SpaceBloc>(),
                      child: ManageSpacePopup(space: _view),
                    ),
                  ),
                );
              }
              break;
            case ViewMoreActionType.moveTo:
              final value = data;
              if (value is! (ViewPB, ViewPB)) {
                return;
              }
              final space = value.$1;
              final target = value.$2;
              await moveViewCrossSpace(
                context,
                space,
                _view,
                widget.parentView,
                widget.spaceType,
                _view,
                target.id,
              );
              break;
            default:
              throw UnsupportedError('$action is not supported');
          }
        },
      ),
    );

    // 如果有外层的 SpaceBloc，使用 BlocProvider.value 传递；否则直接返回
    if (outerSpaceBloc != null) {
      return BlocProvider<SpaceBloc>.value(
        value: outerSpaceBloc,
        child: child,
      );
    } else {
      return child;
    }
  }
}

class _DotIconWidget extends StatelessWidget {
  const _DotIconWidget();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6.0),
      child: Container(
        width: 4,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).iconTheme.color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

// workaround: we should use view.isEndPoint or something to check if the view can contain child views. But currently, we don't have that field.
bool isReferencedDatabaseView(ViewPB view, ViewPB? parentView) {
  if (parentView == null) {
    return false;
  }
  return view.layout.isDatabaseView && parentView.layout.isDatabaseView;
}

/// 移动请求完成后读取 Folder 的最终父级。
///
/// iOS 上 Folder 事件返回成功与本地视图索引更新之间可能存在短暂延迟。
/// 单次立即读取会把已经提交成功的移动误判为失败，因此在提示错误前给
/// 本地索引和同步事件一个有限的收敛窗口。
Future<ViewPB?> _readMovedViewWithRetry({
  required String viewId,
  required String expectedParentId,
}) async {
  const retryDelays = <Duration>[
    Duration.zero,
    Duration(milliseconds: 300),
    Duration(milliseconds: 1000),
    Duration(milliseconds: 2000),
    Duration(milliseconds: 4000),
  ];

  ViewPB? latestView;
  for (var index = 0; index < retryDelays.length; index++) {
    final delay = retryDelays[index];
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }

    final result = await ViewBackendService.getView(viewId);
    latestView = result.fold<ViewPB?>((view) => view, (_) => null);
    final actualParentId = latestView?.parentViewId;
    Log.info(
      '[CrossSpaceMove] 移动结果校验第${index + 1}次: view=$viewId '
      'expectedParent=$expectedParentId actualParent=$actualParentId',
    );
    if (actualParentId == expectedParentId) {
      return latestView;
    }
  }

  return latestView;
}

final CrossSpaceMoveGuard _viewMoveGuard = CrossSpaceMoveGuard();

Future<void> moveViewCrossSpace(
  BuildContext context,
  ViewPB? toSpace,
  ViewPB view,
  ViewPB? parentView,
  FolderSpaceType spaceType,
  ViewPB from,
  String toId,
) async {
  if (isReferencedDatabaseView(view, parentView)) {
    return;
  }

  if (from.id == toId) {
    return;
  }

  if (!_viewMoveGuard.tryAcquire(from.id)) {
    Log.warn(
      '[CrossSpaceMove] 同一文档仍在移动中，忽略重复触发: view=${from.id}',
    );
    return;
  }

  try {
    await _moveViewCrossSpaceOnce(
      context,
      toSpace,
      view,
      parentView,
      spaceType,
      from,
      toId,
    );
  } finally {
    _viewMoveGuard.release(from.id);
  }
}

Future<void> _moveViewCrossSpaceOnce(
  BuildContext context,
  ViewPB? toSpace,
  ViewPB view,
  ViewPB? parentView,
  FolderSpaceType spaceType,
  ViewPB from,
  String toId,
) async {
  // 计算源、目标所属的 section（私有/协作），用于跨空间移动时同步切换 section。
  // 源 section 依据当前视图在侧栏所处的分区；目标 section 依据目标空间的权限类型。
  // 若源与目标 section 相同（同区内移动），后端会跳过 section 变更，无副作用。
  ViewSectionPB? fromSection;
  if (spaceType == FolderSpaceType.private) {
    fromSection = ViewSectionPB.Private;
  } else if (spaceType == FolderSpaceType.public) {
    fromSection = ViewSectionPB.Public;
  }
  fromSection = await resolveViewSection(
    context,
    from,
    fallback: fromSection,
  );
  if (!context.mounted) return;

  ViewSectionPB? toSection;
  if (toSpace != null && toSpace.isSpace) {
    toSection = toSpace.spacePermission == SpacePermission.private
        ? ViewSectionPB.Private
        : ViewSectionPB.Public;
  }

  final viewBloc = context.read<ViewBloc>();
  final spaceBloc = context.read<SpaceBloc>();
  final sidebarRefresher = SidebarMoveStateRefresher.capture(context);
  final currentSpace = spaceBloc.state.currentSpace;
  final sourceSpaceId = await resolveViewSpaceId(from);
  if (!context.mounted) return;
  final movesToAnotherSpace = toSpace != null &&
      (sourceSpaceId != null
          ? sourceSpaceId != toSpace.id
          : currentSpace != null && currentSpace.id != toSpace.id);
  Log.info(
    '[CrossSpaceMove] 源空间解析: view=${from.id} source=$sourceSpaceId '
    'target=${toSpace?.id} crossSpace=$movesToAnotherSpace',
  );

  final outcome = await coordinateViewMove(
    context,
    viewBloc: viewBloc,
    view: from,
    targetParentId: toId,
    prevViewId: null,
    fromSection: fromSection,
    toSection: toSection,
    beforeSubmit: movesToAnotherSpace
        ? () {
            Log.info(
              'Move view(${from.name}) to another space(${toSpace.name}), unpublish the view',
            );
            viewBloc.add(const ViewEvent.unpublish(sync: false));
          }
        : null,
  );
  if (outcome == CrossSpaceMoveOutcome.aborted) {
    return;
  }

  // 普通文档必须等本地 Folder 父级确认后再刷新列表和提示成功。新 Cloud
  // 直接返回并应用 Folder 增量；旧 Cloud 由 Rust 客户端同步拉取完整 Folder
  // 作为兼容路径。有限重试只吸收事件队列的短暂调度延迟。
  if (outcome == CrossSpaceMoveOutcome.moved) {
    ViewPB? confirmedView;
    try {
      confirmedView = await _readMovedViewWithRetry(
        viewId: from.id,
        expectedParentId: toId,
      );
    } catch (error) {
      Log.error(
        '[CrossSpaceMove] 移动结果校验异常: view=${from.id}, error=$error',
      );
    }
    if (confirmedView == null || confirmedView.parentViewId != toId) {
      Log.error(
        '[CrossSpaceMove] 移动提交后父级未更新: view=${from.id} '
        'expectedParent=$toId actualParent=${confirmedView?.parentViewId}',
      );
      showToastNotification(
        message: LocaleKeys.document_plugins_subPage_errors_failedMovePage.tr(),
        type: ToastificationType.error,
      );
      return;
    }
    Log.info(
      '[CrossSpaceMove] 移动结果校验成功: view=${from.id} parent=$toId',
    );
    getIt<MenuSharedState>().refreshLatestOpenView(confirmedView);
  }

  if (movesToAnotherSpace) {
    // 移出协作区时当前文档页和菜单 Overlay 可能先被删除通知卸载，依赖
    // switchToSpaceNotifier 的 Widget 监听器会有丢事件窗口。直接向移动开始前
    // 捕获的 SpaceBloc 打开目标空间，由 open 事件权威拉取目标子文档列表。
    spaceBloc.add(SpaceEvent.open(space: toSpace));
  }

  // 父级已经确认更新后，每个相关空间只重建一次列表。移动空间并没有改变
  // 空间树本身，不再触发 SpaceBloc.initial，也不在同步前反复创建 ViewBloc。
  if (PlatformInfo.isMobile) {
    final refreshSpaceIds = <String>{
      if (sourceSpaceId != null) sourceSpaceId,
      if (toSpace != null) toSpace.id,
    };
    for (final spaceId in refreshSpaceIds) {
      MobileSpaceListRefreshNotifier.instance.requestRefresh(spaceId);
    }
    Log.info(
      '[CrossSpaceMove] 父级确认后刷新移动端涉及空间列表: '
      '${refreshSpaceIds.join(',')}',
    );
  }
  if (view.layout == ViewLayoutPB.Whiteboard && fromSection != toSection) {
    showToastNotification(
      message: LocaleKeys.space_whiteboardMigrationSuccess.tr(),
      type: ToastificationType.success,
    );
  } else {
    showToastNotification(
      message: LocaleKeys.space_moveSuccess.tr(),
      type: ToastificationType.success,
    );
  }
  sidebarRefresher.refresh();
}

Future<void> moveViewToSectionPlaceholder(
  BuildContext context,
  FolderSpaceType spaceType,
  ViewPB from,
  String newParentId,
) async {
  if (from.id == newParentId ||
      (spaceType != FolderSpaceType.private &&
          spaceType != FolderSpaceType.public)) {
    return;
  }

  final fromSection = await resolveViewSection(context, from);
  if (!context.mounted) return;

  final toSection = spaceType.toViewSectionPB;

  final viewBloc = context.read<ViewBloc>();
  final sidebarRefresher = SidebarMoveStateRefresher.capture(context);
  final outcome = await coordinateViewMove(
    context,
    viewBloc: viewBloc,
    view: from,
    targetParentId: newParentId,
    prevViewId: null,
    fromSection: fromSection,
    toSection: toSection,
  );
  if (outcome == CrossSpaceMoveOutcome.aborted) return;
  sidebarRefresher.refresh();
}

class ViewItemDefaultLeftIcon extends StatelessWidget {
  const ViewItemDefaultLeftIcon({
    super.key,
    required this.view,
    required this.parentView,
    required this.isExpanded,
    required this.leftPadding,
    required this.isHovered,
    this.onExpandedChanged,
  });

  final ViewPB view;
  final ViewPB? parentView;
  final bool isExpanded;
  final double leftPadding;
  final ValueNotifier<bool>? isHovered;
  final VoidCallback? onExpandedChanged;

  @override
  Widget build(BuildContext context) {
    if (isReferencedDatabaseView(view, parentView)) {
      return const _DotIconWidget();
    }

    if (context.read<ViewBloc>().state.view.childViews.isEmpty) {
      return HSpace(leftPadding);
    }

    final child = FlowyHover(
      child: GestureDetector(
        child: FlowySvg(
          isExpanded
              ? FlowySvgs.view_item_expand_s
              : FlowySvgs.view_item_unexpand_s,
          size: const Size.square(16.0),
        ),
        onTap: () {
          context.read<ViewBloc>().add(ViewEvent.setIsExpanded(!isExpanded));
          onExpandedChanged?.call();
        },
      ),
    );

    if (isHovered != null) {
      return ValueListenableBuilder<bool>(
        valueListenable: isHovered!,
        builder: (_, isHovered, child) =>
            Opacity(opacity: isHovered ? 1.0 : 0.0, child: child),
        child: child,
      );
    }

    return child;
  }
}
