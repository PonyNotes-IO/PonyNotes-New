import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/workspace/application/favorite/favorite_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart'
    hide AFRolePB;
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
/// - 移入协作区 == 在协作区新增一篇文档，需要**创建**权限；
/// - 移出协作区 == 把文档从协作区拿走，需要**移除**权限。
///
/// 受限成员（Guest）两者皆无。
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

  if (role != AFRolePB.Guest) {
    return null;
  }

  return toSection == ViewSectionPB.Public
      ? LocaleKeys.space_noPermissionToMoveIntoSharedSpace.tr()
      : LocaleKeys.space_noPermissionToMoveOutOfSharedSpace.tr();
}

bool canMoveViewToSpace(
  ViewPB from,
  ViewPB toSpace, {
  ViewPB? parentView,
}) {
  if (from.isSpace || !toSpace.isSpace) {
    return false;
  }

  if (from.id == toSpace.id || from.parentViewId == toSpace.id) {
    return false;
  }

  // Keep referenced database child views inside their database parent.
  // 保持引用数据库子视图留在数据库父级内，避免跨空间移动破坏关系。
  if (parentView != null &&
      from.layout.isDatabaseView &&
      parentView.layout.isDatabaseView) {
    return false;
  }

  return true;
}

Future<bool> moveViewToSpaceFromDropTarget(
  BuildContext context, {
  required ViewPB from,
  required ViewPB toSpace,
  ViewPB? parentView,
}) async {
  if (!canMoveViewToSpace(from, toSpace, parentView: parentView)) {
    return false;
  }

  final result = await ViewBackendService.moveViewV2(
    viewId: from.id,
    newParentId: toSpace.id,
    prevViewId: null,
  );

  return result.fold(
    (_) {
      Log.info(
        'Move view(${from.name}) to space(${toSpace.name}) from drop target',
      );
      refreshSidebarMoveState(context);
      return true;
    },
    (error) {
      Log.error(
        'Move view(${from.name}) to space(${toSpace.name}) failed: ${error.msg}',
      );
      return false;
    },
  );
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
