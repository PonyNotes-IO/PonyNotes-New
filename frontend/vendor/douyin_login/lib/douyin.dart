import './model/resp.dart';

import 'douyin_platform_interface.dart';

class Douyin {
  /// 注册抖音SDK插件
  Future<String> registerDouyinApp({required String apiKey}) {
    return DouyinPlatform.instance.registerDouyinApp(apiKey: apiKey);
  }

  /// 授权抖音登录
  Future<String> authorLogin({required String scopeKey}) {
    return DouyinPlatform.instance.authorLogin(scopeKey: scopeKey);
  }

  /// 接收抖音授权登录结果
  Stream<DouYinResp> respStream() {
    return DouyinPlatform.instance.respStream();
  }
}
