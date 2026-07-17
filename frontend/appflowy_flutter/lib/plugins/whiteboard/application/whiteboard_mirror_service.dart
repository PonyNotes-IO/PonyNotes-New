import 'dart:convert';
import 'dart:io';

import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy_backend/log.dart';
import 'package:path/path.dart' as p;

/// 协作白板「本地镜像」存储服务（严格单向：只写「服务器 → 本地」，永不回推服务器）。
///
/// 背景与红线：
/// 协作区白板的权威数据在 room 服务器（xm-arts / 若依）。为支持断网只读浏览，
/// 客户端在「在线加载 / 保存成功」后，把服务器最新场景快照旁路下载到本地一份镜像；
/// 断网时用该镜像做只读渲染。
///
/// **安全红线**：本类只提供「写入本地」与「读取本地」，绝不提供任何上传/回推能力。
/// 之前类似实现曾因「空场景覆盖」丢过真数据，因此镜像与私有白板 B 套的
/// `{userId}/whiteboards/` 目录严格隔离，独立存放于 `{userId}/whiteboard_mirrors/`，
/// 且镜像永远不会被当作权威数据写回 room / collab。
///
/// 空场景防护：`saveMirror` 会拒绝「无任何活元素」的空快照覆盖已有非空镜像，
/// 与 XMGuard「空场景绝不强推」保持同样的保守策略。
class WhiteboardMirrorService {
  static const String _mirrorDirName = 'whiteboard_mirrors';

  Future<String> _getMirrorDirectory() async {
    final basePath = await getIt<ApplicationDataStorage>().getPath();
    final userProfileResult = await UserBackendService.getCurrentUserProfile();
    final userId = userProfileResult.fold(
      (profile) => profile.id.toString(),
      (error) {
        Log.error(
          '[WBMirror] Failed to get user profile: ${error.msg}',
        );
        return '';
      },
    );

    final mirrorPath = userId.isNotEmpty
        ? p.join(basePath, userId, _mirrorDirName)
        : p.join(basePath, _mirrorDirName);

    final directory = Directory(mirrorPath);
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
      Log.info('[WBMirror] Created mirror directory: $mirrorPath');
    }

    return mirrorPath;
  }

  Future<String> _getMirrorFilePath(String viewId) async {
    final directory = await _getMirrorDirectory();
    return p.join(directory, '$viewId.json');
  }

  /// 统计一份镜像数据里的「活元素」数量（排除 isDeleted 墓碑元素）。
  int _countLiveElements(dynamic elements) {
    if (elements is! List) return 0;
    var live = 0;
    for (final el in elements) {
      if (el is Map && el['isDeleted'] == true) continue;
      live++;
    }
    return live;
  }

  /// 写入/覆盖本地镜像（严格单向：仅「服务器 → 本地」）。
  ///
  /// [data] 应包含 `elements`（List）、可选 `files`（Map）、可选 `appState`（Map）、
  /// 可选 `sceneVersion`（int）。
  ///
  /// 空场景防护：若新快照无任何活元素、且本地已存在「非空」镜像，则拒绝覆盖，
  /// 避免过渡性空场景把有效镜像抹掉。返回是否真正写入。
  Future<bool> saveMirror(String viewId, Map<String, dynamic> data) async {
    try {
      final incomingLive = _countLiveElements(data['elements']);

      final filePath = await _getMirrorFilePath(viewId);
      final file = File(filePath);

      if (incomingLive == 0 && file.existsSync()) {
        try {
          final existing =
              jsonDecode(await file.readAsString()) as Map<String, dynamic>;
          final existingLive = _countLiveElements(existing['elements']);
          if (existingLive > 0) {
            Log.warn(
              '[WBMirror] 跳过空镜像覆盖：新快照活元素0，本地已有非空镜像 view=$viewId',
            );
            return false;
          }
        } catch (_) {
          // 已有镜像损坏，允许用新快照覆盖。
        }
      }

      final mirror = <String, dynamic>{
        'type': 'excalidraw',
        'version': 2,
        'source': 'room-mirror',
        'elements': data['elements'] ?? const [],
        'appState': data['appState'] ?? const {},
        'files': data['files'] ?? const {},
        'sceneVersion': data['sceneVersion'],
        'mirroredAt': DateTime.now().toIso8601String(),
        'viewId': viewId,
      };

      await file.writeAsString(jsonEncode(mirror), flush: true);
      Log.info(
        '[WBMirror] 已写入本地镜像 view=$viewId sceneVersion=${data['sceneVersion']} '
        '活元素=$incomingLive files=${_countFiles(mirror['files'])}',
      );
      return true;
    } catch (e) {
      Log.error('[WBMirror] 写入本地镜像失败 view=$viewId: $e');
      return false;
    }
  }

  int _countFiles(dynamic files) => files is Map ? files.length : 0;

  /// 读取本地镜像；不存在返回 null。仅用于断网只读渲染，永不回推服务器。
  Future<Map<String, dynamic>?> loadMirror(String viewId) async {
    try {
      final filePath = await _getMirrorFilePath(viewId);
      final file = File(filePath);
      if (!file.existsSync()) {
        return null;
      }
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      Log.info('[WBMirror] 已读取本地镜像 view=$viewId');
      return data;
    } catch (e) {
      Log.error('[WBMirror] 读取本地镜像失败 view=$viewId: $e');
      return null;
    }
  }

  /// 本地是否存在（非空）镜像。用于离线时判断是否可切只读浏览。
  Future<bool> hasMirror(String viewId) async {
    try {
      final filePath = await _getMirrorFilePath(viewId);
      final file = File(filePath);
      if (!file.existsSync()) return false;
      // 空文件视为无镜像。
      return file.lengthSync() > 0;
    } catch (e) {
      Log.error('[WBMirror] 检查本地镜像失败 view=$viewId: $e');
      return false;
    }
  }

  /// 读取镜像的场景版本（用于去重/诊断），无镜像返回 null。
  Future<int?> mirrorSceneVersion(String viewId) async {
    final data = await loadMirror(viewId);
    final v = data?['sceneVersion'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return null;
  }
}
