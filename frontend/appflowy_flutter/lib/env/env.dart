// lib/env/env.dart
import 'package:envied/envied.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

part 'env.g.dart';

@Envied(path: '.env')
abstract class Env {
  // Select here so direct Env readers and the Rust SDK share one environment.
  // Profile/release continue using the generated .env values.
  static const String debugCloudUrl = 'http://47.94.42.183';

  // Disable custom cloud configuration - environment is determined at compile time
  // 禁用自定义云配置 - 环境在编译时确定，用户不能手动切换
  static bool get enableCustomCloud {
    return false;
  }

  @EnviedField(
    obfuscate: false,
    varName: 'AUTHENTICATOR_TYPE',
    defaultValue: 2,
  )
  static const int authenticatorType = kDebugMode ? 3 : _Env.authenticatorType;

  /// AppFlowy Cloud Configuration
  @EnviedField(
    obfuscate: false,
    varName: 'APPFLOWY_CLOUD_URL',
    defaultValue: 'https://api.xiaomabiji.com',
  )
  static const String afCloudUrl = kDebugMode ? debugCloudUrl : _Env.afCloudUrl;

  @EnviedField(
    obfuscate: false,
    varName: 'INTERNAL_BUILD',
    defaultValue: '',
  )
  static const String internalBuild = _Env.internalBuild;

  @EnviedField(
    obfuscate: false,
    varName: 'SENTRY_DSN',
    defaultValue: '',
  )
  static const String sentryDsn = _Env.sentryDsn;

  @EnviedField(
    obfuscate: false,
    varName: 'BASE_WEB_DOMAIN',
    defaultValue: 'https://www.xiaomabiji.com',
  )
  static const String baseWebDomain =
      kDebugMode ? debugCloudUrl : _Env.baseWebDomain;
}
