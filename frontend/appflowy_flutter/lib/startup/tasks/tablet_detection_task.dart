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
      }
    } catch (e) {
      isTablet = PlatformInfo.isTablet;
    }
    
    PlatformInfo.setIsTablet(isTablet);
    
    if (isTablet && (Platform.isIOS || Platform.isAndroid)) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }
}
