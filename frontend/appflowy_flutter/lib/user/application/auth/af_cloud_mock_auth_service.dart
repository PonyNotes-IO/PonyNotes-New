import 'dart:async';

import 'package:appflowy/features/ai_internal/application/internal_ai_chat_store.dart';
import 'package:appflowy/features/mcp/application/mcp_server_service.dart';
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
          // OauthSignInPB.map 由 protobuf 生成为 map 字段，构造参数类型是
          // Map<String, String>?，直接传 Map 字面量即可。
          map: <String, String>{
            AuthServiceMapKeys.signInURL: urlPB.signInUrl,
            AuthServiceMapKeys.deviceId: deviceId,
          },
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
    try {
      await McpServerService.instance.revoke();
    } catch (_) {
      // MCP 清理失败不能阻断退出登录
    }
    // 对话内容属于上一个账号，退出时清掉
    InternalAiChatStore.instance.reset();
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
