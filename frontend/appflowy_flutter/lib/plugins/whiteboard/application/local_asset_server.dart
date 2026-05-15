import 'dart:io';
import 'package:appflowy/util/diagnostic_build.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/services.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

class LocalAssetServer {
  HttpServer? _server;
  int? _port;

  static final LocalAssetServer _instance = LocalAssetServer._internal();
  factory LocalAssetServer() => _instance;
  LocalAssetServer._internal();

  final Map<String, Uint8List> _assetCache = {};

  String? get baseUrl => _port != null ? 'http://localhost:$_port' : null;

  Future<String> start() async {
    if (_server != null) {
      return baseUrl!;
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

      _server = await shelf_io.serve(
        handler,
        InternetAddress.loopbackIPv4,
        0,
      );
      _port = _server!.port;

      Log.info('LocalAssetServer started: $baseUrl');
      return baseUrl!;
    } catch (error) {
      Log.error('Failed to start LocalAssetServer: $error');
      rethrow;
    }
  }

  Future<void> stop() async {
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
