import 'dart:io' as io;

import 'package:appflowy_backend/log.dart';
import 'package:flutter/services.dart';

/// Native bridge for opening URLs on Android.
///
/// This is a workaround for [url_launcher_android] 6.x where the Pigeon channel
/// (`dev.flutter.pigeon.url_launcher_android.UrlLauncherApi.*`) fails to
/// register in this project's debug builds (likely due to AGP / compileSdk
/// mismatches in one of the 30+ plugins). We register a MethodChannel in
/// `MainActivity.kt` and call `Intent.ACTION_VIEW` directly, which is the same
/// thing `LaunchMode.externalApplication` would do anyway, but does not depend
/// on `url_launcher_android`'s Pigeon API.
///
/// On non-Android platforms this falls back to the default `url_launcher` so
/// desktop/iOS behavior is unchanged.
class NativeUrlOpener {
  NativeUrlOpener._();

  static const MethodChannel _channel =
      MethodChannel('com.xiaomabiji.app.note/open_url');

  /// Opens [url] in the system browser.
  ///
  /// Returns `true` if the URL was dispatched successfully.
  static Future<bool> open(String url) async {
    if (url.isEmpty) {
      return false;
    }

    // On non-Android platforms, fall back to url_launcher's existing helpers
    // (which work fine on desktop and iOS).
    if (!io.Platform.isAndroid) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('openUrl', {
        'url': url,
      });
      return result ?? false;
    } on MissingPluginException catch (e) {
      Log.error('NativeUrlOpener: channel not registered: $e');
      return false;
    } on PlatformException catch (e) {
      Log.error('NativeUrlOpener: failed to open url: $e');
      return false;
    }
  }
}