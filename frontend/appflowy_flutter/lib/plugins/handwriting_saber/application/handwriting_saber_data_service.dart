import 'dart:io';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:path/path.dart' as p;

// TODO: 生成 Protobuf 代码后添加以下导入：
// import 'dart:convert';
// import 'package:appflowy_backend/dispatch/dispatch.dart';
// import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
// import 'package:appflowy_backend/protobuf/flowy-handwriting-saber/entities.pb.dart';
// import 'package:appflowy_backend/dispatch/dart_event/flowy-handwriting-saber/dart_event.dart';

/// Saber 手写笔记数据服务
/// 负责手写笔记数据的本地存储和加载
/// 
/// 当前阶段（PoC）：使用本地文件系统存储
/// 后续阶段：将通过 Rust 事件接口与 Collab 集成
class HandwritingSaberDataService {
  /// 获取手写笔记数据存储目录
  /// 使用与 Collab DB 一致的路径结构 {basePath}/{userId}/handwriting_saber/
  Future<String> _getHandwritingSaberDirectory() async {
    // 1. 获取基础路径
    final basePath = await getIt<ApplicationDataStorage>().getPath();

    // 2. 获取当前用户 ID
    final userProfileResult = await UserBackendService.getCurrentUserProfile();
    final userId = userProfileResult.fold(
      (profile) => profile.id.toString(),
      (error) {
        Log.error('[HandwritingSaber] Failed to get user profile: ${error.msg}');
        // 回退到不带用户ID的路径（向后兼容）
        return '';
      },
    );

    // 3. 构建路径：{basePath}/{userId}/handwriting_saber/
    final handwritingSaberPath = userId.isNotEmpty
        ? p.join(basePath, userId, 'handwriting_saber')
        : p.join(basePath, 'handwriting_saber'); // 回退路径

    // 4. 确保目录存在
    final directory = Directory(handwritingSaberPath);
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
      Log.info('[HandwritingSaber] Created directory: $handwritingSaberPath');
    }

    return handwritingSaberPath;
  }

  /// 获取手写笔记数据文件路径
  Future<String> _getHandwritingSaberFilePath(String viewId) async {
    final directory = await _getHandwritingSaberDirectory();
    return p.join(directory, '$viewId.sbn2');
  }

  /// 创建手写笔记
  ///
  /// [viewId] 手写笔记视图 ID
  /// [initialData] 可选的初始数据（.sbn2 格式的字节数组）
  Future<FlowyResult<void, FlowyError>> createHandwritingSaber({
    required String viewId,
    List<int>? initialData,
  }) async {
    try {
      // TODO: 生成 Protobuf 代码后取消注释，使用 Rust 事件接口
      /*
      final payload = CreateHandwritingSaberPayloadPB()..viewId = viewId;
      
      if (initialData != null && initialData.isNotEmpty) {
        payload.initialData = initialData;
      }
      
      final result = await HandwritingSaberEventCreateHandwritingSaber(payload).send();
      return result;
      */
      
      // 当前阶段：回退到本地文件系统
      final filePath = await _getHandwritingSaberFilePath(viewId);
      final file = File(filePath);
      
      if (initialData != null && initialData.isNotEmpty) {
        await file.writeAsBytes(initialData);
      } else {
        // 创建空的 .sbn2 文件
        await file.writeAsBytes(const <int>[]);
      }
      
      Log.info('[HandwritingSaber] Created handwriting saber: $viewId');
      return FlowyResult.success(null);
    } catch (e, stackTrace) {
      Log.error('[HandwritingSaber] Exception in createHandwritingSaber: $e\n$stackTrace');
      return FlowyResult.failure(
          FlowyError(msg: 'Failed to create handwriting saber: $e'),);
    }
  }

  /// 打开手写笔记
  ///
  /// [viewId] 手写笔记视图 ID
  Future<FlowyResult<void, FlowyError>> openHandwritingSaber({
    required String viewId,
  }) async {
    try {
      // TODO: 生成 Protobuf 代码后取消注释，使用 Rust 事件接口
      /*
      final payload = ViewIdPB()..value = viewId;
      final result = await HandwritingSaberEventOpenHandwritingSaber(payload).send();
      return result;
      */
      
      // 当前阶段：回退到本地文件系统
      final filePath = await _getHandwritingSaberFilePath(viewId);
      final file = File(filePath);
      
      if (!file.existsSync()) {
        // 如果文件不存在，创建一个空文件
        await file.writeAsBytes(const <int>[]);
      }
      
      Log.info('[HandwritingSaber] Opened handwriting saber: $viewId');
      return FlowyResult.success(null);
    } catch (e, stackTrace) {
      Log.error('[HandwritingSaber] Exception in openHandwritingSaber: $e\n$stackTrace');
      return FlowyResult.failure(
          FlowyError(msg: 'Failed to open handwriting saber: $e'),);
    }
  }

  /// 保存手写笔记数据
  ///
  /// [viewId] 手写笔记视图 ID
  /// [sbn2Data] .sbn2 格式的字节数组
  /// [version] 当前版本号（可选，如果不提供则从 Rust 获取）
  Future<bool> saveHandwritingSaberData(
    String viewId,
    List<int> sbn2Data, {
    int? version,
  }) async {
    Log.info('[HandwritingSaber] =====================================================');
    Log.info('[HandwritingSaber] saveHandwritingSaberData() called');
    Log.info('[HandwritingSaber] ViewID: $viewId');
    Log.info('[HandwritingSaber] Data length: ${sbn2Data.length} bytes');
    Log.info('[HandwritingSaber] Version: ${version ?? "unknown"}');
    Log.info('[HandwritingSaber] =====================================================');

    try {
      // TODO: 生成 Protobuf 代码后取消注释，使用 Rust 事件接口
      /*
      // 1. 先获取当前版本号（如果未提供）
      int currentVersion = version ?? 1;
      if (version == null) {
        final getDataResult = await loadHandwritingSaberData(viewId);
        // 从返回的数据中获取版本号
        // currentVersion = getDataResult.version;
      }
      
      // 2. 保存到 Rust/Collab
      final payload = SaveHandwritingSaberPayloadPB()
        ..viewId = viewId
        ..sbn2Bytes = sbn2Data
        ..version = currentVersion;
      
      final result = await HandwritingSaberEventSaveHandwritingSaber(payload).send();
      
      return result.fold(
        (response) {
          Log.info('[HandwritingSaber] ✅ Saved to Rust/Collab, new version: ${response.newVersion}');
          return true;
        },
        (error) {
          Log.error('[HandwritingSaber] ❌ Failed to save to Rust/Collab: ${error.msg}');
          // 回退到文件系统
          return _saveToFile(viewId, sbn2Data);
        },
      );
      */
      
      // 当前阶段：回退到本地文件系统
      return await _saveToFile(viewId, sbn2Data);
    } catch (e, stackTrace) {
      Log.error('[HandwritingSaber] ❌ Exception in saveHandwritingSaberData: $e');
      Log.error('[HandwritingSaber] Stack trace: $stackTrace');
      return false;
    }
  }
  
  /// 保存到文件系统（内部方法）
  Future<bool> _saveToFile(String viewId, List<int> sbn2Data) async {
    try {
      final filePath = await _getHandwritingSaberFilePath(viewId);
      final file = File(filePath);
      
      await file.writeAsBytes(sbn2Data, flush: true);
      
      Log.info('[HandwritingSaber] ✅ Saved to file: $viewId');
      return true;
    } catch (e) {
      Log.error('[HandwritingSaber] ❌ Failed to save to file: $e');
      return false;
    }
  }

  /// 从本地加载手写笔记数据
  ///
  /// [viewId] 手写笔记视图 ID
  /// 返回 .sbn2 格式的字节数组，如果不存在则返回空数组
  Future<List<int>> loadHandwritingSaberData(String viewId) async {
    Log.info('[HandwritingSaber] =====================================================');
    Log.info('[HandwritingSaber] loadHandwritingSaberData() called');
    Log.info('[HandwritingSaber] ViewID: $viewId');
    Log.info('[HandwritingSaber] =====================================================');

    try {
      // TODO: 生成 Protobuf 代码后取消注释，使用 Rust 事件接口
      /*
      // 1. 先打开手写笔记（加载到内存）
      await openHandwritingSaber(viewId: viewId);
      
      // 2. 获取数据
      final payload = ViewIdPB()..value = viewId;
      final result = await HandwritingSaberEventGetHandwritingSaberData(payload).send();
      
      return result.fold(
        (data) {
          Log.info('[HandwritingSaber] ✅ Loaded from Rust/Collab: $viewId, size: ${data.sbn2Bytes.length} bytes');
          return data.sbn2Bytes;
        },
        (error) {
          Log.warn('[HandwritingSaber] ⚠️ Failed to load from Rust/Collab: ${error.msg}, falling back to file');
          // 回退到文件系统
          return _loadFromFile(viewId);
        },
      );
      */
      
      // 当前阶段：回退到本地文件系统
      return await _loadFromFile(viewId);
    } catch (e, stackTrace) {
      Log.error('[HandwritingSaber] ❌ Exception in loadHandwritingSaberData: $e');
      Log.error('[HandwritingSaber] Stack trace: $stackTrace');
      return <int>[];
    }
  }
  
  /// 从文件系统加载（内部方法）
  Future<List<int>> _loadFromFile(String viewId) async {
    try {
      final filePath = await _getHandwritingSaberFilePath(viewId);
      final file = File(filePath);

      if (!file.existsSync()) {
        Log.info('[HandwritingSaber] File not found, returning empty: $viewId');
        return <int>[];
      }

      final data = await file.readAsBytes();
      Log.info('[HandwritingSaber] ✅ Loaded from file: $viewId, size: ${data.length} bytes');
      return data;
    } catch (e) {
      Log.error('[HandwritingSaber] ❌ Failed to load from file: $e');
      return <int>[];
    }
  }

  /// 关闭手写笔记
  ///
  /// [viewId] 手写笔记视图 ID
  Future<FlowyResult<void, FlowyError>> closeHandwritingSaber({
    required String viewId,
  }) async {
    try {
      // TODO: 生成 Protobuf 代码后取消注释，使用 Rust 事件接口
      /*
      final payload = ViewIdPB()..value = viewId;
      final result = await HandwritingSaberEventCloseHandwritingSaber(payload).send();
      return result;
      */
      
      // 当前阶段：无需特殊处理
      Log.info('[HandwritingSaber] Closed handwriting saber: $viewId');
      return FlowyResult.success(null);
    } catch (e, stackTrace) {
      Log.error('[HandwritingSaber] Exception in closeHandwritingSaber: $e\n$stackTrace');
      return FlowyResult.failure(
          FlowyError(msg: 'Failed to close handwriting saber: $e'),);
    }
  }

  /// 删除手写笔记
  ///
  /// [viewId] 手写笔记视图 ID
  Future<bool> deleteHandwritingSaber(String viewId) async {
    try {
      // TODO: 生成 Protobuf 代码后取消注释，使用 Rust 事件接口
      /*
      final payload = ViewIdPB()..value = viewId;
      final result = await HandwritingSaberEventDeleteHandwritingSaber(payload).send();
      
      final success = result.fold(
        (_) => true,
        (error) {
          Log.error('[HandwritingSaber] Failed to delete from Rust/Collab: ${error.msg}');
          return false;
        },
      );
      
      // 同时删除文件系统中的数据
      final filePath = await _getHandwritingSaberFilePath(viewId);
      final file = File(filePath);
      if (file.existsSync()) {
        await file.delete();
        Log.info('[HandwritingSaber] File data deleted: $viewId');
      }
      
      return success;
      */
      
      // 当前阶段：删除本地文件
      final filePath = await _getHandwritingSaberFilePath(viewId);
      final file = File(filePath);

      if (file.existsSync()) {
        await file.delete();
        Log.info('[HandwritingSaber] File data deleted: $viewId');
      }

      return true;
    } catch (e) {
      Log.error('[HandwritingSaber] Failed to delete handwriting saber data: $e');
      return false;
    }
  }

  /// 检查手写笔记数据是否存在
  ///
  /// [viewId] 手写笔记视图 ID
  Future<bool> handwritingSaberDataExists(String viewId) async {
    try {
      final filePath = await _getHandwritingSaberFilePath(viewId);
      return File(filePath).existsSync();
    } catch (e) {
      Log.error('Failed to check handwriting saber data existence: $e');
      return false;
    }
  }

  /// 获取手写笔记数据大小（字节）
  Future<int?> getHandwritingSaberDataSize(String viewId) async {
    try {
      final filePath = await _getHandwritingSaberFilePath(viewId);
      final file = File(filePath);

      if (!file.existsSync()) {
        return null;
      }

      return file.lengthSync();
    } catch (e) {
      Log.error('Failed to get handwriting saber data size: $e');
      return null;
    }
  }

  /// 获取手写笔记最后修改时间
  Future<DateTime?> getHandwritingSaberLastModified(String viewId) async {
    try {
      final filePath = await _getHandwritingSaberFilePath(viewId);
      final file = File(filePath);

      if (!file.existsSync()) {
        return null;
      }

      return file.lastModifiedSync();
    } catch (e) {
      Log.error('Failed to get handwriting saber last modified time: $e');
      return null;
    }
  }
}

