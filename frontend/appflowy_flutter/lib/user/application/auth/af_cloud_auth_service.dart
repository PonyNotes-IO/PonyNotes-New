import 'dart:async';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/appflowy_cloud_task.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/user/application/auth/backend_auth_service.dart';
import 'package:appflowy/user/application/password/password_http_service.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:fixnum/fixnum.dart';
import 'package:url_launcher/url_launcher.dart';

import 'auth_error.dart';

class AppFlowyCloudAuthService implements AuthService {
  AppFlowyCloudAuthService();

  final BackendAuthService _backendAuthService = BackendAuthService(
    AuthTypePB.Server,
  );

  static const String _refreshTokenKey = 'appflowy_refresh_token';

  /// Store refresh token securely in local storage
  Future<void> _storeRefreshToken(String refreshToken) async {
    final kv = getIt<KeyValueStorage>();
    await kv.set(_refreshTokenKey, refreshToken);
  }

  /// Retrieve refresh token from local storage
  Future<String?> _getRefreshToken() async {
    final kv = getIt<KeyValueStorage>();
    return await kv.get(_refreshTokenKey);
  }

  /// Clear stored refresh token (e.g., on logout)
  Future<void> _clearRefreshToken() async {
    final kv = getIt<KeyValueStorage>();
    await kv.remove(_refreshTokenKey);
  }

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
    final result = await _backendAuthService.signInWithEmailPassword(
      email: email,
      password: password,
      params: params,
    );

    // Store refresh token on successful login
    result.onSuccess((tokenResponse) async {
      if (tokenResponse.refreshToken.isNotEmpty) {
        await _storeRefreshToken(tokenResponse.refreshToken);
      }
    });

    return result;
  }

  @override
  Future<FlowyResult<UserProfilePB, FlowyError>> signUpWithOAuth({
    required String platform,
    Map<String, String> params = const {},
  }) async {
    final provider = ProviderTypePBExtension.fromPlatform(platform);

    // Get the oauth url from the backend
    final result = await UserEventGetOauthURLWithProvider(
      OauthProviderPB.create()..provider = provider,
    ).send();

    return result.fold(
      (data) async {
        // Open the webview with oauth url
        final uri = Uri.parse(data.oauthUrl);
        final isSuccess = await afLaunchUri(
          uri,
          mode: LaunchMode.externalApplication,
          webOnlyWindowName: '_self',
        );

        final completer = Completer<FlowyResult<UserProfilePB, FlowyError>>();
        if (isSuccess) {
          // The [AppFlowyCloudDeepLink] must be registered before using the
          // [AppFlowyCloudAuthService].
          if (getIt.isRegistered<AppFlowyCloudDeepLink>()) {
            getIt<AppFlowyCloudDeepLink>().registerCompleter(completer);
          } else {
            throw Exception('AppFlowyCloudDeepLink is not registered');
          }
        } else {
          completer.complete(
            FlowyResult.failure(AuthError.unableToGetDeepLink),
          );
        }

        return completer.future;
      },
      (r) => FlowyResult.failure(r),
    );
  }

  @override
  Future<void> signOut() async {
    await _backendAuthService.signOut();
    // Clear stored refresh token on logout
    await _clearRefreshToken();
  }

  @override
  Future<FlowyResult<UserProfilePB, FlowyError>> signUpAsGuest({
    Map<String, String> params = const {},
  }) async {
    return _backendAuthService.signUpAsGuest();
  }

  @override
  Future<FlowyResult<UserProfilePB, FlowyError>> signInWithMagicLink({
    required String email,
    Map<String, String> params = const {},
  }) async {
    return _backendAuthService.signInWithMagicLink(
      email: email,
      params: params,
    );
  }

  @override
  Future<FlowyResult<GotrueTokenResponsePB, FlowyError>> signInWithPasscode({
    required String email,
    required String passcode,
  }) async {
    final result = await _backendAuthService.signInWithPasscode(
      email: email,
      passcode: passcode,
    );

    // Store refresh token on successful login
    result.onSuccess((tokenResponse) async {
      if (tokenResponse.refreshToken.isNotEmpty) {
        await _storeRefreshToken(tokenResponse.refreshToken);
      }
    });

    return result;
  }

  @override
  Future<FlowyResult<UserProfilePB, FlowyError>> getUser() async {
    return UserBackendService.getCurrentUserProfile();
  }

  @override
  Future<FlowyResult<GotrueTokenResponsePB, FlowyError>> refreshToken() async {
    try {
      // Get the stored refresh token from secure storage
      final refreshToken = await _getRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        return FlowyResult.failure(
          FlowyError.create()
            ..code = ErrorCode.UserUnauthorized
            ..msg = "No refresh token available",
        );
      }

      // Create a PasswordHttpService to refresh the token
      final sharedEnv = getIt<AppFlowyCloudSharedEnv>();
      final passwordService = PasswordHttpService(
        baseUrl: sharedEnv.appflowyCloudConfig.gotrue_url,
        authToken: '', // No auth token needed for refresh
      );

      // Call the refresh token method
      final refreshResult = await passwordService.refreshToken(refreshToken);

      // Convert the result to GotrueTokenResponsePB
      return refreshResult.fold(
        (tokenMap) async {
          try {
            final gotrueTokenResponse = GotrueTokenResponsePB.create()
              ..accessToken = tokenMap['access_token'] as String? ?? ''
              ..tokenType = tokenMap['token_type'] as String? ?? 'bearer'
              ..expiresIn = Int64((tokenMap['expires_in'] as num?)?.toInt() ?? 3600)
              ..expiresAt = Int64((tokenMap['expires_at'] as num?)?.toInt() ?? 0)
              ..refreshToken = tokenMap['refresh_token'] as String? ?? '';

            // Store the new refresh token
            if (gotrueTokenResponse.refreshToken.isNotEmpty) {
              await _storeRefreshToken(gotrueTokenResponse.refreshToken);
            }

            // Pass the new tokens to the deep link handler to update the session
            getIt<AppFlowyCloudDeepLink>().passGotrueTokenResponse(gotrueTokenResponse);

            return FlowyResult.success(gotrueTokenResponse);
          } catch (e) {
            return FlowyResult.failure(
              FlowyError.create()
                ..code = ErrorCode.Internal
                ..msg = 'Failed to parse refresh token response: $e',
            );
          }
        },
        (error) => FlowyResult<GotrueTokenResponsePB, FlowyError>.failure(error),
      );
    } catch (e) {
      return FlowyResult.failure(
        FlowyError.create()
          ..code = ErrorCode.Internal
          ..msg = 'Refresh token failed: $e',
      );
    }
  }
}

extension ProviderTypePBExtension on ProviderTypePB {
  static ProviderTypePB fromPlatform(String platform) {
    switch (platform) {
      case 'github':
        return ProviderTypePB.Github;
      case 'google':
        return ProviderTypePB.Google;
      case 'discord':
        return ProviderTypePB.Discord;
      case 'apple':
        return ProviderTypePB.Apple;
      default:
        throw UnimplementedError();
    }
  }
}
