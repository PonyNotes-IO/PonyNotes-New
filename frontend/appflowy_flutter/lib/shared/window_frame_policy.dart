import 'package:universal_platform/universal_platform.dart';

/// Keep Windows on native title bar to avoid client-area glitches
/// in packaged builds with mixed DPI/multi-monitor setups.
bool get useCustomWindowTitleBar {
  if (!UniversalPlatform.isWindows) {
    return true;
  }
  return false;
}
