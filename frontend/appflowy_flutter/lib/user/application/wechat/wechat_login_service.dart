import 'dart:async';

import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:universal_platform/universal_platform.dart';

/// Service for handling WeChat login
/// 
/// This service provides a unified interface for WeChat login across different platforms.
/// For mobile platforms (Android/iOS), it should use the WeChat SDK.
/// For desktop platforms (Windows/macOS/Linux), it may use web-based authorization.
class WeChatLoginService {
  WeChatLoginService._();
  
  static final WeChatLoginService instance = WeChatLoginService._();

  Completer<String>? _codeWaiter;
  String? _expectedState;

  /// Gets the authorization code from WeChat
  /// 
  /// Returns the authorization code that can be used to exchange for access token
  /// 
  /// Note: This is a placeholder implementation. For production use:
  /// - Android/iOS: Integrate WeChat SDK (e.g., flutter_wechat_assets_picker or similar)
  /// - Desktop: Use web-based OAuth flow or QR code scanning
  Future<FlowyResult<String, String>> getAuthorizationCode() async {
    try {
      Log.info('🟢[WeChatLoginService] Starting WeChat login...');
      
      if (UniversalPlatform.isAndroid || UniversalPlatform.isIOS) {
        // Mobile platform - should use WeChat SDK
        return await _getCodeFromMobileSDK();
      } else if (UniversalPlatform.isWindows || 
                 UniversalPlatform.isMacOS || 
                 UniversalPlatform.isLinux) {
        // Desktop platform - use web-based authorization or QR code
        return await _getCodeFromDesktop();
      } else {
        return FlowyResult.failure(
          'WeChat login is not supported on this platform',
        );
      }
    } catch (e) {
      Log.error('🟢[WeChatLoginService] Error getting authorization code: $e');
      return FlowyResult.failure('Failed to get WeChat authorization code: $e');
    }
  }

  /// Gets authorization code from mobile SDK
  /// 
  /// TODO: Integrate WeChat SDK for mobile platforms
  /// For Android: https://developers.weixin.qq.com/doc/oplatform/Mobile_App/WeChat_Login/Development_Guide.html
  /// For iOS: Same as Android
  Future<FlowyResult<String, String>> _getCodeFromMobileSDK() async {
    // TODO: Implement WeChat SDK integration
    // This should:
    // 1. Initialize WeChat SDK
    // 2. Call WeChat login API
    // 3. Get authorization code from callback
    // 4. Return the code
    
    Log.warn('🟢[WeChatLoginService] Mobile SDK integration not yet implemented');
    return FlowyResult.failure(
      'WeChat SDK integration is required for mobile platforms. Please integrate WeChat SDK first.',
    );
  }

  /// Gets authorization code from desktop
  /// 
  /// For desktop platforms, we can:
  /// 1. Use web-based OAuth flow (open browser)
  /// 2. Show QR code for scanning with mobile WeChat
  /// 
  /// Opens the WeChat OAuth URL in the system browser and waits for deep link callback.
  Future<FlowyResult<String, String>> _getCodeFromDesktop() async {
    // Build WeChat OAuth URL using the configured public callback endpoint.
    const appId = 'wxf2bf9058a11e9e14';
    const redirectUri = 'https://www.xiaomabiji.com/wechat/callback';
    final state = DateTime.now().microsecondsSinceEpoch.toString();
    _expectedState = state;

    final params = {
      'appid': appId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': 'snsapi_login',
      'state': state,
    };

    final query = Uri(queryParameters: params).query;
    final url = 'https://open.weixin.qq.com/connect/qrconnect?$query#wechat_redirect';

    try {
      Log.info('🟢[WeChatLoginService] Opening WeChat OAuth URL: $url');
      await launchUrlString(url, mode: LaunchMode.externalApplication);

      // Wait for deep link callback (app scheme)
      _codeWaiter = Completer<String>();
      final codeFuture = _codeWaiter!.future;
      final timeout = Future.delayed(const Duration(minutes: 2),
          () => throw TimeoutException('WeChat login timed out'));
      final code = await Future.any([codeFuture, timeout]);
      return FlowyResult.success(code as String);
    } on TimeoutException catch (e) {
      _reset();
      Log.error('🟢[WeChatLoginService] WeChat login timed out: $e');
      return FlowyResult.failure('WeChat login timed out');
    } catch (e) {
      _reset();
      Log.error('🟢[WeChatLoginService] Failed to start WeChat login: $e');
      return FlowyResult.failure('Failed to start WeChat login: $e');
    }
  }

  /// Checks if WeChat is installed (mobile only)
  Future<bool> isWeChatInstalled() async {
    if (!UniversalPlatform.isAndroid && !UniversalPlatform.isIOS) {
      return false;
    }
    
    // TODO: Implement WeChat installation check using SDK
    // This requires WeChat SDK integration
    return false;
  }

  /// Called by deep link handler when the browser redirects to app scheme:
  /// e.g. ponynotes://wechat-callback?code=XXX&state=YYY
  Future<FlowyResult<void, FlowyError>> handleWeChatDeepLink(Uri uri) async {
    final code = uri.queryParameters['code'];
    final state = uri.queryParameters['state'];
    if (code == null || code.isEmpty) {
      return FlowyResult.failure(FlowyError(msg: 'Missing code'));
    }
    if (_expectedState != null && state != _expectedState) {
      return FlowyResult.failure(FlowyError(msg: 'State mismatch'));
    }

    _codeWaiter?.complete(code);
    _reset();
    return FlowyResult.success(null);
  }

  void _reset() {
    _expectedState = null;
    _codeWaiter = null;
  }
}

