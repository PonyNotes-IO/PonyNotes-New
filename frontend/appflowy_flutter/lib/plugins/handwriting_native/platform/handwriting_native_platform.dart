import 'package:flutter/services.dart';

/// 手写笔记原生平台接口
class HandwritingNativePlatform {
  static const MethodChannel _channel = MethodChannel('handwriting_native');

  /// 初始化动态库
  static Future<bool> init(String configJson) async {
    try {
      final result = await _channel.invokeMethod<bool>('init', {'config': configJson});
      return result ?? false;
    } catch (e) {
      print('❌ [HandwritingNativePlatform] init failed: $e');
      return false;
    }
  }

  /// 创建文档
  static Future<String?> createDoc(String optionsJson) async {
    try {
      final result = await _channel.invokeMethod<String>('create_doc', {'options': optionsJson});
      return result;
    } catch (e) {
      print('❌ [HandwritingNativePlatform] createDoc failed: $e');
      return null;
    }
  }

  /// 打开文档
  static Future<String?> openDoc(String xoppPath) async {
    try {
      final result = await _channel.invokeMethod<String>('open_doc', {'path': xoppPath});
      return result;
    } catch (e) {
      print('❌ [HandwritingNativePlatform] openDoc failed: $e');
      return null;
    }
  }

  /// 保存文档
  static Future<bool> saveDoc(String docId, String xoppPath) async {
    try {
      final result = await _channel.invokeMethod<bool>('save_doc', {
        'docId': docId,
        'path': xoppPath,
      });
      return result ?? false;
    } catch (e) {
      print('❌ [HandwritingNativePlatform] saveDoc failed: $e');
      return false;
    }
  }

  /// 关闭文档
  static Future<bool> closeDoc(String docId) async {
    try {
      final result = await _channel.invokeMethod<bool>('close_doc', {'docId': docId});
      return result ?? false;
    } catch (e) {
      print('❌ [HandwritingNativePlatform] closeDoc failed: $e');
      return false;
    }
  }

  /// 处理笔迹
  static Future<bool> handleStroke(String docId, List<Map<String, dynamic>> points) async {
    try {
      final result = await _channel.invokeMethod<bool>('handle_stroke', {
        'docId': docId,
        'points': points,
      });
      return result ?? false;
    } catch (e) {
      print('❌ [HandwritingNativePlatform] handleStroke failed: $e');
      return false;
    }
  }

  /// 渲染页面为PNG
  static Future<String?> renderPage(
    String docId,
    int pageIndex,
    String pngPath,
    int width,
    int height, {
    String? optionsJson,
  }) async {
    try {
      final result = await _channel.invokeMethod<String>('render_page', {
        'docId': docId,
        'pageIndex': pageIndex,
        'pngPath': pngPath,
        'width': width,
        'height': height,
        if (optionsJson != null) 'options': optionsJson,
      });
      return result;
    } catch (e) {
      print('❌ [HandwritingNativePlatform] renderPage failed: $e');
      return null;
    }
  }

  /// 获取页面数量
  static Future<int?> getPageCount(String docId) async {
    try {
      final result = await _channel.invokeMethod<int>('get_page_count', {'docId': docId});
      return result;
    } catch (e) {
      print('❌ [HandwritingNativePlatform] getPageCount failed: $e');
      return null;
    }
  }

  /// 获取页面尺寸
  static Future<Map<String, double>?> getPageSize(String docId, int pageIndex) async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>('get_page_size', {
        'docId': docId,
        'pageIndex': pageIndex,
      });
      if (result != null) {
        return {
          'width': (result['width'] as num).toDouble(),
          'height': (result['height'] as num).toDouble(),
        };
      }
      return null;
    } catch (e) {
      print('❌ [HandwritingNativePlatform] getPageSize failed: $e');
      return null;
    }
  }
}

