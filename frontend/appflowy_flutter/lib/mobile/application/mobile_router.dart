import 'dart:async';
import 'dart:convert';

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

/// 将当前打开的源白板交接为迁移后新建的协作白板。
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
    latestOpenViewId: latestOpenViewId,
    oldViewId: oldView.id,
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

  // 源白板删除通知可能先于迁移 Future 返回，并已经把移动端导航到 /home：
  // - URI 仍是源 /docs：原子 replace，确保旧 Route 被移除；
  // - URI 已不是源 /docs、但 latestOpen 仍指向源：说明业务上仍是从源白板发起，
  //   等当前 frame 完成旧 Route 的退出后 push 新白板，保留 /home 作为返回页。
  //
  // replace/push 返回值都代表“新路由以后被 pop 时的结果”，不能 await 该 Future。
  if (action == MigratedMobileViewNavigationAction.replace) {
    unawaited(router.replace<void>(newUri.toString()));
  } else {
    await WidgetsBinding.instance.endOfFrame;
    unawaited(router.push<void>(newUri.toString()));
  }
}

enum MigratedMobileViewNavigationAction {
  replace,
  push,
  none,
}

/// 源 view 的删除通知可能比迁移 Future 更早到达：移动端旧页面收到
/// DidRemoveMySharedView 后会先 `go('/home')`，此时 URI 已不再携带源 viewId，但
/// [MenuSharedState.latestOpenView] 仍记录着发起移动的源白板。
MigratedMobileViewNavigationAction migratedMobileViewNavigationAction({
  required Uri currentUri,
  required String? latestOpenViewId,
  required String oldViewId,
}) {
  final uriViewId = currentUri.queryParameters[MobileDocumentScreen.viewId];
  if (uriViewId == oldViewId) {
    return MigratedMobileViewNavigationAction.replace;
  }
  if (latestOpenViewId == oldViewId) {
    return MigratedMobileViewNavigationAction.push;
  }
  return MigratedMobileViewNavigationAction.none;
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
