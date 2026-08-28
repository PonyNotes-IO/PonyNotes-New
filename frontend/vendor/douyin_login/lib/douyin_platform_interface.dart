import './model/resp.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'douyin_method_channel.dart';

abstract class DouyinPlatform extends PlatformInterface {
  DouyinPlatform() : super(token: _token);

  static final Object _token = Object();

  static DouyinPlatform _instance = MethodChannelDouyin();

  static DouyinPlatform get instance => _instance;

  static set instance(DouyinPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// 授权回调
  Stream<DouYinResp> respStream() {
    throw UnimplementedError('respStream() has not been implemented');
  }

  /// 注册抖音SDK
  Future<String> registerDouyinApp({required String apiKey}) {
    throw UnimplementedError(
        "registerDouyinApp({required String apiKey}) has not been implemented.");
  }

  /// 授权登录
  Future<String> authorLogin({required String scopeKey}) {
    throw UnimplementedError("authorLogin has not been implemented.");
  }
}
