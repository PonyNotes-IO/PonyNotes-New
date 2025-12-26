import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:appflowy_backend/log.dart';

/// 本地资源HTTP服务器
/// 用于解决file://协议下JavaScript模块加载的安全限制
class LocalAssetServer {
  HttpServer? _server;
  int? _port;

  /// 单例模式
  static final LocalAssetServer _instance = LocalAssetServer._internal();
  factory LocalAssetServer() => _instance;
  LocalAssetServer._internal();

  /// 获取服务器URL
  String? get baseUrl => _port != null ? 'http://localhost:$_port' : null;

  /// 启动服务器
  Future<String> start() async {
    if (_server != null) {
      return baseUrl!;
    }

    try {
      // 创建请求处理器
      final handler = (shelf.Request request) async {
        final assetPath = 'assets/excalidraw/${request.url.path}';

        try {
          // 加载Flutter asset
          final bytes = await rootBundle.load(assetPath);
          
          // 确定Content-Type
          final contentType = _getContentType(assetPath);
          
          // 返回资源信息日志已移除
          
          return shelf.Response.ok(
            bytes.buffer.asUint8List(),
            headers: {
              'Content-Type': contentType,
              'Access-Control-Allow-Origin': '*',
              'Cache-Control': 'no-cache',
            },
          );
        } catch (e) {
          Log.error('❌ 加载资源失败 $assetPath: $e');
          return shelf.Response.notFound('Asset not found: $assetPath');
        }
      };

      // 启动HTTP服务器
      _server = await shelf_io.serve(
        handler,
        InternetAddress.loopbackIPv4,
        0, // 自动选择可用端口
      );

      _port = _server!.port;

      Log.info('🚀 本地资源服务器已启动: $baseUrl');

      return baseUrl!;
    } catch (e) {
      Log.error('❌ 启动本地资源服务器失败: $e');
      rethrow;
    }
  }

  /// 停止服务器
  Future<void> stop() async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
      _port = null;
      Log.info('🛑 本地资源服务器已停止');
    }
  }

  /// 根据文件扩展名确定Content-Type
  String _getContentType(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'html':
        return 'text/html; charset=utf-8';
      case 'js':
        return 'application/javascript; charset=utf-8';
      case 'css':
        return 'text/css; charset=utf-8';
      case 'json':
        return 'application/json; charset=utf-8';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'svg':
        return 'image/svg+xml';
      case 'woff':
        return 'font/woff';
      case 'woff2':
        return 'font/woff2';
      case 'ttf':
        return 'font/ttf';
      case 'map':
        return 'application/json';
      case 'webmanifest':
        return 'application/manifest+json';
      case 'xml':
        return 'application/xml';
      default:
        return 'application/octet-stream';
    }
  }
}

