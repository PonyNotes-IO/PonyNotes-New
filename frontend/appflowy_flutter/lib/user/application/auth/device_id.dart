import 'dart:io';

import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flowy_infra/uuid.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

const String _deviceIdFileName = 'installation_device_id';

String? _cachedDeviceId;
Future<String>? _deviceIdFuture;

Future<String> getDeviceId() async {
  if (integrationMode().isTest) {
    return 'test_device_id';
  }

  final cached = _cachedDeviceId;
  if (cached != null) {
    return cached;
  }

  final inFlight = _deviceIdFuture;
  if (inFlight != null) {
    return inFlight;
  }

  final future = _loadOrCreateInstallationDeviceId();
  _deviceIdFuture = future;
  try {
    final deviceId = await future;
    _cachedDeviceId = deviceId;
    return deviceId;
  } finally {
    if (identical(_deviceIdFuture, future)) {
      _deviceIdFuture = null;
    }
  }
}

Future<String> _loadOrCreateInstallationDeviceId() async {
  try {
    final supportDirectory = await getApplicationSupportDirectory();
    final deviceIdFile =
        File(path.join(supportDirectory.path, _deviceIdFileName));

    if (await deviceIdFile.exists()) {
      final existing = (await deviceIdFile.readAsString()).trim();
      if (existing.isNotEmpty) {
        return existing;
      }
    }

    final deviceId = uuid();
    await deviceIdFile.writeAsString(deviceId, flush: true);
    return deviceId;
  } on PlatformException catch (e) {
    Log.error('Failed to load persistent device id: $e');
  } on IOException catch (e) {
    Log.error('Failed to persist device id: $e');
  } catch (e) {
    Log.error('Unexpected error while loading device id: $e');
  }

  final fallback = uuid();
  _cachedDeviceId = fallback;
  return fallback;
}
