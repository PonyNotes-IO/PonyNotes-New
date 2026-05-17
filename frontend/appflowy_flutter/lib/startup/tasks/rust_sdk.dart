import 'dart:convert';
import 'dart:io';

import 'package:appflowy/env/backend_env.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/user/application/auth/device_id.dart';
import 'package:appflowy_backend/appflowy_backend.dart';
import 'package:appflowy_backend/log.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../startup.dart';

class InitRustSDKTask extends LaunchTask {
  const InitRustSDKTask({
    this.customApplicationPath,
  });

  // Customize the RustSDK initialization path
  final Directory? customApplicationPath;

  @override
  LaunchTaskType get type => LaunchTaskType.dataProcessing;

  @override
  Future<void> initialize(LaunchContext context) async {
    await super.initialize(context);

    Directory root;
    try {
      root = await getApplicationSupportDirectory();
    } catch (e) {
      Log.error('Failed to get application support directory: $e');
      if (Platform.isAndroid) {
        root = Directory('/data/data/com.xiaomabiji.app.note/cache');
      } else {
        root = Directory('./data');
      }
    }
    final applicationPath = await appFlowyApplicationDataDirectory();
    final dir = customApplicationPath ?? applicationPath;
    final deviceId = await getDeviceId();

    // Pass the environment variables to the Rust SDK
    final env = _makeAppFlowyConfiguration(
      root.path,
      context.config.version,
      dir.path,
      applicationPath.path,
      deviceId,
      rustEnvs: context.config.rustEnvs,
    );
    await context.getIt<FlowySDK>().init(jsonEncode(env.toJson()));
  }
}

AppFlowyConfiguration _makeAppFlowyConfiguration(
  String root,
  String appVersion,
  String customAppPath,
  String originAppPath,
  String deviceId, {
  required Map<String, String> rustEnvs,
}) {
  final env = getIt<AppFlowyCloudSharedEnv>();
  return AppFlowyConfiguration(
    root: root,
    app_version: appVersion,
    custom_app_path: customAppPath,
    origin_app_path: originAppPath,
    device_id: deviceId,
    platform: Platform.operatingSystem,
    authenticator_type: env.authenticatorType.value,
    appflowy_cloud_config: env.appflowyCloudConfig,
    envs: rustEnvs,
  );
}

/// The default directory to store the user data. The directory can be
/// customized by the user via the [ApplicationDataStorage]
Future<Directory> appFlowyApplicationDataDirectory() async {
  try {
    switch (integrationMode()) {
      case IntegrationMode.develop:
        try {
          final Directory documentsDir = await getApplicationSupportDirectory()
              .then((directory) => directory.create());
          return Directory(path.join(documentsDir.path, 'data_dev'));
        } catch (e) {
          Log.error('Failed to get application support directory for develop mode: $e');
          // 使用默认路径
          if (Platform.isAndroid) {
            // 在Android上使用缓存目录作为默认路径
            return Directory('/data/data/com.xiaomabiji.app.note/cache/data_dev');
          } else {
            return Directory('./data_dev');
          }
        }
      case IntegrationMode.release:
        try {
          final Directory documentsDir = await getApplicationSupportDirectory();
          return Directory(path.join(documentsDir.path, 'data'));
        } catch (e) {
          Log.error('Failed to get application support directory for release mode: $e');
          // 使用默认路径
          if (Platform.isAndroid) {
            // 在Android上使用缓存目录作为默认路径
            return Directory('/data/data/com.xiaomabiji.app.note/cache/data');
          } else {
            return Directory('./data');
          }
        }
      case IntegrationMode.unitTest:
      case IntegrationMode.integrationTest:
        return Directory(path.join(Directory.current.path, '.sandbox'));
    }
  } catch (e) {
    Log.error('Failed to get application data directory: $e');
    // 使用默认路径
    if (Platform.isAndroid) {
      // 在Android上使用缓存目录作为默认路径
      return Directory('/data/data/com.xiaomabiji.app/cache/data');
    } else {
      return Directory('./data');
    }
  }
}
