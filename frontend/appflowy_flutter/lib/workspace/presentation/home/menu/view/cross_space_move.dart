import 'package:appflowy/workspace/application/favorite/favorite_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
