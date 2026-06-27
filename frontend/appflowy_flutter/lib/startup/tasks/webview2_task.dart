import 'dart:io';

import 'package:appflowy_backend/log.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:universal_platform/universal_platform.dart';

import '../startup.dart';

/// Pre-created WebView2 environment.
/// Uses the system-installed WebView2 Evergreen runtime found via the registry.
/// The installer's [Run] section guarantees WebView2 is present on every
/// target machine before the app starts, so no bundled fixed-version is needed.
WebViewEnvironment? _sharedWebViewEnvironment;

/// Returns the shared WebView2 environment, if initialized.
WebViewEnvironment? get sharedWebViewEnvironment => _sharedWebViewEnvironment;

/// Initializes the WebView2 environment.
///
/// This task must run before any WebView is created. It creates a shared
/// WebViewEnvironment that all InAppWebView widgets on Windows will use.
/// The runtime is the system-installed Evergreen version installed by the
/// installer (MicrosoftEdgeWebview2Setup.exe runs silently during setup).
class WebView2InitTask extends LaunchTask {
  const WebView2InitTask();

  @override
  Future<void> initialize(LaunchContext context) async {
    if (!Platform.isWindows) {
      return;
    }

    try {
      _sharedWebViewEnvironment = await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(),
      );
      Log.info('[WebView2] Environment initialized (system Evergreen runtime)');
    } catch (e, stackTrace) {
      Log.error('[WebView2] Failed to initialize WebView2 environment', e, stackTrace);
    }
  }
}
