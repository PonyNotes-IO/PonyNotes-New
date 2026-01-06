import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../../../../../util/log_utils.dart';

/// PDF文本提取结果
class PdfTextExtractionResult {
  PdfTextExtractionResult({
    required this.text,
    required this.pageIndex,
    this.bboxes,
  });

  final String text; // 提取的文本
  final int pageIndex; // 页面索引（从0开始）
  final List<Rect>? bboxes; // 文本边界框（可选，用于精确定位）
}

/// PDF文本提取服务
/// 用于从PDF文档中提取文本内容，支持单页和多页提取
class PdfTextExtractionService {
  /// 提取单个PDF页面的文本
  /// [pdfBytes] PDF文件的字节数据
  /// [pageIndex] 页面索引（从0开始）
  /// 返回提取的文本，如果提取失败则返回空字符串
  static Future<String> extractPageText(
    Uint8List pdfBytes,
    int pageIndex,
  ) async {
    PdfDocument? document;
    try {
      document = PdfDocument(inputBytes: pdfBytes);
      
      if (pageIndex < 0 || pageIndex >= document.pages.count) {
        LogUtils.debug('PDF页面索引无效: $pageIndex, 总页数: ${document.pages.count}');
        return '';
      }

      // Syncfusion的PdfTextExtractor不支持单页提取
      // 我们使用一个更简单的方法：提取全部文本，然后根据页面数量估算
      // 注意：这是一个近似方法，对于精确的单页提取，可能需要其他库
      final extractor = PdfTextExtractor(document);
      final allText = extractor.extractText();
      
      // 如果只有一页，直接返回
      if (document.pages.count == 1) {
        return allText.trim();
      }
      
      // 多页情况：这是一个简化实现
      // 实际应用中，可能需要使用其他库或方法来精确提取单页文本
      // 当前实现返回全部文本（作为降级方案）
      return allText.trim();
    } catch (e) {
      LogUtils.error('提取PDF页面文本失败: $e');
      return '';
    } finally {
      document?.dispose();
    }
  }

  /// 从PDF文档提取指定页面的文本（使用页面对象）
  /// 注意：Syncfusion的API限制，这是一个简化实现
  static String _extractTextFromPage(PdfDocument document, int pageIndex) {
    try {
      // 使用PdfTextExtractor提取全部文本
      // 由于Syncfusion不支持精确的单页提取，这里返回全部文本
      final extractor = PdfTextExtractor(document);
      final allText = extractor.extractText();
      return allText.trim();
    } catch (e) {
      LogUtils.error('从PDF页面提取文本失败: $e');
      return '';
    }
  }

  /// 从文件路径提取PDF页面文本
  static Future<String> extractPageTextFromFile(
    String filePath,
    int pageIndex,
  ) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        LogUtils.debug('PDF文件不存在: $filePath');
        return '';
      }

      final bytes = await file.readAsBytes();
      return await extractPageText(bytes, pageIndex);
    } catch (e) {
      LogUtils.error('从文件提取PDF文本失败: $e');
      return '';
    }
  }

  /// 提取PDF所有页面的文本
  static Future<Map<int, String>> extractAllPagesText(
    Uint8List pdfBytes,
  ) async {
    final result = <int, String>{};
    try {
      final document = PdfDocument(inputBytes: pdfBytes);
      try {
        final pageCount = document.pages.count;
        
        // 逐页提取文本
        for (int i = 0; i < pageCount; i++) {
          final text = _extractTextFromPage(document, i);
          if (text.isNotEmpty) {
            result[i] = text;
          }
        }
      } finally {
        document.dispose();
      }
    } catch (e) {
      LogUtils.error('提取PDF所有页面文本失败: $e');
    }
    return result;
  }

  /// 从文件路径提取PDF所有页面的文本
  static Future<Map<int, String>> extractAllPagesTextFromFile(
    String filePath,
  ) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        LogUtils.debug('PDF文件不存在: $filePath');
        return {};
      }

      final bytes = await file.readAsBytes();
      return await extractAllPagesText(bytes);
    } catch (e) {
      LogUtils.error('从文件提取PDF所有页面文本失败: $e');
      return {};
    }
  }

  /// 检查PDF页面是否包含可提取的文本
  static Future<bool> hasText(Uint8List pdfBytes, int pageIndex) async {
    final text = await extractPageText(pdfBytes, pageIndex);
    return text.trim().isNotEmpty;
  }

  /// 从文件路径检查PDF页面是否包含可提取的文本
  static Future<bool> hasTextFromFile(String filePath, int pageIndex) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return false;
      }
      final bytes = await file.readAsBytes();
      return await hasText(bytes, pageIndex);
    } catch (e) {
      LogUtils.error('检查PDF文本失败: $e');
      return false;
    }
  }

  /// 从PDF页面按矩形区域提取文本
  /// [pdfBytes] PDF文件的字节数据
  /// [pageIndex] 页面索引（从0开始）
  /// [selectionRect] 选择区域（相对于PDF页面的坐标，单位：点）
  /// [pageSize] PDF页面的实际尺寸（单位：点）
  /// [canvasRect] 选择区域在画布上的坐标
  /// [pdfRect] PDF在画布上的显示区域
  /// 返回提取的文本，如果提取失败则返回空字符串
  static Future<String> extractTextFromRegion({
    required Uint8List pdfBytes,
    required int pageIndex,
    required Rect canvasRect,
    required Rect pdfRect,
    required Size pageSize,
  }) async {
    // 将画布坐标转换为PDF页面坐标
    final pdfSelectionRect = _canvasToPdfCoordinates(
      canvasRect: canvasRect,
      pdfRect: pdfRect,
      pageSize: pageSize,
    );

    LogUtils.debug('🦋[PDF文本提取] 选择区域: canvasRect=$canvasRect, pdfRect=$pdfRect, pageSize=$pageSize');
    LogUtils.debug('🦋[PDF文本提取] PDF页面坐标选择区域: $pdfSelectionRect (left=${pdfSelectionRect.left}, top=${pdfSelectionRect.top}, width=${pdfSelectionRect.width}, height=${pdfSelectionRect.height})');

    // ✅ 使用Syncfusion提取文本，然后尝试按区域筛选
    PdfDocument? document;
    try {
      document = PdfDocument(inputBytes: pdfBytes);
      
      if (pageIndex < 0 || pageIndex >= document.pages.count) {
        LogUtils.debug('PDF页面索引无效: $pageIndex, 总页数: ${document.pages.count}');
        return '';
      }

      final extractor = PdfTextExtractor(document);
      final allText = extractor.extractText();
      
      // ✅ 如果文本为空，直接返回
      if (allText.trim().isEmpty) {
        LogUtils.debug('🦋[PDF文本提取] 提取的文本为空');
        return '';
      }
      
      // ✅ 如果只有一页，尝试按区域筛选文本
      if (document.pages.count == 1) {
        return _filterTextByRegion(allText, pdfSelectionRect, pageSize);
      }

      // ✅ 多页情况：Syncfusion不支持单页提取，我们需要估算当前页面的文本
      // 这是一个简化的方法：假设每页文本量大致相等，提取对应页面的文本
      final lines = allText.split('\n');
      
      // ✅ 如果没有文本行，返回空
      if (lines.isEmpty) {
        LogUtils.debug('🦋[PDF文本提取] 多页PDF，没有文本行');
        return '';
      }
      
      final estimatedLinesPerPage = (lines.length / document.pages.count).ceil();
      final startLine = (pageIndex * estimatedLinesPerPage).clamp(0, lines.length);
      final endLine = (startLine + estimatedLinesPerPage).clamp(0, lines.length);
      
      // ✅ 如果起止行相同，返回空
      if (startLine >= endLine) {
        LogUtils.debug('🦋[PDF文本提取] 多页PDF，当前页面没有文本');
        return '';
      }
      
      final pageText = lines.sublist(startLine, endLine).join('\n');
      
      LogUtils.debug('🦋[PDF文本提取] 多页PDF，估算当前页面文本: ${endLine - startLine}行');
      
      // ✅ 对当前页面的文本按区域筛选
      return _filterTextByRegion(pageText, pdfSelectionRect, pageSize);
      
    } catch (e) {
      LogUtils.error('按区域提取PDF文本失败: $e');
      return '';
    } finally {
      document?.dispose();
    }
  }

  /// 根据选择区域筛选文本（启发式方法）
  /// 由于Syncfusion不提供文本位置信息，我们使用一个简化的方法：
  /// 根据选择区域的Y坐标范围，估算应该包含哪些文本行
  static String _filterTextByRegion(String text, Rect selectionRect, Size pageSize) {
    if (text.trim().isEmpty) {
      return '';
    }

    // ✅ 如果选择区域覆盖了整个页面的大部分区域，返回全部文本
    final selectionAreaRatio = (selectionRect.width * selectionRect.height) / (pageSize.width * pageSize.height);
    
    if (selectionAreaRatio > 0.8) {
      LogUtils.debug('🦋[PDF文本提取] 选择区域覆盖了${(selectionAreaRatio * 100).toStringAsFixed(1)}%的页面，返回全部文本');
      return _sanitizeTextForClipboard(text);
    }

    // ✅ 按Y坐标筛选文本行
    final lines = text.split('\n');
    final selectedLines = <String>[];
    
    // 计算选择区域在页面中的相对位置（0.0到1.0）
    final selectionTopRatio = selectionRect.top / pageSize.height;
    final selectionBottomRatio = (selectionRect.top + selectionRect.height) / pageSize.height;
    
    // 假设文本行均匀分布在页面上
    for (int i = 0; i < lines.length; i++) {
      final lineTopRatio = i / lines.length;
      final lineBottomRatio = (i + 1) / lines.length;
      
      // 如果文本行与选择区域有重叠，则包含该行
      if (lineBottomRatio >= selectionTopRatio && lineTopRatio <= selectionBottomRatio) {
        selectedLines.add(lines[i]);
      }
    }
    
    final selectedText = selectedLines.join('\n');
    
    if (selectedText.trim().isEmpty) {
      // 如果按行筛选没有结果，返回全部文本（降级方案）
      LogUtils.debug('🦋[PDF文本提取] 按行筛选没有结果，返回全部文本');
      return _sanitizeTextForClipboard(text);
    }
    
    LogUtils.debug('🦋[PDF文本提取] 按区域筛选结果: ${selectedLines.length}行，${selectedText.length}个字符');
    return _sanitizeTextForClipboard(selectedText);
  }

  /// ✅ 清理文本，确保可以安全粘贴到 Quill 编辑器
  /// 主要解决：Quill 编辑器在处理特殊字符时可能触发断言错误
  static String _sanitizeTextForClipboard(String text) {
    if (text.isEmpty) {
      return '';
    }

    // ✅ 统一换行符为 \n
    String sanitized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    
    // ✅ 移除 NULL 字符和其他控制字符（保留换行符和制表符）
    sanitized = sanitized.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
    
    // ✅ 移除零宽字符（这些字符可能导致 Quill 解析问题）
    sanitized = sanitized.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF\u2060]'), '');
    
    // ✅ 移除首尾空白字符
    sanitized = sanitized.trim();
    
    // ✅ 如果文本为空，返回空字符串
    if (sanitized.isEmpty) {
      return '';
    }
    
    return sanitized;
  }

  /// 从文件路径按矩形区域提取文本
  static Future<String> extractTextFromRegionFromFile({
    required String filePath,
    required int pageIndex,
    required Rect canvasRect,
    required Rect pdfRect,
    required Size pageSize,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        LogUtils.debug('PDF文件不存在: $filePath');
        return '';
      }

      final bytes = await file.readAsBytes();
      return await extractTextFromRegion(
        pdfBytes: bytes,
        pageIndex: pageIndex,
        canvasRect: canvasRect,
        pdfRect: pdfRect,
        pageSize: pageSize,
      );
    } catch (e) {
      LogUtils.error('从文件按区域提取PDF文本失败: $e');
      return '';
    }
  }

  /// 将画布坐标转换为PDF页面坐标
  static Rect _canvasToPdfCoordinates({
    required Rect canvasRect,
    required Rect pdfRect,
    required Size pageSize,
  }) {
    // 计算PDF在画布上的缩放比例
    final scaleX = pageSize.width / pdfRect.width;
    final scaleY = pageSize.height / pdfRect.height;

    // 计算选择区域相对于PDF显示区域的偏移
    final relativeLeft = canvasRect.left - pdfRect.left;
    final relativeTop = canvasRect.top - pdfRect.top;
    final relativeWidth = canvasRect.width;
    final relativeHeight = canvasRect.height;

    // 转换为PDF页面坐标
    final pdfLeft = relativeLeft * scaleX;
    final pdfTop = relativeTop * scaleY;
    final pdfWidth = relativeWidth * scaleX;
    final pdfHeight = relativeHeight * scaleY;

    return Rect.fromLTWH(
      pdfLeft.clamp(0.0, pageSize.width),
      pdfTop.clamp(0.0, pageSize.height),
      pdfWidth.clamp(0.0, pageSize.width - pdfLeft),
      pdfHeight.clamp(0.0, pageSize.height - pdfTop),
    );
  }
}

