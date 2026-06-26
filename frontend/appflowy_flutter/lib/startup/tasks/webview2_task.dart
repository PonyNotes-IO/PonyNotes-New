import 'dart:io';

import 'package:appflowy_backend/log.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:universal_platform/universal_platform.dart';

import '../startup.dart';

/// Pre-created WebView2 environment using the bundled runtime.
/// Used by all InAppWebView widgets on Windows to avoid relying on system WebView2.
WebViewEnvironment? _sharedWebViewEnvironment;

/// Returns the shared WebView2 environment, if initialized.
WebViewEnvironment? get sharedWebViewEnvironment => _sharedWebViewEnvironment;

/// Initializes the WebView2 environment using the bundled runtime on Windows.
///
/// This task must run before any WebView is created. It configures flutter_inappwebview
/// to use the WebView2 runtime bundled in the `webview2_fixed/` directory next to the
/// executable, so the app works even on machines that never had WebView2 installed.
class WebView2InitTask extends LaunchTask {
  const WebView2InitTask();

  @override
  Future<void> initialize(LaunchContext context) async {
    if (!Platform.isWindows) {
      return;
    }

    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final bundledRuntimePath = '$exeDir\\webview2_fixed';

      Log.info('[WebView2] Bundled runtime path: $bundledRuntimePath');

      _sharedWebViewEnvironment = await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(
          browserExecutableFolder: bundledRuntimePath,
        ),
      );

      Log.info('[WebView2] Environment initialized successfully');
    } catch (e, stackTrace) {
      Log.error('[WebView2] Failed to initialize WebView2 environment', e, stackTrace);
    }
  }
}
