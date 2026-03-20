import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy_backend/log.dart';
import 'package:http/http.dart' as http;

import 'aliyun_doc_parse_processor.dart';

class CustomPdfProcessor {
  static const String baseUrl = 'http://129.153.85.31:8000';
  static const String authToken = 'xiaoma_ocr';

  /// 将 Uint8List 转换为 String，处理编码错误
  ///
  /// 参数:
  /// - bytes: 要转换的字节数据
  /// - defaultValue: 转换失败时的默认值
  ///
  /// 返回值:
  /// - 转换后的字符串，如果转换失败则返回默认值
  static String convertUint8ListToString(
    Uint8List? bytes,
    {String defaultValue = ""}
  ) {
    if (bytes == null) {
      return defaultValue;
    }

    try {
      // 尝试使用 UTF-8 编码转换
      return utf8.decode(bytes);
    } catch (e) {
      try {
        // 如果 UTF-8 失败，尝试使用 Latin1 编码
        return String.fromCharCodes(bytes);
      } catch (e) {
        Log.error('Failed to convert Uint8List to String: $e');
        return defaultValue;
      }
    }
  }

  /// 将 Uint8List 转换为 String，允许畸形编码
  ///
  /// 参数:
  /// - bytes: 要转换的字节数据
  /// - defaultValue: 转换失败时的默认值
  ///
  /// 返回值:
  /// - 转换后的字符串，如果转换失败则返回默认值
  static String convertUint8ListToStringWithAllowMalformed(
    Uint8List? bytes,
    {String defaultValue = ""}
  ) {
    if (bytes == null) {
      return defaultValue;
    }

    try {
      // 允许畸形编码，用替换字符替代无效字符
      return utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      Log.error('Failed to convert Uint8List to String: $e');
      return defaultValue;
    }
  }

  // 健康检查接口
  static Future<bool> healthCheck({CancellationToken? cancellationToken}) async {
    try {
      // 检查是否已取消
      if (cancellationToken?.isCancelled ?? false) {
        Log.info('Health check cancelled');
        return false;
      }

      final response = await http.get(
        Uri.parse('$baseUrl/health'),
        headers: {
          'Authorization': 'Bearer $authToken',
        },
      );

      // 检查是否已取消
      if (cancellationToken?.isCancelled ?? false) {
        Log.info('Health check cancelled');
        return false;
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['ok'] == true;
      } else {
        Log.error('Health check failed: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      Log.error('Health check error: $e');
      return false;
    }
  }

  /// PDF OCR处理接口 (版本1)
  /// 
  /// 对PDF文件进行OCR处理，返回包含OCR文本的PDF文件
  /// 
  /// 参数:
  /// - pdfFile: PDF文件
  /// - forceOcr: 强制重新OCR，即使PDF已有文本
  /// - cancellationToken: 取消令牌，用于取消请求
  /// 
  /// 返回值:
  /// - 处理后的PDF文件字节数据 (Uint8List)，如果操作失败或被取消则返回null
  static Future<Uint8List?> processPdfOcr(
    File pdfFile, 
    {bool forceOcr = false, 
    CancellationToken? cancellationToken}
  ) async {
    try {

      // 检查是否已取消
      if (cancellationToken?.isCancelled ?? false) {
        Log.info('PDF OCR processing cancelled');
        return null;
      }

      bool isHealth = await healthCheck(cancellationToken: cancellationToken);
      if(!isHealth) {
        Log.info('PDF processing healthCheck false');
        return null;
      }

      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/ocr_v1'));
      
      // 添加认证头
      request.headers['Authorization'] = 'Bearer $authToken';
      
      // 添加文件
      request.files.add(await http.MultipartFile.fromPath('file', pdfFile.path));
      
      // 添加可选参数
      if (forceOcr) {
        request.fields['force_ocr'] = 'true';
      }
      
      // 检查是否已取消
      if (cancellationToken?.isCancelled ?? false) {
        Log.info('PDF OCR processing cancelled');
        return null;
      }
      
      final response = await request.send();
      
      // 检查是否已取消
      if (cancellationToken?.isCancelled ?? false) {
        Log.info('PDF OCR processing cancelled');
        // 尝试关闭响应流
        await response.stream.drain();
        return null;
      }
      
      if (response.statusCode == 200) {
        // 创建一个字节列表来存储响应数据
        final bytes = <int>[];
        
        // 逐块读取响应流，并检查取消状态
        await for (final chunk in response.stream) {
          if (cancellationToken?.isCancelled ?? false) {
            Log.info('PDF OCR processing cancelled during download');
            return null;
          }
          bytes.addAll(chunk);
        }
        
        // 检查是否已取消
        if (cancellationToken?.isCancelled ?? false) {
          Log.info('PDF OCR processing cancelled');
          return null;
        }
        
        return Uint8List.fromList(bytes);
      } else {
        Log.error('PDF OCR processing failed: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      Log.error('PDF OCR processing error: $e');
      return null;
    }
  }

  /// 通用OCR文本提取接口 (版本2)
  /// 
  /// 对PDF或图片文件进行OCR，返回提取的文本内容
  /// 
  /// 参数:
  /// - file: PDF或图片文件 (支持: PDF, PNG, JPG, JPEG, TIFF, BMP)
  /// - lang: OCR语言，默认为"spa+eng" (西班牙语+英语)
  /// - optimize: PDF优化级别 0-3，默认为0
  /// - deskew: 是否自动纠斜，默认为1
  /// - clean: 是否清理图像噪点，默认为1
  /// - cancellationToken: 取消令牌，用于取消请求
  /// 
  /// 返回值:
  /// - 包含OCR结果的Map: {
  ///   "text": "提取的文本内容",
  ///   "pages": 页数,
  ///   "engine": "使用的OCR引擎"
  /// }, 如果操作失败或被取消则返回null
  static Future<Map<String, dynamic>?> extractTextOcr(
    File file, 
    {
      String? lang,
      int? optimize,
      int? deskew,
      int? clean,
      CancellationToken? cancellationToken,
    }
  ) async {
    try {
      // 检查是否已取消
      if (cancellationToken?.isCancelled ?? false) {
        Log.info('Text extraction OCR cancelled');
        return null;
      }

      bool isHealth = await healthCheck(cancellationToken: cancellationToken);
      if(!isHealth) {
        Log.info('PDF processing healthCheck false');
        return null;
      }

      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/ocr_v2'));
      
      // 添加认证头
      request.headers['Authorization'] = 'Bearer $authToken';
      
      // 添加文件
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
      
      // 添加可选参数
      if (lang != null) {
        request.fields['lang'] = lang;
      }
      if (optimize != null) {
        request.fields['optimize'] = optimize.toString();
      }
      if (deskew != null) {
        request.fields['deskew'] = deskew.toString();
      }
      if (clean != null) {
        request.fields['clean'] = clean.toString();
      }
      
      // 检查是否已取消
      if (cancellationToken?.isCancelled ?? false) {
        Log.info('Text extraction OCR cancelled');
        return null;
      }
      
      final response = await request.send();
      
      // 检查是否已取消
      if (cancellationToken?.isCancelled ?? false) {
        Log.info('Text extraction OCR cancelled');
        // 尝试关闭响应流
        await response.stream.drain();
        return null;
      }
      
      if (response.statusCode == 200) {
        // 读取完整的响应体
        final chunks = <int>[];
        await for (final chunk in response.stream) {
          if (cancellationToken?.isCancelled ?? false) {
            Log.info('Text extraction OCR cancelled during download');
            return null;
          }
          chunks.addAll(chunk);
        }
        
        // 检查是否已取消
        if (cancellationToken?.isCancelled ?? false) {
          Log.info('Text extraction OCR cancelled');
          return null;
        }
        
        final body = convertUint8ListToStringWithAllowMalformed(Uint8List.fromList(chunks));
        
        try {
          // 解析JSON响应
          final data = json.decode(body) as Map<String, dynamic>;
          
          // 验证返回数据的结构
          if (data.containsKey('text') && data.containsKey('pages') && data.containsKey('engine')) {
            final text = data['text']?.toString() ?? '';
            final pages = data['pages'];
            final engine = data['engine']?.toString() ?? 'unknown';
            
            Log.info('OCR extraction response: pages=$pages, engine=$engine, textLength=${text.length}');
            
            // 如果文本为空，记录警告
            if (text.isEmpty) {
              Log.warn('OCR extraction returned empty text. Response: $body');
            }
            
            return data;
          } else {
            Log.error('Invalid OCR response structure: ${data.keys}');
            Log.error('Response body: $body');
            return null;
          }
        } catch (e) {
          Log.error('Failed to parse OCR JSON response: $e');
          Log.error('Response body: $body');
          return null;
        }
      } else {
        Log.error('Text extraction OCR failed: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      Log.error('Text extraction OCR error: $e');
      return null;
    }
  }

  // 检查文件是否支持OCR处理
  static bool isSupportedFile(File file) {
    final extension = file.path.split('.').last.toLowerCase();
    return {
      'pdf', 'png', 'jpg', 'jpeg', 'tiff', 'bmp'
    }.contains(extension);
  }

  // 获取文件MIME类型
  static String getFileType(File file) {
    final extension = file.path.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'tiff':
        return 'image/tiff';
      case 'bmp':
        return 'image/bmp';
      default:
        return 'application/octet-stream';
    }
  }
}
