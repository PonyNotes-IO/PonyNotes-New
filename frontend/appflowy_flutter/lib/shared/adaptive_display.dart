import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:universal_platform/universal_platform.dart';

enum AdaptiveWindowClass {
  compact,
  medium,
  expanded,
  large,
  extraLarge,
}

class AdaptiveDisplayMetrics {
  const AdaptiveDisplayMetrics({
    required this.windowClass,
    required this.textScale,
    required this.layoutScale,
    required this.hitScale,
  });

  final AdaptiveWindowClass windowClass;
  final double textScale;
  final double layoutScale;
  final double hitScale;

  static AdaptiveDisplayMetrics of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final shortestSide = math.min(size.width, size.height);
    final longestSide = math.max(size.width, size.height);
    final isHeightCompact = size.height < 480;
    final windowClass = _classForWidth(shortestSide);

    if (isHeightCompact) {
      return const AdaptiveDisplayMetrics(
        windowClass: AdaptiveWindowClass.compact,
        textScale: 1.0,
        layoutScale: 1.0,
        hitScale: 1.0,
      );
    }

    final textScale = switch (windowClass) {
      AdaptiveWindowClass.compact => 1.0,
      AdaptiveWindowClass.medium => 1.02,
      AdaptiveWindowClass.expanded => 1.04,
      AdaptiveWindowClass.large => UniversalPlatform.isDesktop ? 1.02 : 1.04,
      AdaptiveWindowClass.extraLarge => 1.04,
    };

    final layoutScale = switch (windowClass) {
      AdaptiveWindowClass.compact => 1.0,
      AdaptiveWindowClass.medium => 1.01,
      AdaptiveWindowClass.expanded => 1.02,
      AdaptiveWindowClass.large => 1.0,
      AdaptiveWindowClass.extraLarge => longestSide >= 2200 ? 1.02 : 1.0,
    };

    return AdaptiveDisplayMetrics(
      windowClass: windowClass,
      textScale: textScale,
      layoutScale: layoutScale,
      hitScale: layoutScale.clamp(1.0, 1.04).toDouble(),
    );
  }

  static AdaptiveWindowClass _classForWidth(double shortestSide) {
    if (shortestSide < 600) {
      return AdaptiveWindowClass.compact;
    }
    if (shortestSide < 840) {
      return AdaptiveWindowClass.medium;
    }
    if (shortestSide < 1200) {
      return AdaptiveWindowClass.expanded;
    }
    if (shortestSide < 1600) {
      return AdaptiveWindowClass.large;
    }
    return AdaptiveWindowClass.extraLarge;
  }
}
