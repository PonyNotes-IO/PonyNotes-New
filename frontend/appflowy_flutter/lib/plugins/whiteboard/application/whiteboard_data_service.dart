import 'dart:convert';
import 'dart:io';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-whiteboard/entities.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:path/path.dart' as p;

/// Excalidraw 白板数据服务
/// 负责白板数据的本地存储和加载
class WhiteboardDataService {
  /// 获取白板数据存储目录
  /// 修复：使用与 Collab DB 一致的路径结构 {basePath}/{userId}/whiteboards/
  Future<String> _getWhiteboardDirectory() async {
    // 1. 获取基础路径
    final basePath = await getIt<ApplicationDataStorage>().getPath();
    
    // 2. 获取当前用户 ID
    final userProfileResult = await UserBackendService.getCurrentUserProfile();
    final userId = userProfileResult.fold(
      (profile) => profile.id.toString(),
      (error) {
        Log.error('[Whiteboard] Failed to get user profile: ${error.msg}');
        // 回退到不带用户ID的路径（向后兼容）
        return '';
      },
    );
    
    // 3. 构建路径：{basePath}/{userId}/whiteboards/
    final whiteboardPath = userId.isNotEmpty 
        ? p.join(basePath, userId, 'whiteboards')
        : p.join(basePath, 'whiteboards');  // 回退路径
    
    // 4. 确保目录存在
    final directory = Directory(whiteboardPath);
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
      Log.info('[Whiteboard] Created directory: $whiteboardPath');
    }
    
    return whiteboardPath;
  }

  /// 获取白板数据文件路径
  Future<String> _getWhiteboardFilePath(String viewId) async {
    final directory = await _getWhiteboardDirectory();
    return p.join(directory, '$viewId.json');
  }

  /// 创建白板
  /// 
  /// [viewId] 白板视图 ID
  /// [initialData] 可选的初始数据
  Future<FlowyResult<void, FlowyError>> createWhiteboard({
    required String viewId,
    Map<String, dynamic>? initialData,
  }) async {
    try {
      final payload = CreateWhiteboardPayloadPB()..viewId = viewId;
      
      if (initialData != null) {
        payload.initialData = jsonEncode(initialData);
      }
      
      final result = await WhiteboardEventCreateWhiteboard(payload).send();
      return result;
    } catch (e, stackTrace) {
      Log.error('[Whiteboard] Exception in createWhiteboard: $e\n$stackTrace');
      return FlowyResult.failure(FlowyError(msg: 'Failed to create whiteboard: $e'));
    }
  }

  /// 打开白板
  /// 
  /// [viewId] 白板视图 ID
  Future<FlowyResult<void, FlowyError>> openWhiteboard({
    required String viewId,
  }) async {
    try {
      final payload = ViewIdPB()..value = viewId;
      final result = await WhiteboardEventOpenWhiteboard(payload).send();
      return result;
    } catch (e, stackTrace) {
      Log.error('[Whiteboard] Exception in openWhiteboard: $e\n$stackTrace');
      return FlowyResult.failure(FlowyError(msg: 'Failed to open whiteboard: $e'));
    }
  }

  /// 保存白板数据（使用 Collab 后端，失败则回退到文件）
  /// 
  /// [viewId] 白板视图 ID
  /// [data] Excalidraw 数据
  Future<bool> saveWhiteboardData(
    String viewId,
    Map<String, dynamic> data,
  ) async {
    Log.info('[Whiteboard] =====================================================');
    Log.info('[Whiteboard] saveWhiteboardData() called');
    Log.info('[Whiteboard] ViewID: $viewId');
    Log.info('[Whiteboard] Data keys: ${data.keys.toList()}');
    Log.info('[Whiteboard] =====================================================');
    
    // 1. 尝试保存到 Collab 后端
    Log.info('[Whiteboard] Step 1: Trying to save to Collab backend...');
    final collabSuccess = await _saveToCollab(viewId, data);
    if (collabSuccess) {
      Log.info('[Whiteboard] ✅ Saved to Collab successfully: $viewId');
      return true;
    }
    
    // 2. 回退到文件系统（向后兼容）
    Log.warn('[Whiteboard] ⚠️ Collab save failed, falling back to file system');
    final fileSuccess = await _saveToFile(viewId, data);
    Log.info('[Whiteboard] File save result: $fileSuccess');
    return fileSuccess;
  }

  /// 保存到 Collab 后端
  Future<bool> _saveToCollab(String viewId, Map<String, dynamic> data) async {
    try {
      Log.info('[Whiteboard] _saveToCollab: Creating payload...');
      
      // 🔍 打印 data 结构以便调试
      Log.info('[Whiteboard] 📊 Data structure:');
      Log.info('[Whiteboard]   - Keys: ${data.keys.toList()}');
      if (data.containsKey('elements')) {
        final elements = data['elements'];
        if (elements is List) {
          Log.info('[Whiteboard]   - elements type: List, length: ${elements.length}');
          if (elements.isNotEmpty) {
            Log.info('[Whiteboard]   - First element: ${elements.first}');
          } else {
            Log.info('[Whiteboard]   - ⚠️  elements is EMPTY!');
          }
        } else {
          Log.info('[Whiteboard]   - ⚠️  elements is NOT a List: ${elements.runtimeType}');
        }
      } else {
        Log.info('[Whiteboard]   - ⚠️  NO elements key found!');
      }
      
      final jsonData = jsonEncode(data);
      Log.info('[Whiteboard] _saveToCollab: JSON data length: ${jsonData.length} characters');
      Log.info('[Whiteboard] 📄 Full JSON: $jsonData');
      
      final payload = UpdateWhiteboardPayloadPB()
        ..viewId = viewId
        ..jsonData = jsonData;
      
      Log.info('[Whiteboard] _saveToCollab: Sending WhiteboardEventUpdateWhiteboard event...');
      final result = await WhiteboardEventUpdateWhiteboard(payload).send();
      
      return result.fold(
        (_) {
          Log.info('[Whiteboard] _saveToCollab: ✅ Success!');
          return true;
        },
        (error) {
          Log.error('[Whiteboard] _saveToCollab: ❌ Error: ${error.msg}');
          Log.error('[Whiteboard] _saveToCollab: Error code: ${error.code}');
          return false;
        },
      );
    } catch (e, stackTrace) {
      Log.error('[Whiteboard] _saveToCollab: ❌ Exception: $e');
      Log.error('[Whiteboard] _saveToCollab: Stack trace: $stackTrace');
      return false;
    }
  }

  /// 保存到文件系统（保持原有实现不变）
  Future<bool> _saveToFile(String viewId, Map<String, dynamic> data) async {
    try {
      final filePath = await _getWhiteboardFilePath(viewId);
      final file = File(filePath);
      
      // 添加元数据
      final dataWithMeta = {
        ...data,
        'savedAt': DateTime.now().toIso8601String(),
        'viewId': viewId,
      };
      
      // 写入文件
      await file.writeAsString(
        jsonEncode(dataWithMeta),
        flush: true,
      );
      
      Log.info('[Whiteboard] Saved to file: $viewId');
      return true;
    } catch (e) {
      Log.error('[Whiteboard] Failed to save to file: $e');
      return false;
    }
  }

  /// 从本地加载白板数据（优先从 Collab，回退到文件）
  /// 
  /// [viewId] 白板视图 ID
  /// 返回 Excalidraw 数据，如果不存在则返回空白板
  Future<Map<String, dynamic>> loadWhiteboardData(String viewId) async {
    // 1. 先尝试打开白板（加载到内存）
    await openWhiteboard(viewId: viewId);
    
    // 2. 尝试从 Collab 后端加载
    final collabData = await _loadFromCollab(viewId);
    if (collabData != null) {
      Log.info('[Whiteboard] ✅ Loaded from Collab: $viewId');
      return collabData;
    }
    
    // 3. 回退到文件系统
    Log.info('[Whiteboard] ℹ️ Collab not found, trying file system');
    final fileData = await _loadFromFile(viewId);
    
    // 4. 如果从文件加载成功，迁移到 Collab
    if (fileData['elements'] != null && (fileData['elements'] as List).isNotEmpty) {
      Log.info('[Whiteboard] 📦 Migrating from file to Collab: $viewId');
      await _saveToCollab(viewId, fileData);
    }
    
    return fileData;
  }

  /// 从 Collab 后端加载
  Future<Map<String, dynamic>?> _loadFromCollab(String viewId) async {
    try {
      final payload = ViewIdPB()..value = viewId;
      final result = await WhiteboardEventGetWhiteboardData(payload).send();
      
      return result.fold(
        (data) {
          if (data.jsonData.isEmpty) {
            return null;
          }
          final json = jsonDecode(data.jsonData) as Map<String, dynamic>;
          return json;
        },
        (error) {
          Log.debug('[Whiteboard] Collab load error (normal if new): ${error.msg}');
          return null;
        },
      );
    } catch (e) {
      Log.debug('[Whiteboard] Exception in _loadFromCollab: $e');
      return null;
    }
  }

  /// 从文件加载（保持原有实现不变）
  Future<Map<String, dynamic>> _loadFromFile(String viewId) async {
    try {
      final filePath = await _getWhiteboardFilePath(viewId);
      final file = File(filePath);
      
      if (!file.existsSync()) {
        Log.info('[Whiteboard] File not found, returning empty: $viewId');
        return _createEmptyWhiteboardData();
      }
      
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      
      Log.info('[Whiteboard] Loaded from file: $viewId');
      return data;
    } catch (e) {
      Log.error('[Whiteboard] Failed to load from file: $e');
      return _createEmptyWhiteboardData();
    }
  }

  /// 关闭白板
  /// 
  /// [viewId] 白板视图 ID
  Future<FlowyResult<void, FlowyError>> closeWhiteboard({
    required String viewId,
  }) async {
    try {
      final payload = ViewIdPB()..value = viewId;
      final result = await WhiteboardEventCloseWhiteboard(payload).send();
      return result;
    } catch (e, stackTrace) {
      Log.error('[Whiteboard] Exception in closeWhiteboard: $e\n$stackTrace');
      return FlowyResult.failure(FlowyError(msg: 'Failed to close whiteboard: $e'));
    }
  }

  /// 删除白板数据
  /// 
  /// [viewId] 白板视图 ID
  Future<bool> deleteWhiteboardData(String viewId) async {
    try {
      // 1. 从 Collab 后端删除
      final payload = ViewIdPB()..value = viewId;
      final result = await WhiteboardEventDeleteWhiteboard(payload).send();
      
      final success = result.fold(
        (_) => true,
        (error) {
          Log.error('[Whiteboard] Failed to delete from Collab: ${error.msg}');
          return false;
        },
      );
      
      // 2. 删除文件系统中的数据
      final filePath = await _getWhiteboardFilePath(viewId);
      final file = File(filePath);
      
      if (file.existsSync()) {
        await file.delete();
        Log.info('[Whiteboard] File data deleted: $viewId');
      }
      
      return success;
    } catch (e) {
      Log.error('[Whiteboard] Failed to delete whiteboard data: $e');
      return false;
    }
  }

  /// 检查白板数据是否存在
  /// 
  /// [viewId] 白板视图 ID
  Future<bool> whiteboardDataExists(String viewId) async {
    try {
      final filePath = await _getWhiteboardFilePath(viewId);
      return File(filePath).existsSync();
    } catch (e) {
      Log.error('Failed to check whiteboard data existence: $e');
      return false;
    }
  }

  /// 导出白板为 JSON 文件
  /// 
  /// [viewId] 白板视图 ID
  /// [exportPath] 导出路径
  Future<bool> exportToJson(String viewId, String exportPath) async {
    try {
      final data = await loadWhiteboardData(viewId);
      final file = File(exportPath);
      
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data),
        flush: true,
      );
      
      Log.info('Whiteboard exported to JSON: $exportPath');
      return true;
    } catch (e) {
      Log.error('Failed to export whiteboard to JSON: $e');
      return false;
    }
  }

  /// 从 JSON 文件导入白板
  /// 
  /// [viewId] 白板视图 ID
  /// [importPath] 导入路径
  Future<Map<String, dynamic>?> importFromJson(
    String viewId,
    String importPath,
  ) async {
    try {
      final file = File(importPath);
      if (!file.existsSync()) {
        Log.error('Import file not found: $importPath');
        return null;
      }
      
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      
      // 验证数据格式
      if (!_isValidExcalidrawData(data)) {
        Log.error('Invalid Excalidraw data format');
        return null;
      }
      
      // 保存导入的数据
      await saveWhiteboardData(viewId, data);
      
      Log.info('Whiteboard imported from JSON: $importPath');
      return data;
    } catch (e) {
      Log.error('Failed to import whiteboard from JSON: $e');
      return null;
    }
  }

  /// 获取所有白板列表
  Future<List<String>> listAllWhiteboards() async {
    try {
      final directory = await _getWhiteboardDirectory();
      final dir = Directory(directory);
      
      if (!dir.existsSync()) {
        return [];
      }
      
      final files = dir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList();
      
      return files
          .map((file) => p.basenameWithoutExtension(file.path))
          .toList();
    } catch (e) {
      Log.error('Failed to list whiteboards: $e');
      return [];
    }
  }

  /// 创建空白板数据
  Map<String, dynamic> _createEmptyWhiteboardData() {
    return {
      'type': 'excalidraw',
      'version': 2,
      'source': 'https://excalidraw.com',
      'elements': [],
      'appState': {
        'gridSize': null,
        'viewBackgroundColor': '#ffffff',
      },
      'files': {},
    };
  }

  /// 验证是否为有效的 Excalidraw 数据格式
  bool _isValidExcalidrawData(Map<String, dynamic> data) {
    return data.containsKey('type') &&
        data['type'] == 'excalidraw' &&
        data.containsKey('elements') &&
        data['elements'] is List;
  }

  /// 获取白板数据大小（字节）
  Future<int?> getWhiteboardDataSize(String viewId) async {
    try {
      final filePath = await _getWhiteboardFilePath(viewId);
      final file = File(filePath);
      
      if (!file.existsSync()) {
        return null;
      }
      
      return file.lengthSync();
    } catch (e) {
      Log.error('Failed to get whiteboard data size: $e');
      return null;
    }
  }

  /// 获取白板最后修改时间
  Future<DateTime?> getWhiteboardLastModified(String viewId) async {
    try {
      final filePath = await _getWhiteboardFilePath(viewId);
      final file = File(filePath);
      
      if (!file.existsSync()) {
        return null;
      }
      
      return file.lastModifiedSync();
    } catch (e) {
      Log.error('Failed to get whiteboard last modified time: $e');
      return null;
    }
  }
}

