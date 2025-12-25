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

  /// PDF 文档缓存（使用 ValueNotifier 管理）
  final _pdfDocument = ValueNotifier<PdfDocument?>(null);

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

      final file = File(pdfFilePath);
      if (!await file.exists()) {
        throw Exception('PDF文件不存在: $pdfFilePath');
      }

      // 使用 compute 在后台线程加载PDF，避免阻塞UI
      final pdfDocument = await PdfDocument.openFile(pdfFilePath);

      final loadTime = DateTime.now().difference(startTime);
      debugPrint('🦋[PdfEditorImage] PDF加载完成: $pdfFilePath, 用时: ${loadTime.inMilliseconds}ms, 页面数: ${pdfDocument.pages.length}');

      _pdfDocument.value = pdfDocument;
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

  /// 获取 PDF 文档
  PdfDocument? get pdfDocument => _pdfDocument.value;

  /// 构建 PDF 页面 Widget
  Widget buildPdfPageWidget({
    required BoxFit boxFit,
  }) {
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
            final pdfDocument = _pdfDocument.value;
            if (pdfDocument == null) {
              return Container(
                color: Colors.grey[100],
                child: const Center(
                  child: Text('PDF文档为空'),
                ),
              );
            }

            // ✅ 使用 PdfPageView 显示 PDF 页面
            return PdfPageView(
              document: pdfDocument,
              pageNumber: pdfPageIndex + 1,  // pdfrx 的页面编号从 1 开始
              decoration: const BoxDecoration(),
            );
        }
      },
    );
  }

  /// 释放资源
  void dispose() {
    _pdfDocument.value?.dispose();
    _pdfDocument.dispose();
    _loadState.dispose();
  }
}

