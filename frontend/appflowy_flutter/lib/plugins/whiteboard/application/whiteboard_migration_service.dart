import 'dart:async';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_data_service.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_room_service.dart';
import 'package:appflowy/plugins/whiteboard/presentation/whiteboard_migration_webview.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
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

  /// 私有空间白板 → 协作区：**在协作区新建一块白板，复制内容，再删除源白板**。
  ///
  /// 返回新建的协作白板；失败返回 null（源白板原封不动）。
  ///
  /// 为什么不沿用「保留 view_id 只切 section」的老做法：那样同一个 view 会同时
  /// 挂着两套存储 —— 原有的本地 collab（B 套，仍在同步）与新建的 room（A 套）。
  /// 哪一套生效取决于路由判定，而判定依赖空间归属、room 可达性等多个异步结果；
  /// 判定走偏一次，这次编辑就落进了另一套存储。表现即「有时正常、有时丢内容、
  /// 有时协作者互相看不到」，且难以复现。
  ///
  /// 新建 view 只有 room 一套存储，源 view 连同其本地 collab 一并删除，
  /// 二义性从根上消失。
  ///
  /// **事务性**：跨「建 view / 传内容 / 删源」三步无法做到真正的原子提交，
  /// 但保证了真正要紧的那条 —— **任何一步失败都不会丢内容**：
  ///   - 内容成功进入新 room 之前，绝不删除源白板；
  ///   - 中途失败则回滚（删掉刚建的空白板），源白板保持原样；
  ///   - 最坏情况是留下一块与源同名的空白板，绝不会两边都没有。
  static Future<ViewPB?> migratePrivateToPublicAsNewView({
    required BuildContext context,
    required ViewPB view,
    required String targetSpaceId,
  }) async {
    final viewId = view.id;
    ViewPB? created;
    try {
      // 1. 先读源内容。读不到就没必要建新 view。
      final dataService = WhiteboardDataService();
      final data = await dataService.loadWhiteboardData(
        viewId,
        source: 'migration-private-to-public',
      );
      final elements = _asList(data['elements']);
      final liveElements =
          elements.where((e) => !(e is Map && e['isDeleted'] == true)).toList();

      // 2. room 凭据必须进入新白板的初始 collab。创建后再补写会与后台首次
      // 上传竞态，后到的空白初始数据可能覆盖 room，其他成员便无法进入同一房间。
      final roomId = WhiteboardRoomService.generateRoomId();
      final roomKey = WhiteboardRoomService.generateRoomKey();

      // 3. 在协作区建一块新白板，名称与源一致。
      if (!context.mounted) return null;
      final createResult = await ViewBackendService.createView(
        layoutType: ViewLayoutPB.Whiteboard,
        parentViewId: targetSpaceId,
        name: view.name,
        // 跨空间迁移创建的新白板与普通新建白板保持一致，插入目标空间顶部。
        index: 0,
        openAfterCreate: false,
        initialDataBytes:
            WhiteboardRoomService.encodeInitialData(roomId, roomKey),
      );
      created = createResult.fold((v) => v, (e) {
        Log.error('[WBMigration] 私有→协作：新建协作白板失败，已中止: ${e.msg}');
        return null;
      });
      if (created == null) return null;

      // 4. 本机保存同一份 room 凭据；服务端初始 collab 已由 createView 携带。
      await WhiteboardRoomService.saveRoom(created.id, roomId, roomKey);

      // 5. 灌内容。空白板无内容可传，直接算成功。
      if (liveElements.isNotEmpty) {
        if (!context.mounted) {
          await _rollbackCreated(created.id);
          return null;
        }
        final files = _prepareFilesForPush(data['files']);
        final result = await runWhiteboardMigrationWebView(
          context: context,
          roomId: roomId,
          roomKey: roomKey,
          isPush: true,
          pushPayload: {'elements': liveElements, 'files': files},
        );
        if (!result.ok) {
          Log.error(
            '[WBMigration] 私有→协作：内容上传失败，已回滚（源白板保留）: ${result.error}',
          );
          await _rollbackCreated(created.id);
          return null;
        }
      } else {
        Log.info('[WBMigration] 私有→协作：源白板为空，跳过内容上传 view=$viewId');
      }

      // 6. 内容已确认到达新 room，此时才删源白板。
      final deleted = await ViewBackendService.deleteView(viewId: viewId);
      var sourceDeleteFailed = false;
      deleted.fold(
        (_) => Log.info('[WBMigration] 私有→协作：源白板已删除 $viewId'),
        (e) {
          sourceDeleteFailed = true;
          Log.error(
            '[WBMigration] 私有→协作：源白板删除失败，正在确认源是否仍存在 $viewId: ${e.msg}',
          );
        },
      );

      if (sourceDeleteFailed) {
        bool? sourceStillExists;
        final sourceCheck = await ViewBackendService.getView(viewId);
        sourceCheck.fold(
          (_) => sourceStillExists = true,
          (error) => sourceStillExists =
              error.code == ErrorCode.RecordNotFound ? false : null,
        );
        if (sourceStillExists == true) {
          await _rollbackCreated(created.id);
          Log.error(
            '[WBMigration] 私有→协作：源仍存在，已回滚新白板避免重复：$viewId',
          );
          return null;
        }
        if (sourceStillExists == null) {
          Log.warn(
            '[WBMigration] 私有→协作：无法确认源删除结果，保留新白板以保证内容不丢：$viewId',
          );
        }
      }

      Log.info(
        '[WBMigration] 私有→协作 完成 源=$viewId 新=${created.id} roomId=$roomId',
      );
      return created;
    } catch (e, s) {
      Log.error('[WBMigration] 私有→协作 异常，已中止: $e\n$s');
      if (created != null) {
        await _rollbackCreated(created.id);
      }
      return null;
    }
  }

  /// 回滚：删掉刚建出来、内容尚未落定的新白板。源白板始终不动。
  static Future<void> _rollbackCreated(String createdViewId) async {
    try {
      await ViewBackendService.deleteView(viewId: createdViewId);
      await WhiteboardRoomService.deleteRoom(createdViewId);
      Log.info('[WBMigration] 已回滚新建的空白板 $createdViewId');
    } catch (e) {
      Log.warn('[WBMigration] 回滚新建白板失败（残留一块空白板）: $createdViewId, $e');
    }
  }

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
      final liveElements =
          elements.where((e) => !(e is Map && e['isDeleted'] == true)).toList();

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
  /// 写成功** → folder 移动成功后清本地 roomId/roomKey，远端 Room 保留为恢复副本。
  /// **不做 section 切换**，
  /// 成功返回 true 由调用方切 section。任一步失败返回 false（room 原内容原封不动）。
  static Future<bool> migratePublicToPrivate({
    required BuildContext context,
    required ViewPB view,
  }) async {
    final viewId = view.id;
    try {
      Log.info('[WBMigration] 协作→私有 开始 view=$viewId');
      final dataService = WhiteboardDataService();
      final room = await _resolveRoomForMigration(viewId, dataService);
      if (room == null) {
        Log.error(
          '[WBMigration] 协作→私有：本地与 collab 均无 room 绑定，已中止 view=$viewId',
        );
        return false;
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
        replace: true,
      );
      if (!saved) {
        Log.error(
          '[WBMigration] 协作→私有 写本地 collab 失败，已中止（room 内容保留）',
        );
        return false;
      }

      // 回读并按元素 id 校验替换结果。空白 room 也必须写入并验证，否则本地残留
      // 元素会在切到私有区后重新出现。
      final verify = await dataService.loadWhiteboardData(
        viewId,
        source: 'migration-verify',
      );
      final verifyElements = _asList(verify['elements'])
          .where((e) => !(e is Map && e['isDeleted'] == true))
          .toList();
      if (!_sameElementIds(liveElements, verifyElements)) {
        Log.error(
          '[WBMigration] 协作→私有 写后校验不一致，已中止（room 内容保留）',
        );
        return false;
      }

      // 此处只完成内容准备。room 要等 folder 跨区移动成功后再解除；否则移动失败
      // 时协作白板会失去原绑定，无法继续在原位置编辑。
      Log.info('[WBMigration] 协作→私有 内容准备完成 view=$viewId');
      return true;
    } catch (e, s) {
      Log.error('[WBMigration] 协作→私有 异常，已中止: $e\n$s');
      return false;
    }
  }

  static Future<void> completePublicToPrivate(String viewId) async {
    await WhiteboardRoomService.deleteRoom(viewId);
    Log.info('[WBMigration] 协作→私有 已解除本地 room，远端副本保留 view=$viewId');
  }

  static Future<WhiteboardRoom?> _resolveRoomForMigration(
    String viewId,
    WhiteboardDataService dataService,
  ) async {
    final localRoom = await WhiteboardRoomService.getRoom(viewId);
    final data = await dataService.loadWhiteboardData(
      viewId,
      source: 'migration-room-lookup',
    );
    final roomId = data['roomId']?.toString() ?? '';
    final roomKey = data['roomKey']?.toString() ?? '';
    if (roomId.isEmpty || roomKey.isEmpty) {
      return localRoom;
    }
    if (localRoom?.roomId != roomId || localRoom?.roomKey != roomKey) {
      await WhiteboardRoomService.saveRoom(viewId, roomId, roomKey);
    }
    return WhiteboardRoom(roomId: roomId, roomKey: roomKey);
  }

  static bool _sameElementIds(List<dynamic> expected, List<dynamic> actual) {
    String? idOf(dynamic element) =>
        element is Map ? element['id']?.toString() : null;
    final expectedIds = expected.map(idOf).whereType<String>().toSet();
    final actualIds = actual.map(idOf).whereType<String>().toSet();
    return expectedIds.length == expected.length &&
        actualIds.length == actual.length &&
        expectedIds.length == actualIds.length &&
        expectedIds.containsAll(actualIds);
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

  static List<dynamic> _asList(dynamic value) =>
      value is List ? value : const [];
}
