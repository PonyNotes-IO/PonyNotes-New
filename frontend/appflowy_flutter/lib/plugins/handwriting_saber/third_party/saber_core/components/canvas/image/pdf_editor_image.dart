import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/plugins/import_page/file_upload_service.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdfrx/pdfrx.dart';
import 'package:uuid/uuid.dart';
import 'package:appflowy/plugins/handwriting_saber/application/handwriting_pdf_cache_service.dart';
import 'package:appflowy/plugins/handwriting_saber/application/handwriting_pdf_download.dart';
import '../../../../../../../util/log_utils.dart';

/// PDF加载状态枚举
enum PdfLoadState {
  notLoaded, // 未加载
  waitingForSync, // 等待源设备上传并同步云地址
  loading, // 正在加载
  loaded, // 已加载成功
  failed, // 加载失败
}

// 移除了_PdfDocumentCacheEntry类，现在直接缓存Future<PdfDocument>

/// PDF文档缓存管理器 - 全局单例（优化版本）
class PdfDocumentCacheManager {
  static final PdfDocumentCacheManager _instance =
      PdfDocumentCacheManager._internal();
  factory PdfDocumentCacheManager() => _instance;

  PdfDocumentCacheManager._internal() {
    // 定期清理过期缓存
    _startCleanupTimer();
  }

  // 文档缓存：文件路径 -> Future<PdfDocument>
  final Map<String, Future<PdfDocument>> _cache = {};

  // 同步文档缓存：文件路径 -> PdfDocument（已完成的文档）
  final Map<String, PdfDocument> _completedCache = {};

  // 弱引用避免页面整体替换但未显式 dispose 时永久占用文档。
  final Map<String, List<WeakReference<Object>>> _documentUsers = {};

  // 页面缓存：文件路径+页面索引 -> 页面Widget
  final Map<String, Widget> _pageWidgetCache = {};

  // 缓存配置
  static const int maxCacheSize = 5; // 减少缓存大小，避免内存占用过多
  static const Duration cacheExpiry = Duration(minutes: 10); // 减少过期时间
  static const Duration cleanupInterval = Duration(minutes: 2); // 更频繁清理

  // 监听器集合
  final Set<VoidCallback> _listeners = {};

  Timer? _cleanupTimer;

  /// 获取或加载PDF文档
  Future<PdfDocument> load(String filePath, {Uint8List? pdfBytes}) {
    // 首先检查已完成的缓存
    if (_completedCache.containsKey(filePath)) {
      LogUtils.debug('🦋[PdfDocumentCache] 从完成缓存获取文档: $filePath');
      return Future.value(_completedCache[filePath]);
    }

    // 检查进行中的缓存
    if (_cache.containsKey(filePath)) {
      LogUtils.debug('🦋[PdfDocumentCache] 返回进行中的文档加载: $filePath');
      return _cache[filePath]!;
    }

    // 先登记 Future 再执行加载。否则同步失败时 catch 已移除缓存，外层赋值
    // 却会把失败 Future 再写回，后续重试永远命中同一个失败结果。
    late final Future<PdfDocument> pending;
    pending = Future<PdfDocument>.microtask(
      () => _loadCacheMiss(filePath, pending, pdfBytes: pdfBytes),
    );
    _cache[filePath] = pending;
    return pending;
  }

  /// 移除尚未完成或已失效的缓存项，供调用方在超时后重试。
  void invalidate(String filePath) {
    releaseDocument(filePath);
  }

  void retainDocument(String filePath, Object owner) {
    final users = _documentUsers.putIfAbsent(filePath, () => []);
    users.removeWhere((reference) => reference.target == null);
    if (!users.any((reference) => identical(reference.target, owner))) {
      users.add(WeakReference(owner));
    }
  }

  void releaseDocumentUsage(String filePath, Object owner) {
    final users = _documentUsers[filePath];
    users?.removeWhere(
      (reference) =>
          reference.target == null || identical(reference.target, owner),
    );
    if (users == null || users.isEmpty) _documentUsers.remove(filePath);
    _cleanupExpiredCache();
  }

  bool _isDocumentInUse(String filePath) {
    final users = _documentUsers[filePath];
    users?.removeWhere((reference) => reference.target == null);
    if (users == null || users.isEmpty) {
      _documentUsers.remove(filePath);
      return false;
    }
    return true;
  }

  /// 加载缓存未命中的文档（参考saber的实现）
  Future<PdfDocument> _loadCacheMiss(
    String filePath,
    Future<PdfDocument> pending, {
    Uint8List? pdfBytes,
  }) async {
    try {
      LogUtils.debug('🦋[PdfDocumentCache] 开始加载PDF文档: $filePath');
      final startTime = DateTime.now();

      // macOS 下 PdfDocument.openData 在部分文件上会长期占用 PDFium worker。
      // 只要存在稳定的本地文件就始终使用 openFile；字节模式仅用于没有本地
      // 文件的兼容场景（例如云端资源刚下载到内存但落盘失败）。
      final hasLocalFile = filePath.isNotEmpty && File(filePath).existsSync();
      final document = hasLocalFile
          ? PdfDocument.openFile(filePath)
          : pdfBytes != null
              ? PdfDocument.openData(pdfBytes, sourceName: filePath)
              : throw FileSystemException('PDF 文件不存在', filePath);

      final pdfDocument = await document;
      if (!identical(_cache[filePath], pending)) {
        // 超时失效后的旧任务不能覆盖新任务或重新进入缓存。
        await pdfDocument.dispose();
        throw StateError('PDF load was invalidated');
      }
      final loadTime = DateTime.now().difference(startTime);

      Log.info(
        '🦋[PdfDocumentCache] PDF文档加载完成: $filePath, 用时: ${loadTime.inMilliseconds}ms, 页面数: ${pdfDocument.pages.length}',
      );

      // 存入缓存
      _completedCache[filePath] = pdfDocument;

      // 清理缓存（如果超过限制）
      _cleanupExpiredCache(protectedPath: filePath);

      // 通知监听器
      _notifyListeners();

      return pdfDocument;
    } catch (e, stackTrace) {
      Log.error('[PdfDocumentCache] Open failed: $filePath: $e', e, stackTrace);
      if (identical(_cache[filePath], pending)) {
        unawaited(_cache.remove(filePath));
      }
      rethrow;
    }
  }

  /// 预加载PDF文档（非阻塞）
  void preloadDocument(String filePath) {
    if (!_completedCache.containsKey(filePath) &&
        !_cache.containsKey(filePath)) {
      unawaited(load(filePath).then<void>((_) {}, onError: (Object _) {}));
    }
  }

  /// 释放PDF文档（参考saber的dispose实现）
  void releaseDocument(String filePath) {
    if (_isDocumentInUse(filePath) && _completedCache.containsKey(filePath)) {
      return;
    }
    final documentFuture = _cache.remove(filePath);
    final document = _completedCache.remove(filePath);
    if (documentFuture != null || document != null) {
      LogUtils.debug('🦋[PdfDocumentCache] 释放PDF文档: $filePath');
      if (document != null) {
        unawaited(document.dispose());
      }
      // 尚未完成的任务由 _loadCacheMiss 的身份检查释放，避免重复 dispose。

      // 清理相关的页面缓存
      _pageWidgetCache.removeWhere((key, _) => key.startsWith('$filePath|'));
      _notifyListeners();
    }
  }

  /// 获取缓存的PDF页面Widget
  Widget? getCachedPageWidget(String filePath, int pageIndex) {
    final key = '$filePath|$pageIndex';
    return _pageWidgetCache[key];
  }

  /// 缓存PDF页面Widget
  void cachePageWidget(String filePath, int pageIndex, Widget widget) {
    final key = '$filePath|$pageIndex';
    _pageWidgetCache[key] = widget;

    // 限制页面缓存大小
    if (_pageWidgetCache.length > 50) {
      // 最多缓存50个页面
      final oldestKey = _pageWidgetCache.keys.first;
      _pageWidgetCache.remove(oldestKey);
    }
  }

  /// 清理指定PDF页面的Widget缓存
  void clearPageWidgetCache(String filePath, int pageIndex) {
    final key = '$filePath|$pageIndex';
    final removed = _pageWidgetCache.remove(key);
    if (removed != null) {
      LogUtils.debug('🧹[PdfDocumentCache] 清理页面Widget缓存: $key');
    }
  }

  /// 清理过期缓存（参考Saber的缓存清理策略）
  void _cleanupExpiredCache({String? protectedPath}) {
    // 只清理已完成且无人使用的文档；进行中的任务不能被容量清理打断。
    // 活跃文档超过上限时允许暂时超限，页面退出后再回收。
    while (_completedCache.length > maxCacheSize) {
      final candidates = _completedCache.keys.where(
        (key) => key != protectedPath && !_isDocumentInUse(key),
      );
      if (candidates.isEmpty) break;
      releaseDocument(candidates.first);
    }
  }

  /// 启动清理定时器
  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(cleanupInterval, (_) {
      _cleanupExpiredCache();
    });
  }

  /// 添加监听器
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  /// 移除监听器
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  /// 通知所有监听器
  void _notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  /// 获取缓存统计信息
  Map<String, dynamic> getCacheStats() {
    return {
      'cachedDocuments': _cache.length,
      'completedDocuments': _completedCache.length,
      'cachedPages': _pageWidgetCache.length,
      'maxCacheSize': maxCacheSize,
    };
  }

  /// 清理所有缓存（用于测试或内存清理）
  void clearAllCache() {
    LogUtils.debug('🦋[PdfDocumentCache] 清理所有缓存');
    final keys = List<String>.from(_cache.keys);
    for (final key in keys) {
      releaseDocument(key);
    }
    _pageWidgetCache.clear();
  }

  /// 销毁管理器（参考Saber的dispose实现）
  void dispose() {
    // 停止清理定时器
    _cleanupTimer?.cancel();
    _cleanupTimer = null;

    // 清理所有监听器
    _listeners.clear();

    clearAllCache();

    LogUtils.debug('🦋[PdfDocumentCacheManager] 已销毁缓存管理器');
  }
}

/// PDF页面加载策略枚举
enum PdfPageLoadStrategy {
  immediate, // 立即加载
  lazy, // 延迟加载（用户滚动到时加载）
  preload, // 预加载（提前加载相邻页面）
}

/// PDF多页管理器 - 用于优化多页PDF的加载性能
class PdfMultiPageManager {
  static final PdfMultiPageManager _instance = PdfMultiPageManager._internal();
  factory PdfMultiPageManager() => _instance;

  PdfMultiPageManager._internal();

  final PdfDocumentCacheManager _cacheManager = PdfDocumentCacheManager();

  // 当前可见的页面集合
  final Set<String> _visiblePages = {};

  // 页面加载策略配置
  static const int preloadAdjacentPages = 2; // 预加载相邻页面的数量
  static const Duration lazyLoadDelay = Duration(milliseconds: 100); // 延迟加载延迟时间

  /// 更新可见页面集合
  void updateVisiblePages(List<String> visiblePageKeys) {
    final previousVisible = Set<String>.from(_visiblePages);
    _visiblePages.clear();
    _visiblePages.addAll(visiblePageKeys);

    // 找出新增的可见页面
    final newVisiblePages = _visiblePages.difference(previousVisible);

    // 为新增的可见页面启动智能加载
    for (final pageKey in newVisiblePages) {
      _loadPageWithStrategy(pageKey, PdfPageLoadStrategy.immediate);
    }

    // 为相邻页面启动预加载
    for (final pageKey in _visiblePages) {
      _preloadAdjacentPages(pageKey);
    }

    // 清理不可见页面的缓存（可选，根据内存情况）
    _cleanupInvisiblePages(previousVisible.difference(_visiblePages));
  }

  /// 解析页面键为文件路径和页面索引
  (String filePath, int pageIndex) _parsePageKey(String pageKey) {
    final parts = pageKey.split('|');
    if (parts.length != 2) {
      throw FormatException('Invalid page key format: $pageKey');
    }
    return (parts[0], int.parse(parts[1]));
  }

  /// 根据策略加载页面
  void _loadPageWithStrategy(String pageKey, PdfPageLoadStrategy strategy) {
    final (filePath, pageIndex) = _parsePageKey(pageKey);

    switch (strategy) {
      case PdfPageLoadStrategy.immediate:
        // 立即预加载文档
        _cacheManager.preloadDocument(filePath);
        break;

      case PdfPageLoadStrategy.lazy:
        // 延迟加载
        Future.delayed(lazyLoadDelay, () {
          if (_visiblePages.contains(pageKey)) {
            _cacheManager.preloadDocument(filePath);
          }
        });
        break;

      case PdfPageLoadStrategy.preload:
        // 预加载（低优先级）
        Future.delayed(const Duration(milliseconds: 50), () {
          if (_visiblePages.contains(pageKey)) {
            _cacheManager.preloadDocument(filePath);
          }
        });
        break;
    }
  }

  /// 预加载相邻页面
  void _preloadAdjacentPages(String pageKey) {
    final (filePath, pageIndex) = _parsePageKey(pageKey);

    // 获取文档来确定总页数
    final document = _cacheManager._completedCache[filePath];
    if (document == null) return;

    // 预加载相邻页面
    for (int i = 1; i <= preloadAdjacentPages; i++) {
      // 上一页
      if (pageIndex - i >= 0) {
        final prevPageKey = '$filePath|${pageIndex - i}';
        _loadPageWithStrategy(prevPageKey, PdfPageLoadStrategy.preload);
      }

      // 下一页
      if (pageIndex + i < document.pages.length) {
        final nextPageKey = '$filePath|${pageIndex + i}';
        _loadPageWithStrategy(nextPageKey, PdfPageLoadStrategy.preload);
      }
    }
  }

  /// 清理不可见页面的缓存（内存优化）
  void _cleanupInvisiblePages(Set<String> invisiblePages) {
    // 这里可以实现更智能的缓存清理策略
    // 例如：清理距离当前页面较远的页面
    for (final pageKey in invisiblePages) {
      // 可以选择清理页面Widget缓存，但保留文档缓存
      // 暂时保留所有缓存，未来可以根据内存压力动态清理
      debugPrint('🦋[PdfMultiPageManager] 不可见页面: $pageKey');
    }
  }

  /// 检查页面是否可见
  bool isPageVisible(String pageKey) {
    return _visiblePages.contains(pageKey);
  }

  /// 获取加载统计信息
  Map<String, dynamic> getLoadStats() {
    return {
      'visiblePages': _visiblePages.length,
      'cacheStats': _cacheManager.getCacheStats(),
    };
  }
}

/// ✅ 简化的 PDF 编辑器图片类，参考 Saber 的 PdfEditorImage
///
/// 支持两种存储模式：
/// 1. 本地路径（pdfFilePath）：本地 PDF 文件，仅当前设备可访问
/// 2. 云存储（pdfUrl）：PDF 上传至云存储，跨设备可访问
///
/// 跨设备同步策略：
/// - 导入 PDF 时，上传到云存储并保存 pdfUrl
/// - fromJson 时优先使用 pdfUrl，若为云 URL 则在本地下载缓存后使用
class PdfEditorImage {
  PdfEditorImage({
    required this.pdfFilePath,
    required this.pdfPageIndex, // PDF 页面索引（从 0 开始）
    required this.naturalSize, // PDF 页面的自然尺寸
    String? pdfUrl, // 云存储 URL（跨设备同步用）
    this.pdfBytes, // PDF 原始字节（用于云URL模式下的本地缓存）
    this.dstRect, // 目标矩形（在画布上的位置和大小）
  }) : pdfUrl = (pdfUrl != null && pdfUrl.isNotEmpty)
            ? pdfUrl
            : (pdfFilePath.startsWith('http') ? pdfFilePath : null);

  /// PDF 文件路径（本地路径 或 云 URL 本地缓存路径）
  String pdfFilePath;

  /// 云存储 URL（优先用于跨设备同步；有此值时 pdfFilePath 可为本地缓存路径）
  String? pdfUrl;

  /// PDF 原始字节（用于从云端下载后内存缓存，避免重复下载）
  Uint8List? pdfBytes;

  /// 是否已被 dispose，用于保护异步回调中对 _loadState 的访问
  bool _isDisposed = false;

  final int pdfPageIndex; // PDF 页面索引（从 0 开始）
  final Size naturalSize; // PDF 页面的自然尺寸
  Rect? dstRect; // 目标矩形（在画布上的位置和大小）

  /// 上传 PDF 到云存储，返回云 URL
  Future<String?> uploadToCloud() async {
    if (pdfUrl != null && pdfUrl!.startsWith('http')) {
      return pdfUrl; // 已上传
    }

    try {
      // 读取本地 PDF 文件
      final file = File(pdfFilePath);
      if (!file.existsSync()) {
        Log.error('[PdfEditorImage] PDF file not found: $pdfFilePath');
        return null;
      }

      final bytes = await file.readAsBytes();
      final fileName =
          'handwriting_pdf_${const Uuid().v4().substring(0, 8)}.pdf';
      Log.info(
        '[PdfEditorImage] Uploading PDF: $fileName (${bytes.length} bytes)',
      );

      final url = await FileUploadService.uploadFile(bytes, fileName);
      pdfUrl = url;
      // ⚡ 导入上传后立即写入工作区持久缓存，首次切换视图回来即命中、无需联网
      await HandwritingPdfCacheService().put(url, bytes);
      Log.info('[PdfEditorImage] ✅ PDF uploaded: $url');
      return url;
    } catch (e) {
      Log.error('[PdfEditorImage] ❌ PDF upload failed: $e');
      return null;
    }
  }

  /// 从云 URL 下载 PDF 并缓存到本地（供 PdfDocument.openFile 使用）
  Future<void> downloadFromCloud({bool forceDownload = false}) async {
    if (pdfUrl == null || !pdfUrl!.startsWith('http')) return;

    // 检查本地缓存是否有效
    if (!forceDownload &&
        pdfFilePath.isNotEmpty &&
        File(pdfFilePath).existsSync() &&
        File(pdfFilePath).lengthSync() > 0) {
      return;
    }

    final entry = await HandwritingPdfCacheService().load(
      pdfUrl!,
      forceDownload: forceDownload,
      download: () async {
        final userResult = await UserBackendService.getCurrentUserProfile();
        final rawToken = userResult.fold((u) => u.token, (_) => '');
        final token = _normalizeToken(rawToken);
        return downloadHandwritingPdf(
          Uri.parse(pdfUrl!),
          headers: token.isNotEmpty ? {'Authorization': 'Bearer $token'} : {},
          client: http.Client(),
        );
      },
    );
    if (_isDisposed) return;
    pdfBytes = entry.path == null ? entry.bytes : null;
    if (entry.path != null) {
      pdfFilePath = entry.path!;
    } else {
      // 落盘失败时用本次完整下载的字节，勿继续解析旧的损坏文件。
      pdfFilePath = pdfUrl!;
    }
  }

  /// 获取PDF文档缓存管理器
  PdfDocumentCacheManager get _cacheManager => PdfDocumentCacheManager();

  /// PDF 加载状态
  final _loadState = ValueNotifier<PdfLoadState>(PdfLoadState.notLoaded);

  /// 加载错误信息
  String? _loadError;

  Future<void>? _loadingTask;
  PdfDocument? _document;
  String? _retainedPath;
  Timer? _retryTimer;
  int _retryCount = 0;
  bool _hasRefreshedCloudCopy = false;
  static const int maxAutomaticRetries = 2;

  /// 获取当前加载状态
  PdfLoadState get loadState => _loadState.value;

  /// 获取加载错误信息
  String? get loadError => _loadError;

  /// 监听加载状态变化
  ValueNotifier<PdfLoadState> get loadStateNotifier => _loadState;

  /// 是否正在加载
  bool get isLoading => _loadState.value == PdfLoadState.loading;

  /// 是否已加载完成
  bool get isLoaded => _loadState.value == PdfLoadState.loaded;

  /// 是否加载失败
  bool get isFailed => _loadState.value == PdfLoadState.failed;

  /// 获取PDF文档（从缓存管理器获取，支持云 URL 先下载后加载）
  Future<PdfDocument?> get cachedPdfDocument async {
    if (_isDisposed) return null;
    await loadPdfDocument();
    return _document;
  }

  /// 获取同步的PDF文档（如果已缓存）
  PdfDocument? get synchronousPdfDocument {
    return _document;
  }

  /// 预加载 PDF 文档（非阻塞，不会等待结果）
  void preloadPdfDocument() {
    if (_isDisposed) return;
    if (_loadState.value == PdfLoadState.notLoaded) {
      unawaited(loadPdfDocument());
    }
  }

  /// 确保页面已经开始加载，重复触发时复用当前任务和文档。
  void resetLoadStateAndPreload() {
    if (_isDisposed) return;
    // 预加载、画布挂载、后台下载可能同时到达；共用当前任务及已打开的文档。
    if (_loadingTask != null || _document != null) return;
    debugPrint(
      '🔄[PdfEditorImage] 重置加载状态并预加载: $pdfFilePath (页面 $pdfPageIndex)',
    );

    _cacheManager.clearPageWidgetCache(pdfFilePath, pdfPageIndex);

    _loadState.value = PdfLoadState.notLoaded;
    _loadError = null;
    _retryCount = 0;
    _hasRefreshedCloudCopy = false;

    preloadPdfDocument();
  }

  /// 异步加载 PDF 文档（参考saber的firstLoad实现）
  Future<void> _loadPdfDocumentAsync() async {
    try {
      // 页面结构可能先于云地址同步到达，源设备的本地路径无法在这里打开。
      if (!(pdfUrl?.startsWith('http') ?? false) &&
          (pdfBytes == null || pdfBytes!.isEmpty) &&
          pdfFilePath.isNotEmpty &&
          !File(pdfFilePath).existsSync()) {
        _loadError = null;
        _loadState.value = PdfLoadState.waitingForSync;
        Log.info(
          '[PdfEditorImage] Waiting for cloud reference: page=$pdfPageIndex',
        );
        return;
      }
      debugPrint(
        '🦋[PdfEditorImage] 开始异步加载 PDF: $pdfFilePath (pdfUrl: $pdfUrl)',
      );
      final startTime = DateTime.now();

      PdfDocument? document;
      try {
        document = await _openDocument();
      } catch (e) {
        if (_isDisposed) return;
        // 缓存有文件不代表能够解析。只在存在云副本时回源一次；不删除唯一的
        // 本地导入文件，也不对 PDFium 解析超时启动更多并发解析。
        if (_hasRefreshedCloudCopy ||
            pdfUrl == null ||
            !pdfUrl!.startsWith('http') ||
            e is TimeoutException) {
          rethrow;
        }
        _hasRefreshedCloudCopy = true;
        Log.warn(
          '[PdfEditorImage] Refreshing cloud copy after open failure: $e',
        );
        await downloadFromCloud(forceDownload: true);
        document = await _openDocument();
      }

      if (_isDisposed || document == null) return;

      if (pdfPageIndex < 0 || pdfPageIndex >= document.pages.length) {
        throw Exception(
          'PDF页面索引无效: $pdfPageIndex, 总页数: ${document.pages.length}',
        );
      }

      final loadTime = DateTime.now().difference(startTime);
      debugPrint(
        '🦋[PdfEditorImage] PDF加载完成: $pdfFilePath (页面 $pdfPageIndex), 用时: ${loadTime.inMilliseconds}ms',
      );

      _document = document;
      if (File(pdfFilePath).existsSync()) pdfBytes = null;
      _loadError = null;
      _retryCount = 0;
      _loadState.value = PdfLoadState.loaded;
    } catch (e, stackTrace) {
      if (_isDisposed) return;
      _loadError = e.toString();
      final willRetry =
          _retryCount < maxAutomaticRetries && e is! TimeoutException;
      _loadState.value = willRetry ? PdfLoadState.loading : PdfLoadState.failed;
      Log.error(
        '[PdfEditorImage] Load failed: page=$pdfPageIndex, '
        'hasCloud=${pdfUrl != null}, retry=$_retryCount: $e',
        e,
        stackTrace,
      );

      if (willRetry) {
        _retryCount++;
        _retryTimer = Timer(const Duration(seconds: 1), () {
          if (_isDisposed) return;
          if (_loadState.value == PdfLoadState.loading) {
            unawaited(loadPdfDocument());
          }
        });
      }
    }
  }

  Future<PdfDocument?> _openDocument() async {
    if (pdfUrl != null &&
        pdfUrl!.startsWith('http') &&
        (pdfFilePath.isEmpty ||
            !File(pdfFilePath).existsSync() ||
            File(pdfFilePath).lengthSync() == 0) &&
        (pdfBytes == null || pdfBytes!.isEmpty)) {
      await downloadFromCloud();
    }
    if (_isDisposed) return null;
    if (pdfFilePath.isEmpty) {
      throw const FileSystemException('PDF file path is empty');
    }
    if (_retainedPath != pdfFilePath) {
      final previous = _retainedPath;
      _cacheManager.retainDocument(pdfFilePath, this);
      _retainedPath = pdfFilePath;
      if (previous != null) _cacheManager.releaseDocumentUsage(previous, this);
    }
    final path = pdfFilePath;
    return _cacheManager.load(path, pdfBytes: pdfBytes).timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        _cacheManager.invalidate(path);
        throw TimeoutException('PDF open timed out');
      },
    );
  }

  /// 加载 PDF 文档（兼容旧接口，会等待加载完成）
  Future<void> loadPdfDocument() async {
    if (_isDisposed) return;

    if (_loadState.value == PdfLoadState.loaded) {
      return;
    }

    final existing = _loadingTask;
    if (existing != null) return existing;
    _retryTimer?.cancel();
    _retryTimer = null;
    _loadState.value = PdfLoadState.loading;
    final task = _loadPdfDocumentAsync();
    _loadingTask = task;
    try {
      await task;
    } finally {
      if (identical(_loadingTask, task)) _loadingTask = null;
    }
  }

  /// 预热页面数据（在pdfrx 1.x版本下的优化实现）
  Future<void> warmUpPage() async {
    final pdfDocument = await cachedPdfDocument;
    if (pdfDocument == null) {
      debugPrint('⚠️ [PdfEditorImage] PDF文档为空，无法预热页面');
      return;
    }

    // 检查页面索引是否有效
    if (pdfPageIndex < 0 || pdfPageIndex >= pdfDocument.pages.length) {
      debugPrint(
        '⚠️ [PdfEditorImage] 页面索引无效: $pdfPageIndex, 总页数: ${pdfDocument.pages.length}',
      );
      return;
    }

    try {
      // 在当前版本下，我们通过访问页面对象来触发预加载
      // 这有助于提前初始化页面数据结构
      final page = pdfDocument.pages[pdfPageIndex];
      debugPrint(
        '🦋[PdfEditorImage] 页面 $pdfPageIndex 预热完成，大小: ${page.width}x${page.height}',
      );
    } catch (e) {
      debugPrint('❌ [PdfEditorImage] 页面 $pdfPageIndex 预热失败: $e');
      // 不抛出异常，允许继续使用
    }
  }

  /// 构建 PDF 页面 Widget（严格按照Saber的PdfEditorImage.buildImageWidget实现）
  Widget buildPdfPageWidget({
    required BoxFit boxFit,
  }) {
    // 不缓存 Widget 实例，避免复用已绑定旧 PdfDocument 的 PdfPageView。
    // 文档本身仍由 PdfDocumentCacheManager 缓存。
    debugPrint(
      '🎨[PdfEditorImage] 构建新的Widget: $pdfFilePath (页面 $pdfPageIndex), loadState=${_loadState.value}',
    );

    // 使用ValueNotifier监听PDF文档加载状态（参考Saber的实现）
    return ValueListenableBuilder<PdfLoadState>(
      valueListenable: _loadState,
      builder: (context, loadState, child) {
        debugPrint(
          '🎨[PdfEditorImage] ValueListenableBuilder rebuild: loadState=$loadState',
        );
        switch (loadState) {
          case PdfLoadState.notLoaded:
          case PdfLoadState.waitingForSync:
          case PdfLoadState.loading:
            // 显示加载状态
            return SizedBox.fromSize(
              size: naturalSize,
              child: Container(
                color: Colors.grey[100],
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 8),
                      Text(
                        (loadState == PdfLoadState.waitingForSync
                                ? LocaleKeys.newSettings_syncState_syncing
                                : LocaleKeys.editor_loading)
                            .tr(),
                      ),
                    ],
                  ),
                ),
              ),
            );

          case PdfLoadState.failed:
            // 显示加载失败状态
            return SizedBox.fromSize(
              size: naturalSize,
              child: Container(
                color: Colors.grey[100],
                child: const Center(
                  child: Icon(Icons.error_outline, color: Colors.red),
                ),
              ),
            );

          case PdfLoadState.loaded:
            // loaded 状态持有同一份文档，重绘时不再创建新的异步加载任务。
            return PdfPageView(
              document: _document!,
              pageNumber: pdfPageIndex + 1,
              decoration: const BoxDecoration(),
            );
        }
      },
    );
  }

  /// 归一化token：如果是JSON字符串则提取access_token
  static String _normalizeToken(String token) {
    if (token.isEmpty) return token;
    if (token.trim().startsWith('{')) {
      try {
        final map = jsonDecode(token);
        if (map is Map && map['access_token'] is String) {
          return map['access_token'] as String;
        }
      } catch (_) {}
    }
    return token;
  }

  /// 释放资源（参考Saber的dispose实现）
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _retryTimer?.cancel();
    _document = null;
    final retainedPath = _retainedPath;
    _retainedPath = null;
    if (retainedPath != null) {
      _cacheManager.releaseDocumentUsage(retainedPath, this);
    }
    _loadState.dispose();
  }
}
