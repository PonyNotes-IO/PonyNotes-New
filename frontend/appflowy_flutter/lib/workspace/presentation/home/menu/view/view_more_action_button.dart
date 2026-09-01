import 'dart:async';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/workspace/application/sidebar/folder/folder_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/move_to/move_page_menu.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_action_type.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/widgets/lock_page_action.dart';
import 'package:appflowy/workspace/presentation/widgets/pop_up_action.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart'
    hide AFRolePB;
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// ··· button beside the view name
class ViewMoreActionPopover extends StatelessWidget {
  const ViewMoreActionPopover({
    super.key,
    required this.view,
    this.controller,
    required this.onEditing,
    required this.onAction,
    required this.spaceType,
    required this.isExpanded,
    required this.buildChild,
    this.showAtCursor = false,
  });

  final ViewPB view;
  final PopoverController? controller;
  final void Function(bool value) onEditing;
  final FutureOr<void> Function(ViewMoreActionType type, dynamic data) onAction;
  final FolderSpaceType spaceType;
  final bool isExpanded;
  final Widget Function(PopoverController) buildChild;
  final bool showAtCursor;

  @override
  Widget build(BuildContext context) {
    final wrappers = _buildActionTypeWrappers(context);
    return PopoverActionList<ViewMoreActionTypeWrapper>(
      controller: controller,
      direction: PopoverDirection.bottomWithLeftAligned,
      offset: const Offset(0, 8),
      actions: wrappers,
      constraints: const BoxConstraints(minWidth: 260),
      onPopupBuilder: () => onEditing(true),
      buildChild: buildChild,
      onSelected: (_, __) {},
      onClosed: () => onEditing(false),
      showAtCursor: showAtCursor,
    );
  }

  List<ViewMoreActionTypeWrapper> _buildActionTypeWrappers(
    BuildContext context,
  ) {
    final actionTypes = _buildActionTypes(context);
    return actionTypes.map(
      (e) {
        final actionWrapper =
            ViewMoreActionTypeWrapper(e, view, (controller, data) async {
          // 移动操作必须保留承载 ViewBloc 的页面上下文，直到异步流程结束。
          // 其他菜单项仍在请求前退出编辑态。
          if (e != ViewMoreActionType.moveTo) {
            onEditing(false);
          }
          // 移动操作需要等待异步的 section 解析和后端请求完成。
          // 若先关闭外层弹层，承载 ViewBloc 的上下文会被卸载，移动流程
          // 会在 context.mounted 检查处提前退出。
          await onAction(e, data);
          if (e == ViewMoreActionType.moveTo && context.mounted) {
            onEditing(false);
          }
          bool enableClose = true;
          if (data is SelectedEmojiIconResult) {
            if (data.keepOpen) enableClose = false;
          }
          if (enableClose) controller.close();
        });

        return actionWrapper;
      },
    ).toList();
  }

  List<ViewMoreActionType> _buildActionTypes(BuildContext? context) {
    final List<ViewMoreActionType> actionTypes = [];

    // 如果是 Space 类型，显示 Space 专用菜单
    if (view.isSpace) {
      actionTypes.addAll([
        ViewMoreActionType.rename,
        ViewMoreActionType.changeIcon,
        ViewMoreActionType.manageSpace,
        ViewMoreActionType.duplicate, // 复制空间
      ]);

      // 根据用户角色显示删除或离开工作区
      if (context != null) {
        // 改版需求：
        // - 私有空间列表：不展示“退出工作区”，改为展示“删除”
        // - 公共空间列表：如果是自己创建的展示“删除”，不展示“退出工作区”
        final isPrivateSpace = view.spacePermission == SpacePermission.private;

        bool isOwner = false;
        try {
          isOwner = context
                  .read<UserWorkspaceBloc?>()
                  ?.state
                  .currentWorkspace
                  ?.role ==
              AFRolePB.Owner;
        } catch (_) {
          isOwner = false;
        }

        bool isCreator = false;
        try {
          final userId = context.read<UserProfilePB?>()?.id;
          isCreator =
              userId != null && view.hasCreatedBy() && view.createdBy == userId;
        } catch (_) {
          isCreator = false;
        }

        final allowDelete = isOwner || isCreator;

        if (isPrivateSpace) {
          actionTypes.add(ViewMoreActionType.divider);
          // 私有空间：始终提供“删除”入口（是否可删由后续逻辑/后端校验）
          actionTypes.add(ViewMoreActionType.delete);
        } else {
          // 公共空间：仅自己创建/Owner 才展示“删除”，且不再展示“退出工作区”
          if (allowDelete) {
            actionTypes.add(ViewMoreActionType.divider);
            actionTypes.add(ViewMoreActionType.delete);
          }
        }
      } else {
        // 如果无法获取上下文，默认显示删除
        actionTypes.add(ViewMoreActionType.divider);
        actionTypes.add(ViewMoreActionType.delete);
      }
      return actionTypes;
    }

    // 文档类型的菜单（原有逻辑）
    if (spaceType == FolderSpaceType.favorite) {
      actionTypes.addAll([
        ViewMoreActionType.unFavorite,
        ViewMoreActionType.divider,
        ViewMoreActionType.rename,
        if (view.layout != ViewLayoutPB.Chat) ...[
          ViewMoreActionType.changeIcon,
          ViewMoreActionType.duplicate,
        ],
      ]);
    } else {
      actionTypes.add(
        view.isFavorite
            ? ViewMoreActionType.unFavorite
            : ViewMoreActionType.favorite,
      );

      actionTypes.addAll([
        ViewMoreActionType.divider,
        ViewMoreActionType.rename,
      ]);

      // Chat doesn't change icon and duplicate
      if (view.layout != ViewLayoutPB.Chat) {
        actionTypes.addAll([
          ViewMoreActionType.changeIcon,
        ]);

        // 同时显示"复制"和"复制到我的空间"选项，让用户选择
        actionTypes.add(ViewMoreActionType.duplicate);
        // actionTypes.add(ViewMoreActionType.duplicateToMySpace);
      }

      actionTypes.addAll([
        ViewMoreActionType.moveTo,
        ViewMoreActionType.delete,
        ViewMoreActionType.divider,
      ]);
    }

    return actionTypes;
  }
}

class ViewMoreActionTypeWrapper extends CustomActionCell {
  ViewMoreActionTypeWrapper(
    this.inner,
    this.sourceView,
    this.onTap, {
    this.moveActionDirection,
    this.moveActionOffset,
  });

  final ViewMoreActionType inner;
  final ViewPB sourceView;
  final FutureOr<void> Function(PopoverController controller, dynamic data)
      onTap;

  // custom the move to action button
  final PopoverDirection? moveActionDirection;
  final Offset? moveActionOffset;

  @override
  Widget buildWithContext(
    BuildContext context,
    PopoverController controller,
    PopoverMutex? mutex,
  ) {
    Widget child;

    if (inner == ViewMoreActionType.divider) {
      child = _buildDivider();
    } else if (inner == ViewMoreActionType.lastModified) {
      child = _buildLastModified(context);
    } else if (inner == ViewMoreActionType.created) {
      child = _buildCreated(context);
    } else if (inner == ViewMoreActionType.changeIcon) {
      child = _buildEmojiActionButton(context, controller);
    } else if (inner == ViewMoreActionType.moveTo) {
      child = _buildMoveToActionButton(context, controller);
    } else if (inner == ViewMoreActionType.export) {
      // Export action is handled by ExportAction widget, not here
      child = const SizedBox.shrink();
    } else {
      child = _buildNormalActionButton(context, controller);
    }

    if (ViewMoreActionType.disableInLockedView.contains(inner) &&
        sourceView.isLocked) {
      child = LockPageButtonWrapper(
        child: child,
      );
    }

    return child;
  }

  Widget _buildNormalActionButton(
    BuildContext context,
    PopoverController controller,
  ) {
    return _buildActionButton(context, () => onTap(controller, null));
  }

  Widget _buildEmojiActionButton(
    BuildContext context,
    PopoverController controller,
  ) {
    final child = _buildActionButton(context, null);

    return AppFlowyPopover(
      constraints: BoxConstraints.loose(const Size(364, 356)),
      margin: const EdgeInsets.all(0),
      clickHandler: PopoverClickHandler.gestureDetector,
      popupBuilder: (_) => FlowyIconEmojiPicker(
        tabs: const [
          PickerTabType.emoji,
          PickerTabType.icon,
          PickerTabType.custom,
        ],
        documentId: sourceView.id,
        initialType: sourceView.icon.toEmojiIconData().type.toPickerTabType(),
        onSelectedEmoji: (result) => onTap(controller, result),
      ),
      child: child,
    );
  }

  Widget _buildMoveToActionButton(
    BuildContext context,
    PopoverController controller,
  ) {
    final userProfile = context.read<SpaceBloc>().userProfile;
    // move to feature doesn't support in local mode
    if (userProfile.workspaceType != WorkspaceTypePB.ServerW) {
      return const SizedBox.shrink();
    }
    return BlocProvider.value(
      value: context.read<SpaceBloc>(),
      child: BlocBuilder<SpaceBloc, SpaceState>(
        builder: (context, state) {
          final child = _buildActionButton(context, null);
          return AppFlowyPopover(
            constraints: const BoxConstraints(
              maxWidth: 260,
              maxHeight: 345,
            ),
            margin: const EdgeInsets.symmetric(
              horizontal: 14.0,
              vertical: 12.0,
            ),
            clickHandler: PopoverClickHandler.gestureDetector,
            direction:
                moveActionDirection ?? PopoverDirection.rightWithTopAligned,
            offset: moveActionOffset,
            popupBuilder: (movePopoverContext) {
              return BlocProvider.value(
                value: context.read<SpaceBloc>(),
                child: MovePageMenu(
                  sourceView: sourceView,
                  onSelected: (space, view) async {
                    // 在异步移动开始前捕获实际的二级弹层容器，避免 await
                    // 后再次使用已失效的 BuildContext。
                    final movePopoverContainer =
                        PopoverContainer.maybeOf(movePopoverContext);
                    // iOS 上关闭二级弹层可能同步卸载父级 Popover 的业务上下文。
                    // 移动流程需要先从该上下文解析源分区、读取父页面并提交后端，
                    // 因此必须等异步移动完成后再关闭二级弹层。
                    await onTap(controller, (space, view));

                    // 只关闭实际的移动目标弹层，不调用 closeAll，避免影响仍可能
                    // 被异步流程使用的父级状态。移动完成后即使容器已被父级关闭，
                    // 捕获的容器也只会执行一次安全的 close。
                    final closed = movePopoverContainer != null;
                    movePopoverContainer?.close();
                    Log.info(
                      '[CrossSpaceMove] 移动请求完成后关闭目标二级弹层: $closed',
                    );
                  },
                ),
              );
            },
            child: child,
          );
        },
      ),
    );
  }

  Widget _buildDivider() {
    return const Padding(
      padding: EdgeInsets.all(8.0),
      child: FlowyDivider(),
    );
  }

  Widget _buildLastModified(BuildContext context) {
    return Container(
      height: 40,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
      ),
    );
  }

  Widget _buildCreated(BuildContext context) {
    return Container(
      height: 40,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    VoidCallback? onTap,
  ) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: FlowyIconTextButton(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        onTap: onTap,
        // show the error color when delete is hovered
        leftIconBuilder: (onHover) => FlowySvg(
          inner.leftIconSvg,
          color: inner == ViewMoreActionType.delete && onHover
              ? Theme.of(context).colorScheme.error
              : null,
        ),
        rightIconBuilder: (_) => inner.rightIcon,
        iconPadding: 10.0,
        textBuilder: (onHover) => FlowyText.regular(
          inner.name,
          fontSize: 14.0,
          lineHeight: 1.0,
          figmaLineHeight: 18.0,
          color: inner == ViewMoreActionType.delete && onHover
              ? Theme.of(context).colorScheme.error
              : null,
        ),
      ),
    );
  }
}

/// 只关闭“移动到”二级菜单，保留父级“更多”菜单的业务上下文。
///
/// [popoverContext] 必须来自二级 [AppFlowyPopover.popupBuilder]，这样取得的
/// [PopoverContainer] 才是当前实际显示的 Overlay，而不是重建后失效的控制器。
bool closeMovePagePopover(BuildContext popoverContext) {
  final container = PopoverContainer.maybeOf(popoverContext);
  if (container == null) {
    return false;
  }
  container.close();
  return true;
}
