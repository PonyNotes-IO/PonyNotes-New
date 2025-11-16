import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:appflowy_backend/log.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'file_upload_service.dart';

/// Cancellation token for cancelling async operations
class CancellationToken {
  bool _cancelled = false;
  
  bool get isCancelled => _cancelled;
  
  void cancel() {
    _cancelled = true;
  }
  
  void reset() {
    _cancelled = false;
  }
}

/// MinerU API-based PDF processor for professional, advanced, OCR, and complex layout handling
class MinerUApiProcessor {
  static const String apiBaseUrl = 'https://mineru.net/api/v4';
  static const String extractEndpoint = '/extract/task';
  static const String apiToken = "eyJ0eXBlIjoiSldUIiwiYWxnIjoiSFM1MTIifQ.eyJqdGkiOiIyMTcwMDU0OCIsInJvbCI6IlJPTEVfUkVHSVNURVIiLCJpc3MiOiJPcGVuWExhYiIsImlhdCI6MTc2MzIxNjI1MCwiY2xpZW50SWQiOiJsa3pkeDU3bnZ5MjJqa3BxOXgydyIsInBob25lIjoiMTc3MTAwNTQ3OTYiLCJvcGVuSWQiOm51bGwsInV1aWQiOiI0NmQ5MjU4MS03ZTRlLTQ0MzUtYjA1Mi0zMDQ2YjY4MWU2ZjYiLCJlbWFpbCI6IiIsImV4cCI6MTc2NDQyNTg1MH0.Z48DoJXOTuwrKpJIxepE4-Y5Gl7QEiDLKxFjoFnK4sM2xThk0UAWR2GDgCd0CWCQCjv7fzpvlZj_p_DZo1jZsA";
  
  /// Process PDF using MinerU API with different modes
  /// Returns a Future that can be cancelled via the returned CancellationToken
  static Future<String> processPdfBytes(
    Uint8List pdfBytes, {
    MinerUMode mode = MinerUMode.professional,
    String? language,
    bool enableOcr = true,
    bool enableTable = false,
    bool enableFormula = false,
    CancellationToken? cancellationToken,
  }) async {
    try {
      Log.info('Starting MinerU API processing with mode: ${mode.name}');
      
      // 检查是否已取消
      if (cancellationToken?.isCancelled ?? false) {
        throw Exception('任务已取消');
      }
      
      // 上传PDF文件到临时服务器或使用文件URL
      final fileUrl = await _uploadPdfFile(pdfBytes, cancellationToken: cancellationToken);
      
      // 检查是否已取消
      if (cancellationToken?.isCancelled ?? false) {
        throw Exception('任务已取消');
      }
      
      // 调用MinerU API
      final result = await _callMinerUApi(
        fileUrl: fileUrl,
        mode: mode,
        language: language,
        enableOcr: enableOcr,
        enableTable: enableTable,
        enableFormula: enableFormula,
        cancellationToken: cancellationToken,
      );
      
      Log.info('MinerU API processing completed successfully');
      return result;
      
    } catch (e) {
      if (e.toString().contains('已取消')) {
        rethrow;
      }
      Log.error('MinerU API processing failed: $e');
      throw Exception('MinerU API处理失败: $e');
    }
  }
  
  /// Process PDF file with MinerU API
  static Future<String> processPdfFile(
    File pdfFile, {
    MinerUMode mode = MinerUMode.professional,
    String? language,
    bool enableOcr = true,
    bool enableTable = false,
    bool enableFormula = false,
    CancellationToken? cancellationToken,
  }) async {
    final bytes = await pdfFile.readAsBytes();
    return processPdfBytes(
      bytes,
      mode: mode,
      language: language,
      enableOcr: enableOcr,
      enableTable: enableTable,
      enableFormula: enableFormula,
      cancellationToken: cancellationToken,
    );
  }
  
  /// Upload PDF file and get URL
  static Future<String> _uploadPdfFile(
    Uint8List pdfBytes, {
    CancellationToken? cancellationToken,
  }) async {
    try {
      // 检查是否已取消
      if (cancellationToken?.isCancelled ?? false) {
        throw Exception('任务已取消');
      }
      
      // 检查文件大小
      if (!FileUploadService.isFileSizeValid(pdfBytes.length)) {
        throw Exception('文件大小超过限制 (${FileUploadService.getFileSizeString(pdfBytes.length)})');
      }
      
      // 上传文件到临时服务
      final fileName = 'document_${DateTime.now().millisecondsSinceEpoch}.pdf';
      
      // 检查是否已取消
      if (cancellationToken?.isCancelled ?? false) {
        throw Exception('任务已取消');
      }
      
      final fileUrl = await FileUploadService.uploadFile(pdfBytes, fileName);
      
      // 检查是否已取消
      if (cancellationToken?.isCancelled ?? false) {
        throw Exception('任务已取消');
      }
      
      Log.info('PDF file uploaded successfully: $fileUrl');
      return fileUrl;
      
    } catch (e) {
      Log.error('Failed to upload PDF file: $e');
      // 透传常见上传错误并给出可操作建议
      final message = e.toString();
      if (message.contains('未授权') || message.contains('401')) {
        throw Exception('PDF文件上传失败: 未授权，请登录 AppFlowy Cloud 后重试');
      }
      if (message.contains('权限不足') || message.contains('403')) {
        throw Exception('PDF文件上传失败: 403 权限不足，请确认 token 有效并检查反向代理是否透传 Authorization');
      }
      if (message.contains('过大') || message.contains('413')) {
        throw Exception('PDF文件上传失败: 文件过大或反向代理限制，请减小文件或调高 client_max_body_size');
      }
      throw Exception('PDF文件上传失败: $e');
    }
  }
  
  /// Call MinerU API
  static Future<String> _callMinerUApi({
    required String fileUrl,
    required MinerUMode mode,
    String? language,
    required bool enableOcr,
    required bool enableTable,
    required bool enableFormula,
    CancellationToken? cancellationToken,
  }) async {
    final url = Uri.parse('$apiBaseUrl$extractEndpoint');
    
    // 构建请求头（包含API Token）
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${apiToken}',
    };
    
    // 构建请求数据
    final data = {
      'url': fileUrl,
      'is_ocr': enableOcr,
      'enable_formula': enableFormula,
      'enable_table': enableTable,
      'mode': _getModeString(mode),
      "model_version": "vlm",
      if (language != null) 'language': language,
    };
    
    Log.info('Calling MinerU API: $url');
    Log.info('Request data: $data');
    
    // 检查是否已取消
    if (cancellationToken?.isCancelled ?? false) {
      throw Exception('任务已取消');
    }
    
    try {
      // 发送请求
      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(data),
      );
      
      // 检查是否已取消
      if (cancellationToken?.isCancelled ?? false) {
        throw Exception('任务已取消');
      }
      
      Log.info('MinerU API response status: ${response.statusCode}');
      Log.info('MinerU API response body: ${response.body}');
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        Log.info('MinerU API response data: $responseData');
        
        // 尝试多种可能的响应格式
        final taskId = responseData['data']?['task_id'] ?? responseData['id'];
        
        if (taskId != null) {
          Log.info('Task ID extracted: $taskId');
          return await _waitForTaskCompletion(
            taskId,
            apiToken,
            cancellationToken: cancellationToken,
          );
        } else {
          Log.error('API响应中未找到任务ID，完整响应: $responseData');
          throw Exception('API响应中未找到任务ID');
        }
      } else if (response.statusCode == 404) {
        Log.error('MinerU API 404错误: ${response.body}');
        throw Exception('API端点不存在(404)，请检查API版本和端点路径是否正确');
      } else {
        Log.error('MinerU API error: ${response.statusCode} - ${response.body}');
        throw Exception('API请求失败: ${response.statusCode} - ${response.body}');
      }
      
    } catch (e) {
      Log.error('Failed to call MinerU API: $e');
      if (e.toString().contains('404')) {
        throw Exception('API端点不存在(404)，请检查MinerU API文档确认正确的端点路径');
      }
      throw Exception('调用MinerU API失败: $e');
    }
  }
  
  /// Get mode string for API
  static String _getModeString(MinerUMode mode) {
    switch (mode) {
      case MinerUMode.professional:
        return 'professional';
      case MinerUMode.advanced:
        return 'advanced';
      case MinerUMode.ocr:
        return 'ocr';
      case MinerUMode.complexLayout:
        return 'complex_layout';
    }
  }
  
  /// Wait for task completion and get result
  /// Uses GET /extract/task/{task_id} to check status and get result
  static Future<String> _waitForTaskCompletion(
    String taskId,
    String apiToken, {
    CancellationToken? cancellationToken,
  }) async {
    const maxAttempts = 60; // 最多等待10分钟（60次 * 10秒）
    const delaySeconds = 10;
    
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      // 检查是否已取消
      if (cancellationToken?.isCancelled ?? false) {
        throw Exception('任务已取消');
      }
      
      try {
        // 使用 GET /extract/task/{task_id} 获取任务状态和结果
        final url = Uri.parse('$apiBaseUrl$extractEndpoint/$taskId');
        final headers = <String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${apiToken}',
        };
        
        Log.info('Checking task status and result: $url (attempt ${attempt + 1}/$maxAttempts)');
        final response = await http.get(url, headers: headers);
        
        // 检查是否已取消
        if (cancellationToken?.isCancelled ?? false) {
          throw Exception('任务已取消');
        }
        
        if (response.statusCode == 200) {
          final responseData = jsonDecode(response.body);
          Log.info('Task response: $responseData');
          
          final code = responseData['code'];
          final data = responseData['data'];
          
          if (code != 0 || data == null) {
            final errMsg = data?['err_msg'] ?? responseData['msg'] ?? '未知错误';
            Log.error('任务返回错误: code=$code, err_msg=$errMsg');
            throw Exception('任务处理失败: $errMsg');
          }
          
          final state = data['state'] as String?;
          if (state == null) {
            Log.error('响应中未找到state字段: $responseData');
            throw Exception('响应格式错误：未找到state字段');
          }
          
          Log.info('Task $taskId state: $state');
          
          // 如果状态为 done，提取 full_zip_url 并处理
          if (state == 'done') {
            final fullZipUrl = data['full_zip_url'] as String?;
            if (fullZipUrl == null || fullZipUrl.isEmpty) {
              Log.error('任务完成但未找到full_zip_url: $data');
              throw Exception('任务完成但未找到结果文件URL');
            }
            
            Log.info('Task completed, downloading ZIP from: $fullZipUrl');
            
            // 下载并处理ZIP文件
            return await _downloadAndExtractZip(
              fullZipUrl,
              cancellationToken: cancellationToken,
            );
          } else if (state == 'running' || state == 'processing' || state == 'pending' || state == 'queued') {
            // 显示进度信息
            final progress = data['extract_progress'];
            if (progress != null) {
              final extractedPages = progress['extracted_pages'] ?? 0;
              final totalPages = progress['total_pages'] ?? 0;
              if (totalPages > 0) {
                Log.info('Extraction progress: $extractedPages/$totalPages pages');
              }
            }
            
          // 继续等待
            await Future.delayed(const Duration(seconds: delaySeconds));
            continue;
          } else if (state == 'failed') {
            final errMsg = data['err_msg'] ?? '任务处理失败';
            Log.error('任务处理失败: $errMsg');
            throw Exception('任务处理失败: $errMsg');
          } else {
            Log.warn('未知任务状态: $state，继续等待');
            await Future.delayed(const Duration(seconds: delaySeconds));
            continue;
          }
        } else if (response.statusCode == 404) {
          Log.error('获取任务信息404错误: ${response.body}');
          throw Exception('任务不存在(404)');
        } else {
          Log.error('获取任务信息错误: ${response.statusCode} - ${response.body}');
          // 对于非404错误，继续重试
          await Future.delayed(const Duration(seconds: delaySeconds));
          continue;
        }
      } catch (e) {
        Log.error('Error checking task status (attempt $attempt): $e');
        
        // 如果是最后一次尝试，抛出异常
        if (attempt == maxAttempts - 1) {
          throw Exception('任务超时或失败: $e');
        }
        
        // 对于网络错误，等待后重试
        if (e.toString().contains('网络') || e.toString().contains('timeout') || e.toString().contains('SocketException')) {
          await Future.delayed(const Duration(seconds: delaySeconds));
          continue;
        }
        
        // 如果错误信息表明任务已失败或取消，直接抛出
        if (e.toString().contains('任务处理失败') || e.toString().contains('任务已取消')) {
          rethrow;
        }
        
        // 其他错误，等待后重试
        await Future.delayed(const Duration(seconds: delaySeconds));
      }
    }
    
    // 如果循环结束仍未获取到结果
    throw Exception('任务处理超时');
  }
  
  /// Download ZIP file from URL and extract content
  static Future<String> _downloadAndExtractZip(
    String zipUrl, {
    CancellationToken? cancellationToken,
  }) async {
    try {
      Log.info('Downloading ZIP file from: $zipUrl');
      
      // 检查是否已取消
      if (cancellationToken?.isCancelled ?? false) {
        throw Exception('任务已取消');
      }
      
      // 下载ZIP文件
      final zipResponse = await http.get(Uri.parse(zipUrl));
      
      // 检查是否已取消
      if (cancellationToken?.isCancelled ?? false) {
        throw Exception('任务已取消');
      }
      
      if (zipResponse.statusCode != 200) {
        throw Exception('下载ZIP文件失败: ${zipResponse.statusCode}');
      }
      
      Log.info('ZIP file downloaded, size: ${zipResponse.bodyBytes.length} bytes');
      
      // 解压ZIP文件
      final archive = ZipDecoder().decodeBytes(zipResponse.bodyBytes);
      
      // 查找 full.md 文件（必须存在）
      ArchiveFile? fullMdFile;
      
      for (final file in archive) {
        final fileName = file.name.toLowerCase();
        // 精确匹配 full.md（忽略路径）
        if (file.isFile && (fileName == 'full.md' || fileName.endsWith('/full.md'))) {
          fullMdFile = file;
          Log.info('Found full.md in ZIP: ${file.name}');
          break;
        }
      }
      
      // 如果未找到 full.md，抛出明确的错误提示
      if (fullMdFile == null) {
        Log.error('full.md not found in ZIP file');
        // 列出ZIP中的所有文件，便于调试
        final fileList = archive.where((f) => f.isFile).map((f) => f.name).toList();
        Log.error('Files in ZIP: $fileList');
        throw Exception('解析失败，请重新提交解析');
      }
      
      // 读取 full.md 文件内容并转换为 Markdown 格式字符串
      final bytes = fullMdFile.content as List<int>;
      
      // 尝试使用 UTF-8 解码
      String markdownContent;
      try {
        markdownContent = utf8.decode(bytes, allowMalformed: false);
      } catch (e) {
        // 如果 UTF-8 解码失败，尝试允许错误的字符（但仍然尝试UTF-8）
        Log.warn('UTF-8 decode failed, trying with allowMalformed: $e');
        markdownContent = utf8.decode(bytes, allowMalformed: true);
      }
      
      // 验证内容不为空
      if (markdownContent.trim().isEmpty) {
        Log.error('full.md file is empty');
        throw Exception('解析失败：full.md 文件为空，请重新提交解析');
      }
      
      // 转换 HTML 表格为 Markdown 表格格式
      markdownContent = _convertHtmlTablesToMarkdown(markdownContent);
      
      Log.info('Extracted full.md content length: ${markdownContent.length} characters');
      Log.debug('Markdown content preview: ${markdownContent.substring(0, markdownContent.length > 200 ? 200 : markdownContent.length)}...');
      
      // 返回 Markdown 格式的字符串
      return markdownContent;
      
    } catch (e) {
      Log.error('Failed to download and extract ZIP: $e');
      if (e.toString().contains('已取消')) {
        rethrow;
      }
      // 如果错误信息已经包含"解析失败"，直接抛出
      if (e.toString().contains('解析失败')) {
        rethrow;
      }
      throw Exception('下载或解压ZIP文件失败: $e');
    }
  }
  
  /// Convert HTML tables to Markdown table format
  static String _convertHtmlTablesToMarkdown(String markdownContent) {
    try {
      // 匹配 HTML 表格标签（支持多行）
      final tableRegex = RegExp(
        r'<table[^>]*>(.*?)</table>',
        dotAll: true,
        caseSensitive: false,
      );
      
      if (!tableRegex.hasMatch(markdownContent)) {
        // 没有 HTML 表格，直接返回原内容
        return markdownContent;
      }
      
      Log.info('Found HTML tables in markdown, converting to Markdown format...');
      
      // 替换所有 HTML 表格为 Markdown 表格
      return markdownContent.replaceAllMapped(tableRegex, (match) {
        final tableHtml = match.group(1) ?? '';
        return _parseHtmlTableToMarkdown(tableHtml);
      });
    } catch (e) {
      Log.warn('Failed to convert HTML tables to Markdown: $e, returning original content');
      return markdownContent;
    }
  }
  
  /// Parse HTML table content and convert to Markdown table format
  static String _parseHtmlTableToMarkdown(String tableHtml) {
    try {
      final StringBuffer markdownTable = StringBuffer();
      markdownTable.writeln(); // 添加前导空行
      
      // 匹配所有表格行（tr标签）
      final trRegex = RegExp(
        r'<tr[^>]*>(.*?)</tr>',
        dotAll: true,
        caseSensitive: false,
      );
      
      final rows = <List<String>>[];
      bool hasHeader = false;
      
      trRegex.allMatches(tableHtml).forEach((match) {
        final trContent = match.group(1) ?? '';
        final cells = <String>[];
        bool isHeaderRow = false;
        
        // 匹配表格单元格（td或th标签）
        final cellRegex = RegExp(
          r'<(td|th)[^>]*>(.*?)</(td|th)>',
          dotAll: true,
          caseSensitive: false,
        );
        
        cellRegex.allMatches(trContent).forEach((cellMatch) {
          final cellTag = cellMatch.group(1)?.toLowerCase() ?? '';
          final cellContent = cellMatch.group(2) ?? '';
          
          if (cellTag == 'th') {
            isHeaderRow = true;
          }
          
          // 提取单元格文本内容，移除内部HTML标签
          String cellText = _extractTextFromHtml(cellContent);
          // 转义 Markdown 表格中的管道符
          cellText = cellText.replaceAll('|', '\\|');
          // 清理空白字符
          cellText = cellText.trim();
          
          cells.add(cellText);
        });
        
        if (cells.isNotEmpty) {
          rows.add(cells);
          if (isHeaderRow && !hasHeader) {
            hasHeader = true;
          }
        }
      });
      
      if (rows.isEmpty) {
        return ''; // 空表格，返回空字符串
      }
      
      // 确定最大列数
      int maxColumns = 0;
      for (final row in rows) {
        if (row.length > maxColumns) {
          maxColumns = row.length;
        }
      }
      
      // 构建 Markdown 表格
      bool headerSeparatorAdded = false;
      for (int i = 0; i < rows.length; i++) {
        final row = rows[i];
        
        // 构建行内容，确保所有行都有相同的列数
        final cells = <String>[];
        for (int j = 0; j < maxColumns; j++) {
          if (j < row.length) {
            cells.add(row[j]);
          } else {
            cells.add(''); // 填充空单元格
          }
        }
        
        // 写入表格行
        markdownTable.writeln('| ${cells.join(' | ')} |');
        
        // 在第一行或第一个表头行后添加分隔符
        if (!headerSeparatorAdded) {
          final separator = '| ${List.generate(maxColumns, (_) => '---').join(' | ')} |';
          markdownTable.writeln(separator);
          headerSeparatorAdded = true;
        }
      }
      
      markdownTable.writeln(); // 添加尾随空行
      
      return markdownTable.toString();
    } catch (e) {
      Log.warn('Failed to parse HTML table: $e');
      return ''; // 解析失败，返回空字符串
    }
  }
  
  /// Extract plain text from HTML content, removing HTML tags
  static String _extractTextFromHtml(String html) {
    try {
      // 移除所有HTML标签
      String text = html.replaceAll(RegExp(r'<[^>]+>'), '');
      // 解码HTML实体
      text = text
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&amp;', '&')
          .replaceAll('&quot;', '"')
          .replaceAll('&#39;', "'")
          .replaceAll('&apos;', "'");
      // 清理多余空白字符
      text = text.replaceAll(RegExp(r'\s+'), ' ');
      return text.trim();
    } catch (e) {
      // 如果解析失败，尝试直接移除标签
      return html.replaceAll(RegExp(r'<[^>]+>'), '').trim();
    }
  }
  
  /// Check if API is available
  static Future<bool> isApiAvailable() async {
    try {
      final url = Uri.parse('$apiBaseUrl/health');
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${apiToken}',
      };
      
      final response = await http.get(url, headers: headers);
      return response.statusCode == 200;
    } catch (e) {
      Log.error('API availability check failed: $e');
      return false;
    }
  }
  
  /// Get supported languages
  static List<String> getSupportedLanguages() {
    return [
      'zh', 'en', 'ja', 'ko', 'es', 'fr', 'de', 'it', 'pt', 'ru',
      'ar', 'hi', 'th', 'vi', 'id', 'ms', 'tl', 'tr', 'pl', 'nl'
    ];
  }
  
  /// Get processing modes
  static List<MinerUMode> getProcessingModes() {
    return MinerUMode.values;
  }
}

/// MinerU processing modes
enum MinerUMode {
  professional('专业模式', '智能识别文档结构，保持格式和层次'),
  advanced('高级模式', '深度分析内容，优化表格和列表'),
  ocr('OCR模式', '图像文字识别，适用于扫描文档'),
  complexLayout('复杂布局模式', '处理复杂排版，旋转表格，跨页内容');

  const MinerUMode(this.displayName, this.description);

  final String displayName;
  final String description;
}

/// MinerU API processing result
class MinerUApiResult {
  final bool success;
  final String processorName;
  final int processingTime;
  final String extractedText;
  final MinerUMode mode;
  final Map<String, dynamic>? metadata;
  final String? errorMessage;
  
  MinerUApiResult({
    required this.success,
    required this.processorName,
    required this.processingTime,
    required this.extractedText,
    required this.mode,
    this.metadata,
    this.errorMessage,
  });
  
  /// Get quality score based on content
  double get qualityScore {
    if (!success || extractedText.isEmpty) return 0.0;
    
    double score = 0.0;
    
    // 基础可读性 (40分)
    final readableChars = extractedText.codeUnits.where((c) => 
      (c >= 32 && c <= 126) || 
      (c >= 0x4e00 && c <= 0x9fff) ||
      c == 9 || c == 10 || c == 13
    ).length;
    score += (readableChars / extractedText.length) * 40;
    
    // 内容丰富度 (30分)
    final words = extractedText.split(RegExp(r'\s+')).where((w) => w.length > 2).length;
    score += (words / 100.0).clamp(0.0, 1.0) * 30;
    
    // 结构完整性 (20分)
    final sentences = extractedText.split(RegExp(r'[.!?。！？]')).where((s) => s.trim().length > 10).length;
    score += (sentences / 20.0).clamp(0.0, 1.0) * 20;
    
    // 多语言支持 (10分)
    final hasEnglish = RegExp(r'[a-zA-Z]').hasMatch(extractedText);
    final hasChinese = RegExp(r'[\u4e00-\u9fff]').hasMatch(extractedText);
    final hasNumbers = RegExp(r'\d').hasMatch(extractedText);
    
    if (hasEnglish) score += 3;
    if (hasChinese) score += 4;
    if (hasNumbers) score += 3;
    
    return score.clamp(0.0, 100.0);
  }
  
  /// Get quality description
  String get qualityDescription {
    if (qualityScore >= 90) return '优秀';
    if (qualityScore >= 75) return '良好';
    if (qualityScore >= 60) return '中等';
    if (qualityScore >= 40) return '较差';
    return '很差';
  }
}

