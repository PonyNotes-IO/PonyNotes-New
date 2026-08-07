import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:appflowy/shared/window_frame_policy.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/app_window_size_manager.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scaled_app/scaled_app.dart';
import 'package:window_manager/window_manager.dart';
import 'package:universal_platform/universal_platform.dart';

const windowsSurfaceChannelName = 'ponynotes/window_surface';
var _windowsSurfaceGeneration = 0;

int nextWindowsSurfaceGeneration() => ++_windowsSurfaceGeneration;

/// 启动阶段（Rust 日志器就绪之前）的窗口初始化轨迹。
///
/// InitAppWindowTask 排在 InitRustSDKTask 之前，此时 Log.* 还写不进日志文件，
/// 整个建窗/设尺寸/居中/显示过程在日志里是一片空白。这里先把轨迹攒起来，
/// 等首帧后表面同步时统一 flush 出去。
final List<String> _windowSetupTrace = <String>[];

void traceWindowSetup(String message) {
  if (_windowSetupTrace.length >= 32) {
    _windowSetupTrace.removeAt(0);
  }
  _windowSetupTrace.add(message);
}

void _flushWindowSetupTrace() {
  if (_windowSetupTrace.isEmpty) {
    return;
  }
  Log.info('[Windows] window setup trace: ${_windowSetupTrace.join(' | ')}');
  _windowSetupTrace.clear();
}

class WindowsSurfaceDimensions {
  const WindowsSurfaceDimensions({
    required this.clientWidth,
    required this.clientHeight,
    required this.childWidth,
    required this.childHeight,
    this.events = const [],
    this.geometry = '',
  });

  factory WindowsSurfaceDimensions.fromMap(Map<dynamic, dynamic> values) {
    int valueFor(String key) {
      final value = values[key];
      if (value is num) {
        return value.toInt();
      }
      throw StateError('Missing Windows surface dimension: $key');
    }

    final rawEvents = values['events'];

    return WindowsSurfaceDimensions(
      clientWidth: valueFor('clientWidth'),
      clientHeight: valueFor('clientHeight'),
      childWidth: valueFor('childWidth'),
      childHeight: valueFor('childHeight'),
      events: rawEvents is List
          ? rawEvents.map((e) => e.toString()).toList(growable: false)
          : const [],
      geometry: values['geometry']?.toString() ?? '',
    );
  }

  final int clientWidth;
  final int clientHeight;
  final int childWidth;
  final int childHeight;

  /// 原生侧记录的窗口几何事件（WM_SIZE / WM_DPICHANGED 等），仅用于诊断。
  final List<String> events;

  /// 原生侧的顶层窗口/子窗口矩形与 DPI 快照，仅用于诊断。
  final String geometry;

  @override
  bool operator ==(Object other) {
    return other is WindowsSurfaceDimensions &&
        clientWidth == other.clientWidth &&
        clientHeight == other.clientHeight &&
        childWidth == other.childWidth &&
        childHeight == other.childHeight;
  }

  @override
  int get hashCode => Object.hash(
        clientWidth,
        clientHeight,
        childWidth,
        childHeight,
      );
}

class WindowsSurfaceSynchronizer {
  WindowsSurfaceSynchronizer({
    MethodChannel? channel,
    bool Function()? isWindows,
  })  : _channel = channel ?? const MethodChannel(windowsSurfaceChannelName),
        _isWindows = isWindows ?? (() => Platform.isWindows);

  final MethodChannel _channel;
  final bool Function() _isWindows;

  Future<WindowsSurfaceDimensions?> synchronize() async {
    if (!_isWindows()) {
      return null;
    }

    final result = await _channel.invokeMapMethod<String, dynamic>(
      'synchronizeSurface',
    );
    if (result == null) {
      return null;
    }

    return WindowsSurfaceDimensions.fromMap(result);
  }
}

/// resync 期间为 true。顶层窗口的 1px 抖动会触发 onWindowResize/onWindowMoved，
/// 此时不能把中间尺寸写进存储，否则保存的窗口尺寸会被污染。
bool _isResynchronizingSurface = false;

bool get isResynchronizingWindowsSurface => _isResynchronizingSurface;

/// 等待一帧结束。带超时，避免窗口不可见等极端情况下把整个启动流程卡住。
Future<void> _waitForFrame() {
  return WidgetsBinding.instance.endOfFrame.timeout(
    const Duration(milliseconds: 500),
    onTimeout: () {},
  );
}

/// 首帧之后强制让引擎重新协商渲染表面。
///
/// 背景（Windows 启动黑边）：启动期窗口几何在首帧之前会变化一次（runner 以 1280x720
/// 逻辑尺寸建窗 → window_manager 改成存储尺寸），而引擎的 resize 握手要等一帧、在
/// runApp() 之前只能超时，首帧因此渲染在与窗口不一致的表面上：画面贴底、上方留黑。
/// 用户手动拖动窗口边缘 1 像素即可恢复。
///
/// 1.1.13 的日志证明：此时 Flutter 的 physicalSize 与原生客户区是**一致的**
/// （matched=true），所以问题不在框架的 metrics，而在其下方的渲染表面；仅抖动子窗口
/// 也无效。因此这里改为由原生侧抖动**顶层窗口** —— 即用户手动拖动的那个对象。
///
/// [maxAttempts] 只影响重试次数；第一次调用就会执行一次 resync，无论 matched 与否。
Future<void> synchronizeWindowsSurfaceAfterFirstFrame({
  required int generation,
  int maxAttempts = 3,
}) async {
  if (!Platform.isWindows) {
    return;
  }

  await _waitForFrame();
  _flushWindowSetupTrace();

  final synchronizer = WindowsSurfaceSynchronizer();
  // 顶层窗口抖动会触发 onWindowResize/onWindowMoved，期间不要持久化窗口尺寸。
  _isResynchronizingSurface = true;

  try {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final dimensions = await synchronizer.synchronize();

      if (dimensions == null) {
        Log.warn(
          '[Windows] surface synchronization returned no dimensions '
          'for generation=$generation',
        );
        return;
      }

      // 原生侧的 resync 抖动是在通道回复之后、从消息循环里执行的（避免阻塞平台线程），
      // 所以这里要多等一帧，让新的 window metrics 到达框架并完成一次重新布局渲染。
      WidgetsBinding.instance.scheduleFrame();
      await _waitForFrame();
      await _waitForFrame();

      final views = PlatformDispatcher.instance.views;
      final dartView = views.isEmpty ? null : views.first;
      final dartSize = dartView?.physicalSize;
      final devicePixelRatio = dartView?.devicePixelRatio;
      final matched = dartSize != null &&
          dartSize.width.round() == dimensions.clientWidth &&
          dartSize.height.round() == dimensions.clientHeight;

      Log.info(
        '[Windows] surface synchronized for generation=$generation '
        'attempt=$attempt/$maxAttempts: matched=$matched, '
        'dartPhysicalSize=${dartSize?.width.round()}x${dartSize?.height.round()}, '
        'devicePixelRatio=$devicePixelRatio, '
        'clientSize=${dimensions.clientWidth}x${dimensions.clientHeight}, '
        'childSize=${dimensions.childWidth}x${dimensions.childHeight}'
        '${dimensions.geometry.isEmpty ? '' : ', geometry=[${dimensions.geometry}]'}'
        '${dimensions.events.isEmpty ? '' : ', nativeEvents=[${dimensions.events.join(' | ')}]'}',
      );

      if (matched) {
        return;
      }
    }

    Log.warn(
      '[Windows] surface still out of sync after $maxAttempts attempts '
      'for generation=$generation',
    );
  } catch (error, stackTrace) {
    Log.warn(
      '[Windows] surface synchronization failed for generation=$generation: '
      '$error',
      error,
      stackTrace,
    );
  } finally {
    // 抖动是异步执行的，多留一帧再恢复尺寸持久化。
    await _waitForFrame();
    _isResynchronizingSurface = false;
  }
}

class InitAppWindowTask extends LaunchTask with WindowListener {
  InitAppWindowTask({this.title = 'PonyNotes'});

  final String title;
  final windowSizeManager = WindowSizeManager();
  static const Size _windowsSafeStartupSize = Size(1280, 720);
  static bool _hasInitializedWindowsWindow = false;

  bool _isDisposed = false;

  @override
  Future<void> initialize(LaunchContext context) async {
    await super.initialize(context);

    if (context.env.isTest || UniversalPlatform.isWeb) {
      return;
    }

    WidgetsFlutterBinding.ensureInitialized();

    if (UniversalPlatform.isMobile) {
      final scale = await windowSizeManager.getScaleFactor();
      // 白板偏移修复后改用标准 WidgetsFlutterBinding，安全屏蔽缩放（缩放暂停用，不崩溃）。
      try {
        ScaledWidgetsFlutterBinding.instance.scaleFactor = (_) => scale;
      } catch (_) {
        Log.info('App 全局缩放暂停用（白板偏移修复改用标准 WidgetsFlutterBinding）');
      }
      return;
    }

    await windowManager.ensureInitialized();
    windowManager.addListener(this);

    if (UniversalPlatform.isWindows && _hasInitializedWindowsWindow) {
      return;
    }

    final storedWindowSize = await windowSizeManager.getSize();
    final windowSize = UniversalPlatform.isWindows
        ? Size(
            math.min(storedWindowSize.width, _windowsSafeStartupSize.width),
            math.min(storedWindowSize.height, _windowsSafeStartupSize.height),
          )
        : storedWindowSize;
    final windowOptions = WindowOptions(
      size: windowSize,
      minimumSize: const Size(
        WindowSizeManager.minWindowWidth,
        WindowSizeManager.minWindowHeight,
      ),
      maximumSize: const Size(
        WindowSizeManager.maxWindowWidth,
        WindowSizeManager.maxWindowHeight,
      ),
      title: title,
    );

    final position = await windowSizeManager.getPosition();

    if (UniversalPlatform.isWindows) {
      final dpr = PlatformDispatcher.instance.views.isEmpty
          ? null
          : PlatformDispatcher.instance.views.first.devicePixelRatio;
      traceWindowSetup(
        'stored=${storedWindowSize.width.round()}x${storedWindowSize.height.round()} '
        'requested=${windowSize.width.round()}x${windowSize.height.round()} dpr=$dpr',
      );

      await windowManager.setTitleBarStyle(
        useCustomWindowTitleBar ? TitleBarStyle.hidden : TitleBarStyle.normal,
      );
      traceWindowSetup('titleBarStyle done');
      await windowManager.waitUntilReadyToShow(windowOptions);
      traceWindowSetup('waitUntilReadyToShow done');
      // Do not restore a saved maximized state before the first Windows
      // show. Creating Flutter's surface directly in maximized bounds can
      // leave the first frame with a stale client area until a manual resize.
      await windowSizeManager.setWindowMaximized(false);
      await windowManager.center();
      traceWindowSetup('center done');
      await windowManager.show();
      await windowManager.focus();
      traceWindowSetup('show+focus done');
      _hasInitializedWindowsWindow = true;
    } else {
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();

        if (position != null) {
          await windowManager.setPosition(position);
        }
      });
    }

    // 白板偏移修复后改用标准 WidgetsFlutterBinding，安全屏蔽启动时的缩放恢复（缩放暂停用，不崩溃）。
    unawaited(
      windowSizeManager.getScaleFactor().then((v) {
        try {
          ScaledWidgetsFlutterBinding.instance.scaleFactor = (_) => v;
        } catch (_) {
          Log.info('App 全局缩放暂停用（白板偏移修复改用标准 WidgetsFlutterBinding）');
        }
      }),
    );
  }

  @override
  Future<void> onWindowMaximize() async {
    if (_isDisposed) {
      return;
    }
    super.onWindowMaximize();
    await windowSizeManager.setWindowMaximized(true);
    await windowSizeManager.setPosition(Offset.zero);
  }

  @override
  Future<void> onWindowUnmaximize() async {
    if (_isDisposed) {
      return;
    }
    super.onWindowUnmaximize();
    await windowSizeManager.setWindowMaximized(false);

    final position = await windowManager.getPosition();
    return windowSizeManager.setPosition(position);
  }

  @override
  Future<void> onWindowEnterFullScreen() async {
    if (_isDisposed) {
      return;
    }
    super.onWindowEnterFullScreen();
    await windowSizeManager.setWindowMaximized(true);
    await windowSizeManager.setPosition(Offset.zero);
  }

  @override
  Future<void> onWindowLeaveFullScreen() async {
    if (_isDisposed) {
      return;
    }
    super.onWindowLeaveFullScreen();
    await windowSizeManager.setWindowMaximized(false);

    final position = await windowManager.getPosition();
    return windowSizeManager.setPosition(position);
  }

  @override
  Future<void> onWindowResize() async {
    if (_isDisposed || _isResynchronizingSurface) {
      return;
    }
    super.onWindowResize();

    if (await windowManager.isMaximized()) {
      return;
    }

    final currentWindowSize = await windowManager.getSize();
    return windowSizeManager.setSize(currentWindowSize);
  }

  @override
  Future<void> onWindowMoved() async {
    if (_isDisposed || _isResynchronizingSurface) {
      return;
    }
    super.onWindowMoved();

    final position = await windowManager.getPosition();
    return windowSizeManager.setPosition(position);
  }

  @override
  Future<void> dispose() async {
    _isDisposed = true;
    await super.dispose();

    windowManager.removeListener(this);
  }
}

/// macOS 窗口恢复处理
/// 当窗口最小化后长时间再打开时，确保窗口正确显示
///
/// 该方法解决以下问题：
/// 1. 窗口最小化后长时间再打开时，窗口可能无法正确显示在桌面
/// 2. 切换笔记后程序崩溃的问题
/// 3. 窗口状态不一致导致的各种异常
Future<void> refreshMacOSWindowAfterMinimize() async {
  if (!Platform.isMacOS) {
    return;
  }

  try {
    // 确保窗口管理器已初始化
    final isInitialized = await windowManager
        .ensureInitialized()
        .then((_) => true)
        .catchError((_) => false);
    if (!isInitialized) {
      Log.warn('[macOS] windowManager not initialized, skipping refresh');
      return;
    }

    // 检查窗口是否被最小化
    final isMinimized =
        await windowManager.isMinimized().catchError((_) => false);
    if (isMinimized) {
      await windowManager.restore().catchError((error) {
        Log.warn('[macOS] failed to restore window: $error');
      });
    }

    // 确保窗口可见并获得焦点
    await windowManager.show().catchError((error) {
      Log.warn('[macOS] failed to show window: $error');
    });

    await windowManager.focus().catchError((error) {
      Log.warn('[macOS] failed to focus window: $error');
    });

    // 额外的安全检查：确保窗口确实在前台
    await Future.delayed(const Duration(milliseconds: 50));
    final isVisible = await windowManager.isVisible().catchError((_) => false);
    if (!isVisible) {
      // 再次尝试显示窗口
      await windowManager.show().catchError((error) {
        Log.warn('[macOS] second attempt to show window failed: $error');
      });
    }

    Log.info('[macOS] refreshed window after minimize');
  } catch (error, stackTrace) {
    Log.warn(
      '[macOS] failed to refresh window after minimize: $error',
      error,
      stackTrace,
    );
  }
}
