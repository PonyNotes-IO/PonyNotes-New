import 'package:appflowy/startup/tasks/appflowy_cloud_task.dart';
import 'package:appflowy/startup/tasks/deeplink/deeplink_handler.dart';
import 'package:appflowy/user/application/wechat/wechat_login_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';

/// Handles deep links like: ponynotes://wechat-callback?code=XXX&state=YYY
class WeChatDeepLinkHandler extends DeepLinkHandler<void> {
  @override
  bool canHandle(Uri uri) {
    // scheme should be the app's deep link schema (e.g. ponynotes)
    if (uri.scheme != appflowyDeepLinkSchema) {
      return false;
    }
    return uri.host == 'wechat-callback' || uri.path == '/wechat-callback';
  }

  @override
  Future<FlowyResult<void, FlowyError>> handle({
    required Uri uri,
    required DeepLinkStateHandler onStateChange,
  }) async {
    onStateChange(this, DeepLinkState.loading);
    final result = await WeChatLoginService.instance.handleWeChatDeepLink(uri);
    onStateChange(this, DeepLinkState.finish);
    return result;
  }
}

