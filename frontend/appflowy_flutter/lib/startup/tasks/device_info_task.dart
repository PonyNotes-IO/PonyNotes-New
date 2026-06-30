import 'dart:io';

import 'package:appflowy_backend/log.dart';
import 'package:auto_updater/auto_updater.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:version/version.dart';

import '../startup.dart';
import '../../user/application/auth/device_id.dart';

class ApplicationInfo {
  static int androidSDKVersion = -1;
  static String applicationVersion = '';
  static String buildNumber = '';
  static String deviceId = '';
  static String architecture = '';
  static String os = '';

  // macOS major version
  static int? macOSMajorVersion;
  static int? macOSMinorVersion;

  // latest version
  static ValueNotifier<String> latestVersionNotifier = ValueNotifier('');
  // the version number is like 0.9.0
  static String get latestVersion => latestVersionNotifier.value;

  // If the latest version is greater than the current version, it means there is an update available
  static bool get isUpdateAvailable {
    try {
      if (latestVersion.isEmpty) {
        return false;
      }
      return Version.parse(latestVersion) > Version.parse(applicationVersion);
    } catch (e) {
      return false;
    }
  }

  // the latest appcast item
  static AppcastItem? _latestAppcastItem;
  static AppcastItem? get latestAppcastItem => _latestAppcastItem;
  static set latestAppcastItem(AppcastItem? value) {
    _latestAppcastItem = value;

    isCriticalUpdateNotifier.value = value?.criticalUpdate == true;
  }

  // is critical update
  static ValueNotifier<bool> isCriticalUpdateNotifier = ValueNotifier(false);
  static bool get isCriticalUpdate => isCriticalUpdateNotifier.value;
}

class ApplicationInfoTask extends LaunchTask {
  const ApplicationInfoTask();

  @override
  Future<void> initialize(LaunchContext context) async {
    await super.initialize(context);
    final DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();
    
    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      ApplicationInfo.applicationVersion = packageInfo.version;
      ApplicationInfo.buildNumber = packageInfo.buildNumber;
    } catch (e) {
      Log.error('Failed to get package info, $e');
      // 如果获取失败，使用默认值
      ApplicationInfo.applicationVersion = '1.0.0';
      ApplicationInfo.buildNumber = '1';
    }

    try {
      if (Platform.isMacOS) {
        final macInfo = await deviceInfoPlugin.macOsInfo;
        ApplicationInfo.macOSMajorVersion = macInfo.majorVersion;
        ApplicationInfo.macOSMinorVersion = macInfo.minorVersion;
      }

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfoPlugin.androidInfo;
        ApplicationInfo.androidSDKVersion = androidInfo.version.sdkInt;
      }

      String? architecture;
      String? os;
      try {
        if (Platform.isAndroid) {
          final AndroidDeviceInfo androidInfo =
              await deviceInfoPlugin.androidInfo;
          architecture = androidInfo.supportedAbis.firstOrNull;
          os = 'android';
        } else if (Platform.isIOS) {
          final IosDeviceInfo iosInfo = await deviceInfoPlugin.iosInfo;
          architecture = iosInfo.utsname.machine;
          os = 'ios';
        } else if (Platform.isMacOS) {
          final MacOsDeviceInfo macInfo = await deviceInfoPlugin.macOsInfo;
          architecture = macInfo.arch;
          os = 'macos';
        } else if (Platform.isWindows) {
          await deviceInfoPlugin.windowsInfo;
          // we only support x86_64 on Windows
          architecture = 'x86_64';
          os = 'windows';
        } else if (Platform.isLinux) {
          await deviceInfoPlugin.linuxInfo;
          // we only support x86_64 on Linux
          architecture = 'x86_64';
          os = 'linux';
        } else {
          architecture = null;
          os = null;
        }
      } catch (e) {
        Log.error('Failed to get platform version, $e');
      }

      ApplicationInfo.deviceId = await getDeviceId();
      ApplicationInfo.architecture = architecture ?? '';
      ApplicationInfo.os = os ?? '';
    } catch (e) {
      Log.error('Failed to get device info, $e');
      // 如果获取失败，使用默认值
      ApplicationInfo.deviceId = '';
      ApplicationInfo.architecture = '';
      ApplicationInfo.os = '';
    }
  }
}
