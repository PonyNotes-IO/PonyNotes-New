import 'dart:async';
import 'dart:convert';

import 'package:appflowy/mobile/application/mobile_view_migration_handoff.dart';
import 'package:appflowy/mobile/presentation/chat/mobile_chat_screen.dart';
import 'package:appflowy/mobile/presentation/database/board/mobile_board_screen.dart';
import 'package:appflowy/mobile/presentation/database/mobile_calendar_screen.dart';
import 'package:appflowy/mobile/presentation/database/mobile_grid_screen.dart';
import 'package:appflowy/mobile/presentation/presentation.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/app_widget.dart' show AppGlobals;
import 'package:appflowy/workspace/application/recent/cached_recent_service.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flowy_infra/platform_extension.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

extension MobileRouter on BuildContext {
  Future<void> pushView(
    ViewPB view, {
    Map<String, dynamic>? arguments,
    bool addInRecent = true,
    bool showMoreButton = true,
    String? fixedTitle,
    String? blockId,
    List<String>? tabs,
  }) async {
    // set the current view before pushing the new view
    getIt<MenuSharedState>().latestOpenView = view;
    unawaited(getIt<CachedRecentService>().updateRecentViews([view.id], true));
    final queryParameters = view.queryParameters(arguments);

    final isDocumentLikeView = switch (view.layout) {
      ViewLayoutPB.Document ||
      ViewLayoutPB.Notebook ||
      ViewLayoutPB.Folder ||
      ViewLayoutPB.Whiteboard =>
        true,
      _ => false,
    };
    if (isDocumentLikeView) {
      queryParameters[MobileDocumentScreen.viewShowMoreButton] =
          showMoreButton.toString();
      if (fixedTitle != null) {
        queryParameters[MobileDocumentScreen.viewFixedTitle] = fixedTitle;
      }
      if (blockId != null) {
        queryParameters[MobileDocumentScreen.viewBlockId] = blockId;
      }
    }
    if (tabs != null) {
      queryParameters[MobileDocumentScreen.viewSelectTabs] = tabs.join('-');
    }

    final uri = Uri(
      path: view.routeName,
      queryParameters: queryParameters,
    ).toString();
    await push(uri);
  }
}

/// 将当前打开的源白板交接为迁移后新建的目标白板。
///
/// 跨区迁移会创建新 view 并删除旧 view。侧栏刷新不会自动更新已经打开的
/// MobileViewPage，因此必须交接路由；如果用户已经切走或当前页面不是源白板，
/// 则不做任何导航，避免打断用户正在查看的其他页面。
Future<void> replaceCurrentMobileView(
  BuildContext context, {
  required ViewPB oldView,
  required ViewPB newView,
}) async {
  if (!PlatformInfo.isMobile) return;

  // 跨空间移动通常从 useRootNavigator=true 的移动端底部弹层触发。迁移完成时，
  // 发起操作的弹层 context 可能已经卸载；此时改用根导航器 context，避免迁移
  // 已成功但因为旧 context 不再 mounted 而静默跳过页面交接。
  final navigationContext = AppGlobals.rootNavKey.currentContext ?? context;
  if (!navigationContext.mounted) {
    Log.warn(
      '[WhiteboardMigrationUI] 跳过移动端白板交接：根导航 context 已卸载 '
      'old=${oldView.id} new=${newView.id}',
    );
    return;
  }

  final router = GoRouter.of(navigationContext);
  final currentUri = router.routerDelegate.currentConfiguration.uri;
  final menuSharedState = getIt<MenuSharedState>();
  final latestOpenViewId = menuSharedState.latestOpenView?.id;
  final action = migratedMobileViewNavigationAction(
    currentUri: currentUri,
    oldViewId: oldView.id,
    latestOpenViewId: latestOpenViewId,
    hasExpectedHandoff:
        MobileViewMigrationHandoff.isExpectedRemoval(oldView.id),
  );
  if (action == MigratedMobileViewNavigationAction.none) {
    Log.info(
      '[WhiteboardMigrationUI] 跳过移动端白板交接：源白板不是当前打开页面 '
      'old=${oldView.id} uri=$currentUri latestOpen=$latestOpenViewId',
    );
    return;
  }

  final newUri = buildMigratedMobileViewUri(currentUri, newView);

  // 不使用 pop + 延迟 + push：移动操作经常位于根 Navigator 的底部弹层中，
  // pop 只会关闭弹层，并不能保证移除下面的旧白板路由；随后 push 还会让旧路由
  // 因 maintainState=true 继续持有旧 plugin/WebView。
  //
  // /docs 的 MaterialExtendedPage 已按 viewId 设置唯一 key。replace 后新旧 Page
  // 无法 canUpdate，Navigator 会真正移除旧路由并创建新路由，旧白板 State、plugin
  // 与 PlatformView 都随旧路由走标准 dispose 链路，不再依赖任意毫秒数猜测资源释放。
  Log.info(
    '[WhiteboardMigrationUI] 移动端白板路由交接 action=$action: '
    '${oldView.id} → ${newView.id}, uri=$currentUri, '
    'latestOpen=$latestOpenViewId',
  );

  // pushView 正常打开页面时会同步 latestOpenView；迁移后的 replace 也必须完成
  // 同样的状态交接，否则移动端首页和“最近打开”仍会记住已删除的源白板。
  menuSharedState.latestOpenView = newView;

  switch (action) {
    case MigratedMobileViewNavigationAction.replace:
      // 源 /docs 仍在声明式路由栈中时原子替换旧白板。replace 返回值代表
      // “新路由以后被 pop 时的结果”，不能 await 该 Future。
      unawaited(router.replace<void>(newUri.toString()));
      return;
    case MigratedMobileViewNavigationAction.resetToReplacement:
      // 移动菜单可能让 GoRouter 配置先显示为 /home，但旧白板及其 WebView 此时
      // 仍存活。这里用 go 重建为单一的新白板路由，避免 push 把退出中的旧 Route
      // 留在下面而再次产生“两次关闭”；新页面返回按钮在不可 pop 时会 go('/home')。
      router.go(newUri.toString());
      return;
    case MigratedMobileViewNavigationAction.none:
      return;
  }
}

enum MigratedMobileViewNavigationAction {
  replace,
  resetToReplacement,
  none,
}

/// 决定迁移后新白板的路由交接方式。
///
/// 正常的源 `/docs` 使用原子 replace。移动菜单造成的 `/home` 过渡态必须同时
/// 满足“源白板仍是 latestOpen”与“删除门闩已登记”，此时用 go 重建路由；普通
/// 首页以及用户已切换到其他页面的情况不导航。
MigratedMobileViewNavigationAction migratedMobileViewNavigationAction({
  required Uri currentUri,
  required String oldViewId,
  String? latestOpenViewId,
  bool hasExpectedHandoff = false,
}) {
  final uriViewId = currentUri.queryParameters[MobileDocumentScreen.viewId];
  if (uriViewId == oldViewId) {
    return MigratedMobileViewNavigationAction.replace;
  }
  if (hasExpectedHandoff &&
      currentUri.path == MobileHomeScreen.routeName &&
      latestOpenViewId == oldViewId) {
    return MigratedMobileViewNavigationAction.resetToReplacement;
  }
  return MigratedMobileViewNavigationAction.none;
}

/// 判断删除源白板前是否应登记迁移交接门闩。
///
/// 真机上移动菜单的 Overlay 生命周期会让 GoRouter 配置提前变成 `/home`，但旧
/// 白板仍在显示，且 [MenuSharedState.latestOpenView] 仍指向源白板。这个组合是本次
/// 操作的迁移过渡态，不应误判为用户已经离开源白板。
bool shouldPrepareCurrentMobileViewReplacement({
  required Uri currentUri,
  required String oldViewId,
  required String? latestOpenViewId,
}) {
  final currentViewId = currentUri.queryParameters[MobileDocumentScreen.viewId];
  return currentViewId == oldViewId ||
      (currentUri.path == MobileHomeScreen.routeName &&
          latestOpenViewId == oldViewId);
}

/// 在源白板删除前登记移动端路由交接。
///
/// 当前 URI 仍是源白板，或处于“URI 已回首页但源白板仍是 latestOpen”的移动菜单
/// 过渡态时才登记；其他页面不登记，避免抑制正常删除通知。
bool prepareCurrentMobileViewReplacement(
  BuildContext context, {
  required ViewPB oldView,
  required ViewPB newView,
}) {
  if (!PlatformInfo.isMobile) return false;

  final navigationContext = AppGlobals.rootNavKey.currentContext ?? context;
  if (!navigationContext.mounted) return false;

  final currentUri =
      GoRouter.of(navigationContext).routerDelegate.currentConfiguration.uri;
  final latestOpenViewId = getIt<MenuSharedState>().latestOpenView?.id;
  if (!shouldPrepareCurrentMobileViewReplacement(
    currentUri: currentUri,
    oldViewId: oldView.id,
    latestOpenViewId: latestOpenViewId,
  )) {
    Log.info(
      '[WhiteboardMigrationUI] 不登记移动端白板交接：源白板不是当前页面 '
      'old=${oldView.id} uri=$currentUri latestOpen=$latestOpenViewId',
    );
    return false;
  }

  MobileViewMigrationHandoff.begin(
    oldViewId: oldView.id,
    newViewId: newView.id,
  );
  Log.info(
    '[WhiteboardMigrationUI] 已登记移动端白板交接：'
    '${oldView.id} → ${newView.id}, uri=$currentUri, '
    'latestOpen=$latestOpenViewId',
  );
  return true;
}

Uri buildMigratedMobileViewUri(Uri currentUri, ViewPB newView) {
  return Uri(
    path: MobileDocumentScreen.routeName,
    queryParameters: <String, String>{
      ...currentUri.queryParameters,
      MobileDocumentScreen.viewId: newView.id,
      MobileDocumentScreen.viewTitle: newView.name,
    },
  );
}

extension on ViewPB {
  String get routeName {
    switch (layout) {
      case ViewLayoutPB.Document:
      case ViewLayoutPB.Notebook:
      case ViewLayoutPB.Folder:
      case ViewLayoutPB.Whiteboard:
        // Notebook / Folder 本质上是文档（复用 DocumentPlugin 渲染）；
        // Whiteboard 有自己的 plugin，但 mobile 端目前通过 MobileViewPage 统一调度，
        // 暂时复用 MobileDocumentScreen 路由，后续如需独立 screen 再拆。
        return MobileDocumentScreen.routeName;
      case ViewLayoutPB.Grid:
        return MobileGridScreen.routeName;
      case ViewLayoutPB.Calendar:
        return MobileCalendarScreen.routeName;
      case ViewLayoutPB.Board:
        return MobileBoardScreen.routeName;
      case ViewLayoutPB.Chat:
        return MobileChatScreen.routeName;

      default:
        throw UnimplementedError('routeName for $this is not implemented');
    }
  }

  Map<String, dynamic> queryParameters([Map<String, dynamic>? arguments]) {
    switch (layout) {
      case ViewLayoutPB.Document:
      case ViewLayoutPB.Notebook:
      case ViewLayoutPB.Folder:
      case ViewLayoutPB.Whiteboard:
        return {
          MobileDocumentScreen.viewId: id,
          MobileDocumentScreen.viewTitle: name,
        };
      case ViewLayoutPB.Grid:
        return {
          MobileGridScreen.viewId: id,
          MobileGridScreen.viewTitle: name,
          MobileGridScreen.viewArgs: jsonEncode(arguments),
        };
      case ViewLayoutPB.Calendar:
        return {
          MobileCalendarScreen.viewId: id,
          MobileCalendarScreen.viewTitle: name,
        };
      case ViewLayoutPB.Board:
        return {
          MobileBoardScreen.viewId: id,
          MobileBoardScreen.viewTitle: name,
        };
      case ViewLayoutPB.Chat:
        return {
          MobileChatScreen.viewId: id,
          MobileChatScreen.viewTitle: name,
        };
      default:
        throw UnimplementedError(
          'queryParameters for $this is not implemented',
        );
    }
  }
}
