import 'package:flutter/material.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy/plugins/util.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_room_service.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_data_service.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_space_util.dart';
import 'package:appflowy/plugins/whiteboard/presentation/remote_whiteboard_page.dart';
import 'package:appflowy/plugins/whiteboard/whiteboard.dart';

class WhiteboardRouter extends StatefulWidget {
  const WhiteboardRouter({
    super.key,
    required this.notifier,
    required this.onViewChanged,
  });

  final ViewPluginNotifier notifier;
  final Function(ViewPB) onViewChanged;

  @override
  State<WhiteboardRouter> createState() => _WhiteboardRouterState();
}

class _WhiteboardRouterState extends State<WhiteboardRouter> {
  String? _roomId;
  String? _roomKey;
  bool _isFetching = false;
  // 是否属于私有空间：
  // - true  私有空间白板 -> 始终走 B 套本地 collab（本地权威 + 静默云备份），忽略 room；
  // - false 协作空间白板 -> 维持现状（有 room 走 RemoteWhiteboardPage）；
  // - null  尚未判定完成（判定完成前不拉取/生成 room，默认渲染 B 套本地页）。
  bool? _isPrivateSpace;

  @override
  void initState() {
    super.initState();
    Log.info('🚀 [WhiteboardRouter] initState called for view: ${widget.notifier.view.id}');
    _resolveSpaceThenFetch(widget.notifier.view);
  }

  @override
  void dispose() {
    Log.info('💀 [WhiteboardRouter] dispose called for view: ${widget.notifier.view.id}');
    Log.info('💀 [WhiteboardRouter] Disposing with roomId: $_roomId, roomKey: $_roomKey');
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant WhiteboardRouter oldWidget) {
    super.didUpdateWidget(oldWidget);
    Log.info('🔄 [WhiteboardRouter] didUpdateWidget: oldView=${oldWidget.notifier.view.id}, newView=${widget.notifier.view.id}');
    if (oldWidget.notifier.view.id != widget.notifier.view.id) {
      Log.info('🔄 [WhiteboardRouter] View changed, resetting roomId/roomKey');
      _roomId = null;
      _roomKey = null;
      _isPrivateSpace = null;
      _resolveSpaceThenFetch(widget.notifier.view);
    }
  }

  /// 先判定白板所属空间，再决定是否拉取/生成 room。
  ///
  /// 私有空间白板：始终走 B 套本地 collab（本地权威 + 静默云备份），
  /// 不建 room、不连 xm-arts，因此完全跳过 room 拉取与自动生成逻辑。
  /// 协作空间白板：维持现状，正常拉取/生成 room。
  Future<void> _resolveSpaceThenFetch(ViewPB view) async {
    bool isPrivate = false;
    try {
      isPrivate = await isViewInPrivateSpace(view);
    } catch (e) {
      Log.warn('⚠️ [WhiteboardRouter] 判定空间失败，按协作空间处理: $e');
      isPrivate = false;
    }

    if (!mounted) return;
    setState(() => _isPrivateSpace = isPrivate);

    if (isPrivate) {
      Log.info(
        '🔒 [WhiteboardRouter] 私有空间白板，走本地 collab（B 套），忽略 room: ${view.id}',
      );
      return;
    }

    Log.info(
      '🤝 [WhiteboardRouter] 协作空间白板，维持 room 流程: ${view.id}',
    );
    await _tryFetchRoomInfo(view);
  }

  Future<void> _tryFetchRoomInfo(ViewPB view) async {
    Log.debug('🔍 [WhiteboardRouter] Initial view: id=${view.id}');

    if (_isFetching) return;
    setState(() => _isFetching = true);

    try {
      final room = await WhiteboardRoomService.getRoom(view.id);
      
      if (room != null) {
        Log.debug('🟢 [WhiteboardRouter] Found room in local storage: roomId=${room.roomId}');
        setState(() {
          _roomId = room.roomId;
          _roomKey = room.roomKey;
        });
      }

      final whiteboardData = await WhiteboardDataService().loadWhiteboardData(view.id);
      Log.debug('🔍 [WhiteboardRouter] Loaded whiteboard data keys: ${whiteboardData.keys}');
      Log.debug('🔍 [WhiteboardRouter] Full whiteboard data: $whiteboardData');
      
      final serverRoomId = whiteboardData['roomId'];
      final serverRoomKey = whiteboardData['roomKey'];
      Log.debug('🔍 [WhiteboardRouter] serverRoomId type: ${serverRoomId.runtimeType}, value: $serverRoomId');
      Log.debug('🔍 [WhiteboardRouter] serverRoomKey type: ${serverRoomKey.runtimeType}, value: $serverRoomKey');

      if (serverRoomId != null && serverRoomId.toString().isNotEmpty && serverRoomKey != null && serverRoomKey.toString().isNotEmpty) {
        final roomIdStr = serverRoomId is String ? serverRoomId : serverRoomId.toString();
        final roomKeyStr = serverRoomKey is String ? serverRoomKey : serverRoomKey.toString();
        
        Log.debug('🟢 [WhiteboardRouter] Found room in server data: roomId=$roomIdStr');
        
        if (roomIdStr != _roomId || roomKeyStr != _roomKey) {
          await WhiteboardRoomService.saveRoom(view.id, roomIdStr, roomKeyStr);
          Log.debug('✅ [WhiteboardRouter] Synced server room to local storage: roomId=$roomIdStr');
        }
        
        setState(() {
          _roomId = roomIdStr;
          _roomKey = roomKeyStr;
        });
        return;
      }

      if (_roomId != null && _roomKey != null) {
        Log.debug('🟢 [WhiteboardRouter] Using existing room from local storage: roomId=$_roomId');
        return;
      }

      Log.debug('🟡 [WhiteboardRouter] No room found for view ${view.id}, generating new one');
      final newRoomId = WhiteboardRoomService.generateRoomId();
      final newRoomKey = WhiteboardRoomService.generateRoomKey();
      
      Log.info('🆕 [WhiteboardRouter] Generated NEW roomId=$newRoomId, roomKey=$newRoomKey for view ${view.id}');
      
      await WhiteboardRoomService.saveRoom(view.id, newRoomId, newRoomKey);
      Log.info('✅ [WhiteboardRouter] Saved room to local storage: viewId=${view.id}, roomId=$newRoomId');
      
      Log.info('📤 [WhiteboardRouter] Saving room info to server...');
      final saveResult = await WhiteboardDataService().saveWhiteboardData(
        view.id,
        {
          'roomId': newRoomId,
          'roomKey': newRoomKey,
        },
        source: 'room-init',
      );
      
      if (saveResult) {
        Log.info('✅ [WhiteboardRouter] SUCCESSFULLY saved room info to server: roomId=$newRoomId, roomKey=$newRoomKey');
        // 立即验证：尝试从服务端读取回来
        Log.info('🔍 [WhiteboardRouter] Verifying save by loading from server...');
        final verifyData = await WhiteboardDataService().loadWhiteboardData(view.id, source: 'room-verify');
        final verifyRoomId = verifyData['roomId'];
        final verifyRoomKey = verifyData['roomKey'];
        Log.info('🔍 [WhiteboardRouter] Verification result: roomId=$verifyRoomId, roomKey=$verifyRoomKey');
        if (verifyRoomId == newRoomId && verifyRoomKey == newRoomKey) {
          Log.info('✅✅ [WhiteboardRouter] VERIFICATION PASSED: saved and loaded roomId/roomKey match!');
        } else {
          Log.error('❌❌ [WhiteboardRouter] VERIFICATION FAILED: saved roomId=$newRoomId, loaded roomId=$verifyRoomId');
          Log.error('❌❌ [WhiteboardRouter] VERIFICATION FAILED: saved roomKey=$newRoomKey, loaded roomKey=$verifyRoomKey');
        }
      } else {
        Log.error('❌ [WhiteboardRouter] FAILED to save room info to server');
      }
      
      setState(() {
        _roomId = newRoomId;
        _roomKey = newRoomKey;
      });
    } catch (e) {
      Log.error('❌ [WhiteboardRouter] Error fetching/generating room: $e');
    } finally {
      setState(() => _isFetching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ViewPB>(
      valueListenable: widget.notifier.viewNotifier,
      builder: (context, view, child) {
        // 空间归属判定完成前，先渲染中性占位，避免在（协作空间）判定窗口内
        // 误挂载 B 套本地 collab 页而触发多余的云端 collab 初始化。
        if (_isPrivateSpace == null) {
          return const ColoredBox(
            color: Color(0xFFFFFFFF),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        // 私有空间白板：始终渲染 B 套 WhiteboardPage（本地 collab + 静默云备份），忽略 room。
        if (_isPrivateSpace == true) {
          Log.debug('🔒 [WhiteboardRouter] 私有空间，使用本地 WhiteboardPage（B 套）: ${view.id}');
          return WhiteboardPage(
            key: ValueKey('whiteboard_page_${view.id}'),
            view: view,
            onViewChanged: widget.onViewChanged,
          );
        }
        // 协作空间白板：有 room 走 RemoteWhiteboardPage（A 套），否则回退 B 套。
        if (_roomId != null && _roomKey != null) {
          Log.debug('🟢 [WhiteboardRouter] Using RemoteWhiteboardPage: roomId=$_roomId, roomKey=$_roomKey');
          return RemoteWhiteboardPage(
            key: ValueKey('remote_whiteboard_page_${view.id}'),
            view: view,
            roomId: _roomId!,
            roomKey: _roomKey!,
          );
        } else {
          Log.debug('🔵 [WhiteboardRouter] Using WhiteboardPage: roomId=$_roomId, roomKey=$_roomKey');
          return WhiteboardPage(
            key: ValueKey('whiteboard_page_${view.id}'),
            view: view,
            onViewChanged: widget.onViewChanged,
          );
        }
      },
    );
  }
}