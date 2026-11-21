import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;

/// 鸿蒙设备形态。鸿蒙 fork 上 dart:io 的 isAndroid/isIOS/isWindows/... 全为 false
/// （operatingSystem == 'ohos'），因此需要单独的形态判定层。
/// - phone：手机，走移动端 UI（MobileHomeScreen）
/// - tablet：平板，走桌面/大屏 UI（DesktopHomeScreen）
/// - desktop：2in1 / PC，走桌面 UI（DesktopHomeScreen）
enum OhosDeviceForm { phone, tablet, desktop }

class PlatformInfo {
  PlatformInfo._();

  static bool? _isTabletValue;

  static void setIsTablet(bool value) {
    _isTabletValue = value;
  }

  /// 是否为鸿蒙平台。注意鸿蒙上所有 isXXX 都是 false，必须用 operatingSystem 判定。
  static bool get isOhos {
    if (kIsWeb) {
      return false;
    }
    return io.Platform.operatingSystem == 'ohos';
  }

  /// 鸿蒙设备形态，由 ApplicationInfoTask 从 device_info 的 deviceType 采集后写入。
  /// 可能值：phone / tablet / 2in1 / pc。
  static String? _ohosDeviceType;
  static String? get ohosDeviceType => _ohosDeviceType;
  static void setOhosDeviceType(String? value) {
    _ohosDeviceType = value;
    _cachedOhosForm = null;
  }

  static OhosDeviceForm? _cachedOhosForm;

  /// 解析鸿蒙设备形态：
  /// 1) 优先使用原生上报的 deviceType；
  /// 2) 未采集到时（如早期 Task 早于 ApplicationInfoTask）用屏幕最短边兜底：
  ///    shortestSide >= 600dp 视为平板，否则视为手机。
  /// 这样即便形态数据还没就绪，路由注册与跳转也能用同一个判定，避免 GoException。
  static OhosDeviceForm get _ohosForm {
    if (_cachedOhosForm != null) {
      return _cachedOhosForm!;
    }
    final dt = _ohosDeviceType?.toLowerCase().trim();
    OhosDeviceForm? form;
    if (dt == 'phone') {
      form = OhosDeviceForm.phone;
    } else if (dt == 'tablet') {
      form = OhosDeviceForm.tablet;
    } else if (dt == '2in1' || dt == 'pc' || dt == 'desktop') {
      form = OhosDeviceForm.desktop;
    } else {
      final shortestSideInDp = _shortestSideInDp();
      form = (shortestSideInDp != null && shortestSideInDp >= 600)
          ? OhosDeviceForm.tablet
          : OhosDeviceForm.phone;
    }
    _cachedOhosForm = form;
    return form;
  }

  static double? _shortestSideInDp() {
    try {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isNotEmpty) {
        final view = views.first;
        return view.physicalSize.shortestSide / view.devicePixelRatio;
      }
    } catch (_) {}
    return null;
  }

  static bool get isOhosPhone => isOhos && _ohosForm == OhosDeviceForm.phone;
  static bool get isOhosTablet => isOhos && _ohosForm == OhosDeviceForm.tablet;
  static bool get isOhosDesktop => isOhos && _ohosForm == OhosDeviceForm.desktop;

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
    if (isOhos) {
      return isOhosDesktop;
    }
    return io.Platform.isWindows || io.Platform.isLinux || io.Platform.isMacOS;
  }

  static bool get isDesktopOrTablet {
    if (kIsWeb) {
      return true;
    }
    if (isOhos) {
      // 鸿蒙平板与桌面都使用大屏（DesktopHomeScreen）布局。
      return isOhosTablet || isOhosDesktop;
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
    if (isOhos) {
      return isOhosTablet;
    }
    if (_isTabletValue != null) {
      return _isTabletValue!;
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
    if (isOhos) {
      // 鸿蒙手机 = 移动端；平板/桌面 = 大屏，不能走移动端路由。
      return isOhosPhone;
    }
    if (_isTabletValue != null) {
      return (io.Platform.isAndroid || io.Platform.isIOS) && !_isTabletValue!;
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

  /// Android or iOS (phone and tablet). Web and desktop return false.
  ///
  /// Uses [defaultTargetPlatform] rather than [io.Platform] so widget tests can
  /// override the platform. Phone sign-in flows that apply to both mobile
  /// platforms should use this instead of an Android-only check.
  static bool get isAndroidOrIOS {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  static bool _isIOSTablet() {
    try {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isNotEmpty) {
        final view = views.first;
        final shortestSide = view.physicalSize.shortestSide;
        final devicePixelRatio = view.devicePixelRatio;
        final shortestSideInDp = shortestSide / devicePixelRatio;
        return shortestSideInDp >= 550;
      }
    } catch (_) {
    }
    return false;
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
