import 'dart:async';

import 'package:appflowy/startup/tasks/deeplink/deeplink_handler.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/user/application/auth/device_id.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';

class LoginDeepLinkHandler extends DeepLinkHandler<UserProfilePB> {
  @override
  bool canHandle(Uri uri) {
    final containsAccessToken = uri.fragment.contains('access_token');
    if (!containsAccessToken) {
      return false;
    }

    return true;
  }

  @override
  Future<FlowyResult<UserProfilePB, FlowyError>> handle({
    required Uri uri,
    required DeepLinkStateHandler onStateChange,
  }) async {
    Log.info('🟢 [LoginDeepLinkHandler] handle called with URI: ${uri.toString()}');
    final deviceId = await getDeviceId();
    Log.info('🟢 [LoginDeepLinkHandler] deviceId: $deviceId');
    
    final payload = OauthSignInPB(
      authType: AuthTypePB.Server,
      map: {
        AuthServiceMapKeys.signInURL: uri.toString(),
        AuthServiceMapKeys.deviceId: deviceId,
      },
    );

    Log.info('🟢 [LoginDeepLinkHandler] calling onStateChange(loading)');
    onStateChange(this, DeepLinkState.loading);

    Log.info('🟢 [LoginDeepLinkHandler] sending UserEventOauthSignIn to Rust');
    final result = await UserEventOauthSignIn(payload).send();

    Log.info('🟢 [LoginDeepLinkHandler] UserEventOauthSignIn result: ${result.isSuccess ? "success" : "failure"}');
    result.fold(
      (userProfile) {
        Log.info('🟢 [LoginDeepLinkHandler] Login SUCCESS! User email: ${userProfile.email}');
      },
      (error) {
        Log.error('🟢 [LoginDeepLinkHandler] Login FAILED! Error: ${error.msg}');
      },
    );

    Log.info('🟢 [LoginDeepLinkHandler] calling onStateChange(finish)');
    onStateChange(this, DeepLinkState.finish);

    return result;
  }
}
