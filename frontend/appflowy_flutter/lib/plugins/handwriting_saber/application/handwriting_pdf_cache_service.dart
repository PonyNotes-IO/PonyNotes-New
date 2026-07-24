import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy_backend/log.dart';
import 'package:path/path.dart' as p;

/// 手写笔记 PDF 底图本地磁盘缓存服务
///
/// 背景：手写笔记导入 PDF 后，PDF 会上传云存储并以 pdfUrl 记录。为避免协作文档
/// 膨胀，Collab 序列化时 pdfFilePath 只保存云 URL（见 saber page.dart 的
/// forCollab 分支）。因此切换视图/重开客户端重新加载时，pdfFilePath 是云 URL，
/// `File(url).existsSync()` 恒为 false，导致每次都从云端重新下载整个 PDF，加载缓慢。
/// 此前的 downloadFromCloud 虽写过缓存，但用的是 getTemporaryDirectory()
/// （系统临时目录、会被清理、非工作区），且下载前未按 URL 命中已存在的缓存。
///
/// 本服务提供工作区持久缓存：以 pdfUrl 的稳定末段文件名为 key，将 PDF 缓存到
/// {appData}/{userId}/handwriting_saber/pdf_cache/。与 WebView origin、临时目录
/// 无关，天然跨重启可用。加载时优先命中本地缓存（不联网），未命中再回源云端，
/// 下载后写入缓存。
class HandwritingPdfCacheService {
  HandwritingPdfCacheService._();

  static final HandwritingPdfCacheService instance =
      HandwritingPdfCacheService._();

  factory HandwritingPdfCacheService() => instance;

  String? _cachedDir;

  /// 缓存总容量上限（默认 500MB，PDF 通常较大），超出按最近最少使用(mtime)淘汰
  static const int maxCacheBytes = 500 * 1024 * 1024;

  static final RegExp _unsafeChars = RegExp('[^a-zA-Z0-9_.-]');

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
        Log.error('[PdfCache] Failed to get user profile: ${error.msg}');
        return '';
      },
    );

    final cachePath = userId.isNotEmpty
        ? p.join(basePath, userId, 'handwriting_saber', 'pdf_cache')
        : p.join(basePath, 'handwriting_saber', 'pdf_cache');

    final directory = Directory(cachePath);
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
      Log.info('[PdfCache] Created cache directory: $cachePath');
    }

    _cachedDir = cachePath;
    return cachePath;
  }

  /// 由 pdfUrl 推导稳定缓存文件名（取末段 blob 文件名，跨重启稳定）
  String _keyForUrl(String pdfUrl) {
    var seg = pdfUrl;
    final qIdx = seg.indexOf('?');
    if (qIdx != -1) {
      seg = seg.substring(0, qIdx);
    }
    final slash = seg.lastIndexOf('/');
    if (slash != -1 && slash < seg.length - 1) {
      seg = seg.substring(slash + 1);
    }
    seg = seg.replaceAll(_unsafeChars, '_');
    if (seg.isEmpty) {
      seg = 'pdf_${pdfUrl.length}_${pdfUrl.hashCode.abs()}';
    }
    if (!seg.toLowerCase().endsWith('.pdf')) {
      seg = '$seg.pdf';
    }
    return seg;
  }

  Future<String> resolvedPath(String pdfUrl) async {
    final dir = await _getCacheDirectory();
    return p.join(dir, _keyForUrl(pdfUrl));
  }

  /// 命中则返回本地缓存文件路径(并刷新 mtime 供 LRU)，未命中返回 null
  Future<String?> cachedPathIfExists(String pdfUrl) async {
    try {
      final path = await resolvedPath(pdfUrl);
      final file = File(path);
      if (!file.existsSync() || file.lengthSync() == 0) {
        return null;
      }
      try {
        await file.setLastModified(DateTime.now());
      } catch (_) {}
      return path;
    } catch (e) {
      Log.warn('[PdfCache] cachedPathIfExists failed: $e');
      return null;
    }
  }

  /// 将 PDF 字节写入工作区持久缓存，返回缓存文件路径；失败返回 null
  Future<String?> put(String pdfUrl, Uint8List bytes) async {
    if (bytes.isEmpty) {
      return null;
    }
    try {
      final path = await resolvedPath(pdfUrl);
      final file = File(path);
      if (file.existsSync() && file.lengthSync() == bytes.length) {
        try {
          await file.setLastModified(DateTime.now());
        } catch (_) {}
        return path;
      }
      await file.writeAsBytes(bytes, flush: true);
      Log.info('[PdfCache] Cached PDF $path (${bytes.length} bytes)');
      unawaited(_enforceLimit());
      return path;
    } catch (e) {
      Log.warn('[PdfCache] put failed: $e');
      return null;
    }
  }

  /// Streams a PDF into the persistent cache without retaining the whole file
  /// in memory. Partial files are removed when the stream fails.
  Future<String?> putStream(
    String pdfUrl,
    Stream<List<int>> bytes, {
    int? expectedLength,
  }) async {
    File? file;
    IOSink? sink;
    try {
      final path = await resolvedPath(pdfUrl);
      file = File(path);
      sink = file.openWrite();

      var written = 0;
      await for (final chunk in bytes) {
        sink.add(chunk);
        written += chunk.length;
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (written == 0 ||
          (expectedLength != null &&
              expectedLength >= 0 &&
              written != expectedLength)) {
        await file.delete();
        Log.warn(
          '[PdfCache] Streamed PDF length mismatch: '
          'expected=$expectedLength, written=$written',
        );
        return null;
      }

      Log.info('[PdfCache] Streamed PDF to $path ($written bytes)');
      unawaited(_enforceLimit());
      return path;
    } catch (e) {
      await sink?.close();
      if (file != null && file.existsSync()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      Log.warn('[PdfCache] putStream failed: $e');
      return null;
    }
  }

  /// 容量上限 LRU 淘汰：超过 [maxCacheBytes] 时按 mtime 升序删至 90% 以下
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
            '[PdfCache] LRU evicted $removed PDFs, total now ${totalBytes ~/ 1024}KB');
      }
    } catch (e) {
      Log.warn('[PdfCache] _enforceLimit failed: $e');
    }
  }
}
