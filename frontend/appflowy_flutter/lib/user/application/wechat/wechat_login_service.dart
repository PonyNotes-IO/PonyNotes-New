import 'dart:async';

import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flowy_infra/platform_extension.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:fluwx/fluwx.dart' as fluwx;

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
      
      if (PlatformInfo.isDesktopOrTablet) {
        // Desktop platform - use web-based authorization or QR code
        return await _getCodeFromDesktop();
      } else if (PlatformInfo.isMobile) {
        // Mobile platform - should use WeChat SDK
        return await _getCodeFromMobileSDK();
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
  /// For Android: https://developers.weixin.qq.com/doc/oplatform/Mobile_App/WeChat_Login/Development_Guide.html
  /// For iOS: Same as Android
  Future<FlowyResult<String, String>> _getCodeFromMobileSDK() async {
    try {
      // Initialize WeChat SDK
      await _initializeWeChatSDK();
      
      // Check if WeChat is installed
      final isInstalled = await isWeChatInstalled();
      if (!isInstalled) {
        return FlowyResult.failure('WeChat is not installed on this device');
      }
      
      // Create a completer to wait for the authorization code
      final codeCompleter = Completer<String>();
      
      // Set up event handler for WeChat response
      final subscription = fluwx.Fluwx().addSubscriber((event) {
        if (event is fluwx.WeChatAuthResponse) {
          if (event.errCode == 0) {
            // Login success, get code
            final code = event.code;
            if (code != null && code.isNotEmpty) {
              codeCompleter.complete(code);
            } else {
              codeCompleter.completeError('Invalid authorization code');
            }
          } else {
            // Login failed
            codeCompleter.completeError('WeChat login failed: ${event.errCode}');
          }
        }
      });
      if(UniversalPlatform.isIOS) {
        await fluwx.Fluwx().authBy(which: fluwx.PhoneLogin(scope: 'snsapi_userinfo',state: DateTime.now().microsecondsSinceEpoch.toString(),));
      } else {
        await fluwx.Fluwx().authBy(which: fluwx.NormalAuth(scope: 'snsapi_userinfo',state: DateTime.now().microsecondsSinceEpoch.toString(),));
      }
      // Send WeChat authorization request
      // Wait for the authorization code with timeout
      final code = await codeCompleter.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () => throw TimeoutException('WeChat login timed out'),
      );
      
      // Cancel subscription
      subscription.cancel();
      
      return FlowyResult.success(code);
    } on TimeoutException catch (e) {
      Log.error('🟢[WeChatLoginService] WeChat login timed out: $e');
      return FlowyResult.failure('WeChat login timed out');
    } catch (e) {
      Log.error('🟢[WeChatLoginService] Error getting authorization code: $e');
      return FlowyResult.failure('Failed to get WeChat authorization code: $e');
    }
  }

  /// Initializes WeChat SDK
  Future<void> _initializeWeChatSDK() async {
    try {
      // WeChat App ID
      const appId = 'wx3b1a7737f52a004b';
      // Universal Link for iOS
      const universalLink = 'https://www.xiaomabiji.com/ponynotes/';
      
      // Register WeChat API
      await fluwx.Fluwx().registerApi(
        appId: appId,
        universalLink: universalLink,
      );
      
      Log.info('🟢[WeChatLoginService] WeChat SDK initialized successfully');
    } catch (e) {
      Log.error('🟢[WeChatLoginService] Failed to initialize WeChat SDK: $e');
      throw Exception('Failed to initialize WeChat SDK: $e');
    }
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
    const redirectUri = 'https://www.xiaomabiji.com/wechat/callback/';
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
    try {
      // Use fluwx to check if WeChat is installed
      final isInstalled = await fluwx.Fluwx().isWeChatInstalled;
      Log.info('🟢[WeChatLoginService] WeChat installed: $isInstalled');
      return isInstalled;
    } catch (e) {
      Log.error('🟢[WeChatLoginService] Error checking if WeChat is installed: $e');
      return false;
    }
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

