import 'dart:io';

import '../third_party/saber_core/components/canvas/image/pdf_editor_image.dart';

/// 同一编辑器内串行上传 PDF，同一本地文件的所有页面共享云地址。
/// 不保留跨笔记、账号或工作区的上传结果缓存。
class HandwritingPdfAssetUploader {
  Future<void>? _pendingUpload;

  Future<void> upload(Iterable<PdfEditorImage> images) async {
    // 导入或切换笔记可能替换页面列表，上传只处理调用时的资源快照。
    final snapshot = images.toList();
    final previous = _pendingUpload;
    final task = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {
          // 前一个调用向自己的调用方报告失败，不阻止后续保存重新尝试。
        }
      }
      await _uploadFiles(snapshot);
    }();
    _pendingUpload = task;
    try {
      await task;
    } finally {
      if (identical(_pendingUpload, task)) {
        _pendingUpload = null;
      }
    }
  }

  Future<void> _uploadFiles(List<PdfEditorImage> images) async {
    final files = <String, List<PdfEditorImage>>{};
    for (final image in images) {
      final path = image.pdfFilePath;
      if (path.isNotEmpty && !path.startsWith('http')) {
        files.putIfAbsent(path, () => []).add(image);
      }
    }

    for (final entry in files.entries) {
      String? url;
      for (final image in entry.value) {
        if (_isCloudUrl(image.pdfUrl)) {
          url = image.pdfUrl;
          break;
        }
      }
      if (url == null && File(entry.key).existsSync()) {
        final image = entry.value.first;
        url = await image.uploadToCloud();
        if (!_isCloudUrl(url)) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          url = await image.uploadToCloud();
        }
      }
      if (_isCloudUrl(url)) {
        for (final image in entry.value) {
          // 同路径的历史页面可能已有各自有效的 URL，不覆盖已保存的云引用。
          if (!_isCloudUrl(image.pdfUrl)) image.pdfUrl = url;
        }
      }
    }
  }

  bool _isCloudUrl(String? url) => url != null && url.startsWith('http');
}
