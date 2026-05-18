import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:media_kit/media_kit.dart';
import 'package:appflowy_backend/log.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:flowy_infra/platform_extension.dart';

import '../../util/log_utils.dart';
import '../startup.dart';

class InitMediaKitTask extends LaunchTask {
  const InitMediaKitTask();

  @override
  Future<void> initialize(LaunchContext context) async {
    await super.initialize(context);
    try {
      if(UniversalPlatform.isAndroid) return;
      Log.info('Initializing MediaKit...');
      MediaKit.ensureInitialized();
      Log.info('MediaKit initialized successfully');
    } catch (e) {
      LogUtils.warning('Failed to initialize MediaKit: $e');
      LogUtils.error(e.runtimeType);
    }
  }

  @override
  Future<void> dispose() async {
    await super.dispose();
  }
}

