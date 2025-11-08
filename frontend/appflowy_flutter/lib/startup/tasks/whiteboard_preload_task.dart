import 'package:appflowy_backend/log.dart';
import 'package:appflowy/plugins/whiteboard/application/local_asset_server.dart';
import 'package:flutter/services.dart';
import '../startup.dart';

/// 白板预热任务
/// 在应用启动时预先加载 Excalidraw WebView 相关资源
/// 这样可以避免用户首次打开白板视图时的卡顿和首次加载失败问题
class WhiteboardPreloadTask extends LaunchTask {
  const WhiteboardPreloadTask();

  @override
  LaunchTaskType get type => LaunchTaskType.dataProcessing;

  @override
  Future<void> initialize(LaunchContext context) async {
    await super.initialize(context);

    Log.info('🎨 [WhiteboardPreload] Starting whiteboard preload task...');

    try {
      // 1. 启动本地资源服务器（单例模式，只需要启动一次）
      final assetServer = LocalAssetServer();
      final baseUrl = await assetServer.start();
      Log.info('✅ [WhiteboardPreload] Local asset server started: $baseUrl');

      // 2. 预先加载关键资源到内存中
      // 这样可以避免首次加载时的延迟
      await _preloadCriticalAssets();

      Log.info('✅ [WhiteboardPreload] Whiteboard preload completed successfully');
    } catch (e, stackTrace) {
      // 预热失败不应该阻止应用启动
      // 只记录错误，让应用继续运行
      Log.error(
        '⚠️ [WhiteboardPreload] Failed to preload whiteboard resources: $e',
        e,
        stackTrace,
      );
    }
  }

  /// 预先加载关键资源
  /// 将常用的 Excalidraw 资源加载到内存中，减少首次加载延迟
  Future<void> _preloadCriticalAssets() async {
    try {
      Log.info('📦 [WhiteboardPreload] Preloading critical assets...');

      // 预加载主 HTML 文件
      try {
        await rootBundle.load('assets/excalidraw/index.html');
        Log.info('✅ [WhiteboardPreload] Preloaded: index.html');
      } catch (e) {
        Log.warn('⚠️ [WhiteboardPreload] Failed to preload index.html: $e');
      }

      // 预加载 flutter_bridge.html（白板桥接文件）
      try {
        await rootBundle.load('assets/excalidraw/flutter_bridge.html');
        Log.info('✅ [WhiteboardPreload] Preloaded: flutter_bridge.html');
      } catch (e) {
        Log.warn('⚠️ [WhiteboardPreload] Failed to preload flutter_bridge.html: $e');
      }

      // 预加载主要的 JavaScript 文件（如果存在）
      final jsFiles = [
        'assets/excalidraw/excalidraw.min.js',
        'assets/excalidraw/excalidraw.js',
        'assets/excalidraw/flutter_bridge.js',
      ];

      for (final jsFile in jsFiles) {
        try {
          await rootBundle.load(jsFile);
          Log.info('✅ [WhiteboardPreload] Preloaded: $jsFile');
          break; // 只加载第一个存在的文件
        } catch (e) {
          // 文件不存在，继续尝试下一个
          continue;
        }
      }

      Log.info('✅ [WhiteboardPreload] Critical assets preloaded');
    } catch (e, stackTrace) {
      Log.error(
        '⚠️ [WhiteboardPreload] Error preloading assets: $e',
        e,
        stackTrace,
      );
      // 不抛出异常，让应用继续启动
    }
  }

  @override
  Future<void> dispose() async {
    await super.dispose();
    Log.info('🗑️ [WhiteboardPreload] Whiteboard preload task disposed');
    // 注意：不要在这里停止 LocalAssetServer
    // 因为它是单例，被所有白板视图共享
    // 服务器应该在应用关闭时统一清理
  }
}

