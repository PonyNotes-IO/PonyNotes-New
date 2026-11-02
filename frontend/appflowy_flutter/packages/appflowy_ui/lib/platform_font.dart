import 'package:flutter/foundation.dart';

// Resolve the empty, persisted "Default" setting only at render time.
// This keeps a Windows font name out of settings synced to other platforms.
String resolvePlatformFontFamily(String fontFamily) {
  if (fontFamily.isEmpty &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.windows) {
    return 'Microsoft YaHei UI';
  }
  return fontFamily;
}

List<String>? get platformFontFamilyFallback =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows
        ? const [
            'Microsoft YaHei UI',
            'Microsoft YaHei',
            'Segoe UI',
            'Segoe UI Emoji',
          ]
        : null;
