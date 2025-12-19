import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

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

  /// 加载 PDF 文档
  Future<void> loadPdfDocument() async {
    if (_pdfDocument.value != null) {
      return;  // 已经加载
    }

    try {
      final file = File(pdfFilePath);
      if (await file.exists()) {
        _pdfDocument.value = await PdfDocument.openFile(pdfFilePath);
      }
    } catch (e) {
      debugPrint('❌ [PdfEditorImage] Failed to load PDF: $e');
    }
  }

  /// 获取 PDF 文档
  PdfDocument? get pdfDocument => _pdfDocument.value;

  /// 构建 PDF 页面 Widget
  Widget buildPdfPageWidget({
    required BoxFit boxFit,
  }) {
    return ValueListenableBuilder<PdfDocument?>(
      valueListenable: _pdfDocument,
      builder: (context, pdfDocument, child) {
        if (pdfDocument == null) {
          // PDF 未加载，显示占位符
          return Container(
            color: Colors.grey[200],
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // ✅ 使用 PdfPageView 显示 PDF 页面
        return PdfPageView(
          document: pdfDocument,
          pageNumber: pdfPageIndex + 1,  // pdfrx 的页面编号从 1 开始
          decoration: const BoxDecoration(),
        );
      },
    );
  }

  /// 释放资源
  void dispose() {
    _pdfDocument.value?.dispose();
    _pdfDocument.dispose();
  }
}

