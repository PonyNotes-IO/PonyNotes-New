import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';

/// 白板所属空间判定工具。
///
/// 阶段1：私有空间白板走纯本地存储 + 静默云备份（B 套本地 collab），不建 room；
/// 协作空间白板维持 room 协作（A 套）。
///
/// 判定方式复用既有能力（对齐 unified_view_top_right_actions.dart 的
/// `_getSpacePermission`）：若 view 本身是 space，直接读它的 spacePermission；
/// 否则沿祖先链找到所属 space，读其 spacePermission。
/// `SpacePermission.private` 即私有空间。
///
/// 解析失败或找不到所属 space 时，按「协作空间」处理（返回 false），
/// 以保证不破坏既有 room 协作流程。
Future<bool> isViewInPrivateSpace(ViewPB view) async {
  try {
    if (view.isSpace) {
      return view.spacePermission == SpacePermission.private;
    }

    final ancestorsResult = await ViewBackendService.getViewAncestors(view.id);
    return ancestorsResult.fold(
      (ancestors) {
        for (final ancestor in ancestors.items) {
          if (ancestor.isSpace) {
            return ancestor.spacePermission == SpacePermission.private;
          }
        }
        return false;
      },
      (error) {
        Log.warn(
          '[Whiteboard] isViewInPrivateSpace 获取祖先失败: ${error.msg}，按协作空间处理',
        );
        return false;
      },
    );
  } catch (e) {
    Log.warn('[Whiteboard] isViewInPrivateSpace 异常: $e，按协作空间处理');
    return false;
  }
}

/// 根据创建视图时显式传入的 section 判断是否属于私有空间。
///
/// 在本项目的空间模型下 section 与 space 权限一一对应
/// （私有空间 -> Private，协作空间 -> Public，见 shared_widget.dart 与
/// folder_bloc.dart 的 `toViewSectionPB`），因此创建白板时可直接用 section 快速判定。
///
/// 返回：
/// - `true`  已知属于私有空间；
/// - `false` 已知属于协作空间；
/// - `null`  section 未指定，需回退到 [isViewInPrivateSpace] 依据父视图判定。
bool? isPrivateSectionOrNull(ViewSectionPB? section) {
  if (section == null) {
    return null;
  }
  return section == ViewSectionPB.Private;
}
