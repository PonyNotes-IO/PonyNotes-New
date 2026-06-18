import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy_backend/log.dart';
import 'package:path/path.dart' as p;

/// 白板图片本地磁盘缓存服务
///
/// 背景：白板图片上传云端后，为避免协作文档体积膨胀，base64 dataURL 会在
/// 写入 Collab 前被剥离（见 WhiteboardDataService._stripDataURLsForCollab）。
/// 因此重新打开/切换视图时，files 里只剩云端 url，导致每次都要回源云端下载，
/// 加载缓慢。Excalidraw 原生的 IndexedDB 文件缓存又因本地服务随机端口（origin
/// 跨重启漂移）而无法跨重启复用。
///
/// 本服务提供一层 Flutter 侧磁盘缓存：以 Excalidraw 的 fileId（图片内容 SHA-1，
/// 稳定唯一）为 key，将图片二进制缓存到 native 文件系统。它与 WebView origin 无关，
/// 天然支持跨重启。加载图片时优先读本地缓存命中即秒开，未命中再回源云端，
/// 下载后写入缓存。
///
/// 缓存目录：{appData}/{userId}/whiteboards/image_cache/
class WhiteboardImageCacheService {
  WhiteboardImageCacheService._();

  static final WhiteboardImageCacheService instance =
      WhiteboardImageCacheService._();

  factory WhiteboardImageCacheService() => instance;

  /// 缓存目录路径缓存，避免重复解析用户 profile
  String? _cachedDir;

  /// 缓存总容量上限（默认 200MB），超出后按最近最少使用（mtime）淘汰
  static const int maxCacheBytes = 200 * 1024 * 1024;

  /// fileId 仅允许的安全字符（Excalidraw fileId 为十六进制，稳妥起见仍做清洗）
  static final RegExp _unsafeChars = RegExp(r'[^a-zA-Z0-9_-]');

  Future<String> _getCacheDirectory() async {
    final cached = _cachedDir;
    if (cached != null) {
      return cached;
    }

    final basePath = await getIt<ApplicationDataStorage>().getPath();
    final userProfileResult = await UserBackendService.getCurrentUserProfile();
    final userId = userProfileResult.fold(
      (profile) => profile.id.toString(),
      (error) {
        Log.error('[WBImageCache] Failed to get user profile: ${error.msg}');
        return '';
      },
    );

    final cachePath = userId.isNotEmpty
        ? p.join(basePath, userId, 'whiteboards', 'image_cache')
        : p.join(basePath, 'whiteboards', 'image_cache');

    final directory = Directory(cachePath);
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
      Log.info('[WBImageCache] Created cache directory: $cachePath');
    }

    _cachedDir = cachePath;
    return cachePath;
  }

  String? _sanitizeFileId(String fileId) {
    final sanitized = fileId.replaceAll(_unsafeChars, '');
    if (sanitized.isEmpty) {
      return null;
    }
    return sanitized;
  }

  Future<String?> _getFilePath(String fileId) async {
    final safeId = _sanitizeFileId(fileId);
    if (safeId == null) {
      return null;
    }
    final dir = await _getCacheDirectory();
    return p.join(dir, safeId);
  }

  /// 读取本地缓存图片字节，命中返回字节并刷新 mtime（用于 LRU），未命中返回 null
  Future<Uint8List?> read(String fileId) async {
    try {
      final filePath = await _getFilePath(fileId);
      if (filePath == null) {
        return null;
      }
      final file = File(filePath);
      if (!file.existsSync()) {
        return null;
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        return null;
      }
      // 刷新最近使用时间（best-effort），供 LRU 淘汰参考
      try {
        await file.setLastModified(DateTime.now());
      } catch (_) {}
      return bytes;
    } catch (e) {
      Log.warn('[WBImageCache] Failed to read cache for $fileId: $e');
      return null;
    }
  }

  /// 将图片字节写入本地缓存（已存在且大小一致则跳过），写后触发容量上限淘汰
  Future<bool> write(String fileId, Uint8List bytes) async {
    if (bytes.isEmpty) {
      return false;
    }
    try {
      final filePath = await _getFilePath(fileId);
      if (filePath == null) {
        return false;
      }
      final file = File(filePath);
      if (file.existsSync() && file.lengthSync() == bytes.length) {
        // 已缓存且大小一致，视为命中，仅刷新 mtime
        try {
          await file.setLastModified(DateTime.now());
        } catch (_) {}
        return true;
      }
      await file.writeAsBytes(bytes, flush: true);
      Log.info('[WBImageCache] Cached image $fileId (${bytes.length} bytes)');
      // 写入后异步执行容量淘汰，不阻塞当前调用
      unawaited(_enforceLimit());
      return true;
    } catch (e) {
      Log.warn('[WBImageCache] Failed to write cache for $fileId: $e');
      return false;
    }
  }

  /// 判断某个 fileId 是否已缓存
  Future<bool> contains(String fileId) async {
    final filePath = await _getFilePath(fileId);
    if (filePath == null) {
      return false;
    }
    return File(filePath).existsSync();
  }

  /// 容量上限 LRU 淘汰：当缓存总大小超过 [maxCacheBytes] 时，
  /// 按最近最少使用（文件 mtime 升序）删除，直至降到上限的 90% 以下。
  Future<void> _enforceLimit() async {
    try {
      final dir = Directory(await _getCacheDirectory());
      if (!dir.existsSync()) {
        return;
      }
      final files = dir.listSync().whereType<File>().toList();
      var totalBytes = 0;
      for (final f in files) {
        totalBytes += f.lengthSync();
      }
      if (totalBytes <= maxCacheBytes) {
        return;
      }

      // 按最近使用时间升序（最久未用的在前）
      files.sort(
        (a, b) => a.statSync().modified.compareTo(b.statSync().modified),
      );

      final target = (maxCacheBytes * 0.9).floor();
      var removed = 0;
      for (final f in files) {
        if (totalBytes <= target) {
          break;
        }
        final size = f.lengthSync();
        try {
          await f.delete();
          totalBytes -= size;
          removed++;
        } catch (_) {}
      }
      if (removed > 0) {
        Log.info(
            '[WBImageCache] LRU evicted $removed files, total now ${totalBytes ~/ 1024}KB');
      }
    } catch (e) {
      Log.warn('[WBImageCache] _enforceLimit failed: $e');
    }
  }
}
