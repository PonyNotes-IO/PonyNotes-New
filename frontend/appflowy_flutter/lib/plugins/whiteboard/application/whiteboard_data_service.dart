import 'dart:convert';
import 'dart:io';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy_backend/log.dart';
import 'package:path/path.dart' as p;

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

  /// 保存白板数据到本地
  /// 
  /// [viewId] 白板视图 ID
  /// [data] Excalidraw 数据，格式：
  /// ```json
  /// {
  ///   "type": "excalidraw",
  ///   "version": 2,
  ///   "source": "https://excalidraw.com",
  ///   "elements": [ /* 绘图元素数组 */ ],
  ///   "appState": { /* 应用状态 */ },
  ///   "files": { /* 图片文件映射 */ }
  /// }
  /// ```
  Future<bool> saveWhiteboardData(
    String viewId,
    Map<String, dynamic> data,
  ) async {
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
      
      Log.info('Whiteboard data saved successfully: $viewId');
      return true;
    } catch (e) {
      Log.error('Failed to save whiteboard data: $e');
      return false;
    }
  }

  /// 从本地加载白板数据
  /// 
  /// [viewId] 白板视图 ID
  /// 返回 Excalidraw 数据，如果不存在则返回空白板
  Future<Map<String, dynamic>> loadWhiteboardData(String viewId) async {
    try {
      final filePath = await _getWhiteboardFilePath(viewId);
      final file = File(filePath);
      
      if (!file.existsSync()) {
        Log.info('Whiteboard data not found, returning empty: $viewId');
        return _createEmptyWhiteboardData();
      }
      
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      
      Log.info('Whiteboard data loaded successfully: $viewId');
      return data;
    } catch (e) {
      Log.error('Failed to load whiteboard data: $e');
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

