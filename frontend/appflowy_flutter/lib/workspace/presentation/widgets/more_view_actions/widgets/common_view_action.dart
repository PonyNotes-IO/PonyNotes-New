import 'dart:async';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/home/mobile_home_page.dart';
import 'package:appflowy/mobile/presentation/home/space/mobile_space_list_refresh.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/folder/folder_bloc.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_action_type.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/cross_space_move.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_item.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_more_action_button.dart';
import 'package:appflowy/startup/tasks/app_widget.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flowy_infra/platform_extension.dart';
import 'package:go_router/go_router.dart';

import '../../../../application/recent/cached_recent_service.dart';

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
          // 先捕获业务 Bloc。弹层关闭后当前 context 可能被卸载，桌面端删除后的
          // 侧栏刷新不能依赖届时再从 context 查找 Provider。
          final refreshSpaceBloc = _tryReadSpaceBloc(context);
          final dialogContext = AppGlobals.rootNavKey.currentContext ?? context;
          FocusManager.instance.primaryFocus?.unfocus();
          mutex?.close();
          await Future<void>.delayed(const Duration(milliseconds: 16));
          // iOS 会同步关闭弹层，菜单项上下文可能在当前帧前被销毁；
          // 根导航上下文仍然有效，应由它承载删除确认弹窗。
          if (!dialogContext.mounted) {
            Log.warn('Skip delete confirmation because root navigator is gone: '
                '${view.id}');
            return;
          }
          await _handleDeleteAction(
            dialogContext: dialogContext,
            refreshSpaceBloc: refreshSpaceBloc,
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
        try {
          Log.info(
            '[CrossSpaceMove] 更多菜单触发 view=${view.id} '
            'parent=${view.parentViewId} target=${target.id}',
          );
        } catch (_) {}
        final result = await ViewBackendService.getView(view.parentViewId);
        if (!context.mounted) return;
        final parentView = result.fold((parent) => parent, (_) => null);
        if (parentView == null && view.parentViewId.isNotEmpty) {
          result.fold(
            (_) {},
            (f) => Log.warn(
              '[CrossSpaceMove] 获取源父页面失败，继续按祖先链解析: ${f.msg}',
            ),
          );
        }
        await moveViewCrossSpace(
          context,
          space,
          view,
          parentView,
          FolderSpaceType.unknown,
          view,
          target.id,
        );

        // the move action is handled in the button itself
        break;
      default:
        throw UnimplementedError();
    }
  }

  Future<void> _handleDeleteAction({
    required BuildContext dialogContext,
    required SpaceBloc? refreshSpaceBloc,
  }) async {
    final (containPublishedPage, _) =
        await ViewBackendService.containPublishedPage(view);
    // 异步检查期间弹层上下文可能已被销毁，后续只需要导航上下文。
    if (!dialogContext.mounted) {
      Log.warn('Skip delete confirmation after view check: ${view.id}');
      return;
    }

    if (containPublishedPage) {
      await showConfirmDeletionDialog(
        context: dialogContext,
        name: view.nameOrDefault,
        description: LocaleKeys.publish_containsPublishedPage.tr(),
        onConfirm: () {
          Log.info(
            'Confirm delete published view from more actions: ${view.id}',
          );
          unawaited(
            _onDeleteConfirmed(
              navigationContext: dialogContext,
              refreshSpaceBloc: refreshSpaceBloc,
            ),
          );
        },
      );
    } else {
      await showDeleteViewToTrashConfirmDialog(
        context: dialogContext,
        name: view.nameOrDefault,
        onConfirm: () {
          Log.info('Confirm delete view from more actions: ${view.id}');
          unawaited(
            _onDeleteConfirmed(
              navigationContext: dialogContext,
              refreshSpaceBloc: refreshSpaceBloc,
            ),
          );
        },
      );
    }
  }

  Future<void> _onDeleteConfirmed({
    required BuildContext navigationContext,
    required SpaceBloc? refreshSpaceBloc,
  }) async {
    // 删除后 Folder 无法再追溯父级链，必须在提交删除前保存所属空间。
    final mobileSpaceId =
        PlatformInfo.isMobile ? await resolveViewSpaceId(view) : null;
    final didTriggerDelete = await _triggerDelete();
    if (!didTriggerDelete) {
      return;
    }

    // 移动端使用 MobileSpaceListRefreshNotifier；桌面端使用捕获的 SpaceBloc。
    // 两套刷新机制互斥，避免移动端重复重建临时 SpaceBloc。
    if (!PlatformInfo.isMobile) {
      _refreshSpaceListIfNeeded(refreshSpaceBloc);
    }
    if (navigationContext.mounted) {
      _returnToMobileHomeIfDeletingCurrentView(navigationContext);
    }
    _refreshMobileSpaceListIfNeeded(mobileSpaceId);
  }

  void _refreshMobileSpaceListIfNeeded(String? spaceId) {
    if (!PlatformInfo.isMobile || spaceId == null) {
      return;
    }
    MobileSpaceListRefreshNotifier.instance.requestRefresh(spaceId);
    Log.info('Refresh mobile space list after delete: $spaceId/${view.id}');
  }

  void _returnToMobileHomeIfDeletingCurrentView(BuildContext actionContext) {
    if (!PlatformInfo.isMobile ||
        getIt<MenuSharedState>().latestOpenView?.id != view.id) {
      return;
    }

    // 先清除旧入口，避免首页或最近访问继续指向已移入废纸篓的文档。
    getIt<MenuSharedState>().latestOpenView = null;
    GoRouter.of(actionContext).go(MobileHomeScreen.routeName);
  }

  void _refreshSpaceListIfNeeded(SpaceBloc? spaceBloc) {
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      if (spaceBloc == null || spaceBloc.isClosed) {
        return;
      }

      spaceBloc.add(const SpaceEvent.didUpdateCurrentSpaceChildViews());
      Log.info('Refresh SpaceBloc after delete: ${view.id}');
    });
  }

  SpaceBloc? _tryReadSpaceBloc(BuildContext context) {
    try {
      return context.read<SpaceBloc>();
    } catch (_) {
      return null;
    }
  }

  Future<bool> _triggerDelete() async {
    if (view.layout != ViewLayoutPB.Chat) {
      try {
        final (_, publishedPages) =
            await ViewBackendService.containPublishedPage(view);
        await Future.wait(
          publishedPages.map(
            (publishedView) => ViewBackendService.unpublish(publishedView),
          ),
        );
      } catch (e) {
        Log.error('unpublish before delete failed in more actions: $e');
      }
    }

    final deleteResult = await ViewBackendService.deleteView(viewId: view.id);
    await deleteResult.fold(
      (_) async {
        await getIt<CachedRecentService>().updateRecentViews(
          [view.id],
          false,
        );
      },
      (error) {
        Log.error('delete view failed in more actions: $error');
      },
    );
    return deleteResult.isSuccess;
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
