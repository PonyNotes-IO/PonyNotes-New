import 'dart:async';
import 'dart:convert';

import 'package:appflowy/mobile/presentation/chat/mobile_chat_screen.dart';
import 'package:appflowy/mobile/presentation/database/board/mobile_board_screen.dart';
import 'package:appflowy/mobile/presentation/database/mobile_calendar_screen.dart';
import 'package:appflowy/mobile/presentation/database/mobile_grid_screen.dart';
import 'package:appflowy/mobile/presentation/presentation.dart';
import 'package:appflowy/mobile/presentation/whiteboard/mobile_whiteboard_screen.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/recent/cached_recent_service.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
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
      case ViewLayoutPB.Whiteboard:
        return MobileWhiteboardScreen.routeName;

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
      case ViewLayoutPB.Whiteboard:
        return {
          MobileWhiteboardScreen.viewId: id,
          MobileWhiteboardScreen.viewTitle: name,
        };
      default:
        throw UnimplementedError(
          'queryParameters for $this is not implemented',
        );
    }
  }
}
