import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:appflowy_backend/log.dart';
import 'package:http/http.dart' as http;
import 'file_upload_service.dart';

/// MinerU API-based PDF processor for professional, advanced, OCR, and complex layout handling
class MinerUApiProcessor {
  static const String apiBaseUrl = 'https://mineru.net/api/v4';
  static const String extractEndpoint = '/extract/task';
  static const String statusEndpoint = '/extract/status';
  static const String resultEndpoint = '/extract/result';
  static const String apiToken = "eyJ0eXBlIjoiSldUIiwiYWxnIjoiSFM1MTIifQ.eyJqdGkiOiIyMTcwMDU0OCIsInJvbCI6IlJPTEVfUkVHSVNURVIiLCJpc3MiOiJPcGVuWExhYiIsImlhdCI6MTc1OTk3NTY5MCwiY2xpZW50SWQiOiJsa3pkeDU3bnZ5MjJqa3BxOXgydyIsInBob25lIjoiMTc3MTAwNTQ3OTYiLCJvcGVuSWQiOm51bGwsInV1aWQiOiI2NTdmOWY5OS1iN2RiLTRiNjUtODFiMS00ZWY3NTNkMzBjNjUiLCJlbWFpbCI6IiIsImV4cCI6MTc2MTE4NTI5MH0.ZPWm5VNx2Vg_WcOEH1HCqka4f38cIsG0Y9dsirToMoOwVljlhGZoZXjKcWYEPpNlKhvSwY9wAIn-eGyktQvw-g";
  
  /// Process PDF using MinerU API with different modes
  static Future<String> processPdfBytes(
    Uint8List pdfBytes, {
    MinerUMode mode = MinerUMode.professional,
    String? language,
    bool enableOcr = true,
    bool enableTable = false,
    bool enableFormula = false,
  }) async {
    try {
      Log.info('Starting MinerU API processing with mode: ${mode.name}');
      
      // 上传PDF文件到临时服务器或使用文件URL
      final fileUrl = await _uploadPdfFile(pdfBytes);
      
      // 调用MinerU API
      final result = await _callMinerUApi(
        fileUrl: fileUrl,
        mode: mode,
        language: language,
        enableOcr: enableOcr,
        enableTable: enableTable,
        enableFormula: enableFormula,
      );
      
      Log.info('MinerU API processing completed successfully');
      return result;
      
    } catch (e) {
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
  }) async {
    final bytes = await pdfFile.readAsBytes();
    return processPdfBytes(
      bytes,
      mode: mode,
      language: language,
      enableOcr: enableOcr,
      enableTable: enableTable,
      enableFormula: enableFormula,
    );
  }
  
  /// Upload PDF file and get URL
  static Future<String> _uploadPdfFile(Uint8List pdfBytes) async {
    try {
      // 检查文件大小
      if (!FileUploadService.isFileSizeValid(pdfBytes.length)) {
        throw Exception('文件大小超过限制 (${FileUploadService.getFileSizeString(pdfBytes.length)})');
      }
      
      // 上传文件到临时服务
      final fileName = 'document_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final fileUrl = await FileUploadService.uploadFile(pdfBytes, fileName);
      
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
  }) async {
    final url = Uri.parse('$apiBaseUrl$extractEndpoint');
    
    // 构建请求头
    final headers = {
      'Content-Type': 'application/json',
    };
    
    // 构建请求数据
    final data = {
      'url': fileUrl,
      'is_ocr': enableOcr,
      'enable_formula': enableFormula,
      'enable_table': enableTable,
      'mode': _getModeString(mode),
      if (language != null) 'language': language,
    };
    
    Log.info('Calling MinerU API: $url');
    Log.info('Request data: $data');
    
    try {
      // 发送请求
      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(data),
      );
      
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        Log.info('MinerU API response: $responseData');
        
        // 检查任务状态
        final taskId = responseData['data']?['task_id'];
        if (taskId != null) {
          return await _waitForTaskCompletion(taskId, apiToken);
        } else {
          throw Exception('API响应中未找到任务ID');
        }
      } else {
        Log.error('MinerU API error: ${response.statusCode} - ${response.body}');
        throw Exception('API请求失败: ${response.statusCode}');
      }
      
    } catch (e) {
      Log.error('Failed to call MinerU API: $e');
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
  
  /// Wait for task completion
  static Future<String> _waitForTaskCompletion(String taskId, String apiToken) async {
    const maxAttempts = 30; // 最多等待5分钟
    const delaySeconds = 10;
    
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        // 检查任务状态
        final status = await _checkTaskStatus(taskId);
        
        if (status == 'completed') {
          // 获取结果
          return await _getTaskResult(taskId);
        } else if (status == 'failed') {
          throw Exception('任务处理失败');
        } else if (status == 'processing') {
          // 继续等待
          await Future.delayed(const Duration(seconds: delaySeconds));
          continue;
        } else {
          throw Exception('未知的任务状态: $status');
        }
        
      } catch (e) {
        Log.error('Error checking task status: $e');
        if (attempt == maxAttempts - 1) {
          throw Exception('任务超时或失败: $e');
        }
        await Future.delayed(const Duration(seconds: delaySeconds));
      }
    }
    
    throw Exception('任务处理超时');
  }
  
  /// Check task status
  static Future<String> _checkTaskStatus(String taskId) async {
    final url = Uri.parse('$apiBaseUrl$statusEndpoint/$taskId');
    
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    
    final response = await http.get(url, headers: headers);
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['data']?['status'] ?? 'unknown';
    } else {
      throw Exception('状态检查失败: ${response.statusCode}');
    }
  }
  
  /// Get task result
  static Future<String> _getTaskResult(String taskId) async {
    final url = Uri.parse('$apiBaseUrl$resultEndpoint/$taskId');
    
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    
    final response = await http.get(url, headers: headers);
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final result = data['data']?['result'];
      
      if (result != null) {
        return _formatApiResult(result);
      } else {
        throw Exception('未找到处理结果');
      }
    } else {
      throw Exception('获取结果失败: ${response.statusCode}');
    }
  }
  
  /// Format API result
  static String _formatApiResult(dynamic result) {
    if (result is String) {
      return result;
    } else if (result is Map<String, dynamic>) {
      // 处理结构化结果
      final buffer = StringBuffer();
      
      // 添加标题
      if (result['title'] != null) {
        buffer.writeln('# ${result['title']}');
        buffer.writeln();
      }
      
      // 处理内容
      if (result['content'] != null) {
        buffer.writeln(result['content']);
      }
      
      // 处理表格
      if (result['tables'] is List) {
        for (final table in result['tables']) {
          buffer.writeln(_formatTable(table));
          buffer.writeln();
        }
      }
      
      // 处理图像
      if (result['images'] is List) {
        for (final image in result['images']) {
          buffer.writeln('![Image](${image['url'] ?? ''})');
        }
      }
      
      return buffer.toString();
    }
    
    return result.toString();
  }
  
  /// Format table content
  static String _formatTable(dynamic table) {
    if (table is! Map || table['rows'] is! List) {
      return '';
    }
    
    final buffer = StringBuffer();
    final rows = table['rows'] as List;
    
    if (rows.isEmpty) return '';
    
    // 表头
    final header = rows.first;
    if (header is List) {
      buffer.writeln('| ${header.join(' | ')} |');
      buffer.writeln('| ${header.map((_) => '---').join(' | ')} |');
    }
    
    // 数据行
    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row is List) {
        buffer.writeln('| ${row.join(' | ')} |');
      }
    }
    
    return buffer.toString();
  }
  
  /// Check if API is available
  static Future<bool> isApiAvailable() async {
    try {
      final url = Uri.parse('$apiBaseUrl/health');
      final headers = <String, String>{
        'Content-Type': 'application/json',
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
