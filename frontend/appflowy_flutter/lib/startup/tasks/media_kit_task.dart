import 'dart:io';
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:media_kit/media_kit.dart';
import 'package:appflowy_backend/log.dart';

import '../../util/log_utils.dart';
import '../startup.dart';

class InitMediaKitTask extends LaunchTask {
  const InitMediaKitTask();

  @override
  Future<void> initialize(LaunchContext context) async {
    await super.initialize(context);
    try {
      MediaKit.ensureInitialized();
    } catch (e) {
      LogUtils.error(e.runtimeType);
    }

    // Initialize media_kit for video/audio playback support
    // Skip initialization on macOS as it requires additional native libraries
  }

  @override
  Future<void> dispose() async {
    await super.dispose();
  }
}

