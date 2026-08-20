import 'dart:async';

import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:douyin_login/douyin.dart';
import 'package:flowy_infra/platform_extension.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:url_launcher/url_launcher.dart';
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

  final _douyinPlugin = Douyin();
  String _initState = "none";
  String _code = "";

  /// Sentinel value returned in [getAuthorizationCode] when the device does not
  /// have the Douyin app installed. Callers (e.g. SignInBloc) match this
  /// exact string to display a friendly installation hint instead of the
  /// generic error toast.
  static const String notInstalledError =
      'Douyin is not installed on this device';

  /// Gets the authorization code from DouYin
  ///
  /// Returns the authorization code that can be used to exchange for access token
  ///
  /// Note: This is a placeholder implementation. For production use:
  /// - Android/iOS: Integrate DouYin SDK
  /// - Desktop: Use web-based OAuth flow or QR code scanning
  Future<FlowyResult<String, String>> getAuthorizationCode() async {
    try {
      if (PlatformInfo.isDesktopOrTablet) {
        // Desktop platform - use web-based authorization or QR code
        return await _getCodeFromDesktop();
      } else if (PlatformInfo.isMobile) {
        // Mobile platform - should use DouYin SDK
        return await _getCodeFromMobileSDK();
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
  /// For Android/iOS: Uses douyin_login plugin to integrate DouYin SDK
  Future<FlowyResult<String, String>> _getCodeFromMobileSDK() async {
    try {
      // 1. Initialize DouYin SDK
      await initPlatformState();

      // 2. Check if DouYin is installed
      final isInstalled = await isDouYinInstalled();
      if (!isInstalled) {
        return FlowyResult.failure(notInstalledError);
      }

      // 3. Set up event listener for login response
      final codeCompleter = Completer<String>();

      authorResultState(codeCompleter);

      // 4. Call DouYin login API
      await _douyinPlugin.authorLogin(
        scopeKey: 'trial.whitelist,user_info',
      );

      // 5. Wait for the authorization code with timeout
      final code = await codeCompleter.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () => throw TimeoutException('DouYin login timed out'),
      );

      return FlowyResult.success(code);
    } on TimeoutException catch (e) {
      Log.error('🟢[DouYinLoginService] DouYin login timed out: $e');
      return FlowyResult.failure('DouYin login timed out');
    } catch (e) {
      Log.error('🟢[DouYinLoginService] Error getting authorization code: $e');
      return FlowyResult.failure('Failed to get DouYin authorization code: $e');
    }
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

  void authorResultState(Completer<String> codeCompleter) {
    _douyinPlugin.respStream().listen((response) {
      if (response.code == 0) {
        // Login success
        final authCode = response.authCode;
        if (authCode != null && authCode.isNotEmpty) {
          codeCompleter.complete(authCode);
        } else {
          codeCompleter.completeError('Invalid authorization code');
        }
      } else {
        // Login failed
        codeCompleter
            .completeError('DouYin login failed: ${response.toJson()}');
      }
    });
  }

  Future<void> initPlatformState() async {
    try {
      // iOS SDK 生命周期已在 AppDelegate 的应用启动阶段完成初始化。
      // 此处仅通过插件注册同一个公开 ClientKey 后再发送授权请求。
      await _douyinPlugin.registerDouyinApp(
        apiKey: 'aws8ujfhmwybxv72',
      );
      _initState = 'success';
      Log.info('🟢[DouYinLoginService] DouYin SDK initialized successfully');
    } catch (e) {
      Log.error('🟢[DouYinLoginService] Failed to initialize DouYin SDK: $e');
      _initState = 'failed';
      throw Exception('Failed to initialize DouYin SDK: $e');
    }
  }

  /// Checks if DouYin is installed (mobile only)
  Future<bool> isDouYinInstalled() async {
    if (!UniversalPlatform.isAndroid && !UniversalPlatform.isIOS) {
      return false;
    }

    try {
      if (UniversalPlatform.isAndroid) {
        const douyinPackageName = 'com.ss.android.ugc.aweme';
        final isInstalled =
            await InstalledApps.isAppInstalled(douyinPackageName) ?? false;
        Log.info(
          '🟢[DouYinLoginService] DouYin installed (Android): $isInstalled',
        );
        return isInstalled;
      }

      // installed_apps only implements Android. On iOS, query the URL schemes
      // declared in Info.plist; package/bundle enumeration is not available.
      const douyinSchemes = [
        'douyinopensdk',
        'douyinv1opensdk',
        'douyinliteopensdk',
        'douyinHTSOpenSDK',
        'douyinDSOpenSDK',
        'douyinSelectOpenSDK',
        'douyinSearchOpenSDK',
        'douyinsharesdk',
        'douyinsharesdkLite',
        'douyinsharesdkHTS',
        'douyinsharesdkDS',
        'douyinshareSelect',
        'douyinshareSearch',
        'snssdk1128',
      ];
      for (final scheme in douyinSchemes) {
        if (await canLaunchUrl(Uri.parse('$scheme://'))) {
          Log.info(
            '🟢[DouYinLoginService] DouYin installed (iOS): true, scheme: $scheme',
          );
          return true;
        }
      }

      Log.info(
        '🟢[DouYinLoginService] DouYin installed (iOS): false',
      );
      return false;
    } catch (e) {
      Log.error(
        '🟢[DouYinLoginService] Error checking if DouYin is installed: $e',
      );
      return false;
    }
  }
}
