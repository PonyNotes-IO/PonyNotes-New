import 'dart:async';

import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/user/application/auth/backend_auth_service.dart';
import 'package:appflowy/user/application/auth/device_id.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flowy_infra/uuid.dart';
import 'package:flutter/material.dart';

/// Only used for testing.
class AppFlowyCloudMockAuthService implements AuthService {
  AppFlowyCloudMockAuthService({String? email})
      : userEmail = email ?? "${uuid()}@appflowy.io";

  final String userEmail;

  final BackendAuthService _appFlowyAuthService =
      BackendAuthService(AuthTypePB.Server);

  @override
  Future<FlowyResult<UserProfilePB, FlowyError>> signUp({
    required String name,
    required String email,
    required String password,
    Map<String, String> params = const {},
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<FlowyResult<GotrueTokenResponsePB, FlowyError>>
      signInWithEmailPassword({
    required String email,
    required String password,
    Map<String, String> params = const {},
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<FlowyResult<UserProfilePB, FlowyError>> signUpWithOAuth({
    required String platform,
    Map<String, String> params = const {},
  }) async {
    final payload = SignInUrlPayloadPB.create()
      ..authenticator = AuthTypePB.Server
      // don't use nanoid here, the gotrue server will transform the email
      ..email = userEmail;

    final deviceId = await getDeviceId();
    final getSignInURLResult = await UserEventGenerateSignInURL(payload).send();

    return getSignInURLResult.fold(
      (urlPB) async {
        final payload = OauthSignInPB(
          authType: AuthTypePB.Server,
          // OauthSignInPB.map 是 $pb.PbMap<String,String>,
          // 工厂构造参数期望 Iterable<MapEntry<String,String>>,
          // 直接传 Map<String,String> 在 Dart 3.8+ 会触发 ambiguous literal。
          // 用 Map.fromEntries 显式转为 Map<String,String>,内部会被 addEntries 接受。
          map: <MapEntry<String, String>>[
            MapEntry<String, String>(AuthServiceMapKeys.signInURL, urlPB.signInUrl),
            MapEntry<String, String>(AuthServiceMapKeys.deviceId, deviceId),
          ],
        );
        Log.info("UserEventOauthSignIn with payload: $payload");
        return UserEventOauthSignIn(payload).send().then((value) {
          value.fold(
            (l) => null,
            (err) {
              debugPrint("mock auth service Error: $err");
              Log.error(err);
            },
          );
          return value;
        });
      },
      (r) {
        debugPrint("mock auth service error: $r");
        return FlowyResult.failure(r);
      },
    );
  }

  @override
  Future<void> signOut() async {
    await _appFlowyAuthService.signOut();
    UserBackendService.clearCurrentUserProfileCache();
  }

  @override
  Future<FlowyResult<UserProfilePB, FlowyError>> signUpAsGuest({
    Map<String, String> params = const {},
  }) async {
    return _appFlowyAuthService.signUpAsGuest();
  }

  @override
  Future<FlowyResult<UserProfilePB, FlowyError>> signInWithMagicLink({
    required String email,
    Map<String, String> params = const {},
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<FlowyResult<UserProfilePB, FlowyError>> getUser() async {
    return UserBackendService.getCurrentUserProfile();
  }

  @override
  Future<FlowyResult<GotrueTokenResponsePB, FlowyError>> signInWithPasscode({
    required String email,
    required String passcode,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<FlowyResult<GotrueTokenResponsePB, FlowyError>> refreshToken() {
    return _appFlowyAuthService.refreshToken();
  }

  @override
  Future<void> updateAuthToken({
    required String accessToken,
    required String refreshToken,
  }) async {
    // Mock implementation - no-op for testing
  }
}
