import 'dart:convert';
import 'dart:io';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy_backend/log.dart';
import 'package:path/path.dart' as p;

// TODO: 取消注释以下导入（需要先生成 protobuf 代码）
// import 'package:appflowy_backend/protobuf/flowy-whiteboard/protobuf.dart';
// import 'package:appflowy_backend/dispatch/dispatch.dart';

/// Excalidraw 白板数据服务
/// 负责白板数据的本地存储和加载
class WhiteboardDataService {
  /// 获取白板数据存储目录
  Future<String> _getWhiteboardDirectory() async {
    final path = await getIt<ApplicationDataStorage>().getPath();
    final whiteboardPath = p.join(path, 'whiteboards');
    
    // 确保目录存在
    final directory = Directory(whiteboardPath);
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    
    return whiteboardPath;
  }

  /// 获取白板数据文件路径
  Future<String> _getWhiteboardFilePath(String viewId) async {
    final directory = await _getWhiteboardDirectory();
    return p.join(directory, '$viewId.json');
  }

  /// 保存白板数据（优先使用 Collab，失败则回退到文件）
  /// 
  /// [viewId] 白板视图 ID
  /// [data] Excalidraw 数据
  Future<bool> saveWhiteboardData(
    String viewId,
    Map<String, dynamic> data,
  ) async {
    // TODO: 取消注释以启用 Collab 保存
    // 1. 尝试保存到 Collab
    // final collabSuccess = await _saveToCollab(viewId, data);
    // if (collabSuccess) {
    //   Log.info('[Whiteboard] ✅ Saved to Collab: $viewId');
    //   return true;
    // }
    
    // 2. 回退到文件系统（当前默认行为，向后兼容）
    // Log.warn('[Whiteboard] ⚠️ Collab not available, using file system');
    return await _saveToFile(viewId, data);
  }

  /// TODO: 取消注释以启用 Collab 保存
  /// 保存到 Collab
  // Future<bool> _saveToCollab(String viewId, Map<String, dynamic> data) async {
  //   try {
  //     final payload = UpdateWhiteboardPayloadPB(
  //       viewId: viewId,
  //       jsonData: jsonEncode(data),
  //     );
  //     
  //     final result = await WhiteboardEventUpdateWhiteboard(payload).send();
  //     
  //     return result.fold(
  //       (_) => true,
  //       (error) {
  //         Log.error('[Whiteboard] Collab save error: $error');
  //         return false;
  //       },
  //     );
  //   } catch (e, stackTrace) {
  //     Log.error('[Whiteboard] Exception in _saveToCollab: $e\n$stackTrace');
  //     return false;
  //   }
  // }

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
    // TODO: 取消注释以启用 Collab 加载
    // 1. 尝试从 Collab 加载
    // final collabData = await _loadFromCollab(viewId);
    // if (collabData != null) {
    //   Log.info('[Whiteboard] ✅ Loaded from Collab: $viewId');
    //   return collabData;
    // }
    
    // 2. 回退到文件系统
    // Log.info('[Whiteboard] ℹ️ Collab not found, trying file system');
    final fileData = await _loadFromFile(viewId);
    
    // TODO: 取消注释以启用自动迁移
    // 3. 如果从文件加载成功，迁移到 Collab
    // if (fileData['elements'] != null && (fileData['elements'] as List).isNotEmpty) {
    //   Log.info('[Whiteboard] 📦 Migrating from file to Collab: $viewId');
    //   await _saveToCollab(viewId, fileData);
    // }
    
    return fileData;
  }

  /// TODO: 取消注释以启用 Collab 加载
  /// 从 Collab 加载
  // Future<Map<String, dynamic>?> _loadFromCollab(String viewId) async {
  //   try {
  //     final payload = ViewIdPB(value: viewId);
  //     final result = await WhiteboardEventGetWhiteboardData(payload).send();
  //     
  //     return result.fold(
  //       (data) {
  //         final json = jsonDecode(data.jsonData) as Map<String, dynamic>;
  //         return json;
  //       },
  //       (error) {
  //         Log.debug('[Whiteboard] Collab load error (normal if new): $error');
  //         return null;
  //       },
  //     );
  //   } catch (e) {
  //     Log.debug('[Whiteboard] Exception in _loadFromCollab: $e');
  //     return null;
  //   }
  // }

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

  /// 删除白板数据
  /// 
  /// [viewId] 白板视图 ID
  Future<bool> deleteWhiteboardData(String viewId) async {
    try {
      final filePath = await _getWhiteboardFilePath(viewId);
      final file = File(filePath);
      
      if (file.existsSync()) {
        await file.delete();
        Log.info('Whiteboard data deleted: $viewId');
      }
      
      return true;
    } catch (e) {
      Log.error('Failed to delete whiteboard data: $e');
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

