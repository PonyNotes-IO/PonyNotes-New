import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/plugins/document/presentation/document_collaborators.dart';
import 'package:appflowy/plugins/shared/share/share_button.dart';
import 'package:appflowy/workspace/application/view_info/view_info_bloc.dart';
import 'package:appflowy/workspace/presentation/home/full_window_controller.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/widgets/favorite_button.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/more_view_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_svg/flowy_svg.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

const _floatingActionIconColorLight = Color(0xFF111111);
const _floatingActionIconColorDark = Color(0xFFF3F4F6);
const _fullWindowIcon = FlowySvgData('assets/images/icons/app_full_window.svg');
const _exitFullWindowIcon =
    FlowySvgData('assets/images/icons/app_exit_full_window.svg');

class UnifiedViewTopRightActions extends StatelessWidget {
  const UnifiedViewTopRightActions({
    super.key,
    required this.view,
    this.viewInfoBloc,
    this.pageAccessLevelBloc,
    this.showCollaborators = false,
    this.useFloatingSurface = false,
    this.trailingSpacing = 4,
    this.showShareButton = true,
    this.showFavoriteButton = true,
    this.showFullWindowButton = true,
    this.iconColorOverride,
    this.customActions,
  });

  final ViewPB view;
  final ViewInfoBloc? viewInfoBloc;
  final PageAccessLevelBloc? pageAccessLevelBloc;
  final bool showCollaborators;
  final bool useFloatingSurface;
  final double trailingSpacing;
  final bool showShareButton;
  final bool showFavoriteButton;
  final bool showFullWindowButton;
  final Color? iconColorOverride;
  final List<Widget>? customActions;

  @override
  Widget build(BuildContext context) {
    final safeViewInfoBloc = _viewInfoBlocForView(viewInfoBloc, view);
    final safePageAccessLevelBloc =
        _pageAccessLevelBlocForView(pageAccessLevelBloc, view);

    Widget child = _UnifiedViewTopRightActionsContent(
      view: view,
      viewInfoBloc: safeViewInfoBloc,
      pageAccessLevelBloc: safePageAccessLevelBloc,
      showCollaborators: showCollaborators,
      useFloatingSurface: useFloatingSurface,
      trailingSpacing: trailingSpacing,
      showShareButton: showShareButton,
      showFavoriteButton: showFavoriteButton,
      showFullWindowButton: showFullWindowButton,
      iconColorOverride: iconColorOverride,
      customActions: customActions,
    );

    final bloc = safeViewInfoBloc;
    if (bloc != null) {
      child = BlocProvider<ViewInfoBloc>.value(
        value: bloc,
        child: child,
      );
    }

    final accessLevelBloc = safePageAccessLevelBloc;
    if (accessLevelBloc != null) {
      child = BlocProvider<PageAccessLevelBloc>.value(
        value: accessLevelBloc,
        child: child,
      );
    }

    return child;
  }

  ViewInfoBloc? _viewInfoBlocForView(ViewInfoBloc? bloc, ViewPB view) {
    if (bloc == null || bloc.view.id != view.id) {
      return null;
    }
    return bloc;
  }

  PageAccessLevelBloc? _pageAccessLevelBlocForView(
    PageAccessLevelBloc? bloc,
    ViewPB view,
  ) {
    if (bloc == null || bloc.view.id != view.id) {
      return null;
    }
    return bloc;
  }
}

class _UnifiedViewTopRightActionsContent extends StatelessWidget {
  const _UnifiedViewTopRightActionsContent({
    required this.view,
    required this.viewInfoBloc,
    required this.pageAccessLevelBloc,
    required this.showCollaborators,
    required this.useFloatingSurface,
    required this.trailingSpacing,
    required this.showShareButton,
    required this.showFavoriteButton,
    required this.showFullWindowButton,
    required this.iconColorOverride,
    required this.customActions,
  });

  final ViewPB view;
  final ViewInfoBloc? viewInfoBloc;
  final PageAccessLevelBloc? pageAccessLevelBloc;
  final bool showCollaborators;
  final bool useFloatingSurface;
  final double trailingSpacing;
  final bool showShareButton;
  final bool showFavoriteButton;
  final bool showFullWindowButton;
  final Color? iconColorOverride;
  final List<Widget>? customActions;

  @override
  Widget build(BuildContext context) {
    final iconColor = iconColorOverride ??
        (useFloatingSurface
            ? _floatingActionIconColor(context)
            : Theme.of(context).colorScheme.onSurface);
    final themedChild = Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(context).colorScheme.copyWith(
              onSurface: iconColor,
            ),
        iconTheme: Theme.of(context).iconTheme.copyWith(color: iconColor),
      ),
      child: IconTheme(
        data: IconThemeData(color: iconColor),
        child: _buildActions(context, iconColor),
      ),
    );

    if (!useFloatingSurface) {
      return themedChild;
    }

    // Fake-delete the floating frame while preserving hit areas and icons.
    // 假删除悬浮外框/背景/阴影，只保留图标和原有点击区域。
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: HomeSizes.topActionBarHeight,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: themedChild,
      ),
    );
  }

  Widget _buildActions(BuildContext context, Color iconColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showCollaborators) ...[
          DocumentCollaborators(
            key: ValueKey('collaborators_${view.id}'),
            width: 120,
            height: HomeSizes.topActionBarItemExtent,
            view: view,
          ),
          const HSpace(8),
        ] else
          const HSpace(2),
        if (showShareButton) ...[
          ShareButton(
            key: ValueKey('share_button_${view.id}'),
            view: view,
          ),
          const HSpace(4),
        ],
        if (showFavoriteButton) ...[
          ViewFavoriteButton(
            key: ValueKey('favorite_button_${view.id}'),
            view: view,
            inactiveColor: iconColor,
          ),
          const HSpace(4),
        ],
        if (showFullWindowButton) ...[
          ValueListenableBuilder<bool>(
            valueListenable: FullWindowController.isFullWindow,
            builder: (context, isFullWindow, _) {
              return FlowyTooltip(
                message: isFullWindow
                    ? '\u9000\u51fa\u5e94\u7528\u5185\u5168\u5c4f'
                    : '\u5e94\u7528\u5185\u5168\u5c4f',
                child: SizedBox.square(
                  dimension: HomeSizes.topActionBarItemExtent,
                  child: FlowyButton(
                    margin: EdgeInsets.zero,
                    text: FlowySvg(
                      isFullWindow ? _exitFullWindowIcon : _fullWindowIcon,
                      size: const Size.square(20),
                      color: iconColor,
                    ),
                    onTap: FullWindowController.toggle,
                  ),
                ),
              );
            },
          ),
          const HSpace(4),
        ],
        MoreViewActions(
          view: view,
          viewInfoBloc: viewInfoBloc ?? _maybeReadViewInfoBloc(context),
          pageAccessLevelBloc:
              pageAccessLevelBloc ?? _maybeReadPageAccessLevelBloc(context),
          iconColor: iconColor,
          customActions: customActions ?? const [],
        ),
        HSpace(trailingSpacing),
      ],
    );
  }

  Color _floatingActionIconColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? _floatingActionIconColorDark
        : _floatingActionIconColorLight;
  }

  ViewInfoBloc? _maybeReadViewInfoBloc(BuildContext context) {
    try {
      final bloc = context.read<ViewInfoBloc>();
      return bloc.view.id == view.id ? bloc : null;
    } catch (_) {
      return null;
    }
  }

  PageAccessLevelBloc? _maybeReadPageAccessLevelBloc(BuildContext context) {
    try {
      final bloc = context.read<PageAccessLevelBloc>();
      return bloc.view.id == view.id ? bloc : null;
    } catch (_) {
      return null;
    }
  }
}
