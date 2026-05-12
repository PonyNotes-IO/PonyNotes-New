import 'dart:io';
import 'dart:typed_data';
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

  final Map<String, Uint8List> _assetCache = {};

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
        // 处理路径：根路径映射到 index.html，移除前导斜杠
        String requestPath = request.url.path;
        if (requestPath.isEmpty || requestPath == '/') {
          requestPath = 'index.html';
        } else {
          // 移除前导斜杠
          requestPath = requestPath.startsWith('/') 
              ? requestPath.substring(1) 
              : requestPath;
        }
        
        final assetPath = 'assets/excalidraw/$requestPath';

        try {
          // 加载Flutter asset
          final bytes = await _loadAssetBytes(assetPath);
          
          // 确定Content-Type
          final contentType = _getContentType(assetPath);
          
          // 返回资源信息日志已移除
          
          return shelf.Response.ok(
            bytes,
            headers: {
              'Content-Type': contentType,
              'Access-Control-Allow-Origin': '*',
              'Cache-Control': _cacheControlForPath(requestPath),
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
      _assetCache.clear();
      Log.info('🛑 本地资源服务器已停止');
    }
  }

  /// 根据文件扩展名确定Content-Type
  Future<Uint8List> _loadAssetBytes(String assetPath) async {
    final cached = _assetCache[assetPath];
    if (cached != null) {
      return cached;
    }

    final bytes = await rootBundle.load(assetPath);
    final data = bytes.buffer.asUint8List(
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
    _assetCache[assetPath] = data;
    return data;
  }

  String _cacheControlForPath(String requestPath) {
    final normalizedPath = requestPath.replaceAll('\\', '/');
    if (normalizedPath == 'index.html' ||
        normalizedPath == 'sw.js' ||
        normalizedPath == 'service-worker.js') {
      return 'public, max-age=300';
    }

    if (normalizedPath.startsWith('assets/')) {
      return 'public, max-age=31536000, immutable';
    }

    return 'public, max-age=86400';
  }

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
