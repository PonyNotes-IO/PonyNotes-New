import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;

class PlatformInfo {
  PlatformInfo._();

  static bool get isMacOS {
    if (kIsWeb) {
      return false;
    }
    return io.Platform.isMacOS;
  }

  static bool get isWindows {
    if (kIsWeb) {
      return false;
    }
    return io.Platform.isWindows;
  }

  static bool get isLinux {
    if (kIsWeb) {
      return false;
    }
    return io.Platform.isLinux;
  }

  static bool get isDesktopOrWeb {
    if (kIsWeb) {
      return true;
    }
    return isDesktop;
  }

  static bool get isDesktop {
    if (kIsWeb) {
      return false;
    }
    return io.Platform.isWindows || io.Platform.isLinux || io.Platform.isMacOS;
  }

  static bool get isDesktopOrTablet {
    if (kIsWeb) {
      return true;
    }
    return isDesktop || isTablet;
  }

  static bool get isDesktopOrTabletOrWeb {
    return isDesktopOrTablet;
  }

  static bool get isTablet {
    if (kIsWeb) {
      return false;
    }
    if (io.Platform.isIOS) {
      return _isIOSTablet();
    }
    if (io.Platform.isAndroid) {
      return _isAndroidTablet();
    }
    return false;
  }

  static bool get isMobile {
    if (kIsWeb) {
      return false;
    }
    if (io.Platform.isAndroid) {
      return !_isAndroidTablet();
    }
    if (io.Platform.isIOS) {
      return !_isIOSTablet();
    }
    return io.Platform.isAndroid || io.Platform.isIOS;
  }

  static bool get isNotMobile {
    if (kIsWeb) {
      return false;
    }
    return !isMobile;
  }

  static bool _isIOSTablet() {
    return io.Platform.localHostname.contains('iPad') ||
        io.Platform.operatingSystemVersion.contains('iPad');
  }

  static bool _isAndroidTablet() {
    try {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isNotEmpty) {
        final view = views.first;
        final shortestSide = view.physicalSize.shortestSide;
        final devicePixelRatio = view.devicePixelRatio;
        final shortestSideInDp = shortestSide / devicePixelRatio;
        return shortestSideInDp >= 600;
      }
    } catch (_) {
    }
    return false;
  }
}