import 'dart:io';
import 'package:appflowy_backend/log.dart';
import 'package:path/path.dart' as path;

/// WebView缓存管理器（单例）
/// 负责管理网页内容的缓存和读取
class WebViewCacheManager {
  static final WebViewCacheManager _instance = WebViewCacheManager._internal();
  factory WebViewCacheManager() => _instance;
  WebViewCacheManager._internal();

  /// 获取缓存目录路径
  /// sbnPath: 笔记文件路径，例如 /path/to/note.sbn2
  /// 返回: /path/to/note.sbn2.cache/
  String _getCacheDirectory(String sbnPath) {
    return '$sbnPath.cache';
  }

  /// 获取缓存文件的完整路径
  String _getCacheFilePath(String sbnPath, String cacheFileName) {
    final cacheDir = _getCacheDirectory(sbnPath);
    return path.join(cacheDir, cacheFileName);
  }

  /// 确保缓存目录存在
  Future<void> _ensureCacheDirectoryExists(String sbnPath) async {
    final cacheDir = Directory(_getCacheDirectory(sbnPath));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
      Log.info('创建缓存目录: ${cacheDir.path}');
    }
  }

  /// 检查缓存内容是否存在
  Future<bool> hasCachedContent(String sbnPath, String cacheFileName) async {
    try {
      final cacheFilePath = _getCacheFilePath(sbnPath, cacheFileName);
      final file = File(cacheFilePath);
      return await file.exists();
    } catch (e) {
      Log.warn('检查缓存文件失败: $e');
      return false;
    }
  }

  /// 加载缓存内容
  Future<String?> loadCachedContent(String sbnPath, String cacheFileName) async {
    try {
      final cacheFilePath = _getCacheFilePath(sbnPath, cacheFileName);
      final file = File(cacheFilePath);
      
      if (!await file.exists()) {
        Log.info('缓存文件不存在: $cacheFilePath');
        return null;
      }

      final content = await file.readAsString();
      Log.info('成功加载缓存: $cacheFileName (${content.length} bytes)');
      return content;
    } catch (e) {
      Log.error('加载缓存失败: $e');
      return null;
    }
  }

  /// 保存缓存内容
  Future<void> saveCachedContent(
    String sbnPath,
    String cacheFileName,
    String htmlContent,
  ) async {
    try {
      await _ensureCacheDirectoryExists(sbnPath);
      
      final cacheFilePath = _getCacheFilePath(sbnPath, cacheFileName);
      final file = File(cacheFilePath);
      
      await file.writeAsString(htmlContent);
      Log.info('成功保存缓存: $cacheFileName (${htmlContent.length} bytes)');
    } catch (e) {
      Log.error('保存缓存失败: $e');
      rethrow;
    }
  }

  /// 删除缓存内容
  Future<void> deleteCachedContent(String sbnPath, String cacheFileName) async {
    try {
      final cacheFilePath = _getCacheFilePath(sbnPath, cacheFileName);
      final file = File(cacheFilePath);
      
      if (await file.exists()) {
        await file.delete();
        Log.info('成功删除缓存: $cacheFileName');
      }
    } catch (e) {
      Log.warn('删除缓存失败: $e');
    }
  }

  /// 清除笔记的所有缓存
  Future<void> clearAllCache(String sbnPath) async {
    try {
      final cacheDir = Directory(_getCacheDirectory(sbnPath));
      
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
        Log.info('成功清除所有缓存: ${cacheDir.path}');
      }
    } catch (e) {
      Log.warn('清除所有缓存失败: $e');
    }
  }

  /// 获取缓存大小（字节）
  Future<int> getCacheSize(String sbnPath) async {
    try {
      final cacheDir = Directory(_getCacheDirectory(sbnPath));
      
      if (!await cacheDir.exists()) {
        return 0;
      }

      int totalSize = 0;
      await for (final entity in cacheDir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
      
      return totalSize;
    } catch (e) {
      Log.warn('获取缓存大小失败: $e');
      return 0;
    }
  }

  /// 格式化缓存大小为可读字符串
  String formatCacheSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
  }
}






