import 'dart:async';
import 'dart:io';

import 'package:appflowy_backend/log.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:ohos_native_bridge/ohos_native_bridge.dart';
import 'package:pdfrx/pdfrx.dart';

import 'startup/startup.dart';
import 'startup/android_privacy_consent.dart';
import 'startup/startup_shell.dart';
import 'workspace/presentation/home/page_windows.dart';
import 'util/performance_trace.dart';

// Stores the initial deep link passed from the native runner.
String? _initialDeepLink;

String get _lockFilePath {
  final appData = Platform.environment['APPDATA'] ??
      Platform.environment['LOCALAPPDATA'] ??
      '.';
  return '$appData\\PonyNotes\\instance.lock';
}

Future<void> _cleanupLegacyLockFile() async {
  final lockFile = File(_lockFilePath);
  try {
    if (await lockFile.exists()) {
      await lockFile.delete();
      Log.info('Single instance: Deleted legacy Dart lock file');
    }
  } catch (e) {
    Log.error('Single instance: Error deleting legacy Dart lock file: $e');
  }
}

Future<void> main(List<String> args) async {
  PerformanceTrace.mark('process_start');

  if (Platform.isWindows) {
    Log.info('DeepLink: ==== App started with args: $args ====');

    final envUrl = Platform.environment['APP_URI'];
    if (envUrl != null) {
      Log.info('DeepLink: Got URL from environment: $envUrl');
    }

    // Windows single-instance handling already lives in the native runner
    // via PonyNotesMutex and deep_link.txt forwarding. Remove the legacy
    // Dart lock file so stale crash leftovers do not force exit(0).
    await _cleanupLegacyLockFile();
  }

  // 白板平台视图偏移修复(2026-06-09)：scaled_app 的 ScaledWidgetsFlutterBinding 在
  // Flutter 3.35 macOS 上会破坏平台视图(WKWebView)的显示↔事件坐标对齐，导致白板工具栏
  // 鼠标选工具偏移、绘图轨迹错位、画布整体漂移。改用标准 WidgetsFlutterBinding 彻底修复。
  // 代价：App 全局缩放(Cmd +/-)暂停用（相关调用已在 hotkeys/windows 中安全屏蔽，按键不再生效也不崩溃）。
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    if (!await AndroidPrivacyConsent.ensureAccepted()) return;
    await AndroidPrivacyConsent.initializePlugins();
  }
  // 用 operatingSystem 字符串判断而非 Platform.isOhos：后者是鸿蒙 fork 私有 getter，
  // 标准 Dart SDK 的 dart:io 没有它，在 Android 构建上会抛 NoSuchMethodError 卡启动。
  if (Platform.operatingSystem == 'ohos') {
    // 鸿蒙：显式注册仍使用旧版 static platform 模式的插件。
    // ohos_native_bridge 的 ArkTS 侧已注册各插件原有的 MethodChannel，
    // 这里把 Dart 侧平台实现切到通用 MethodChannel 实现，使业务调用点无需改动。
    FilePicker.platform = FilePickerIO();
    await OhosNativeBridge.registerOhosPlatformOverrides();
  }
  pdfrxFlutterInitialize();
  PerformanceTrace.mark('flutter_binding_ready');

  if ((Platform.isWindows || Platform.isMacOS || Platform.isLinux) &&
      await PageWindows.initialize()) {
    return;
  }

  if (Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isLinux ||
      Platform.operatingSystem == 'ohos') {
    // Render a Flutter frame before the dependency-heavy application startup.
    // Linux also needs a visible surface while the Rust SDK restores the
    // workspace, which may involve slow cloud requests.
    // HarmonyOS(ohos) 同样需要先渲染启动画面，否则白屏直到 runAppFlowy 完成。
    PerformanceTrace.mark('startup_shell_run_app');
    runApp(const StartupShell());
    await WidgetsBinding.instance.endOfFrame;
    PerformanceTrace.mark('first_frame');
    PerformanceTrace.mark('startup_shell_ready');
  }

  if (args.isNotEmpty) {
    final url = args.first;
    if (url.startsWith('ponynotes://')) {
      Log.info('DeepLink: Received initial URL from command line: $url');
      _initialDeepLink = url;
    }
  }

  await runAppFlowy();
}

String? getInitialDeepLink() => _initialDeepLink;
