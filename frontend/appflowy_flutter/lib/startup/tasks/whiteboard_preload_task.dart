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

      String? indexHtml;
      try {
        indexHtml =
            await rootBundle.loadString('assets/excalidraw/index.html');
        Log.info('✅ [WhiteboardPreload] Preloaded: index.html');
      } catch (e) {
        Log.warn('⚠️ [WhiteboardPreload] Failed to preload index.html: $e');
      }

      final assetPaths = <String>{
        'assets/excalidraw/flutter_bridge.js',
      };

      if (indexHtml != null) {
        final assetRefRegex =
            RegExp(r'''(?:src|href)=["']/assets/([^"']+\.(?:js|css))["']''');
        for (final match in assetRefRegex.allMatches(indexHtml)) {
          assetPaths.add('assets/excalidraw/assets/${match.group(1)}');
        }
      }

      for (final assetPath in assetPaths) {
        try {
          await rootBundle.load(assetPath);
          Log.info('✅ [WhiteboardPreload] Preloaded: $assetPath');
        } catch (e) {
          Log.warn('⚠️ [WhiteboardPreload] Failed to preload $assetPath: $e');
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
