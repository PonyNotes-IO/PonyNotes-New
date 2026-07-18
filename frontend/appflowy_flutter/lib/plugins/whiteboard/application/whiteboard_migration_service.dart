import 'dart:async';
import 'dart:io';

import 'package:appflowy/plugins/whiteboard/application/whiteboard_data_service.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_room_service.dart';
import 'package:appflowy/plugins/whiteboard/presentation/whiteboard_migration_webview.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/widgets.dart';

/// 白板跨空间「内容迁移」编排服务。
///
/// 加解密一律委托 xm-arts 页面自身完成（见 whiteboard_migration_webview.dart）：
/// 客户端无法可靠复现 room 的 AES-GCM 加解密，故不在本地做任何加解密。
///
/// 数据安全红线（贯穿两个方向）：
/// - **源内容全程不删**：迁移期间私有本地 collab / 协作 room 的原内容均保留，
///   任一步失败即中止、由调用方放弃 section 切换 → 白板绝不会变空。
/// - **目标端确认成功后调用方才切 section**：本服务返回 true 才代表内容已安全到达
///   目标存储；返回 false 调用方必须放弃 moveViewV2。
class WhiteboardMigrationService {
  WhiteboardMigrationService._();

  static const String _roomHost = 'https://xm-arts.xiaomabiji.com';

  /// 私有空间白板 → 协作空间：把本地明文内容上传到新建 room（页面自身加密）。
  ///
  /// 步骤：读本地明文 → 建 roomId/roomKey → 隐藏 webview 灌入元素并确认 POST 200 →
  /// 保存 room 元数据（本地 + B 套 collab，供本机路由与多设备）。**不做 section 切换**，
  /// 成功返回 true 由调用方切 section。任一步失败返回 false（源内容原封不动）。
  static Future<bool> migratePrivateToPublic({
    required BuildContext context,
    required ViewPB view,
  }) async {
    final viewId = view.id;
    try {
      final dataService = WhiteboardDataService();
      final data = await dataService.loadWhiteboardData(
        viewId,
        source: 'migration-private-to-public',
      );

      final elements = _asList(data['elements']);
      final liveElements = elements
          .where((e) => !(e is Map && e['isDeleted'] == true))
          .toList();

      final roomId = WhiteboardRoomService.generateRoomId();
      final roomKey = WhiteboardRoomService.generateRoomKey();

      if (liveElements.isEmpty) {
        // 空白板：无内容可丢，直接建 room 元数据并切区即可（跳过上传）。
        Log.info(
          '[WBMigration] 私有→协作：空白板，跳过上传直接建 room view=$viewId',
        );
      } else {
        if (!context.mounted) return false;
        final files = _prepareFilesForPush(data['files']);
        final result = await runWhiteboardMigrationWebView(
          context: context,
          roomId: roomId,
          roomKey: roomKey,
          isPush: true,
          pushPayload: {
            'elements': liveElements,
            'files': files,
          },
        );
        if (!result.ok) {
          Log.error(
            '[WBMigration] 私有→协作 上传失败，已中止（源内容保留）: ${result.error}',
          );
          return false;
        }
      }

      // 上传成功后才写 room 元数据。
      await WhiteboardRoomService.saveRoom(viewId, roomId, roomKey);
      await dataService.saveWhiteboardData(
        viewId,
        {'roomId': roomId, 'roomKey': roomKey},
        source: 'migration-room-init',
      );
      Log.info('[WBMigration] 私有→协作 成功 view=$viewId roomId=$roomId');
      return true;
    } catch (e, s) {
      Log.error('[WBMigration] 私有→协作 异常，已中止: $e\n$s');
      return false;
    }
  }

  /// 协作空间白板 → 私有空间：拉取 room 明文内容写入本地 B 套 collab。
  ///
  /// 步骤：隐藏 webview 让页面 GET+解密+渲染 → 读回明文场景 → **写 B 套 collab 并校验
  /// 写成功** → 清本地 roomId/roomKey → best-effort 删若依残留。**不做 section 切换**，
  /// 成功返回 true 由调用方切 section。任一步失败返回 false（room 原内容原封不动）。
  static Future<bool> migratePublicToPrivate({
    required BuildContext context,
    required ViewPB view,
  }) async {
    final viewId = view.id;
    try {
      final room = await WhiteboardRoomService.getRoom(viewId);
      if (room == null) {
        // 无 room 绑定：本就无协作内容，直接允许切区（不丢内容）。
        Log.info('[WBMigration] 协作→私有：无 room 绑定，直接切区 view=$viewId');
        return true;
      }

      if (!context.mounted) return false;
      final result = await runWhiteboardMigrationWebView(
        context: context,
        roomId: room.roomId,
        roomKey: room.roomKey,
        isPush: false,
      );
      if (!result.ok || result.scene == null) {
        Log.error(
          '[WBMigration] 协作→私有 拉取失败，已中止（room 内容保留）: ${result.error}',
        );
        return false;
      }

      final scene = result.scene!;
      final liveElements = _asList(scene['elements']);

      // 有内容才写 B 套；空白板（合法空房）不写、直接切区。
      if (liveElements.isNotEmpty) {
        final dataService = WhiteboardDataService();
        final payload = <String, dynamic>{
          'type': 'excalidraw',
          'version': 2,
          'elements': liveElements,
          'files': scene['files'] ?? const {},
          'appState': scene['appState'] ?? const {},
        };
        final saved = await dataService.saveWhiteboardData(
          viewId,
          payload,
          source: 'migration-public-to-private',
        );
        if (!saved) {
          Log.error(
            '[WBMigration] 协作→私有 写本地 collab 失败，已中止（room 内容保留）',
          );
          return false;
        }

        // 【校验写成功】回读本地 collab，确认元素已落地，才继续解除 room 绑定。
        final verify = await dataService.loadWhiteboardData(
          viewId,
          source: 'migration-verify',
        );
        final verifyElements = _asList(verify['elements'])
            .where((e) => !(e is Map && e['isDeleted'] == true))
            .toList();
        if (verifyElements.isEmpty) {
          Log.error(
            '[WBMigration] 协作→私有 写后校验为空，已中止（room 内容保留）',
          );
          return false;
        }
      }

      // 本地已是权威副本，解除 room 绑定（本地）。
      await WhiteboardRoomService.deleteRoom(viewId);
      // best-effort 删除若依残留（删不掉不影响：本地已存权威副本，残留仅服务端垃圾）。
      await _bestEffortDeleteRoomScene(room.roomId);

      Log.info('[WBMigration] 协作→私有 成功 view=$viewId');
      return true;
    } catch (e, s) {
      Log.error('[WBMigration] 协作→私有 异常，已中止: $e\n$s');
      return false;
    }
  }

  /// 把 B 套 files（可能只带云 url、无 dataURL）整理成 excalidraw 可加载的文件对象。
  ///
  /// 图片按协调结论「不搬物理文件、URL 随元素带过去」处理：私有白板图片走
  /// PonyNotes-Cloud 的可移植代理 URL，跨空间移动 workspaceId 不变、链接仍有效，
  /// 故把 url 作为 dataURL 传入让 xm-arts 直接按 URL 加载显示。
  static Map<String, dynamic> _prepareFilesForPush(dynamic files) {
    final result = <String, dynamic>{};
    if (files is! Map) return result;
    files.forEach((key, value) {
      if (value is! Map) return;
      final fileMap = Map<String, dynamic>.from(value);
      final id = (fileMap['id'] as String?) ?? key.toString();
      final dataUrl = fileMap['dataURL'] ?? fileMap['url'];
      if (dataUrl == null) return; // 无可用图源，跳过。
      result[key.toString()] = {
        'id': id,
        'dataURL': dataUrl,
        if (fileMap['mimeType'] != null) 'mimeType': fileMap['mimeType'],
        'created': fileMap['created'] ?? DateTime.now().millisecondsSinceEpoch,
      };
    });
    return result;
  }

  /// best-effort 删除若依上的 room 场景残留。若依是否支持 DELETE 未确认——
  /// 任何失败（含 404/405/超时）只记日志、绝不抛出、绝不阻断迁移。
  static Future<void> _bestEffortDeleteRoomScene(String roomId) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final request = await client
          .deleteUrl(Uri.parse('$_roomHost/api/scenes/$roomId'))
          .timeout(const Duration(seconds: 5));
      final response = await request.close().timeout(const Duration(seconds: 5));
      await response.drain<void>();
      Log.info(
        '[WBMigration] best-effort 删若依残留 roomId=$roomId status=${response.statusCode}',
      );
    } catch (e) {
      Log.warn(
        '[WBMigration] best-effort 删若依残留失败(已忽略) roomId=$roomId: $e',
      );
    } finally {
      client?.close(force: true);
    }
  }

  static List<dynamic> _asList(dynamic value) =>
      value is List ? value : const [];
}
