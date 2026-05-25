import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/features/share_tab/data/models/share_access_level.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/handwriting_saber/presentation/handwriting_export_action.dart';
import 'package:appflowy/plugins/whiteboard/presentation/whiteboard_export_action.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view_info/view_info_bloc.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_action_type.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/widgets/common_view_action.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/widgets/database_export_action.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/widgets/export_action.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/widgets/font_size_action.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/widgets/lock_page_action.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/widgets/view_meta_info.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
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
    this.pageAccessLevelBloc,
    this.iconColor,
  });

  final ViewPB view;
  final List<Widget> customActions;
  final ViewInfoBloc? viewInfoBloc;
  final PageAccessLevelBloc? pageAccessLevelBloc;
  final Color? iconColor;

  @override
  State<MoreViewActions> createState() => _MoreViewActionsState();
}

class _MoreViewActionsState extends State<MoreViewActions> {
  final popoverMutex = PopoverMutex();
  final PopoverController _popoverController = PopoverController();
  ViewInfoBloc? _fallbackViewInfoBloc;
  PageAccessLevelBloc? _fallbackPageAccessLevelBloc;
  bool _showPopoverWhenAccessReady = false;

  @override
  void dispose() {
    popoverMutex.dispose();
    _fallbackViewInfoBloc?.close();
    _fallbackPageAccessLevelBloc?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInfoBloc = _resolveViewInfoBloc(context);
    final pageAccessLevelBloc = _resolvePageAccessLevelBloc(context);

    final child = BlocBuilder<ViewInfoBloc, ViewInfoState>(
      bloc: viewInfoBloc,
      builder: (context, state) {
        return AppFlowyPopover(
          controller: _popoverController,
          mutex: popoverMutex,
          constraints: const BoxConstraints(maxWidth: 264),
          direction: PopoverDirection.bottomWithRightAligned,
          offset: const Offset(0, 14),
          triggerActions: PopoverTriggerFlags.none,
          popupBuilder: (_) => _buildPopup(state, pageAccessLevelBloc),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: SizedBox.square(
              dimension: HomeSizes.topActionBarItemExtent,
              child: FlowyButton(
                margin: EdgeInsets.zero,
                onTap: () => _handleOpenRequest(pageAccessLevelBloc),
                text: _ThreeDots(iconColor: widget.iconColor),
              ),
            ),
          ),
        );
      },
    );

    if (pageAccessLevelBloc == null) {
      return child;
    }

    return BlocListener<PageAccessLevelBloc, PageAccessLevelState>(
      bloc: pageAccessLevelBloc,
      listenWhen: (previous, current) =>
          previous.isLoadingLockStatus && !current.isLoadingLockStatus,
      listener: (_, __) {
        if (!_showPopoverWhenAccessReady) {
          return;
        }
        _showPopoverWhenAccessReady = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _popoverController.show();
          }
        });
      },
      child: child,
    );
  }

  ViewInfoBloc _resolveViewInfoBloc(BuildContext context) {
    if (widget.viewInfoBloc != null) {
      return widget.viewInfoBloc!;
    }

    try {
      return context.read<ViewInfoBloc>();
    } catch (_) {
      final fallbackBloc = _fallbackViewInfoBloc;
      if (fallbackBloc == null || fallbackBloc.view.id != widget.view.id) {
        fallbackBloc?.close();
        _fallbackViewInfoBloc = ViewInfoBloc(view: widget.view)
          ..add(const ViewInfoEvent.started());
      }
      return _fallbackViewInfoBloc!;
    }
  }

  PageAccessLevelBloc? _resolvePageAccessLevelBloc(BuildContext context) {
    if (widget.pageAccessLevelBloc != null) {
      return widget.pageAccessLevelBloc;
    }

    try {
      return context.read<PageAccessLevelBloc>();
    } catch (_) {
      final fallbackBloc = _fallbackPageAccessLevelBloc;
      if (fallbackBloc == null || fallbackBloc.view.id != widget.view.id) {
        fallbackBloc?.close();
        _fallbackPageAccessLevelBloc = PageAccessLevelBloc(view: widget.view)
          ..add(const PageAccessLevelEvent.initial());
      }
      return _fallbackPageAccessLevelBloc;
    }
  }

  void _handleOpenRequest(PageAccessLevelBloc? pageAccessLevelBloc) {
    if (pageAccessLevelBloc != null &&
        pageAccessLevelBloc.state.isLoadingLockStatus) {
      _showPopoverWhenAccessReady = true;
      return;
    }

    _showPopoverWhenAccessReady = false;
    _popoverController.show();
  }

  Widget _buildPopup(
    ViewInfoState viewInfoState,
    PageAccessLevelBloc? pageAccessLevelBloc,
  ) {
    final userWorkspaceBloc = context.read<UserWorkspaceBloc>();
    final userProfile = userWorkspaceBloc.state.userProfile;
    final workspaceId =
        userWorkspaceBloc.state.currentWorkspace?.workspaceId ?? '';

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
    final accessBloc =
        pageAccessLevelBloc?.view.id == view.id ? pageAccessLevelBloc : null;
    final accessProvider = accessBloc != null
        ? BlocProvider<PageAccessLevelBloc>.value(value: accessBloc)
        : BlocProvider<PageAccessLevelBloc>(
            create: (_) => PageAccessLevelBloc(view: view)
              ..add(const PageAccessLevelEvent.initial()),
          );

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
        accessProvider,
      ],
      child: BlocBuilder<ViewBloc, ViewState>(
        builder: (context, _) {
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
      ShareAccessLevel.readOnly => <ViewMoreActionType>[],
      _ => <ViewMoreActionType>[
          if (view.layout != ViewLayoutPB.Chat) ViewMoreActionType.duplicate,
          ViewMoreActionType.moveTo,
          ViewMoreActionType.delete,
          ViewMoreActionType.divider,
        ],
    };

    final isHandwriting = isHandwritingNote(view);
    final isWhiteboard = isWhiteboardView(view);

    return [
      ...customActions,
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
        LockPageAction(view: viewFromState),
        ViewAction(
          type: ViewMoreActionType.divider,
          view: viewFromState,
          mutex: popoverMutex,
        ),
      ],
      if (isHandwriting) ...[
        HandwritingExportAction(view: viewFromState),
        HandwritingImportAction(view: viewFromState),
        ViewAction(
          type: ViewMoreActionType.divider,
          view: viewFromState,
          mutex: popoverMutex,
        ),
      ] else if (isWhiteboard) ...[
        WhiteboardImportAction(view: viewFromState),
        WhiteboardExportAction(view: viewFromState),
        ViewAction(
          type: ViewMoreActionType.divider,
          view: viewFromState,
          mutex: popoverMutex,
        ),
      ] else if (view.isDocument) ...[
        ExportAction(view: viewFromState),
        ViewAction(
          type: ViewMoreActionType.divider,
          view: viewFromState,
          mutex: popoverMutex,
        ),
      ],
      if (view.isDatabase) ...[
        DatabaseExportAction(view: viewFromState),
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
  }
}

class _ThreeDots extends StatelessWidget {
  const _ThreeDots({this.iconColor});

  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return FlowyHover(
      style: HoverStyle(
        foregroundColorOnHover: Theme.of(context).colorScheme.onPrimary,
      ),
      builder: (context, isHovering) => Padding(
        padding: const EdgeInsets.all(6),
        child: FlowySvg(
          FlowySvgs.three_dots_s,
          size: const Size.square(18),
          color: isHovering
              ? (iconColor ?? Theme.of(context).colorScheme.onSurface)
              : (iconColor ?? Theme.of(context).iconTheme.color),
        ),
      ),
    );
  }
}
