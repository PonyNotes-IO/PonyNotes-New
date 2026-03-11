import 'dart:async';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/folder/folder_bloc.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_action_type.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_item.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_more_action_button.dart';
import 'package:appflowy/startup/tasks/app_widget.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ViewAction extends StatelessWidget {
  const ViewAction({
    super.key,
    required this.type,
    required this.view,
    this.mutex,
  });

  final ViewMoreActionType type;
  final ViewPB view;
  final PopoverMutex? mutex;

  @override
  Widget build(BuildContext context) {
    final wrapper = ViewMoreActionTypeWrapper(
      type,
      view,
      (controller, data) async {
        if (type == ViewMoreActionType.delete) {
          final viewBloc = context.read<ViewBloc>();
          final dialogContext = AppGlobals.rootNavKey.currentContext ?? context;
          FocusManager.instance.primaryFocus?.unfocus();
          mutex?.close();
          await Future<void>.delayed(const Duration(milliseconds: 16));
          await _handleDeleteAction(
            actionContext: context,
            dialogContext: dialogContext,
            viewBloc: viewBloc,
          );
          return;
        }
        await _onAction(context, data);
        mutex?.close();
      },
      moveActionDirection: PopoverDirection.leftWithTopAligned,
      moveActionOffset: const Offset(-10, 0),
    );
    return wrapper.buildWithContext(
      context,
      // this is a dummy controller, we don't need to control the popover here.
      PopoverController(),
      null,
    );
  }

  Future<void> _onAction(
    BuildContext context,
    dynamic data,
  ) async {
    switch (type) {
      case ViewMoreActionType.delete:
        // Handled in wrapper callback to ensure popover/focus ordering is correct.
        break;
      case ViewMoreActionType.duplicate:
        context.read<ViewBloc>().add(const ViewEvent.duplicate());
      case ViewMoreActionType.moveTo:
        final value = data;
        if (value is! (ViewPB, ViewPB)) {
          return;
        }
        final space = value.$1;
        final target = value.$2;
        final result = await ViewBackendService.getView(view.parentViewId);
        result.fold(
          (parentView) => moveViewCrossSpace(
            context,
            space,
            view,
            parentView,
            FolderSpaceType.public,
            view,
            target.id,
          ),
          (f) => Log.error(f),
        );

        // the move action is handled in the button itself
        break;
      default:
        throw UnimplementedError();
    }
  }

  Future<void> _handleDeleteAction(
    {
    required BuildContext actionContext,
    required BuildContext dialogContext,
    required ViewBloc viewBloc,
  }
  ) async {
    final (containPublishedPage, _) =
        await ViewBackendService.containPublishedPage(view);

    if (containPublishedPage && dialogContext.mounted) {
      await showConfirmDeletionDialog(
        context: dialogContext,
        name: view.nameOrDefault,
        description: LocaleKeys.publish_containsPublishedPage.tr(),
        onConfirm: () {
          unawaited(_onDeleteConfirmed(actionContext, viewBloc));
        },
      );
    } else {
      await _onDeleteConfirmed(actionContext, viewBloc);
    }
  }

  Future<void> _onDeleteConfirmed(
    BuildContext actionContext,
    ViewBloc viewBloc,
  ) async {
    final didTriggerDelete = await _triggerDelete(viewBloc);
    if (didTriggerDelete) {
      _refreshSpaceListIfNeeded(actionContext);
    }
  }

  void _refreshSpaceListIfNeeded(BuildContext actionContext) {
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      if (!actionContext.mounted) {
        return;
      }

      try {
        final spaceBloc = actionContext.read<SpaceBloc>();
        if (!spaceBloc.isClosed) {
          spaceBloc.add(const SpaceEvent.didUpdateCurrentSpaceChildViews());
          Log.info('Refresh SpaceBloc after delete: ${view.id}');
        }
      } catch (_) {
        // Ignore when current context is not inside SpaceHub.
      }
    });
  }

  Future<bool> _triggerDelete(ViewBloc viewBloc) async {
    if (!viewBloc.isClosed) {
      viewBloc.add(const ViewEvent.delete());
      return true;
    }

    // Fallback path: the source view bloc might be disposed after popover closes.
    // Execute direct delete flow to avoid user-facing failure.
    Log.warn('ViewBloc already closed, fallback to direct delete for view=${view.id}');

    final (_, publishedPages) = await ViewBackendService.containPublishedPage(view);
    await Future.wait(
      publishedPages.map((publishedView) => ViewBackendService.unpublish(publishedView)),
    );

    final deleteResult = await ViewBackendService.deleteView(viewId: view.id);
    return deleteResult.fold(
      (_) => true,
      (error) {
        Log.error('fallback delete view failed: $error');
        return false;
      },
    );
  }
}

class CustomViewAction extends StatelessWidget {
  const CustomViewAction({
    super.key,
    required this.view,
    required this.leftIcon,
    required this.label,
    this.tooltipMessage,
    this.disabled = false,
    this.onTap,
    this.mutex,
  });

  final ViewPB view;
  final FlowySvgData leftIcon;
  final String label;
  final bool disabled;
  final String? tooltipMessage;
  final VoidCallback? onTap;
  final PopoverMutex? mutex;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: FlowyTooltip(
        message: tooltipMessage,
        child: FlowyButton(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          disable: disabled,
          onTap: onTap,
          leftIcon: FlowySvg(
            leftIcon,
            size: const Size.square(16.0),
            color: disabled ? Theme.of(context).disabledColor : null,
          ),
          iconPadding: 10.0,
          text: FlowyText(
            label,
            figmaLineHeight: 18.0,
            color: disabled ? Theme.of(context).disabledColor : null,
          ),
        ),
      ),
    );
  }
}
