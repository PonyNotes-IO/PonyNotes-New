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
/// 
/// ✅ 重要改进：使用 extractTextLines 获取精确的文本行位置信息
/// 这样可以准确地判断哪些文本行在用户选择的区域内
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

      // ✅ 使用 extractTextLines 提取指定页面的文本
      final extractor = PdfTextExtractor(document);
      final textLines = extractor.extractTextLines(
        startPageIndex: pageIndex,
        endPageIndex: pageIndex,
      );
      
      if (textLines.isEmpty) {
        return '';
      }
      
      // 合并所有文本行
      final texts = textLines.map((line) => line.text).toList();
      return texts.join('\n').trim();
    } catch (e) {
      LogUtils.error('提取PDF页面文本失败: $e');
      return '';
    } finally {
      document?.dispose();
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
        final extractor = PdfTextExtractor(document);
        
        // 逐页提取文本
        for (int i = 0; i < pageCount; i++) {
          final textLines = extractor.extractTextLines(
            startPageIndex: i,
            endPageIndex: i,
          );
          if (textLines.isNotEmpty) {
            final texts = textLines.map((line) => line.text).toList();
            result[i] = texts.join('\n').trim();
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

  /// ✅ 从PDF页面按矩形区域提取文本（使用精确的文本行位置）
  /// 
  /// [pdfBytes] PDF文件的字节数据
  /// [pageIndex] 页面索引（从0开始）
  /// [canvasRect] 选择区域在画布上的坐标
  /// [pdfRect] PDF在画布上的显示区域
  /// [pageSize] PDF页面的原始尺寸（单位：点）
  /// 
  /// 返回提取的文本，如果提取失败则返回空字符串
  static Future<String> extractTextFromRegion({
    required Uint8List pdfBytes,
    required int pageIndex,
    required Rect canvasRect,
    required Rect pdfRect,
    required Size pageSize,
  }) async {
    PdfDocument? document;
    try {
      document = PdfDocument(inputBytes: pdfBytes);
      
      if (pageIndex < 0 || pageIndex >= document.pages.count) {
        LogUtils.debug('PDF页面索引无效: $pageIndex, 总页数: ${document.pages.count}');
        return '';
      }

      // ✅ 使用 extractTextLines 获取精确的文本行位置信息
      final extractor = PdfTextExtractor(document);
      final textLines = extractor.extractTextLines(
        startPageIndex: pageIndex,
        endPageIndex: pageIndex,
      );
      
      if (textLines.isEmpty) {
        LogUtils.debug('🦋[PDF文本提取] 页面 $pageIndex 没有文本行');
        return '';
      }

      // ✅ 将画布选择区域转换为PDF页面坐标
      final pdfSelectionRect = _canvasToPdfCoordinates(
        canvasRect: canvasRect,
        pdfRect: pdfRect,
        pageSize: pageSize,
      );

      LogUtils.debug('🦋[PDF文本提取] ========== 开始提取 ==========');
      LogUtils.debug('🦋[PDF文本提取] 画布选择区域: $canvasRect');
      LogUtils.debug('🦋[PDF文本提取] PDF显示区域: $pdfRect');
      LogUtils.debug('🦋[PDF文本提取] PDF页面尺寸: $pageSize');
      LogUtils.debug('🦋[PDF文本提取] PDF坐标选择区域: $pdfSelectionRect');
      LogUtils.debug('🦋[PDF文本提取] 总文本行数: ${textLines.length}');

      // ✅ 根据选择区域筛选文本行
      final selectedTexts = <String>[];
      
      for (int i = 0; i < textLines.length; i++) {
        final line = textLines[i];
        final lineBounds = line.bounds;
        
        // ✅ 检查文本行是否与选择区域有重叠
        // 注意：PDF坐标系是左下角为原点，Y轴向上
        // 但 Syncfusion 的 TextLine.bounds 已经转换为左上角原点
        if (_rectsOverlap(pdfSelectionRect, lineBounds)) {
          selectedTexts.add(line.text);
          LogUtils.debug('🦋[PDF文本提取] ✓ 行 $i 被选中: bounds=$lineBounds, text="${line.text.substring(0, line.text.length.clamp(0, 30))}..."');
        }
      }

      if (selectedTexts.isEmpty) {
        LogUtils.debug('🦋[PDF文本提取] 选择区域内没有文本，尝试扩大搜索范围');
        
        // ✅ 尝试扩大选择区域（增加10%的容差）
        final expandedRect = Rect.fromLTRB(
          pdfSelectionRect.left - pageSize.width * 0.05,
          pdfSelectionRect.top - pageSize.height * 0.05,
          pdfSelectionRect.right + pageSize.width * 0.05,
          pdfSelectionRect.bottom + pageSize.height * 0.05,
        );
        
        for (int i = 0; i < textLines.length; i++) {
          final line = textLines[i];
          if (_rectsOverlap(expandedRect, line.bounds)) {
            selectedTexts.add(line.text);
            LogUtils.debug('🦋[PDF文本提取] ✓ (扩大范围) 行 $i 被选中: "${line.text.substring(0, line.text.length.clamp(0, 30))}..."');
          }
        }
      }

      if (selectedTexts.isEmpty) {
        LogUtils.debug('🦋[PDF文本提取] 仍然没有找到文本，打印所有文本行位置用于调试');
        for (int i = 0; i < textLines.length && i < 10; i++) {
          final line = textLines[i];
          LogUtils.debug('🦋[PDF文本提取] 行 $i: bounds=${line.bounds}, text="${line.text.substring(0, line.text.length.clamp(0, 50))}..."');
        }
        return '';
      }

      final result = _sanitizeTextForClipboard(selectedTexts.join('\n'));
      LogUtils.debug('🦋[PDF文本提取] 提取完成: ${selectedTexts.length} 行, ${result.length} 字符');
      return result;
      
    } catch (e, stackTrace) {
      LogUtils.error('按区域提取PDF文本失败: $e');
      LogUtils.error('堆栈: $stackTrace');
      return '';
    } finally {
      document?.dispose();
    }
  }

  /// ✅ 检查两个矩形是否有重叠
  static bool _rectsOverlap(Rect rect1, Rect rect2) {
    // 如果一个矩形在另一个矩形的上方、下方、左侧或右侧，则不重叠
    if (rect1.right < rect2.left || rect2.right < rect1.left) {
      return false;
    }
    if (rect1.bottom < rect2.top || rect2.bottom < rect1.top) {
      return false;
    }
    return true;
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
    
    // ✅ 移除代理对中的孤立字符（可能导致 Quill 断言错误）
    // 这些是 UTF-16 代理对的一部分，单独出现时是无效的
    sanitized = sanitized.replaceAll(RegExp(r'[\uD800-\uDFFF]'), '');
    
    // ✅ 移除首尾空白字符
    sanitized = sanitized.trim();
    
    // ✅ 确保文本不以换行符结尾（可能导致 Quill 断言错误）
    while (sanitized.endsWith('\n')) {
      sanitized = sanitized.substring(0, sanitized.length - 1);
    }
    
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

  /// ✅ 将画布坐标转换为PDF页面坐标
  /// 
  /// 画布坐标系：左上角为原点，Y轴向下
  /// PDF坐标系：Syncfusion 的 TextLine.bounds 已经是左上角原点，Y轴向下
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
      pdfWidth.clamp(0.0, pageSize.width - pdfLeft.clamp(0.0, pageSize.width)),
      pdfHeight.clamp(0.0, pageSize.height - pdfTop.clamp(0.0, pageSize.height)),
    );
  }
}
