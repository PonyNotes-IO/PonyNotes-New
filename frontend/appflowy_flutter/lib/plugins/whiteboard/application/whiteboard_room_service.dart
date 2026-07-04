import 'dart:math';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:appflowy_backend/log.dart';

class WhiteboardRoom {
  const WhiteboardRoom({
    required this.roomId,
    required this.roomKey,
  });

  final String roomId;
  final String roomKey;
}

class WhiteboardRoomService {
  static const String _roomIdPrefix = 'whiteboard_room_id_';
  static const String _roomKeyPrefix = 'whiteboard_room_key_';

  static Future<WhiteboardRoom?> getRoom(String viewId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final roomId = prefs.getString('$_roomIdPrefix$viewId');
      final roomKey = prefs.getString('$_roomKeyPrefix$viewId');

      if (roomId != null && roomKey != null) {
        Log.debug('🔍 [WhiteboardRoomService] Found room for view $viewId: $roomId');
        return WhiteboardRoom(roomId: roomId, roomKey: roomKey);
      }
    } catch (e) {
      Log.error('❌ [WhiteboardRoomService] Failed to get room: $e');
    }
    return null;
  }

  static Future<void> saveRoom(String viewId, String roomId, String roomKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_roomIdPrefix$viewId', roomId);
      await prefs.setString('$_roomKeyPrefix$viewId', roomKey);
      Log.debug('✅ [WhiteboardRoomService] Saved room for view $viewId: $roomId');
    } catch (e) {
      Log.error('❌ [WhiteboardRoomService] Failed to save room: $e');
    }
  }

  static Future<bool> hasRoom(String viewId) async {
    final room = await getRoom(viewId);
    return room != null;
  }

  static Future<void> deleteRoom(String viewId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_roomIdPrefix$viewId');
      await prefs.remove('$_roomKeyPrefix$viewId');
      Log.debug('🗑️ [WhiteboardRoomService] Deleted room for view $viewId');
    } catch (e) {
      Log.error('❌ [WhiteboardRoomService] Failed to delete room: $e');
    }
  }

  static String generateRoomId() {
    final random = Random.secure();
    final bytes = List<int>.generate(10, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String generateRoomKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final base64 = base64Url.encode(bytes);
    return base64.replaceAll('=', '');
  }
}