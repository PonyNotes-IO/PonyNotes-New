import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flowy_infra/platform_extension.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../startup.dart';

class TabletDetectionTask extends LaunchTask {
  const TabletDetectionTask();

  @override
  Future<void> initialize(LaunchContext context) async {
    await super.initialize(context);
    
    WidgetsFlutterBinding.ensureInitialized();
    
    bool isTablet = false;
    
    try {
      if (Platform.isIOS) {
        final deviceInfoPlugin = DeviceInfoPlugin();
        final iosInfo = await deviceInfoPlugin.iosInfo;
        
        final model = iosInfo.model ?? '';
        final machine = iosInfo.utsname.machine ?? '';
        final name = iosInfo.name ?? '';
        
        isTablet = model.contains('iPad') || 
                   machine.contains('iPad') ||
                   machine.startsWith('iPad') ||
                   name.contains('iPad');
      } else if (Platform.isAndroid) {
        isTablet = PlatformInfo.isTablet;
      } else if (PlatformInfo.isOhos) {
        // 鸿蒙：形态由 ApplicationInfoTask 采集的 deviceType（或屏幕尺寸兜底）决定。
        // 注意此时不再用 setIsTablet 覆盖，PlatformInfo 内部对 ohos 有独立判定。
        isTablet = PlatformInfo.isTablet;
      }
    } catch (e) {
      isTablet = PlatformInfo.isTablet;
    }

    // 鸿蒙使用 PlatformInfo 内部的 ohos 形态判定，不能写入 _isTabletValue，
    // 否则会污染 isMobile/isDesktop 的 ohos 分支（它们优先读形态，但保持数据干净）。
    if (!PlatformInfo.isOhos) {
      PlatformInfo.setIsTablet(isTablet);
    }

    if (isTablet && (Platform.isIOS || Platform.isAndroid)) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }
}
