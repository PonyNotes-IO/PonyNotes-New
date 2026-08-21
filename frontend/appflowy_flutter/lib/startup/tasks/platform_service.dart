import 'dart:async';

import 'package:appflowy/core/network_monitor.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/widgets.dart';
import '../startup.dart';

class InitPlatformServiceTask extends LaunchTask {
  bool _disposed = false;
  NetworkListener? _networkListener;

  @override
  LaunchTaskType get type => LaunchTaskType.dataProcessing;

  @override
  Future<void> initialize(LaunchContext context) async {
    await super.initialize(context);

    if (context.env.isTest) {
      return _start();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) {
        unawaited(_start());
      }
    });
  }

  Future<void> _start() async {
    try {
      final listener = getIt<NetworkListener>();
      _networkListener = listener;
      await listener.start();
    } catch (error) {
      Log.error('Failed to initialize network listener: $error');
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await super.dispose();

    await _networkListener?.stop();
  }
}
