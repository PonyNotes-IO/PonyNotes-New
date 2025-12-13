import 'dart:async';

import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:universal_platform/universal_platform.dart';

/// Service for handling DouYin (TikTok) login
/// 
/// This service provides a unified interface for DouYin login across different platforms.
/// For mobile platforms (Android/iOS), it should use the DouYin SDK.
/// For desktop platforms (Windows/macOS/Linux), it may use web-based authorization.
class DouYinLoginService {
  DouYinLoginService._();
  
  static final DouYinLoginService instance = DouYinLoginService._();

  Completer<String>? _codeWaiter;
  String? _expectedState;

  /// Gets the authorization code from DouYin
  /// 
  /// Returns the authorization code that can be used to exchange for access token
  /// 
  /// Note: This is a placeholder implementation. For production use:
  /// - Android/iOS: Integrate DouYin SDK
  /// - Desktop: Use web-based OAuth flow or QR code scanning
  Future<FlowyResult<String, String>> getAuthorizationCode() async {
    try {
      Log.info('🟢[DouYinLoginService] Starting DouYin login...');
      
      if (UniversalPlatform.isAndroid || UniversalPlatform.isIOS) {
        // Mobile platform - should use DouYin SDK
        return await _getCodeFromMobileSDK();
      } else if (UniversalPlatform.isWindows || 
                 UniversalPlatform.isMacOS || 
                 UniversalPlatform.isLinux) {
        // Desktop platform - use web-based authorization or QR code
        return await _getCodeFromDesktop();
      } else {
        return FlowyResult.failure(
          'DouYin login is not supported on this platform',
        );
      }
    } catch (e) {
      Log.error('🟢[DouYinLoginService] Error getting authorization code: $e');
      return FlowyResult.failure('Failed to get DouYin authorization code: $e');
    }
  }

  /// Gets authorization code from mobile SDK
  /// 
  /// TODO: Integrate DouYin SDK for mobile platforms
  Future<FlowyResult<String, String>> _getCodeFromMobileSDK() async {
    // TODO: Implement DouYin SDK integration
    // This should:
    // 1. Initialize DouYin SDK
    // 2. Call DouYin login API
    // 3. Get authorization code from callback
    // 4. Return the code
    
    Log.warn('🟢[DouYinLoginService] Mobile SDK integration not yet implemented');
    return FlowyResult.failure(
      'DouYin SDK integration is required for mobile platforms. Please integrate DouYin SDK first.',
    );
  }

  /// Gets authorization code from desktop
  /// 
  /// For desktop platforms, we can:
  /// 1. Use web-based OAuth flow (open browser)
  /// 2. Show QR code for scanning with mobile DouYin
  /// 
  /// Opens the DouYin OAuth URL in the system browser and waits for deep link callback.
  /// 
  /// Note: AppID (Client Key) can be hardcoded here as it's public in OAuth flow.
  /// AppSecret (Client Secret) must NEVER be in frontend code - it's only configured
  /// in backend environment variables (GOTRUE_EXTERNAL_THIRD_PARTY_DOU_YIN_CLIENT_SECRET).
  Future<FlowyResult<String, String>> _getCodeFromDesktop() async {
    // Build DouYin OAuth URL using the configured public callback endpoint.
    // AppID is safe to hardcode as it's public in OAuth URLs
    const appId = 'awwln96o098l1hik';
    const redirectUri = 'https://www.xiaomabiji.com/douyin/callback';
    final state = DateTime.now().microsecondsSinceEpoch.toString();
    _expectedState = state;

    final params = {
      'client_key': appId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': 'user_info',
      'state': state,
    };

    final query = Uri(queryParameters: params).query;
    // DouYin OAuth URL format (需要根据实际抖音开放平台文档调整)
    final url = 'https://open.douyin.com/platform/oauth/connect?$query';

    try {
      Log.info('🟢[DouYinLoginService] Opening DouYin OAuth URL: $url');
      await launchUrlString(url, mode: LaunchMode.externalApplication);

      // Wait for deep link callback (app scheme)
      _codeWaiter = Completer<String>();
      final codeFuture = _codeWaiter!.future;
      final timeout = Future.delayed(const Duration(minutes: 2),
          () => throw TimeoutException('DouYin login timed out'));
      final code = await Future.any([codeFuture, timeout]);
      return FlowyResult.success(code as String);
    } on TimeoutException catch (e) {
      _reset();
      Log.error('🟢[DouYinLoginService] DouYin login timed out: $e');
      return FlowyResult.failure('DouYin login timed out');
    } catch (e) {
      _reset();
      Log.error('🟢[DouYinLoginService] Failed to start DouYin login: $e');
      return FlowyResult.failure('Failed to start DouYin login: $e');
    }
  }

  /// Checks if DouYin is installed (mobile only)
  Future<bool> isDouYinInstalled() async {
    if (!UniversalPlatform.isAndroid && !UniversalPlatform.isIOS) {
      return false;
    }
    
    // TODO: Implement DouYin installation check using SDK
    // This requires DouYin SDK integration
    return false;
  }

  /// Called by deep link handler when the browser redirects to app scheme:
  /// e.g. ponynotes://douyin-callback?code=XXX&state=YYY
  Future<FlowyResult<void, FlowyError>> handleDouYinDeepLink(Uri uri) async {
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

