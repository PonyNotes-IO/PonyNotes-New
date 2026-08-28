import 'package:appflowy_backend/log.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// iOS 原生 Apple 登录。
///
/// Apple 只在首次授权时返回姓名，服务端登录所需的稳定凭证是
/// identityToken，因此客户端将 identityToken 交给 GoTrue 的 id_token grant
/// 校验，不在客户端保存 Apple 私钥或自行解析 JWT。
class AppleLoginService {
  AppleLoginService._();

  static final AppleLoginService instance = AppleLoginService._();

  Future<FlowyResult<String, String>> getIdentityToken() async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final token = credential.identityToken;
      if (token == null || token.isEmpty) {
        return FlowyResult.failure('APPLE_IDENTITY_TOKEN_MISSING');
      }
      return FlowyResult.success(token);
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) {
        return FlowyResult.failure('CANCELLED:Apple 登录已取消');
      }
      Log.error('[AppleLoginService] Apple authorization failed: $error');
      return FlowyResult.failure('APPLE_AUTHORIZATION_FAILED');
    } catch (error) {
      Log.error('[AppleLoginService] Apple authorization error: $error');
      return FlowyResult.failure('APPLE_AUTHORIZATION_FAILED');
    }
  }
}
