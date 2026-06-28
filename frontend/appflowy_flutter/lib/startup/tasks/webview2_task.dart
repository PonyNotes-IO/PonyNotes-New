import 'dart:io';

import 'package:appflowy_backend/log.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:universal_platform/universal_platform.dart';

import '../startup.dart';

/// Pre-created WebView2 environment.
///
/// On Windows, WebView2 needs a writable directory to store its user data
/// (cache, cookies, local storage, Crashpad dumps, etc.). The default is
/// `{exe}.WebView2` next to the executable. When the app is installed under
/// `C:\Program Files\` (or any other UAC-protected location) the Edge child
/// process can't create that directory, which causes every InAppWebView
/// (third-party login QR dialogs, payment page, whiteboard, handwriting
/// canvas, legal documents) to fail to initialize.
///
/// We override `userDataFolder` with a writable path under
/// `%APPDATA%\PonyNotes\WebView2\` so it works no matter where the app is
/// installed (system drive, secondary drive, portable, etc.).
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
    await super.initialize(context);

    if (!Platform.isWindows) {
      return;
    }

    try {
      final availableVersion = await WebViewEnvironment.getAvailableVersion();
      if (availableVersion == null) {
        Log.error(
          '[WebView2] No WebView2 Runtime found on this machine. '
          'The installer should have installed it.',
        );
        return;
      }

      // ApplicationSupportDirectory maps to %APPDATA%\<AppName>\
      // on Windows, which is always writable for the current user.
      String userDataFolder;
      try {
        final supportDir = await getApplicationSupportDirectory();
        userDataFolder = p.join(supportDir.path, 'WebView2');
      } catch (e) {
        // Fallback: %LOCALAPPDATA%\<AppName>\WebView2\
        Log.warn(
          '[WebView2] getApplicationSupportDirectory failed, '
          'falling back to getApplicationDocumentsDirectory: $e',
        );
        final fallback = await getApplicationDocumentsDirectory();
        userDataFolder = p.join(fallback.path, 'WebView2');
      }

      // Make sure the directory exists before WebView2 tries to use it.
      final dir = Directory(userDataFolder);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      _sharedWebViewEnvironment = await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(
          userDataFolder: userDataFolder,
        ),
      );
      Log.info(
        '[WebView2] Environment initialized '
        '(runtime=$availableVersion, userDataFolder=$userDataFolder)',
      );
    } catch (e, stackTrace) {
      Log.error(
        '[WebView2] Failed to initialize WebView2 environment',
        e,
        stackTrace,
      );
    }
  }
}
