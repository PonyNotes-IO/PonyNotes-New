import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/features/share_tab/data/models/share_access_level.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/handwriting_saber/presentation/handwriting_export_action.dart';
import 'package:appflowy/plugins/whiteboard/presentation/whiteboard_export_action.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view_info/view_info_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_action_type.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/widgets/common_view_action.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/widgets/database_export_action.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/widgets/export_action.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/widgets/font_size_action.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/widgets/lock_page_action.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/widgets/view_meta_info.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/hover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class MoreViewActions extends StatefulWidget {
  const MoreViewActions({
    super.key,
    required this.view,
    this.customActions = const [],
    this.viewInfoBloc,
  });

  /// The view to show the actions for.
  ///
  final ViewPB view;

  /// Custom actions to show in the popover, will be laid out at the top.
  ///
  final List<Widget> customActions;

  /// 可选：外部传入的 ViewInfoBloc，避免 context 中有多个 ViewInfoBloc 实例的问题
  final ViewInfoBloc? viewInfoBloc;

  @override
  State<MoreViewActions> createState() => _MoreViewActionsState();
}

class _MoreViewActionsState extends State<MoreViewActions> {
  final popoverMutex = PopoverMutex();

  @override
  void dispose() {
    popoverMutex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 优先使用传入的 ViewInfoBloc，否则从 context 中获取
    ViewInfoBloc viewInfoBloc;
    PageAccessLevelBloc? pageAccessLevelBloc;
    if (widget.viewInfoBloc != null) {
      viewInfoBloc = widget.viewInfoBloc!;
    } else {
      try {
        viewInfoBloc = context.read<ViewInfoBloc>();
      } catch (e) {
        return const _ThreeDots();
      }
    }

    // 尝试从 context 获取 PageAccessLevelBloc（如果存在）
    try {
      pageAccessLevelBloc = context.read<PageAccessLevelBloc>();
    } catch (_) {
      // PageAccessLevelBloc 不在 context 中，popup 中会自己创建
    }

    return BlocBuilder<ViewInfoBloc, ViewInfoState>(
      bloc: viewInfoBloc,
      builder: (context, state) {
        return AppFlowyPopover(
          mutex: popoverMutex,
          constraints: const BoxConstraints(maxWidth: 245),
          direction: PopoverDirection.bottomWithRightAligned,
          offset: const Offset(0, 12),
          popupBuilder: (_) => _buildPopup(state, pageAccessLevelBloc),
          child: const _ThreeDots(),
        );
      },
    );
  }

  Widget _buildPopup(ViewInfoState viewInfoState, PageAccessLevelBloc? pageAccessLevelBloc) {
    // 使用传入的 context（MoreViewActions 的 context），因为它有 UserWorkspaceBloc
    final userWorkspaceBloc = context.read<UserWorkspaceBloc>();
    final userProfile = userWorkspaceBloc.state.userProfile;
    final workspaceId = userWorkspaceBloc.state.currentWorkspace?.workspaceId ?? '';

    // 在这里创建所有 providers
    return _MoreViewActionsPopupContent(
      view: widget.view,
      userProfile: userProfile,
      workspaceId: workspaceId,
      viewInfoState: viewInfoState,
      pageAccessLevelBloc: pageAccessLevelBloc,
      customActions: widget.customActions,
      popoverMutex: popoverMutex,
    );
  }
}

/// 分离出来的 popup 内容组件，避免 provider context 问题
class _MoreViewActionsPopupContent extends StatelessWidget {
  const _MoreViewActionsPopupContent({
    required this.view,
    required this.userProfile,
    required this.workspaceId,
    required this.viewInfoState,
    this.pageAccessLevelBloc,
    required this.customActions,
    required this.popoverMutex,
  });

  final ViewPB view;
  final UserProfilePB userProfile;
  final String workspaceId;
  final ViewInfoState viewInfoState;
  final PageAccessLevelBloc? pageAccessLevelBloc;
  final List<Widget> customActions;
  final PopoverMutex popoverMutex;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => ViewBloc(view: view)..add(const ViewEvent.initial()),
        ),
        BlocProvider(
          create: (_) => SpaceBloc(
            userProfile: userProfile,
            workspaceId: workspaceId,
          )..add(const SpaceEvent.initial(openFirstPage: false)),
        ),
        BlocProvider<PageAccessLevelBloc>(
          create: (_) => pageAccessLevelBloc ?? PageAccessLevelBloc(view: view)
            ..add(const PageAccessLevelEvent.initial()),
        ),
      ],
      child: BlocBuilder<ViewBloc, ViewState>(
        builder: (context, viewState) {
          return BlocBuilder<SpaceBloc, SpaceState>(
            builder: (context, state) {
              if (state.spaces.isEmpty &&
                  userProfile.workspaceType == WorkspaceTypePB.ServerW) {
                return const SizedBox.shrink();
              }

              final actions = _buildActions(context, viewInfoState);
              return ListView.builder(
                key: ValueKey(state.spaces.hashCode),
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: actions.length,
                physics: StyledScrollPhysics(),
                itemBuilder: (_, index) => actions[index],
              );
            },
          );
        },
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context, ViewInfoState state) {
    final pageAccessLevelBloc = context.watch<PageAccessLevelBloc>();
    final pageAccessLevelState = pageAccessLevelBloc.state;
    final viewFromState = pageAccessLevelState.view;

    final appearanceSettings = context.watch<AppearanceSettingsCubit>().state;
    final dateFormat = appearanceSettings.dateFormat;
    final timeFormat = appearanceSettings.timeFormat;

    final viewMoreActionTypes = switch (pageAccessLevelState.accessLevel) {
      ShareAccessLevel.readOnly => [],
      _ => [
          if (view.layout != ViewLayoutPB.Chat)
            ViewMoreActionType.duplicate,
          ViewMoreActionType.moveTo,
          ViewMoreActionType.delete,
          ViewMoreActionType.divider,
        ],
    };

    // 检测是否是手写笔记类型
    final isHandwriting = isHandwritingNote(view);

    // 检测是否是白板类型
    final isWhiteboard = isWhiteboardView(view);

    final actions = [
      ...customActions,
      // 手写笔记不显示字体大小选项
      if (view.isDocument && !isHandwriting) ...[
        const FontSizeAction(),
        ViewAction(
          type: ViewMoreActionType.divider,
          view: viewFromState,
          mutex: popoverMutex,
        ),
      ],
      if (state.workspaceType == WorkspaceTypePB.ServerW &&
          (view.isDocument || view.isDatabase) &&
          !pageAccessLevelState.isReadOnly &&
          !isHandwriting) ...[
        LockPageAction(
          view: viewFromState,
        ),
        ViewAction(
          type: ViewMoreActionType.divider,
          view: viewFromState,
          mutex: popoverMutex,
        ),
      ],
      // 手写笔记使用专用的导出/导入组件
      if (isHandwriting) ...[
        HandwritingExportAction(
          view: viewFromState,
        ),
        HandwritingImportAction(
          view: viewFromState,
        ),
        ViewAction(
          type: ViewMoreActionType.divider,
          view: viewFromState,
          mutex: popoverMutex,
        ),
      ] else if (isWhiteboard) ...[
        // 白板使用专用的导出/导入组件
        WhiteboardImportAction(
          view: viewFromState,
        ),
        WhiteboardExportAction(
          view: viewFromState,
        ),
        ViewAction(
          type: ViewMoreActionType.divider,
          view: viewFromState,
          mutex: popoverMutex,
        ),
      ] else if (view.isDocument) ...[
        ExportAction(
          view: viewFromState,
        ),
        ViewAction(
          type: ViewMoreActionType.divider,
          view: viewFromState,
          mutex: popoverMutex,
        ),
      ],
      if (view.isDatabase) ...[
        DatabaseExportAction(
          view: viewFromState,
        ),
        ViewAction(
          type: ViewMoreActionType.divider,
          view: viewFromState,
          mutex: popoverMutex,
        ),
      ],
      ...viewMoreActionTypes.map(
        (type) => ViewAction(
          type: type,
          view: viewFromState,
          mutex: popoverMutex,
        ),
      ),
      if (state.documentCounters != null || state.createdAt != null) ...[
        ViewMetaInfo(
          dateFormat: dateFormat,
          timeFormat: timeFormat,
          documentCounters: state.documentCounters,
          titleCounters: state.titleCounters,
          createdAt: state.createdAt,
        ),
        const VSpace(4.0),
      ],
    ];
    return actions;
  }
}

class _ThreeDots extends StatelessWidget {
  const _ThreeDots();

  @override
  Widget build(BuildContext context) {
    return FlowyTooltip(
      message: LocaleKeys.moreAction_moreOptions.tr(),
      child: FlowyHover(
        style: HoverStyle(
          foregroundColorOnHover: Theme.of(context).colorScheme.onPrimary,
        ),
        builder: (context, isHovering) => Padding(
          padding: const EdgeInsets.all(6),
          child: FlowySvg(
            FlowySvgs.three_dots_s,
            size: const Size.square(18),
            color: isHovering
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).iconTheme.color,
          ),
        ),
      ),
    );
  }
}
