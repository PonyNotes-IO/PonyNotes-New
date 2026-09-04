import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/mobile/application/mobile_router.dart';
import 'package:appflowy/mobile/application/mobile_view_migration_handoff.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_migration_service.dart';
import 'package:appflowy/plugins/whiteboard/presentation/whiteboard_router.dart';
import 'package:appflowy/workspace/application/favorite/favorite_bloc.dart';
import 'package:appflowy/workspace/application/menu/sidebar_sections_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart'
    hide AFRolePB;
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flowy_infra/platform_extension.dart';

/// 文档在「私有空间」与「协作区」之间移动的权限门禁和内容迁移协调器。
///
/// 普通文档只改变 folder 归属；白板还必须先完成本地 collab 与协作 Room 的
/// 内容迁移，再提交 folder move。所以这里要管的是「谁有资格改变归属」和
/// 「所有入口是否遵守同一条迁移顺序」：
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
/// 取不到角色时默认拒绝。跨区移动会改变共享边界，不能使用普通 UI 操作的
/// fail-open 降级策略；服务端仍会重复校验，客户端这里只负责尽早阻止错误操作。
String? crossSpaceMoveDenyReason(
  BuildContext context,
  ViewSectionPB toSection,
) {
  AFRolePB? role;
  try {
    final state = context.read<UserWorkspaceBloc>().state;
    role = state.currentUserRole;
    final workspace = state.currentWorkspace;
    if (role == null && workspace != null && workspace.hasRole()) {
      role = workspace.role;
    }
  } catch (_) {
    role = null;
  }

  return crossSpaceMoveDenyReasonForRole(role, toSection);
}

String? crossSpaceMoveDenyReasonForRole(
  AFRolePB? role,
  ViewSectionPB toSection,
) {
  if (role == null) {
    // 跨空间移动会改变共享边界。角色未加载完成时必须拒绝，避免在权限
    // 状态未知的瞬间放行敏感操作；调用方可在角色加载后重试。
    return toSection == ViewSectionPB.Public
        ? LocaleKeys.space_noPermissionToMoveIntoSharedSpace.tr()
        : LocaleKeys.space_noPermissionToMoveOutOfSharedSpace.tr();
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
  /// 移动事件已经由统一协调器提交。
  moved,

  /// 调用方按原有方式继续移动（切 section）。非白板、以及协作→私有走这条。
  proceed,

  /// 迁移已自行完成移动（在目标区新建白板并删除了源白板），
  /// 调用方**不要**再执行任何移动，否则会去动一个已被删除的 view。
  alreadyMoved,

  /// 已中止并提示过用户，调用方不要移动。
  aborted,
}

bool canCurrentUserMoveWhiteboard(ViewPB view, int currentUserId) {
  return view.layout != ViewLayoutPB.Whiteboard ||
      (view.hasCreatedBy() && view.createdBy.toInt() == currentUserId);
}

bool isOfflinePrivateMove(
  ViewSectionPB? fromSection,
  ViewSectionPB? toSection,
) =>
    fromSection == ViewSectionPB.Private && toSection == ViewSectionPB.Private;

/// 同一视图移动的进程内互斥器。
class CrossSpaceMoveGuard {
  final Set<String> _inFlight = <String>{};

  bool tryAcquire(String viewId) => _inFlight.add(viewId);

  void release(String viewId) => _inFlight.remove(viewId);
}

/// 同一白板跨区移动的进程内互斥器。
///
/// 移动菜单、侧栏拖拽和分区占位符都能进入统一协调器；若手势/菜单回调在很短
/// 时间内重复触发，会同时创建多个迁移 WebView，导致重复失败提示、弹窗互相关闭，
/// 甚至同一份内容被并发写入。不同白板仍可独立迁移，不互相阻塞。
class CrossSpaceWhiteboardMoveGuard extends CrossSpaceMoveGuard {}

final CrossSpaceWhiteboardMoveGuard _whiteboardMoveGuard =
    CrossSpaceWhiteboardMoveGuard();

/// 跨空间移动开始前捕获侧栏相关 Bloc，移动完成后即使菜单/页面 context 已卸载，
/// 仍能刷新目标空间的文档列表。
///
/// 移出协作区会触发 `DidRemoveMySharedView`，移动端可能因此先关闭当前页面和菜单
/// Overlay。若完成回调再通过旧 context 查找 Bloc，刷新会被直接跳过，表现为后端
/// 已移动成功，但目标私有空间列表一直缺少该文档。
class SidebarMoveStateRefresher {
  SidebarMoveStateRefresher({
    required VoidCallback refreshSpaces,
    required VoidCallback refreshFavorites,
  })  : _refreshSpaces = refreshSpaces,
        _refreshFavorites = refreshFavorites;

  factory SidebarMoveStateRefresher.capture(BuildContext context) {
    SpaceBloc? spaceBloc;
    FavoriteBloc? favoriteBloc;
    try {
      spaceBloc = context.read<SpaceBloc>();
    } catch (_) {}
    try {
      favoriteBloc = context.read<FavoriteBloc>();
    } catch (_) {}

    return SidebarMoveStateRefresher(
      refreshSpaces: () {
        if (spaceBloc != null && !spaceBloc.isClosed) {
          spaceBloc.add(const SpaceEvent.didReceiveSpaceUpdate());
        }
      },
      refreshFavorites: () {
        if (favoriteBloc != null && !favoriteBloc.isClosed) {
          favoriteBloc.add(const FavoriteEvent.fetchFavorites());
        }
      },
    );
  }

  final VoidCallback _refreshSpaces;
  final VoidCallback _refreshFavorites;

  void refresh() {
    _refreshSpaces();
    _refreshFavorites();
  }
}

Future<ViewSectionPB?> resolveViewSection(
  BuildContext context,
  ViewPB view, {
  ViewSectionPB? fallback,
}) async {
  if (fallback != null) {
    return fallback;
  }

  SidebarSectionsBloc? sectionsBloc;
  try {
    sectionsBloc = context.read<SidebarSectionsBloc>();
  } catch (_) {}

  var current = view;
  final visited = <String>{};
  while (visited.add(current.id)) {
    if (current.isSpace) {
      return current.spacePermission == SpacePermission.private
          ? ViewSectionPB.Private
          : ViewSectionPB.Public;
    }
    final section = sectionsBloc?.getViewSection(current);
    if (section != null) {
      return section;
    }
    if (current.parentViewId.isEmpty) {
      break;
    }
    final parent = await ViewBackendService.getView(current.parentViewId);
    final next = parent.fold<ViewPB?>((view) => view, (_) => null);
    if (next == null) {
      break;
    }
    current = next;
  }

  // The document toolbar can run in an overlay without SidebarSectionsBloc.
  // Resolve from the authoritative ancestor chain in that case.
  final ancestorsResult = await ViewBackendService.getViewAncestors(view.id);
  final ancestors =
      ancestorsResult.fold<List<ViewPB>?>((value) => value.items, (_) => null);
  if (ancestors != null) {
    for (final ancestor in ancestors) {
      if (ancestor.isSpace) {
        return ancestor.spacePermission == SpacePermission.private
            ? ViewSectionPB.Private
            : ViewSectionPB.Public;
      }
    }
  }
  return null;
}

/// 解析视图所属的顶层空间 ID。
///
/// 移动端文档页中的移动菜单会创建独立的 `SpaceBloc`，其 `currentSpace` 可能尚未
/// 恢复。跨空间判断不能依赖这个临时状态，必须根据文档的父级链读取真实归属。
Future<String?> resolveViewSpaceId(
  ViewPB view,
) async {
  var current = view;
  final visited = <String>{};

  while (visited.add(current.id)) {
    if (current.isSpace) {
      return current.id;
    }
    if (current.parentViewId.isEmpty) {
      break;
    }

    final parentResult = await ViewBackendService.getView(current.parentViewId);
    final parent = parentResult.fold<ViewPB?>((value) => value, (_) => null);
    if (parent == null) {
      break;
    }
    current = parent;
  }

  // 某些移动端缓存只返回当前视图，父级链读取失败时再使用后端祖先接口兜底。
  final ancestorsResult = await ViewBackendService.getViewAncestors(view.id);
  final ancestors =
      ancestorsResult.fold<List<ViewPB>?>((value) => value.items, (_) => null);
  if (ancestors != null) {
    for (final ancestor in ancestors) {
      if (ancestor.isSpace) {
        return ancestor.id;
      }
    }
  }
  return null;
}

/// 菜单移动、拖拽到页面、拖拽到空分区统一经过这里。
///
/// section 或角色信息缺失时拒绝敏感移动；确认跨区后先迁移白板内容，最后才提交
/// Folder move。这样任何入口都无法绕过权限或内容迁移。
Future<CrossSpaceMoveOutcome> coordinateViewMove(
  BuildContext context, {
  required ViewBloc viewBloc,
  required ViewPB view,
  required String targetParentId,
  required String? prevViewId,
  required ViewSectionPB? fromSection,
  required ViewSectionPB? toSection,
  VoidCallback? beforeSubmit,
  FutureOr<void> Function(ViewPB createdView)? onWhiteboardRecreated,
}) async {
  final shouldLockWhiteboardMove = view.layout == ViewLayoutPB.Whiteboard &&
      fromSection != null &&
      toSection != null &&
      fromSection != toSection;
  if (shouldLockWhiteboardMove && !_whiteboardMoveGuard.tryAcquire(view.id)) {
    Log.warn(
      '[CrossSpaceMove] 同一白板已有迁移任务，忽略重复触发 view=${view.id}',
    );
    return CrossSpaceMoveOutcome.aborted;
  }

  try {
    return await _coordinateViewMoveUnlocked(
      context,
      viewBloc: viewBloc,
      view: view,
      targetParentId: targetParentId,
      prevViewId: prevViewId,
      fromSection: fromSection,
      toSection: toSection,
      beforeSubmit: beforeSubmit,
      onWhiteboardRecreated: onWhiteboardRecreated,
    );
  } finally {
    if (shouldLockWhiteboardMove) {
      _whiteboardMoveGuard.release(view.id);
    }
  }
}

Future<CrossSpaceMoveOutcome> _coordinateViewMoveUnlocked(
  BuildContext context, {
  required ViewBloc viewBloc,
  required ViewPB view,
  required String targetParentId,
  required String? prevViewId,
  required ViewSectionPB? fromSection,
  required ViewSectionPB? toSection,
  VoidCallback? beforeSubmit,
  FutureOr<void> Function(ViewPB createdView)? onWhiteboardRecreated,
}) async {
  if (fromSection == null || toSection == null) {
    try {
      Log.warn(
        '[CrossSpaceMove] 分区解析失败，终止移动 view=${view.id} '
        'from=$fromSection to=$toSection',
      );
    } catch (_) {}
    showToastNotification(
      message: crossSpaceMoveDenyReasonForRole(
        null,
        toSection ?? ViewSectionPB.Public,
      ),
      type: ToastificationType.error,
    );
    return CrossSpaceMoveOutcome.aborted;
  }

  if (fromSection != toSection) {
    final denyReason = crossSpaceMoveDenyReason(context, toSection);
    if (denyReason != null) {
      try {
        Log.warn(
          '[CrossSpaceMove] 权限校验失败，终止移动 view=${view.id} '
          'to=$toSection reason=$denyReason',
        );
      } catch (_) {}
      showToastNotification(
        message: denyReason,
        type: ToastificationType.error,
      );
      return CrossSpaceMoveOutcome.aborted;
    }

    if (view.layout == ViewLayoutPB.Whiteboard) {
      int? currentUserId;
      try {
        currentUserId =
            context.read<UserWorkspaceBloc>().state.userProfile.id.toInt();
      } catch (_) {
        currentUserId = null;
      }
      if (currentUserId == null ||
          !canCurrentUserMoveWhiteboard(view, currentUserId)) {
        showToastNotification(
          message: LocaleKeys.space_onlyWhiteboardCreatorCanMove.tr(),
          type: ToastificationType.error,
        );
        return CrossSpaceMoveOutcome.aborted;
      }
    }

    final outcome = await ensureWhiteboardContentMigrated(
      context,
      view: view,
      toSection: toSection,
      targetParentId: targetParentId,
      onWhiteboardRecreated: onWhiteboardRecreated ??
          (createdView) => replaceCurrentWhiteboardView(
                context,
                oldView: view,
                newView: createdView,
              ),
    );
    if (outcome != CrossSpaceMoveOutcome.proceed) {
      return outcome;
    }

    beforeSubmit?.call();
    final result = await ViewBackendService.moveViewV2(
      viewId: view.id,
      newParentId: targetParentId,
      prevViewId: prevViewId,
      fromSection: fromSection,
      toSection: toSection,
    );
    String? errorMessage;
    result.fold((_) {}, (error) => errorMessage = error.msg);
    if (errorMessage != null) {
      Log.error(
        '[CrossSpaceMove] 跨区移动提交失败，原归属与 room 绑定保持不变：'
        'view=${view.id}, error=$errorMessage',
      );
      showToastNotification(
        message: errorMessage!,
        type: ToastificationType.error,
      );
      return CrossSpaceMoveOutcome.aborted;
    }

    if (view.layout == ViewLayoutPB.Whiteboard) {
      WhiteboardRouter.invalidateSpaceTypeCache(view.id);
      if (toSection == ViewSectionPB.Private) {
        await WhiteboardMigrationService.completePublicToPrivate(view.id);
      }
    }
    return CrossSpaceMoveOutcome.moved;
  }

  beforeSubmit?.call();
  final result = isOfflinePrivateMove(fromSection, toSection)
      ? await ViewBackendService.moveViewV2(
          viewId: view.id,
          newParentId: targetParentId,
          prevViewId: prevViewId,
          fromSection: fromSection,
          toSection: toSection,
        )
      : await viewBloc.moveView(
          from: view,
          newParentId: targetParentId,
          prevId: prevViewId,
          fromSection: fromSection,
          toSection: toSection,
        );
  if (result == null) {
    return CrossSpaceMoveOutcome.aborted;
  }

  String? errorMessage;
  result.fold((_) {}, (error) => errorMessage = error.msg);
  if (errorMessage != null) {
    Log.error(
      '[CrossSpaceMove] 同区移动提交失败，原位置保持不变：'
      'view=${view.id}, error=$errorMessage',
    );
    showToastNotification(
      message: errorMessage!,
      type: ToastificationType.error,
    );
    return CrossSpaceMoveOutcome.aborted;
  }
  return CrossSpaceMoveOutcome.moved;
}

/// 迁移成功后交接当前白板页面。
///
/// 移动端使用声明式路由替换；桌面端则通过 TabsBloc 打开新视图。两者都只在
/// 源白板仍是当前打开视图时执行，侧栏后台移动不会打断用户正在看的页面。
Future<void> replaceCurrentWhiteboardView(
  BuildContext context, {
  required ViewPB oldView,
  required ViewPB newView,
}) async {
  if (PlatformInfo.isMobile) {
    await replaceCurrentMobileView(
      context,
      oldView: oldView,
      newView: newView,
    );
    return;
  }

  final tabsBloc = getIt<TabsBloc>();
  final latestOpenView = getIt<MenuSharedState>().latestOpenView;
  final currentPluginId = tabsBloc.state.currentPageManager.plugin.id;
  if (latestOpenView?.id != oldView.id &&
      currentPluginId != oldView.id &&
      !MobileViewMigrationHandoff.isExpectedRemoval(oldView.id)) {
    Log.info(
      '[WhiteboardMigrationUI] 跳过桌面端白板交接：源白板不是当前打开页面 '
      'old=${oldView.id} currentPlugin=$currentPluginId '
      'latestOpen=${latestOpenView?.id}',
    );
    return;
  }

  Log.info(
    '[WhiteboardMigrationUI] 桌面端白板路由交接: '
    '${oldView.id} → ${newView.id}',
  );
  // 源视图删除会同时关闭移动菜单，不能依赖菜单 context 仍挂在树上。
  tabsBloc.openPlugin(newView);
}

/// 在删除源白板前登记当前页面交接。
///
/// 桌面端的共享访问撤销监听也会收到迁移产生的源视图删除通知；若不先登记，
/// 它会抢先打开主页并销毁白板。门闩让监听器只忽略这一次已知删除，目标数据
/// 校验完成后由 [replaceCurrentWhiteboardView] 打开新白板。
bool prepareCurrentWhiteboardReplacement(
  BuildContext context, {
  required ViewPB oldView,
  required ViewPB newView,
}) {
  if (PlatformInfo.isMobile) {
    return prepareCurrentMobileViewReplacement(
      context,
      oldView: oldView,
      newView: newView,
    );
  }

  final tabsBloc = getIt<TabsBloc>();
  final latestOpenViewId = getIt<MenuSharedState>().latestOpenView?.id;
  final currentPluginId = tabsBloc.state.currentPageManager.plugin.id;
  if (!shouldPrepareDesktopWhiteboardReplacement(
    oldViewId: oldView.id,
    latestOpenViewId: latestOpenViewId,
    currentPluginId: currentPluginId,
  )) {
    return false;
  }

  MobileViewMigrationHandoff.begin(
    oldViewId: oldView.id,
    newViewId: newView.id,
  );
  Log.info(
    '[WhiteboardMigrationUI] 已登记桌面端白板交接：'
    '${oldView.id} → ${newView.id}',
  );
  return true;
}

bool shouldPrepareDesktopWhiteboardReplacement({
  required String oldViewId,
  required String? latestOpenViewId,
  required String currentPluginId,
}) =>
    latestOpenViewId == oldViewId || currentPluginId == oldViewId;

Future<CrossSpaceMoveOutcome> ensureWhiteboardContentMigrated(
  BuildContext context, {
  required ViewPB view,
  required ViewSectionPB toSection,
  required String targetParentId,
  FutureOr<void> Function(ViewPB createdView)? onWhiteboardRecreated,
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
    var handoffPrepared = false;
    final created =
        await WhiteboardMigrationService.migratePrivateToPublicAsNewView(
      context: context,
      view: view,
      targetSpaceId: targetParentId,
      beforeSourceDelete: (createdView) {
        handoffPrepared = prepareCurrentWhiteboardReplacement(
          context,
          oldView: view,
          newView: createdView,
        );
      },
    );
    if (created == null) {
      if (handoffPrepared) {
        MobileViewMigrationHandoff.finish(view.id);
      }
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
    try {
      await onWhiteboardRecreated?.call(created);
    } finally {
      if (handoffPrepared) {
        MobileViewMigrationHandoff.finish(view.id);
      }
    }
    return CrossSpaceMoveOutcome.alreadyMoved;
  }

  // 协作 → 私有也采用与私有 → 协作相同的“目标新建 + 内容复制 + 删除源”流程。
  // 目标空间由 createChildViews 稳定刷新，且新 view 只绑定本地 collab，避免保留
  // 原 ID 跨 section 移动造成 Folder 关系索引与可见列表实例之间的竞态。
  var handoffPrepared = false;
  final created =
      await WhiteboardMigrationService.migratePublicToPrivateAsNewView(
    context: context,
    view: view,
    targetSpaceId: targetParentId,
    beforeSourceDelete: (createdView) {
      handoffPrepared = prepareCurrentWhiteboardReplacement(
        context,
        oldView: view,
        newView: createdView,
      );
    },
  );
  if (created == null) {
    if (handoffPrepared) {
      MobileViewMigrationHandoff.finish(view.id);
    }
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

  WhiteboardRouter.invalidateSpaceTypeCache(view.id);
  try {
    await onWhiteboardRecreated?.call(created);
  } finally {
    if (handoffPrepared) {
      MobileViewMigrationHandoff.finish(view.id);
    }
  }
  return CrossSpaceMoveOutcome.alreadyMoved;
}

void refreshSidebarMoveState(BuildContext context) {
  SidebarMoveStateRefresher.capture(context).refresh();
}
