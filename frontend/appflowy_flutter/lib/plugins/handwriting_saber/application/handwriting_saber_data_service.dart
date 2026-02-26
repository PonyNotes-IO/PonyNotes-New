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

/// Saber 手写笔记数据服务
/// 负责手写笔记数据的存储和加载（通过 Rust Collab 接口同步）
class HandwritingSaberDataService {
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

          // ✅ 如果 Collab 返回空数据，尝试从本地文件恢复
          // 场景：Collab 同步因数据过大失败，但本地文件有最新备份
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

          // ✅ 对比 Collab 和本地文件，使用数据更大（更完整）的那份
          final localData = await _loadFromFile(viewId);
          if (localData.length > data.sbn2Bytes.length) {
            Log.warn(
              '[HandwritingSaber] ⚠️ Local file ($viewId) has more data '
              '(${localData.length} bytes) than Collab (${data.sbn2Bytes.length} bytes), '
              'using local file',
            );
            return localData;
          }

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
