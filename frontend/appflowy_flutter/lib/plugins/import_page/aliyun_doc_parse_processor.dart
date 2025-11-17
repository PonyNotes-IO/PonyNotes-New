import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:appflowy_backend/log.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

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

/// 阿里云文档解析处理器
/// 使用阿里云文档解析API进行文件解析
class AliyunDocParseProcessor {
  static const String apiBaseUrl = 'https://www.xiaomabiji.com/prod-api';
  static const String parseEndpoint = '/tool/docParse/parse';
  
  // 阿里云API文件大小限制（根据nginx 413错误，设置为20MB）
  static const int maxFileSize = 50 * 1024 * 1024; // 20MB
  
  /// 处理PDF文件
  static Future<String> processPdfFile(
    File pdfFile, {
    CancellationToken? cancellationToken,
  }) async {
    final bytes = await pdfFile.readAsBytes();
    return processPdfBytes(
      bytes,
      cancellationToken: cancellationToken,
    );
  }
  
  /// 处理PDF字节数据
  static Future<String> processPdfBytes(
    Uint8List pdfBytes, {
    CancellationToken? cancellationToken,
  }) async {
    return _processFile(
      pdfBytes,
      'document.pdf',
      cancellationToken: cancellationToken,
    );
  }
  
  /// 处理Word文件
  static Future<String> processWordFile(
    File wordFile, {
    CancellationToken? cancellationToken,
  }) async {
    final bytes = await wordFile.readAsBytes();
    final extension = _getWordFileExtension(wordFile.path);
    return processWordBytes(
      bytes,
      fileExtension: extension,
      cancellationToken: cancellationToken,
    );
  }
  
  /// 处理Word字节数据
  static Future<String> processWordBytes(
    Uint8List wordBytes, {
    String fileExtension = 'docx',
    CancellationToken? cancellationToken,
  }) async {
    return _processFile(
      wordBytes,
      'document.$fileExtension',
      cancellationToken: cancellationToken,
    );
  }
  
  /// 获取Word文件扩展名
  static String _getWordFileExtension(String filePath) {
    final fileName = filePath.toLowerCase();
    if (fileName.endsWith('.docx')) {
      return 'docx';
    } else if (fileName.endsWith('.doc')) {
      return 'doc';
    }
    return 'docx';
  }
  
  /// 获取文件大小的可读字符串
  static String _getFileSizeString(int fileSizeInBytes) {
    if (fileSizeInBytes < 1024) {
      return '${fileSizeInBytes}B';
    } else if (fileSizeInBytes < 1024 * 1024) {
      return '${(fileSizeInBytes / 1024).toStringAsFixed(1)}KB';
    } else if (fileSizeInBytes < 1024 * 1024 * 1024) {
      return '${(fileSizeInBytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    } else {
      return '${(fileSizeInBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
    }
  }
  
  /// 检查文件大小是否有效
  static bool isFileSizeValid(int fileSizeInBytes) {
    return fileSizeInBytes <= maxFileSize;
  }
  
  /// 处理文件的通用方法
  static Future<String> _processFile(
    Uint8List fileBytes,
    String fileName, {
    CancellationToken? cancellationToken,
  }) async {
    try {
      Log.info('Starting Aliyun document parsing for file: $fileName');
      
      // 检查是否已取消
      if (cancellationToken?.isCancelled ?? false) {
        throw Exception('任务已取消');
      }
      
      // 检查文件大小
      if (fileBytes.length > maxFileSize) {
        final fileSizeStr = _getFileSizeString(fileBytes.length);
        final maxSizeStr = _getFileSizeString(maxFileSize);
        throw Exception('文件大小超过限制（最大$maxSizeStr），当前文件大小：$fileSizeStr。请压缩文件或使用较小的文件。');
      }
      
      // 调用阿里云解析API
      final result = await _callAliyunParseApi(
        fileBytes: fileBytes,
        fileName: fileName,
        cancellationToken: cancellationToken,
      );
      
      Log.info('Aliyun document parsing completed successfully');
      return result;
      
    } catch (e) {
      if (e.toString().contains('已取消')) {
        rethrow;
      }
      if (e.toString().contains('文件大小超过限制')) {
        rethrow;
      }
      Log.error('Aliyun document parsing failed: $e');
      throw Exception('阿里云文档解析失败: $e');
    }
  }
  
  /// 调用阿里云解析API
  static Future<String> _callAliyunParseApi({
    required Uint8List fileBytes,
    required String fileName,
    CancellationToken? cancellationToken,
  }) async {
    final url = Uri.parse('$apiBaseUrl$parseEndpoint');
    
    Log.info('Calling Aliyun parse API: $url');
    Log.info('File name: $fileName, Size: ${fileBytes.length} bytes');
    
    // 检查是否已取消
    if (cancellationToken?.isCancelled ?? false) {
      throw Exception('任务已取消');
    }
    
    try {
      // 创建multipart请求
      final request = http.MultipartRequest('POST', url);
      
      // 添加文件字段，字段名为 'doc'
      final multipartFile = http.MultipartFile.fromBytes(
        'doc',
        fileBytes,
        filename: fileName,
        contentType: _getContentType(fileName),
      );
      request.files.add(multipartFile);
      
      // 发送请求
      final streamedResponse = await request.send();
      
      // 检查是否已取消
      if (cancellationToken?.isCancelled ?? false) {
        throw Exception('任务已取消');
      }
      
      // 读取响应
      final response = await http.Response.fromStream(streamedResponse);
      
      Log.info('Aliyun API response status: ${response.statusCode}');
      Log.info('Aliyun API response body length: ${response.body.length}');
      
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        Log.info('Aliyun API response data keys: ${responseData.keys}');
        
        // 检查响应格式
        if (responseData['code'] != null && responseData['code'] != 200) {
          final msg = responseData['msg'] ?? '未知错误';
          Log.error('Aliyun API returned error: code=${responseData['code']}, msg=$msg');
          throw Exception('阿里云解析失败: $msg');
        }
        
        // 解析返回的数据并转换为Markdown
        final markdownContent = _parseResponseToMarkdown(responseData);
        
        if (markdownContent.isEmpty) {
          Log.warn('Parsed markdown content is empty');
          throw Exception('解析结果为空，请检查文件内容');
        }
        
        Log.info('Successfully converted response to markdown, length: ${markdownContent.length}');
        return markdownContent;
        
      } else if (response.statusCode == 413) {
        // 413 Request Entity Too Large - 文件太大
        final fileSizeStr = _getFileSizeString(fileBytes.length);
        final maxSizeStr = _getFileSizeString(maxFileSize);
        Log.error('Aliyun API 413 error: File too large. File size: $fileSizeStr, Max: $maxSizeStr');
        throw Exception('文件大小超过服务器限制（最大$maxSizeStr），当前文件大小：$fileSizeStr。请压缩文件或使用较小的文件。');
      } else {
        Log.error('Aliyun API error: ${response.statusCode} - ${response.body}');
        throw Exception('API请求失败: ${response.statusCode} - ${response.body}');
      }
      
    } catch (e) {
      Log.error('Failed to call Aliyun parse API: $e');
      if (e.toString().contains('已取消')) {
        rethrow;
      }
      if (e.toString().contains('解析失败') || e.toString().contains('解析结果为空')) {
        rethrow;
      }
      if (e.toString().contains('文件大小超过')) {
        rethrow;
      }
      throw Exception('调用阿里云解析API失败: $e');
    }
  }
  
  /// 获取文件Content-Type
  static MediaType _getContentType(String fileName) {
    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.pdf')) {
      return MediaType('application', 'pdf');
    } else if (lowerName.endsWith('.docx')) {
      return MediaType('application', 'vnd.openxmlformats-officedocument.wordprocessingml.document');
    } else if (lowerName.endsWith('.doc')) {
      return MediaType('application', 'msword');
    }
    return MediaType('application', 'octet-stream');
  }
  
  /// 解析API响应并转换为Markdown格式
  static String _parseResponseToMarkdown(Map<String, dynamic> responseData) {
    try {
      // 提取data字段
      final data = responseData['data'];
      if (data == null) {
        Log.error('Response data is null');
        return '';
      }
      
      // 提取data.data字段（嵌套的data）
      final innerData = data['data'];
      if (innerData == null) {
        Log.error('Response data.data is null');
        return '';
      }
      
      // 提取layouts（布局信息，包含文本内容）
      final layouts = innerData['layouts'] as List<dynamic>?;
      if (layouts == null || layouts.isEmpty) {
        Log.warn('No layouts found in response');
        // 尝试从其他字段提取内容
        return _extractContentFromOtherFields(innerData);
      }
      
      // 提取docInfo（文档信息）
      final docInfo = innerData['docInfo'] as Map<String, dynamic>?;
      
      // 提取styles（样式信息）
      final styles = innerData['styles'] as List<dynamic>?;
      
      // 提取logics（逻辑结构）
      final logics = innerData['logics'] as Map<String, dynamic>?;
      
      // 构建Markdown内容
      final StringBuffer markdown = StringBuffer();
      
      // 添加文档信息（如果有）
      if (docInfo != null) {
        _addDocInfoToMarkdown(markdown, docInfo);
      }
      
      // 处理layouts，转换为Markdown
      _processLayoutsToMarkdown(markdown, layouts, styles);
      
      // 处理logics（文档树结构）
      if (logics != null) {
        _processLogicsToMarkdown(markdown, logics);
      }
      
      final result = markdown.toString().trim();
      if (result.isEmpty) {
        Log.warn('Generated markdown is empty, trying alternative extraction');
        return _extractContentFromOtherFields(innerData);
      }
      
      return result;
      
    } catch (e) {
      Log.error('Failed to parse response to markdown: $e');
      return '';
    }
  }
  
  /// 从其他字段提取内容（备用方案）
  static String _extractContentFromOtherFields(Map<String, dynamic> innerData) {
    final StringBuffer content = StringBuffer();
    
    // 尝试从paragraphKVs提取
    final logics = innerData['logics'] as Map<String, dynamic>?;
    if (logics != null) {
      final paragraphKVs = logics['paragraphKVs'] as List<dynamic>?;
      if (paragraphKVs != null && paragraphKVs.isNotEmpty) {
        for (final kv in paragraphKVs) {
          if (kv is Map<String, dynamic>) {
            final key = kv['key'] as List<dynamic>?;
            final value = kv['value'] as List<dynamic>?;
            
            if (key != null && key.isNotEmpty) {
              final keyText = key.map((e) => e.toString()).join(' ');
              content.writeln('**$keyText**');
            }
            
            if (value != null && value.isNotEmpty) {
              final valueText = value.map((e) => e.toString()).join(' ');
              content.writeln(valueText);
              content.writeln();
            }
          }
        }
      }
    }
    
    return content.toString().trim();
  }
  
  /// 添加文档信息到Markdown
  static void _addDocInfoToMarkdown(StringBuffer markdown, Map<String, dynamic> docInfo) {
    final docType = docInfo['docType'] as String?;
    final pageCount = docInfo['pageCountEstimate'] as int? ?? docInfo['pageCount'] as int?;
    final paragraphCount = docInfo['paragraphCount'] as int?;
    final tableCount = docInfo['tableCount'] as int?;
    final imageCount = docInfo['imageCount'] as int?;
    
    if (docType != null || pageCount != null) {
      markdown.writeln('---');
      markdown.writeln();
      
      if (docType != null) {
        markdown.writeln('**文档类型:** $docType');
      }
      
      if (pageCount != null && pageCount > 0) {
        markdown.writeln('**页数:** $pageCount');
      }
      
      if (paragraphCount != null && paragraphCount > 0) {
        markdown.writeln('**段落数:** $paragraphCount');
      }
      
      if (tableCount != null && tableCount > 0) {
        markdown.writeln('**表格数:** $tableCount');
      }
      
      if (imageCount != null && imageCount > 0) {
        markdown.writeln('**图片数:** $imageCount');
      }
      
      markdown.writeln();
      markdown.writeln('---');
      markdown.writeln();
    }
  }
  
  /// 处理layouts并转换为Markdown
  static void _processLayoutsToMarkdown(
    StringBuffer markdown,
    List<dynamic> layouts,
    List<dynamic>? styles,
  ) {
    if (layouts.isEmpty) {
      return;
    }
    
    // 创建样式映射
    final Map<int, Map<String, dynamic>> styleMap = {};
    if (styles != null) {
      for (final style in styles) {
        if (style is Map<String, dynamic>) {
          final styleId = style['styleId'] as int?;
          if (styleId != null) {
            styleMap[styleId] = style;
          }
        }
      }
    }
    
    // 按页面和位置排序layouts
    final sortedLayouts = List<Map<String, dynamic>>.from(
      layouts.whereType<Map<String, dynamic>>(),
    )..sort((a, b) {
      // 先按页码排序
      final pageA = _getFirstPageNum(a);
      final pageB = _getFirstPageNum(b);
      if (pageA != pageB) {
        return pageA.compareTo(pageB);
      }
      
      // 再按位置排序（y坐标，从上到下）
      final posA = a['pos'] as Map<String, dynamic>?;
      final posB = b['pos'] as Map<String, dynamic>?;
      final yA = posA?['y'] as int? ?? 0;
      final yB = posB?['y'] as int? ?? 0;
      return yA.compareTo(yB);
    });
    
    String? lastType;
    for (final layout in sortedLayouts) {
      final type = layout['type'] as String?;
      final text = layout['text'] as String?;
      final subType = layout['subType'] as String?;
      final alignment = layout['alignment'] as String?;
      final blocks = layout['blocks'] as List<dynamic>?;
      final styleId = layout['styleId'] as int?;
      
      if (text == null || text.trim().isEmpty) {
        // 尝试从blocks提取文本
        if (blocks != null && blocks.isNotEmpty) {
          final blockTexts = <String>[];
          for (final block in blocks) {
            if (block is Map<String, dynamic>) {
              final blockText = block['text'] as String?;
              if (blockText != null && blockText.trim().isNotEmpty) {
                blockTexts.add(blockText.trim());
              }
            }
          }
          if (blockTexts.isNotEmpty) {
            _addLayoutToMarkdown(
              markdown,
              type: type,
              text: blockTexts.join(' '),
              subType: subType,
              alignment: alignment,
              styleId: styleId,
              styleMap: styleMap,
              lastType: lastType,
            );
            lastType = type;
            continue;
          }
        }
        continue;
      }
      
      _addLayoutToMarkdown(
        markdown,
        type: type,
        text: text,
        subType: subType,
        alignment: alignment,
        styleId: styleId,
        styleMap: styleMap,
        lastType: lastType,
      );
      
      lastType = type;
    }
  }
  
  /// 获取第一个页码
  static int _getFirstPageNum(Map<String, dynamic> layout) {
    final pageNum = layout['pageNum'] as List<dynamic>?;
    if (pageNum != null && pageNum.isNotEmpty) {
      final firstPage = pageNum.first;
      if (firstPage is int) {
        return firstPage;
      } else if (firstPage is String) {
        return int.tryParse(firstPage) ?? 0;
      }
    }
    return 0;
  }
  
  /// 添加单个layout到Markdown
  static void _addLayoutToMarkdown(
    StringBuffer markdown,
    {
    required String? type,
    required String text,
    String? subType,
    String? alignment,
    int? styleId,
    required Map<int, Map<String, dynamic>> styleMap,
    String? lastType,
  }) {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) {
      return;
    }
    
    // 获取样式信息
    Map<String, dynamic>? style;
    if (styleId != null) {
      style = styleMap[styleId];
    }
    
    // 根据类型和子类型格式化文本
    switch (type?.toLowerCase()) {
      case 'title':
      case 'heading':
        // 标题
        final level = _determineHeadingLevel(subType, style);
        markdown.writeln('${'#' * level} $trimmedText');
        markdown.writeln();
        break;
        
      case 'paragraph':
      case 'text':
        // 段落
        String formattedText = trimmedText;
        
        // 应用样式
        if (style != null) {
          final bold = style['bold'] as bool? ?? false;
          final italic = style['italic'] as bool? ?? false;
          
          if (bold) {
            formattedText = '**$formattedText**';
          }
          if (italic) {
            formattedText = '*$formattedText*';
          }
        }
        
        // 处理对齐方式
        if (alignment == 'center' || alignment == 'CENTER') {
          markdown.writeln('<center>$formattedText</center>');
        } else {
          markdown.writeln(formattedText);
        }
        
        // 如果不是列表项，添加空行
        if (lastType != 'list' && subType != 'list_item') {
          markdown.writeln();
        }
        break;
        
      case 'list':
      case 'list_item':
        // 列表项
        final listMarker = subType == 'ordered' ? '1. ' : '- ';
        markdown.writeln('$listMarker$trimmedText');
        break;
        
      case 'table':
        // 表格（如果subType是table，可能需要特殊处理）
        markdown.writeln(trimmedText);
        markdown.writeln();
        break;
        
      default:
        // 默认作为普通文本处理
        markdown.writeln(trimmedText);
        if (lastType != 'list' && subType != 'list_item') {
          markdown.writeln();
        }
    }
  }
  
  /// 确定标题级别
  static int _determineHeadingLevel(String? subType, Map<String, dynamic>? style) {
    if (subType != null) {
      switch (subType.toLowerCase()) {
        case 'h1':
        case 'heading1':
          return 1;
        case 'h2':
        case 'heading2':
          return 2;
        case 'h3':
        case 'heading3':
          return 3;
        case 'h4':
        case 'heading4':
          return 4;
        case 'h5':
        case 'heading5':
          return 5;
        case 'h6':
        case 'heading6':
          return 6;
      }
    }
    
    // 根据字体大小判断（如果样式中有）
    if (style != null) {
      final fontSize = style['fontSize'] as int?;
      if (fontSize != null) {
        if (fontSize >= 24) return 1;
        if (fontSize >= 20) return 2;
        if (fontSize >= 18) return 3;
        if (fontSize >= 16) return 4;
        if (fontSize >= 14) return 5;
      }
    }
    
    // 默认使用二级标题
    return 2;
  }
  
  /// 处理logics（文档树结构）到Markdown
  static void _processLogicsToMarkdown(
    StringBuffer markdown,
    Map<String, dynamic> logics,
  ) {
    // 如果layouts已经处理了主要内容，这里可以处理文档树结构
    // 例如：添加目录、章节结构等
    final docTree = logics['docTree'] as List<dynamic>?;
    if (docTree != null && docTree.isNotEmpty) {
      // 可以在这里处理文档树，添加目录等
      // 目前主要依赖layouts中的内容
    }
  }
  
  /// 检查API是否可用
  static Future<bool> isApiAvailable() async {
    try {
      final url = Uri.parse('$apiBaseUrl$parseEndpoint');
      // 发送一个HEAD请求或小的测试请求
      final response = await http.head(url).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw Exception('请求超时');
        },
      );
      return response.statusCode < 500; // 只要不是服务器错误就认为可用
    } catch (e) {
      Log.error('API availability check failed: $e');
      return false;
    }
  }
}

