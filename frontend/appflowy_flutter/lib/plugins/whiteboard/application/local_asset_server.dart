import 'dart:io';
import 'package:appflowy/util/diagnostic_build.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/services.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:synchronized/synchronized.dart';

class LocalAssetServer {
  HttpServer? _server;
  int? _port;
  final Lock _lifecycleLock = Lock();

  static final LocalAssetServer _instance = LocalAssetServer._internal();
  factory LocalAssetServer() => _instance;
  LocalAssetServer._internal();

  final Map<String, Uint8List> _assetCache = {};

  // 服务只绑定 loopbackIPv4，因此 URL 也必须明确使用 IPv4。iOS 可能把
  // localhost 优先解析为 ::1，连接一个仅监听 127.0.0.1 的服务会偶发失败。
  String? get baseUrl => _port != null ? 'http://127.0.0.1:$_port' : null;

  Future<String> start() => _lifecycleLock.synchronized(_startUnlocked);

  Future<String> _startUnlocked() async {
    if (_server != null) {
      if (await _isHealthy()) {
        return baseUrl!;
      }
      Log.warn(
        '[LocalAssetServer] 已记录的本地服务不可达，将重建监听 socket: $baseUrl',
      );
      await _stopUnlocked();
    }

    try {
      final handler = (shelf.Request request) async {
        final stopwatch = Stopwatch()..start();
        var requestPath = request.url.path;
        if (requestPath.isEmpty || requestPath == '/') {
          requestPath = 'index.html';
        } else if (requestPath.startsWith('/')) {
          requestPath = requestPath.substring(1);
        }

        if (requestPath == '__health') {
          return shelf.Response.ok('ok');
        }

        final assetPath = 'assets/excalidraw/$requestPath';
        final cacheHit = _assetCache.containsKey(assetPath);

        try {
          final bytes = await _loadAssetBytes(assetPath);
          final contentType = _getContentType(assetPath);
          if (!cacheHit || requestPath == 'index.html') {
            logDiagnosticEvent(
              'WhiteboardLoad',
              'asset_request_ok',
              {
                'requestPath': requestPath,
                'assetPath': assetPath,
                'cacheHit': cacheHit,
                'contentType': contentType,
                'elapsedMs': stopwatch.elapsedMilliseconds,
              },
            );
          }

          return shelf.Response.ok(
            bytes,
            headers: {
              'Content-Type': contentType,
              'Access-Control-Allow-Origin': '*',
              'Cache-Control': _cacheControlForPath(requestPath),
            },
          );
        } catch (error) {
          Log.error('Failed to load whiteboard asset $assetPath: $error');
          logDiagnosticEvent(
            'WhiteboardLoad',
            'asset_request_anomaly',
            {
              'requestPath': requestPath,
              'assetPath': assetPath,
              'cacheHit': cacheHit,
              'status': 404,
              'elapsedMs': stopwatch.elapsedMilliseconds,
              'error': '$error',
            },
            warning: true,
          );
          return shelf.Response.notFound('Asset not found: $assetPath');
        }
      };

      // ⚡ 固定端口优先：稳定 WebView 的 origin(http://127.0.0.1:<port>)。
      // 端口随机(0)会导致每次重启 origin 漂移，WebView 侧 HTTP 缓存/IndexedDB/
      // localStorage 全部孤儿化、无法跨重启复用。固定端口可保持 origin 稳定；
      // 若该端口被占用，则优雅回退到系统随机端口（不影响功能）。
      const preferredPort = 51789;
      try {
        _server = await shelf_io.serve(
          handler,
          InternetAddress.loopbackIPv4,
          preferredPort,
        );
      } catch (error) {
        Log.warn(
            '[LocalAssetServer] preferred port $preferredPort unavailable ($error), falling back to random port');
        _server = await shelf_io.serve(
          handler,
          InternetAddress.loopbackIPv4,
          0,
        );
      }
      _port = _server!.port;

      Log.info('LocalAssetServer started: $baseUrl');
      return baseUrl!;
    } catch (error) {
      Log.error('Failed to start LocalAssetServer: $error');
      rethrow;
    }
  }

  Future<bool> _isHealthy() async {
    final url = baseUrl;
    if (url == null) return false;

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    try {
      final request = await client.getUrl(Uri.parse('$url/__health')).timeout(
            const Duration(seconds: 2),
          );
      final response = await request.close().timeout(
            const Duration(seconds: 2),
          );
      await response.drain<void>();
      return response.statusCode == HttpStatus.ok;
    } catch (error) {
      Log.debug('[LocalAssetServer] 健康检查失败: $error');
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<String> restart() => _lifecycleLock.synchronized(() async {
        await _stopUnlocked();
        return _startUnlocked();
      });

  Future<void> stop() => _lifecycleLock.synchronized(_stopUnlocked);

  Future<void> _stopUnlocked() async {
    if (_server == null) {
      return;
    }

    await _server!.close(force: true);
    _server = null;
    _port = null;
    _assetCache.clear();
    Log.info('LocalAssetServer stopped');
  }

  Future<void> preloadAssets(Iterable<String> assetPaths) async {
    for (final assetPath in assetPaths.toSet()) {
      try {
        await _loadAssetBytes(assetPath);
        Log.info('[LocalAssetServer] Preloaded asset: $assetPath');
      } catch (error) {
        Log.warn('[LocalAssetServer] Failed to preload $assetPath: $error');
      }
    }
  }

  Future<Uint8List> _loadAssetBytes(String assetPath) async {
    final cached = _assetCache[assetPath];
    if (cached != null) {
      return cached;
    }

    try {
      final bytes = await rootBundle.load(assetPath);
      final data = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
      _assetCache[assetPath] = data;
      return data;
    } catch (e) {
      Log.warn(
          'Failed to load asset from rootBundle: $assetPath, trying file system');
      final file = File(assetPath);
      if (await file.exists()) {
        final data = await file.readAsBytes();
        _assetCache[assetPath] = data;
        return data;
      }
      rethrow;
    }
  }

  String _cacheControlForPath(String requestPath) {
    final normalizedPath = requestPath.replaceAll('\\', '/');
    if (normalizedPath == 'index.html' ||
        normalizedPath == 'flutter_bridge.js' ||
        normalizedPath == 'sw.js' ||
        normalizedPath == 'service-worker.js') {
      return normalizedPath == 'index.html' || normalizedPath == 'flutter_bridge.js'
          ? 'no-store, no-cache, must-revalidate, max-age=0'
          : 'public, max-age=300';
    }

    if (normalizedPath.startsWith('assets/') ||
        normalizedPath.startsWith('fonts/') ||
        normalizedPath.startsWith('locales/')) {
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
