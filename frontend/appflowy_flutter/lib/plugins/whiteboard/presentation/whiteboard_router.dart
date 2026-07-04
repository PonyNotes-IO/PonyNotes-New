import 'package:flutter/material.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy/plugins/util.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_room_service.dart';
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

  @override
  void initState() {
    super.initState();
    _tryFetchRoomInfo(widget.notifier.view);
  }

  @override
  void didUpdateWidget(covariant WhiteboardRouter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notifier.view.id != widget.notifier.view.id) {
      _roomId = null;
      _roomKey = null;
      _tryFetchRoomInfo(widget.notifier.view);
    }
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
        return;
      }

      Log.debug('🟡 [WhiteboardRouter] No room found for view ${view.id}, generating new one');
      final newRoomId = WhiteboardRoomService.generateRoomId();
      final newRoomKey = WhiteboardRoomService.generateRoomKey();
      
      await WhiteboardRoomService.saveRoom(view.id, newRoomId, newRoomKey);
      Log.debug('✅ [WhiteboardRouter] Generated and saved new room: viewId=${view.id}, roomId=$newRoomId');
      
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
        if (_roomId != null && _roomKey != null) {
          Log.debug('🟢 [WhiteboardRouter] Using RemoteWhiteboardPage: roomId=$_roomId');
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