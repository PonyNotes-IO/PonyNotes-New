import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_migration_service.dart';
import 'package:appflowy/plugins/whiteboard/presentation/whiteboard_router.dart';
import 'package:appflowy/workspace/application/favorite/favorite_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart'
    hide AFRolePB;
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// 文档在「私有空间」与「协作区」之间移动的权限门禁。
///
/// 跨区移动**不搬运内容** —— view_id 不变，内容所在的 collab 也不变，改变的
/// 只是它在 folder 里归属哪个 section（见 flowy-folder `move_nested_view`：
/// 只挪树节点 + 增删 private_view_ids）。所以这里要管的不是数据安全，而是
/// 「谁有资格改变文档的归属」：
///
/// - **移入协作区** == 在协作区新增一篇文档 → 需要 Member 及以上；
/// - **移出协作区** == 把文档从协作区拿走 → 需要 Owner。
///
/// 移出之所以要求更高：folder 的 section 是**按 uid 隔离**的
/// （collab-folder `section.rs` 的 `section_id_by_uid`），某个成员把共享文档
/// 移进自己的私有区，等同于把它从其他所有人眼前拿走。这条划分正好对上服务端
/// Casbin 既有的动作模型 —— Member 有 Write，只有 Owner 有 Delete。
///
/// 与服务端 `move-cross-space` 接口（PonyNotes-Cloud-New `cea05695`）
/// **必须保持同一套规则**，两边不一致会表现为「界面放行、服务端拒绝」。
///
/// 返回 `null` 表示放行；返回非空字符串表示阻断，内容即提示文案。
///
/// 角色取自 [UserWorkspaceBloc] 的内存态，**不发网络请求**：跨区移动可由拖拽
/// 触发，是高频交互，不能为此每次去拉一遍工作区成员列表。
///
/// 取不到角色时**放行**，与 `space_bloc.dart` 里 `_checkCreatePermission` 的
/// 降级策略保持一致 —— 宁可漏拦也不误伤正常成员。
String? crossSpaceMoveDenyReason(
  BuildContext context,
  ViewSectionPB toSection,
) {
  final AFRolePB? role;
  try {
    role = context.read<UserWorkspaceBloc>().state.currentUserRole;
  } catch (_) {
    return null;
  }

  if (role == null) {
    return null;
  }

  // 移入协作区：Member 及以上即可，只拦受限成员。
  if (toSection == ViewSectionPB.Public) {
    return role == AFRolePB.Guest
        ? LocaleKeys.space_noPermissionToMoveIntoSharedSpace.tr()
        : null;
  }

  // 移出协作区：仅 Owner。
  return role == AFRolePB.Owner
      ? null
      : LocaleKeys.space_noPermissionToMoveOutOfSharedSpace.tr();
}

/// 跨区移动中白板的处理结果。
enum CrossSpaceMoveOutcome {
  /// 调用方按原有方式继续移动（切 section）。非白板、以及协作→私有走这条。
  proceed,

  /// 迁移已自行完成移动（在目标区新建白板并删除了源白板），
  /// 调用方**不要**再执行任何移动，否则会去动一个已被删除的 view。
  alreadyMoved,

  /// 已中止并提示过用户，调用方不要移动。
  aborted,
}

Future<CrossSpaceMoveOutcome> ensureWhiteboardContentMigrated(
  BuildContext context, {
  required ViewPB view,
  required ViewSectionPB toSection,
  required String targetParentId,
}) async {
  if (view.layout != ViewLayoutPB.Whiteboard) {
    return CrossSpaceMoveOutcome.proceed;
  }

  final toPrivate = toSection == ViewSectionPB.Private;

  // 私有 → 协作：改用「在目标区新建白板 + 复制内容 + 删除源白板」。
  //
  // 老做法保留 view_id 只切 section，会让同一个 view 同时挂着两套存储 ——
  // 原有的本地 collab（B 套，仍在同步）与新建的 room（A 套）。哪一套生效取决于
  // 路由判定，而判定依赖空间归属、room 可达性等多个异步结果；判定走偏一次，
  // 这次编辑就落进了另一套存储，表现为「有时正常、有时丢内容、有时协作者
  // 互相看不到」，且难以复现。新建的 view 只有 room 一套，二义性从根上消失。
  if (!toPrivate) {
    final created =
        await WhiteboardMigrationService.migratePrivateToPublicAsNewView(
      context: context,
      view: view,
      targetSpaceId: targetParentId,
    );
    if (created == null) {
      Log.error(
        '[CrossSpaceMove] 白板迁移失败，源白板保持原样：view=${view.id}',
      );
      showToastNotification(
        message: LocaleKeys.space_whiteboardMigrationFailed.tr(),
        type: ToastificationType.error,
      );
      return CrossSpaceMoveOutcome.aborted;
    }
    // 源 view 已删除，其空间归属缓存必须一并清掉，避免残留影响同 id 的复用。
    WhiteboardRouter.invalidateSpaceTypeCache(view.id);
    return CrossSpaceMoveOutcome.alreadyMoved;
  }

  // 协作 → 私有：维持原有方式（拉取 room 内容写回本地 collab，再由调用方切区）。
  final ok = await WhiteboardMigrationService.migratePublicToPrivate(
    context: context,
    view: view,
  );
  if (!ok) {
    Log.error(
      '[CrossSpaceMove] 白板内容迁移失败，已阻止切区（内容保留在原处）：'
      'view=${view.id}',
    );
    showToastNotification(
      message: LocaleKeys.space_whiteboardMigrationFailed.tr(),
      type: ToastificationType.error,
    );
    return CrossSpaceMoveOutcome.aborted;
  }

  // 内容已到达目标存储，归属随即改变 —— 必须让路由的空间归属缓存失效。
  WhiteboardRouter.invalidateSpaceTypeCache(view.id);
  return CrossSpaceMoveOutcome.proceed;
}

void refreshSidebarMoveState(BuildContext context) {
  try {
    final spaceBloc = context.read<SpaceBloc>();
    if (!spaceBloc.isClosed) {
      spaceBloc.add(const SpaceEvent.didReceiveSpaceUpdate());
      spaceBloc.add(const SpaceEvent.didUpdateCurrentSpaceChildViews());
    }
  } catch (_) {
    // SpaceBloc may be absent in isolated menu contexts.
    // 某些菜单上下文可能没有 SpaceBloc，忽略即可。
  }

  try {
    final favoriteBloc = context.read<FavoriteBloc>();
    if (!favoriteBloc.isClosed) {
      favoriteBloc.add(const FavoriteEvent.fetchFavorites());
    }
  } catch (_) {
    // FavoriteBloc only exists under favorite/sidebar contexts.
    // FavoriteBloc 只存在于最爱/侧栏上下文中。
  }
}
