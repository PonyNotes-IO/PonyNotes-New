// lib/env/env.dart
import 'package:envied/envied.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

part 'env.g.dart';

@Envied(path: '.env')
abstract class Env {
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
  static const int authenticatorType = _Env.authenticatorType;

  /// AppFlowy Cloud Configuration
  @EnviedField(
    obfuscate: false,
    varName: 'APPFLOWY_CLOUD_URL',
    defaultValue: 'https://api.xiaomabiji.com',
  )
  static const String afCloudUrl =
      kDebugMode ? 'http://47.94.42.183' : _Env.afCloudUrl;

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
      kDebugMode ? 'http://47.94.42.183' : _Env.baseWebDomain;
}
