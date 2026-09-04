import 'dart:io';

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
class HandwritingSaberDataService {
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
    );
    if (!saved) {
      return false;
    }

    if (snapshot.localData.isNotEmpty) {
      try {
        final filePath = await _getHandwritingSaberFilePath(viewId);
        await File(filePath).writeAsBytes(snapshot.localData, flush: true);
        Log.info(
          '[HandwritingSaber] Copied local backup to duplicate: $viewId, '
          'size=${snapshot.localData.length} bytes',
        );
      } catch (e) {
        Log.warn(
          '[HandwritingSaber] Failed to copy local backup to duplicate: $e',
        );
      }
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
        Log.error('[HandwritingSaber] Failed to get user profile: ${error.msg}');
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

  /// 保存手写笔记数据（通过 Rust Collab 接口）
  Future<bool> saveHandwritingSaberData(
    String viewId,
    List<int> sbn2Data, {
    int? version,
  }) async {
    Log.info('[HandwritingSaber] saveHandwritingSaberData() ViewID=$viewId, '
        'size=${sbn2Data.length} bytes');

    try {
      final payload = SaveHandwritingSaberPayloadPB()
        ..viewId = viewId
        ..sbn2Bytes = sbn2Data
        ..version = Int64(version ?? 1);

      final result =
          await HandwritingSaberEventSaveHandwritingSaber(payload).send();

      return result.fold(
        (response) {
          Log.info(
            '[HandwritingSaber] ✅ Saved to Rust/Collab, new version: ${response.newVersion}',
          );
          return true;
        },
        (error) {
          Log.error(
            '[HandwritingSaber] ❌ Failed to save to Rust/Collab: ${error.msg}',
          );
          return false;
        },
      );
    } catch (e, stackTrace) {
      Log.error('[HandwritingSaber] ❌ Exception in saveHandwritingSaberData: $e');
      Log.error('[HandwritingSaber] Stack trace: $stackTrace');
      return false;
    }
  }

  /// 加载手写笔记数据（从 Rust Collab 接口，Collab 为空或失败时回退到本地文件）
  Future<List<int>> loadHandwritingSaberData(String viewId) async {
    Log.info('[HandwritingSaber] loadHandwritingSaberData() ViewID=$viewId');

    try {
      final payload = ViewIdPB()..value = viewId;
      final result =
          await HandwritingSaberEventGetHandwritingSaberData(payload).send();

      return await result.fold(
        (data) async {
          Log.info(
            '[HandwritingSaber] ✅ Loaded from Rust/Collab: $viewId, '
            'size: ${data.sbn2Bytes.length} bytes',
          );

          // Collab 返回空数据时回退到本地文件
          if (data.sbn2Bytes.isEmpty) {
            Log.warn(
              '[HandwritingSaber] ⚠️ Collab returned empty data for $viewId, '
              'trying local file backup',
            );
            final localData = await _loadFromFile(viewId);
            if (localData.isNotEmpty) {
              Log.info(
                '[HandwritingSaber] ✅ Recovered from local file: $viewId, '
                'size: ${localData.length} bytes',
              );
              return localData;
            }
          }

          // Collab 有数据则优先使用（跨设备同步的数据源）
          // Collab 中的数据是精简版（云 URL 模式），加载后会从云端下载图片
          return data.sbn2Bytes;
        },
        (error) {
          Log.warn(
            '[HandwritingSaber] ⚠️ Failed to load from Rust/Collab: ${error.msg}, '
            'falling back to local file',
          );
          return _loadFromFile(viewId);
        },
      );
    } catch (e, stackTrace) {
      Log.error('[HandwritingSaber] ❌ Exception in loadHandwritingSaberData: $e');
      Log.error('[HandwritingSaber] Stack trace: $stackTrace');
      // ✅ 异常时也尝试从本地文件恢复
      return _loadFromFile(viewId);
    }
  }

  /// 仅读取本地完整备份文件（含 base64 图片字节）。
  ///
  /// 与 [loadHandwritingSaberData] 不同：本方法**只读本地备份**、不走 Collab，
  /// 用于打开笔记时从本地按 id 回填图片字节，避免对本地图片重复联网下载。
  Future<List<int>> loadLocalBackupData(String viewId) => _loadFromFile(viewId);

  /// 从文件系统加载（回退方案）
  Future<List<int>> _loadFromFile(String viewId) async {
    try {
      final filePath = await _getHandwritingSaberFilePath(viewId);
      final file = File(filePath);
      if (!file.existsSync()) {
        Log.info('[HandwritingSaber] File not found, returning empty: $viewId');
        return <int>[];
      }
      final data = await file.readAsBytes();
      Log.info(
        '[HandwritingSaber] ✅ Loaded from file: $viewId, size: ${data.length} bytes',
      );
      return data;
    } catch (e) {
      Log.error('[HandwritingSaber] ❌ Failed to load from file: $e');
      return <int>[];
    }
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
