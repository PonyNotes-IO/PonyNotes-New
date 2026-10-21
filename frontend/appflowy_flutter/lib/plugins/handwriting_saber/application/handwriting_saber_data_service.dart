import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'handwriting_file_store.dart';
import 'package:uuid/uuid.dart';

import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-handwriting-saber/entities.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;
import 'package:path/path.dart' as p;

class HandwritingSaberSnapshot {
  const HandwritingSaberSnapshot({
    required this.collabData,
    required this.localData,
  });

  final List<int> collabData;
  final List<int> localData;
}

typedef HandwritingSaberSnapshotProvider = HandwritingSaberSnapshot? Function();

/// Saber 手写笔记数据服务
/// 负责手写笔记数据的存储和加载（通过 Rust Collab 接口同步）
typedef HandwritingSession = ({String userId, String workspaceId});

class HandwritingSaberDataService {
  HandwritingSaberDataService()
      : _readRemote = null,
        _writeRemote = null,
        _pathFor = null,
        _readSession = currentSession;

  @visibleForTesting
  HandwritingSaberDataService.forTesting({
    required Future<List<int>> Function(String) readRemote,
    required Future<SaveHandwritingSaberResponsePB> Function(
            SaveHandwritingSaberPayloadPB)
        writeRemote,
    required Future<String> Function(String) pathFor,
    required Future<HandwritingSession> Function() readSession,
  })  : _readRemote = readRemote,
        _writeRemote = writeRemote,
        _pathFor = pathFor,
        _readSession = readSession;

  final Future<List<int>> Function(String)? _readRemote;
  final Future<SaveHandwritingSaberResponsePB> Function(
      SaveHandwritingSaberPayloadPB)? _writeRemote;
  final Future<String> Function(String)? _pathFor;
  final Future<HandwritingSession> Function() _readSession;
  Future<HandwritingSession>? _session;

  static Future<HandwritingSession> currentSession() async {
    final profile = await UserBackendService.getCurrentUserProfile();
    final workspace = await UserBackendService.getCurrentWorkspace();
    return (
      userId:
          profile.fold((u) => u.id.toString(), (e) => throw StateError(e.msg)),
      workspaceId: workspace.fold((w) => w.id, (e) => throw StateError(e.msg)),
    );
  }

  Future<void> _checkSession(HandwritingSession expected) async {
    if (await _readSession() != expected)
      throw StateError('Handwriting session changed');
  }

  Future<SaveHandwritingSaberResponsePB> _submit(
      SaveHandwritingSaberPayloadPB payload) async {
    if (_writeRemote != null) return _writeRemote(payload);
    final result =
        await HandwritingSaberEventSaveHandwritingSaber(payload).send();
    return result.fold((r) => r, (e) => throw StateError(e.msg));
  }

  Future<List<int>> _fetch(String viewId) async {
    if (_readRemote != null) return _readRemote(viewId);
    final result = await HandwritingSaberEventGetHandwritingSaberData(
            ViewIdPB()..value = viewId)
        .send();
    return result.fold((r) => r.sbn2Bytes, (e) => throw StateError(e.msg));
  }

  final Map<String, List<int>> _bases = {};
  final Map<String, Future<bool>> _saves = {};
  final Set<String> _localOnly = {};

  void acceptSnapshot(String viewId, List<int> bytes) {
    _bases[viewId] = Uint8List.fromList(bytes);
  }

  /// Match Rust's deterministic legacy IDs before the editor creates any objects.
  static List<int> normalizeLegacy(String viewId, List<int> bytes) {
    if (bytes.isEmpty) return bytes;
    final doc = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final pages = doc['pages'] as List;
    for (var i = 0; i < pages.length; i++) {
      final page = pages[i] as Map<String, dynamic>;
      page['id'] ??= const Uuid().v5(Namespace.oid.value, '$viewId/pages/$i');
      for (final kind in const [
        'strokes',
        'images',
        'webViews',
        'textBoxes',
        'listBoxes',
        'taskListBoxes'
      ]) {
        final items = page[kind] as List? ?? [];
        for (var j = 0; j < items.length; j++) {
          final item = items[j] as Map<String, dynamic>;
          final id =
              const Uuid().v5(Namespace.oid.value, '$viewId/pages/$i/$kind/$j');
          item['id'] ??= kind == 'webViews' ? _numericId(id) : id;
        }
      }
    }
    return utf8.encode(jsonEncode(doc));
  }

  /// 页面注册的 reload 回调（导入成功后调用，触发页面重新加载数据）
  static final Map<String, void Function()> _reloadCallbacks = {};
  static final Map<String, HandwritingSaberSnapshotProvider>
      _snapshotProviders = {};

  static void registerReloadCallback(String viewId, void Function() cb) {
    _reloadCallbacks[viewId] = cb;
  }

  static void unregisterReloadCallback(String viewId) {
    _reloadCallbacks.remove(viewId);
  }

  static void triggerReload(String viewId) {
    _reloadCallbacks[viewId]?.call();
  }

  static void registerSnapshotProvider(
    String viewId,
    HandwritingSaberSnapshotProvider provider,
  ) {
    _snapshotProviders[viewId] = provider;
  }

  static void unregisterSnapshotProvider(String viewId) {
    _snapshotProviders.remove(viewId);
  }

  /// 获取用于复制的最新数据。当前画布已打开时直接抓取内存快照，避免尚在
  /// 防抖窗口内的笔迹没有写入 Collab；否则从 Collab 和本地备份读取。
  Future<HandwritingSaberSnapshot> captureSnapshotForDuplicate(
    String viewId,
  ) async {
    final provider = _snapshotProviders[viewId];
    if (provider != null) {
      try {
        final snapshot = provider();
        if (snapshot != null) {
          Log.info(
            '[HandwritingSaber] Captured live duplicate snapshot: $viewId, '
            'collab=${snapshot.collabData.length} bytes, '
            'local=${snapshot.localData.length} bytes',
          );
          return snapshot;
        }
      } catch (e) {
        Log.warn(
          '[HandwritingSaber] Failed to capture live duplicate snapshot: $e',
        );
      }
    }

    final collabData = await loadHandwritingSaberData(viewId);
    final localData = await loadLocalBackupData(viewId);
    return HandwritingSaberSnapshot(
      collabData: collabData.isNotEmpty ? collabData : localData,
      localData: localData.isNotEmpty ? localData : collabData,
    );
  }

  /// 将源手写笔记快照写入刚创建的副本。
  Future<bool> restoreSnapshotToDuplicate(
    String viewId,
    HandwritingSaberSnapshot snapshot,
  ) async {
    final saved = await saveHandwritingSaberData(
      viewId,
      snapshot.collabData,
      localData:
          snapshot.localData.isEmpty ? snapshot.collabData : snapshot.localData,
    );
    if (!saved) {
      return false;
    }

    triggerReload(viewId);
    return true;
  }

  /// 获取手写笔记数据存储目录（用于本地文件缓存回退）
  Future<String> _getHandwritingSaberDirectory() async {
    final basePath = await getIt<ApplicationDataStorage>().getPath();
    final userProfileResult = await UserBackendService.getCurrentUserProfile();
    final userId = userProfileResult.fold(
      (profile) => profile.id.toString(),
      (error) {
        Log.error(
            '[HandwritingSaber] Failed to get user profile: ${error.msg}');
        return '';
      },
    );
    final handwritingSaberPath = userId.isNotEmpty
        ? p.join(basePath, userId, 'handwriting_saber')
        : p.join(basePath, 'handwriting_saber');
    final directory = Directory(handwritingSaberPath);
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return handwritingSaberPath;
  }

  Future<String> _getHandwritingSaberFilePath(String viewId) async {
    if (_pathFor != null) return _pathFor(viewId);
    final directory = await _getHandwritingSaberDirectory();
    return p.join(directory, '$viewId.sbn2');
  }

  /// 创建手写笔记
  Future<FlowyResult<void, FlowyError>> createHandwritingSaber({
    required String viewId,
    List<int>? initialData,
  }) async {
    try {
      final payload = CreateHandwritingSaberPayloadPB()..viewId = viewId;
      if (initialData != null && initialData.isNotEmpty) {
        payload.initialData = initialData;
      }
      final result =
          await HandwritingSaberEventCreateHandwritingSaber(payload).send();
      return result.fold(
        (_) {
          Log.info('[HandwritingSaber] ✅ Created via Rust/Collab: $viewId');
          return FlowyResult.success(null);
        },
        (error) {
          Log.error(
            '[HandwritingSaber] ❌ Failed to create via Rust/Collab: ${error.msg}',
          );
          return FlowyResult.failure(error);
        },
      );
    } catch (e, stackTrace) {
      Log.error(
        '[HandwritingSaber] Exception in createHandwritingSaber: $e\n$stackTrace',
      );
      return FlowyResult.failure(
        FlowyError(msg: 'Failed to create handwriting saber: $e'),
      );
    }
  }

  /// 打开手写笔记（加载到 Collab 内存）
  Future<FlowyResult<void, FlowyError>> openHandwritingSaber({
    required String viewId,
  }) async {
    try {
      final payload = ViewIdPB()..value = viewId;
      final result =
          await HandwritingSaberEventOpenHandwritingSaber(payload).send();
      return result.fold(
        (_) {
          Log.info('[HandwritingSaber] ✅ Opened via Rust/Collab: $viewId');
          return FlowyResult.success(null);
        },
        (error) {
          Log.error(
            '[HandwritingSaber] ❌ Failed to open via Rust/Collab: ${error.msg}',
          );
          return FlowyResult.failure(error);
        },
      );
    } catch (e, stackTrace) {
      Log.error(
        '[HandwritingSaber] Exception in openHandwritingSaber: $e\n$stackTrace',
      );
      return FlowyResult.failure(
        FlowyError(msg: 'Failed to open handwriting saber: $e'),
      );
    }
  }

  /// Serialize local snapshots; the next save must include the preceding local commit.
  Future<bool> saveHandwritingSaberData(
    String viewId,
    List<int> sbn2Data, {
    int? version,
    List<int>? localData,
    String? backupPath,
  }) {
    final snapshot = Uint8List.fromList(sbn2Data);
    final full = Uint8List.fromList(localData ?? sbn2Data);
    final session = _session ??= _readSession();
    final previous = _saves[viewId];
    late final Future<bool> task;
    task = () async {
      if (previous != null) await previous;
      try {
        final identity = await session;
        await _checkSession(identity);
        normalizeLegacy(viewId,
            snapshot); // Reject corrupt input before replacing a backup.
        final editedBase = _localOnly.contains(viewId)
            ? <int>[]
            : (_bases[viewId] ?? await loadHandwritingSaberData(viewId));
        final path = backupPath ?? await _getHandwritingSaberFilePath(viewId);
        await _checkSession(identity);
        await HandwritingFileStore.write(
            '$path.pending',
            utf8.encode(jsonEncode({
              'base': base64Encode(editedBase),
              'next': base64Encode(snapshot),
              'userId': identity.userId,
              'workspaceId': identity.workspaceId,
            })),
            keepBackups: false);
        await HandwritingFileStore.write(path, full);
        final response = await _submit(SaveHandwritingSaberPayloadPB()
          ..viewId = viewId
          ..sbn2Bytes = snapshot
          ..baseSbn2Bytes = editedBase
          ..userId = identity.userId
          ..workspaceId = identity.workspaceId
          ..version = Int64(version ?? 0));
        final pending = File('$path.pending');
        if (await pending.exists()) await pending.delete();
        _localOnly.remove(viewId);
        acceptSnapshot(viewId, response.localSnapshot);
        return true;
      } catch (e) {
        Log.error(
            '[HandwritingSaber] Save failed; recovery files retained: $e');
        return false;
      }
    }()
        .whenComplete(() {
      if (identical(_saves[viewId], task)) _saves.remove(viewId);
    });
    _saves[viewId] = task;
    return task;
  }

  /// Read a merged snapshot, replaying any durable local delta before exposing it.
  Future<List<int>> loadHandwritingSaberData(String viewId,
      {bool acceptAsBase = true}) async {
    final identity = await (_session ??= _readSession());
    await _checkSession(identity);
    final path = await _getHandwritingSaberFilePath(viewId);
    final pending = File('$path.pending');
    Map<String, dynamic>? journal;
    if (await pending.exists()) {
      journal =
          jsonDecode(utf8.decode(await HandwritingFileStore.read(pending.path)))
              as Map<String, dynamic>;
      if (journal['userId'] != identity.userId ||
          journal['workspaceId'] != identity.workspaceId) {
        throw StateError('Pending handwriting belongs to a different session');
      }
    }
    try {
      var bytes = await _fetch(viewId);
      await _checkSession(identity);
      if (journal != null && _saves[viewId] == null) {
        await _submit(SaveHandwritingSaberPayloadPB()
          ..viewId = viewId
          ..userId = identity.userId
          ..workspaceId = identity.workspaceId
          ..baseSbn2Bytes = base64Decode(journal['base'] as String)
          ..sbn2Bytes = base64Decode(journal['next'] as String));
        await pending.delete();
        bytes = await _fetch(viewId);
        await _checkSession(identity);
      }
      if (bytes.isEmpty) {
        bytes = await _readLocalBackup(path, viewId);
        if (bytes.isNotEmpty) _localOnly.add(viewId);
      }
      bytes = normalizeLegacy(viewId, bytes);
      if (acceptAsBase) acceptSnapshot(viewId, bytes);
      return bytes;
    } catch (e) {
      await _checkSession(identity);
      var local = await _readLocalBackup(path, viewId);
      if (local.isEmpty && journal != null)
        local = base64Decode(journal['next'] as String);
      if (local.isEmpty) rethrow;
      final bytes = normalizeLegacy(viewId, local);
      if (acceptAsBase) {
        if (journal != null) {
          acceptSnapshot(viewId, base64Decode(journal['base'] as String));
        } else {
          _localOnly.add(
              viewId); // No known cloud base: publish all local entities without deleting remote ones.
        }
      }
      Log.warn('[HandwritingSaber] Loaded durable local copy: $e');
      return bytes;
    }
  }

  /// 仅读取本地完整备份文件（含 base64 图片字节）。
  ///
  /// 与 [loadHandwritingSaberData] 不同：本方法**只读本地备份**、不走 Collab，
  /// 用于打开笔记时从本地按 id 回填图片字节，避免对本地图片重复联网下载。
  Future<List<int>> loadLocalBackupData(String viewId) => _loadFromFile(viewId);

  /// 从文件系统加载（回退方案）
  Future<List<int>> _readLocalBackup(String path, String viewId) async {
    var found = false;
    for (final candidate in [path, '$path.previous', '$path.legacy']) {
      if (!await File(candidate).exists()) continue;
      found = true;
      try {
        final bytes = await HandwritingFileStore.read(candidate);
        normalizeLegacy(viewId, bytes);
        if (bytes.isNotEmpty) return bytes;
      } catch (e) {
        Log.warn(
            '[HandwritingSaber] Invalid backup retained at $candidate: $e');
      }
    }
    if (found)
      throw const FormatException(
          'No valid handwriting backup; original files retained');
    return <int>[];
  }

  Future<List<int>> _loadFromFile(String viewId) async {
    return _readLocalBackup(await _getHandwritingSaberFilePath(viewId), viewId);
  }

  static int _numericId(String uuid) =>
      int.parse(uuid.replaceAll('-', '').substring(0, 13), radix: 16);

  static int newWebViewId() => _numericId(const Uuid().v4());

  static void assignNewPageIds(Map<String, dynamic> page) {
    page['id'] = const Uuid().v4();
    for (final kind in const [
      'strokes',
      'images',
      'webViews',
      'textBoxes',
      'listBoxes',
      'taskListBoxes'
    ]) {
      for (final item in page[kind] as List? ?? []) {
        item['id'] = kind == 'webViews' ? newWebViewId() : const Uuid().v4();
      }
    }
  }

  Future<bool> replaceDocument(String viewId, List<int> bytes) async {
    await loadHandwritingSaberData(viewId);
    final doc = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    for (final page in doc['pages'] as List) {
      assignNewPageIds(page as Map<String, dynamic>);
    }
    return saveHandwritingSaberData(viewId, utf8.encode(jsonEncode(doc)));
  }

  /// 关闭手写笔记
  Future<FlowyResult<void, FlowyError>> closeHandwritingSaber({
    required String viewId,
  }) async {
    try {
      final payload = ViewIdPB()..value = viewId;
      final result =
          await HandwritingSaberEventCloseHandwritingSaber(payload).send();
      return result.fold(
        (_) {
          Log.info('[HandwritingSaber] ✅ Closed: $viewId');
          return FlowyResult.success(null);
        },
        (error) {
          Log.error(
            '[HandwritingSaber] ❌ Failed to close: ${error.msg}',
          );
          return FlowyResult.failure(error);
        },
      );
    } catch (e, stackTrace) {
      Log.error(
        '[HandwritingSaber] Exception in closeHandwritingSaber: $e\n$stackTrace',
      );
      return FlowyResult.failure(
        FlowyError(msg: 'Failed to close handwriting saber: $e'),
      );
    }
  }

  /// 删除手写笔记
  Future<bool> deleteHandwritingSaber(String viewId) async {
    try {
      final payload = ViewIdPB()..value = viewId;
      final result =
          await HandwritingSaberEventDeleteHandwritingSaber(payload).send();

      return result.fold(
        (_) {
          Log.info('[HandwritingSaber] ✅ Deleted: $viewId');
          return true;
        },
        (error) {
          Log.error(
            '[HandwritingSaber] ❌ Failed to delete: ${error.msg}',
          );
          return false;
        },
      );
    } catch (e) {
      Log.error('[HandwritingSaber] Failed to delete handwriting saber: $e');
      return false;
    }
  }

  /// 计算冲突副本路径。远端内容为空或与本地完全一致时返回 null，不需要备份。
  static String? conflictFilePath({
    required String filePath,
    required List<int> remoteBytes,
    required List<int> localBytes,
    required int timestampMs,
  }) {
    if (remoteBytes.isEmpty) return null;
    if (listEquals(remoteBytes, localBytes)) return null;
    return filePath.replaceFirst(
      RegExp(r'\.sbn2$'),
      '.conflict.$timestampMs.sbn2',
    );
  }

  /// 只保留最近 [keep] 个冲突副本，避免长期积累占满磁盘。
  Future<void> pruneConflictFiles(String viewId, {int keep = 5}) async {
    try {
      final filePath = await _getHandwritingSaberFilePath(viewId);
      final directory = Directory(p.dirname(filePath));
      if (!directory.existsSync()) return;

      final marker = '$viewId.conflict.';
      final files = directory
          .listSync()
          .whereType<File>()
          .where((file) => p.basename(file.path).startsWith(marker))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));

      for (final file in files.skip(keep)) {
        try {
          file.deleteSync();
        } catch (_) {}
      }
    } catch (e) {
      Log.error('[HandwritingSaber] prune conflict files failed: $e');
    }
  }

  /// 仅用于调试：返回本地文件路径
  Future<String> getHandwritingSaberFilePathForDebug(String viewId) async {
    return _getHandwritingSaberFilePath(viewId);
  }

  /// 检查手写笔记数据是否存在（本地文件回退检查）
  Future<bool> handwritingSaberDataExists(String viewId) async {
    try {
      final filePath = await _getHandwritingSaberFilePath(viewId);
      return File(filePath).existsSync();
    } catch (e) {
      Log.error('Failed to check handwriting saber data existence: $e');
      return false;
    }
  }

  /// 获取手写笔记数据大小（本地文件回退）
  Future<int?> getHandwritingSaberDataSize(String viewId) async {
    try {
      final filePath = await _getHandwritingSaberFilePath(viewId);
      final file = File(filePath);
      if (!file.existsSync()) return null;
      return file.lengthSync();
    } catch (e) {
      Log.error('Failed to get handwriting saber data size: $e');
      return null;
    }
  }

  /// 获取手写笔记最后修改时间（本地文件回退）
  Future<DateTime?> getHandwritingSaberLastModified(String viewId) async {
    try {
      final filePath = await _getHandwritingSaberFilePath(viewId);
      final file = File(filePath);
      if (!file.existsSync()) return null;
      return file.lastModifiedSync();
    } catch (e) {
      Log.error('Failed to get handwriting saber last modified time: $e');
      return null;
    }
  }
}
