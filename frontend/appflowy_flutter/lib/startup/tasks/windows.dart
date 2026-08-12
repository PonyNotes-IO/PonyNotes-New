import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/app_window_size_manager.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/material.dart';
import 'package:scaled_app/scaled_app.dart';
import 'package:window_manager/window_manager.dart';
import 'package:universal_platform/universal_platform.dart';

const Size _windowsSafeStartupSize = Size(1280, 720);

Size clampWindowsStartupSize(Size storedSize) => Size(
      math.min(storedSize.width, _windowsSafeStartupSize.width),
      math.min(storedSize.height, _windowsSafeStartupSize.height),
    );

class WindowsStartupWindowState {
  const WindowsStartupWindowState({required this.size});

  final Size size;
}

/// Owns the Dart-side Windows startup transition.
///
/// The native Flutter runner owns window creation and the one-time Show call.
/// Dart only applies persisted geometry after Flutter has rasterized its first
/// frame, so the engine never creates its initial backing surface while the
/// top-level window is being reframed or shown by a second owner.
class WindowsWindowStartupCoordinator {
  WindowsWindowStartupCoordinator({
    required bool Function() isWindows,
    required Future<void> Function() waitForFirstFrame,
    required Future<void> Function(WindowsStartupWindowState) applyState,
  })  : _isWindows = isWindows,
        _waitForFirstFrame = waitForFirstFrame,
        _applyState = applyState;

  final bool Function() _isWindows;
  final Future<void> Function() _waitForFirstFrame;
  final Future<void> Function(WindowsStartupWindowState) _applyState;

  WindowsStartupWindowState? _preparedState;
  Future<void>? _application;

  void prepare(WindowsStartupWindowState state) {
    if (_application == null) {
      _preparedState = state;
    }
  }

  Future<void> applyAfterFirstFrame() {
    if (!_isWindows() || _preparedState == null) {
      return Future<void>.value();
    }
    return _application ??= _apply(_preparedState!);
  }

  Future<void> _apply(WindowsStartupWindowState state) async {
    await _waitForFirstFrame();
    await _applyState(state);
  }
}

final WindowsWindowStartupCoordinator _windowsWindowStartupCoordinator =
    WindowsWindowStartupCoordinator(
  isWindows: () => Platform.isWindows,
  waitForFirstFrame: () =>
      WidgetsBinding.instance.waitUntilFirstFrameRasterized,
  applyState: (state) async {
    await windowManager.setMinimumSize(
      const Size(
        WindowSizeManager.minWindowWidth,
        WindowSizeManager.minWindowHeight,
      ),
    );
    await windowManager.setMaximumSize(
      const Size(
        WindowSizeManager.maxWindowWidth,
        WindowSizeManager.maxWindowHeight,
      ),
    );
    await windowManager.setSize(state.size);
    await WindowSizeManager().setWindowMaximized(false);
    await windowManager.center();
    await windowManager.focus();
  },
);

Future<void> applyWindowsWindowStateAfterFirstFrame() =>
    _windowsWindowStartupCoordinator.applyAfterFirstFrame();

class InitAppWindowTask extends LaunchTask with WindowListener {
  InitAppWindowTask({this.title = 'PonyNotes'});

  final String title;
  final windowSizeManager = WindowSizeManager();
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
        ? clampWindowsStartupSize(storedWindowSize)
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

    if (UniversalPlatform.isWindows) {
      _windowsWindowStartupCoordinator.prepare(
        WindowsStartupWindowState(size: windowSize),
      );
      _hasInitializedWindowsWindow = true;
    } else {
      final position = await windowSizeManager.getPosition();
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
    if (_isDisposed) {
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
    if (_isDisposed) {
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
