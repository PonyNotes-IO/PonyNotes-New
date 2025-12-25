import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// PDF加载状态枚举
enum PdfLoadState {
  notLoaded,    // 未加载
  loading,      // 正在加载
  loaded,       // 已加载成功
  failed,       // 加载失败
}

/// PDF文档缓存条目
class _PdfDocumentCacheEntry {
  _PdfDocumentCacheEntry(this.document, this.lastAccessTime);

  final PdfDocument document;
  DateTime lastAccessTime;

  void updateAccessTime() {
    lastAccessTime = DateTime.now();
  }
}

/// PDF文档缓存管理器 - 全局单例
class PdfDocumentCacheManager {
  static final PdfDocumentCacheManager _instance = PdfDocumentCacheManager._internal();
  factory PdfDocumentCacheManager() => _instance;

  PdfDocumentCacheManager._internal() {
    // 定期清理过期缓存
    _startCleanupTimer();
  }

  // 文档缓存：文件路径 -> 缓存条目
  final Map<String, _PdfDocumentCacheEntry> _documentCache = {};

  // 页面缓存：文件路径+页面索引 -> 页面Widget
  final Map<String, Widget> _pageWidgetCache = {};

  // 缓存配置
  static const int maxCacheSize = 10; // 最大缓存文档数量
  static const Duration cacheExpiry = Duration(minutes: 30); // 缓存过期时间
  static const Duration cleanupInterval = Duration(minutes: 5); // 清理间隔

  // 监听器集合
  final Set<VoidCallback> _listeners = {};

  Timer? _cleanupTimer;

  /// 获取或加载PDF文档（带缓存）
  Future<PdfDocument?> getOrLoadDocument(String filePath) async {
    // 检查缓存
    if (_documentCache.containsKey(filePath)) {
      final entry = _documentCache[filePath]!;
      entry.updateAccessTime();
      debugPrint('🦋[PdfDocumentCache] 从缓存获取文档: $filePath');
      return entry.document;
    }

    // 检查文件是否存在
    final file = File(filePath);
    if (!await file.exists()) {
      debugPrint('❌ [PdfDocumentCache] PDF文件不存在: $filePath');
      return null;
    }

    try {
      debugPrint('🦋[PdfDocumentCache] 开始加载PDF文档: $filePath');
      final startTime = DateTime.now();

      final document = await PdfDocument.openFile(filePath);
      final loadTime = DateTime.now().difference(startTime);

      debugPrint('🦋[PdfDocumentCache] PDF文档加载完成: $filePath, 用时: ${loadTime.inMilliseconds}ms, 页面数: ${document.pages.length}');

      // 添加到缓存
      _addToCache(filePath, document);

      // 通知监听器
      _notifyListeners();

      return document;
    } catch (e) {
      debugPrint('❌ [PdfDocumentCache] 加载PDF文档失败: $filePath, 错误: $e');
      return null;
    }
  }

  /// 预加载PDF文档（非阻塞）
  void preloadDocument(String filePath) {
    if (!_documentCache.containsKey(filePath)) {
      getOrLoadDocument(filePath); // 异步预加载，不等待结果
    }
  }

  /// 释放PDF文档
  void releaseDocument(String filePath) {
    final entry = _documentCache.remove(filePath);
    if (entry != null) {
      debugPrint('🦋[PdfDocumentCache] 释放PDF文档: $filePath');
      entry.document.dispose();

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
    if (_pageWidgetCache.length > 50) { // 最多缓存50个页面
      final oldestKey = _pageWidgetCache.keys.first;
      _pageWidgetCache.remove(oldestKey);
    }
  }

  /// 清理过期缓存
  void _cleanupExpiredCache() {
    final now = DateTime.now();
    final expiredKeys = <String>[];

    _documentCache.forEach((key, entry) {
      if (now.difference(entry.lastAccessTime) > cacheExpiry) {
        expiredKeys.add(key);
      }
    });

    for (final key in expiredKeys) {
      debugPrint('🦋[PdfDocumentCache] 清理过期缓存: $key');
      releaseDocument(key);
    }

    // 如果缓存过大，清理最旧的文档
    while (_documentCache.length > maxCacheSize) {
      final oldestKey = _documentCache.keys.reduce((a, b) =>
        _documentCache[a]!.lastAccessTime.isBefore(_documentCache[b]!.lastAccessTime) ? a : b
      );
      debugPrint('🦋[PdfDocumentCache] 清理超限缓存: $oldestKey');
      releaseDocument(oldestKey);
    }
  }

  /// 添加文档到缓存
  void _addToCache(String filePath, PdfDocument document) {
    _documentCache[filePath] = _PdfDocumentCacheEntry(document, DateTime.now());

    // 清理过期和超限缓存
    _cleanupExpiredCache();
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
      'cachedDocuments': _documentCache.length,
      'cachedPages': _pageWidgetCache.length,
      'maxCacheSize': maxCacheSize,
    };
  }

  /// 清理所有缓存（用于测试或内存清理）
  void clearAllCache() {
    debugPrint('🦋[PdfDocumentCache] 清理所有缓存');
    final keys = List<String>.from(_documentCache.keys);
    for (final key in keys) {
      releaseDocument(key);
    }
    _pageWidgetCache.clear();
  }

  /// 销毁管理器
  void dispose() {
    _cleanupTimer?.cancel();
    clearAllCache();
    _listeners.clear();
  }
}

/// PDF页面加载策略枚举
enum PdfPageLoadStrategy {
  immediate,   // 立即加载
  lazy,        // 延迟加载（用户滚动到时加载）
  preload,     // 预加载（提前加载相邻页面）
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
    final document = _cacheManager._documentCache[filePath]?.document;
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
class PdfEditorImage {
  PdfEditorImage({
    required this.pdfFilePath,
    required this.pdfPageIndex,  // PDF 页面索引（从 0 开始）
    required this.naturalSize,   // PDF 页面的自然尺寸
    this.dstRect,                // 目标矩形（在画布上的位置和大小）
  });

  final String pdfFilePath;      // PDF 文件路径
  final int pdfPageIndex;         // PDF 页面索引（从 0 开始）
  final Size naturalSize;         // PDF 页面的自然尺寸
  Rect? dstRect;                  // 目标矩形（在画布上的位置和大小）

  /// 获取PDF文档缓存管理器
  PdfDocumentCacheManager get _cacheManager => PdfDocumentCacheManager();

  /// PDF 加载状态
  final _loadState = ValueNotifier<PdfLoadState>(PdfLoadState.notLoaded);

  /// 加载错误信息
  String? _loadError;

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

  /// 获取PDF文档（从缓存管理器获取）
  PdfDocument? get cachedPdfDocument {
    return _cacheManager._documentCache[pdfFilePath]?.document;
  }

  /// 预加载 PDF 文档（非阻塞，不会等待结果）
  void preloadPdfDocument() {
    if (_loadState.value == PdfLoadState.notLoaded) {
      _loadState.value = PdfLoadState.loading;
      _loadPdfDocumentAsync();
    }
  }

  /// 异步加载 PDF 文档（内部方法）
  Future<void> _loadPdfDocumentAsync() async {
    try {
      debugPrint('🦋[PdfEditorImage] 开始异步加载 PDF: $pdfFilePath');
      final startTime = DateTime.now();

      // 通过缓存管理器获取或加载文档
      final document = await _cacheManager.getOrLoadDocument(pdfFilePath);

      if (document == null) {
        throw Exception('无法加载PDF文档');
      }

      // 检查页面索引是否有效
      if (pdfPageIndex < 0 || pdfPageIndex >= document.pages.length) {
        throw Exception('PDF页面索引无效: $pdfPageIndex, 总页数: ${document.pages.length}');
      }

      final loadTime = DateTime.now().difference(startTime);
      debugPrint('🦋[PdfEditorImage] PDF加载完成: $pdfFilePath (页面 $pdfPageIndex), 用时: ${loadTime.inMilliseconds}ms');

      _loadState.value = PdfLoadState.loaded;
      _loadError = null;

    } catch (e) {
      debugPrint('❌ [PdfEditorImage] PDF加载失败: $e');
      _loadState.value = PdfLoadState.failed;
      _loadError = e.toString();

      // 简单的重试机制，延迟1秒后重试一次
      Future.delayed(const Duration(seconds: 1), () {
        if (_loadState.value == PdfLoadState.failed) {
          debugPrint('🦋[PdfEditorImage] 尝试重试加载 PDF: $pdfFilePath');
          _loadState.value = PdfLoadState.notLoaded;
          preloadPdfDocument();
        }
      });
    }
  }

  /// 加载 PDF 文档（兼容旧接口，会等待加载完成）
  Future<void> loadPdfDocument() async {
    if (_loadState.value == PdfLoadState.loaded) {
      return;  // 已经加载完成
    }

    if (_loadState.value == PdfLoadState.loading) {
      // 正在加载中，等待完成
      await _waitForLoading();
      return;
    }

    // 开始加载
    _loadState.value = PdfLoadState.loading;
    await _loadPdfDocumentAsync();
  }

  /// 等待加载完成（用于兼容旧接口）
  Future<void> _waitForLoading() async {
    if (_loadState.value != PdfLoadState.loading) return;

    await Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 50));
      return _loadState.value == PdfLoadState.loading;
    });
  }

  /// 构建 PDF 页面 Widget
  Widget buildPdfPageWidget({
    required BoxFit boxFit,
  }) {
    // 先检查页面Widget缓存
    final cachedWidget = _cacheManager.getCachedPageWidget(pdfFilePath, pdfPageIndex);
    if (cachedWidget != null) {
      return cachedWidget;
    }

    return ValueListenableBuilder<PdfLoadState>(
      valueListenable: _loadState,
      builder: (context, loadState, child) {
        switch (loadState) {
          case PdfLoadState.notLoaded:
          case PdfLoadState.loading:
            // 显示加载状态
            return Container(
              color: Colors.grey[100],
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 8),
                    Text(
                      loadState == PdfLoadState.loading ? '正在加载PDF...' : '准备加载PDF...',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            );

          case PdfLoadState.failed:
            // 显示加载失败状态
            return Container(
              color: Colors.grey[100],
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 8),
                    const Text(
                      'PDF加载失败',
                      style: TextStyle(fontSize: 14, color: Colors.red),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _loadError ?? '未知错误',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: preloadPdfDocument,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            );

          case PdfLoadState.loaded:
            // PDF 已加载成功，显示PDF页面
            final pdfDocument = this.cachedPdfDocument;
            if (pdfDocument == null) {
              return Container(
                color: Colors.grey[100],
                child: const Center(
                  child: Text('PDF文档为空'),
                ),
              );
            }

            // 检查页面索引是否有效
            if (pdfPageIndex < 0 || pdfPageIndex >= pdfDocument.pages.length) {
              return Container(
                color: Colors.grey[100],
                child: Center(
                  child: Text('PDF页面不存在 (页面 ${pdfPageIndex + 1}/${pdfDocument.pages.length})'),
                ),
              );
            }

            // ✅ 创建并缓存 PdfPageView
            final pageWidget = PdfPageView(
              document: pdfDocument,
              pageNumber: pdfPageIndex + 1,  // pdfrx 的页面编号从 1 开始
              decoration: const BoxDecoration(),
            );

            // 缓存页面Widget
            _cacheManager.cachePageWidget(pdfFilePath, pdfPageIndex, pageWidget);

            return pageWidget;
        }
      },
    );
  }

  /// 释放资源
  void dispose() {
    _loadState.dispose();
    // 注意：PDF文档现在由PdfDocumentCacheManager管理，不在这里释放
  }
}

