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
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

const _floatingActionIconColorLight = Color(0xFF111111);
const _floatingActionIconColorDark = Color(0xFFF3F4F6);
const _floatingActionSurfaceColorLight = Color(0xF7FFFFFF);
const _floatingActionSurfaceColorDark = Color(0xE61B1C20);
const _floatingActionBorderColorLight = Color(0x16000000);
const _floatingActionBorderColorDark = Color(0x22FFFFFF);

class UnifiedViewTopRightActions extends StatelessWidget {
  const UnifiedViewTopRightActions({
    super.key,
    required this.view,
    this.viewInfoBloc,
    this.pageAccessLevelBloc,
    this.showCollaborators = false,
    this.useFloatingSurface = false,
    this.trailingSpacing = 8,
    this.showShareButton = true,
    this.showFavoriteButton = true,
    this.showFullWindowButton = true,
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
  final List<Widget>? customActions;

  @override
  Widget build(BuildContext context) {
    final iconColor = useFloatingSurface
        ? _floatingActionIconColor(context)
        : Theme.of(context).colorScheme.onSurface;
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

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark
          ? _floatingActionSurfaceColorDark
          : _floatingActionSurfaceColorLight,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.24 : 0.12),
      borderRadius: BorderRadius.circular(HomeRadii.floatingSurface),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(HomeRadii.floatingSurface),
          border: Border.all(
            color: isDark
                ? _floatingActionBorderColorDark
                : _floatingActionBorderColorLight,
          ),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: HomeSizes.topActionBarHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: themedChild,
          ),
        ),
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
          const HSpace(12),
        ] else
          const HSpace(2),
        if (showShareButton) ...[
          ShareButton(
            key: ValueKey('share_button_${view.id}'),
            view: view,
          ),
          const HSpace(6),
        ],
        if (showFavoriteButton) ...[
          ViewFavoriteButton(
            key: ValueKey('favorite_button_${view.id}'),
            view: view,
            inactiveColor: iconColor,
          ),
          const HSpace(6),
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
                    text: Icon(
                      isFullWindow
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                      size: 20,
                      color: iconColor,
                    ),
                    onTap: FullWindowController.toggle,
                  ),
                ),
              );
            },
          ),
          const HSpace(6),
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
