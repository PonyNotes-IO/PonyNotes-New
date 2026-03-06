import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:appflowy/shared/window_frame_policy.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/app_window_size_manager.dart';
import 'package:flutter/material.dart';
import 'package:scaled_app/scaled_app.dart';
import 'package:window_manager/window_manager.dart';
import 'package:universal_platform/universal_platform.dart';

class InitAppWindowTask extends LaunchTask with WindowListener {
  InitAppWindowTask({this.title = 'AppFlowy'});

  final String title;
  final windowSizeManager = WindowSizeManager();
  static const Size _windowsSafeStartupSize = Size(1280, 720);

  @override
  Future<void> initialize(LaunchContext context) async {
    await super.initialize(context);

    // Don't initialize in tests or on web
    if (context.env.isTest || UniversalPlatform.isWeb) {
      return;
    }

    if (UniversalPlatform.isMobile) {
      final scale = await windowSizeManager.getScaleFactor();
      ScaledWidgetsFlutterBinding.instance.scaleFactor = (_) => scale;
      return;
    }

    await windowManager.ensureInitialized();
    windowManager.addListener(this);

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
      await windowManager.setTitleBarStyle(
        useCustomWindowTitleBar ? TitleBarStyle.hidden : TitleBarStyle.normal,
      );
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();

        /// on Windows we maximize the window if it was previously closed
        /// from a maximized state.
        final isMaximized = await windowSizeManager.getWindowMaximized();
        if (isMaximized) {
          await windowManager.maximize();
        } else {
          // Avoid restoring stale coordinates from previous monitor layouts
          // that can place the window in a visually "half-screen" position.
          await windowManager.center();
        }
      });
    } else {
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();

        if (position != null) {
          await windowManager.setPosition(position);
        }
      });
    }

    unawaited(
      windowSizeManager.getScaleFactor().then(
            (v) => ScaledWidgetsFlutterBinding.instance.scaleFactor = (_) => v,
          ),
    );
  }

  @override
  Future<void> onWindowMaximize() async {
    super.onWindowMaximize();
    await windowSizeManager.setWindowMaximized(true);
    await windowSizeManager.setPosition(Offset.zero);
  }

  @override
  Future<void> onWindowUnmaximize() async {
    super.onWindowUnmaximize();
    await windowSizeManager.setWindowMaximized(false);

    final position = await windowManager.getPosition();
    return windowSizeManager.setPosition(position);
  }

  @override
  void onWindowEnterFullScreen() async {
    super.onWindowEnterFullScreen();
    await windowSizeManager.setWindowMaximized(true);
    await windowSizeManager.setPosition(Offset.zero);
  }

  @override
  Future<void> onWindowLeaveFullScreen() async {
    super.onWindowLeaveFullScreen();
    await windowSizeManager.setWindowMaximized(false);

    final position = await windowManager.getPosition();
    return windowSizeManager.setPosition(position);
  }

  @override
  Future<void> onWindowResize() async {
    super.onWindowResize();

    if (await windowManager.isMaximized()) {
      return;
    }

    final currentWindowSize = await windowManager.getSize();
    return windowSizeManager.setSize(currentWindowSize);
  }

  @override
  void onWindowMoved() async {
    super.onWindowMoved();

    final position = await windowManager.getPosition();
    return windowSizeManager.setPosition(position);
  }

  @override
  Future<void> dispose() async {
    await super.dispose();

    windowManager.removeListener(this);
  }
}
