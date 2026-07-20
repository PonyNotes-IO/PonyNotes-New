import 'dart:async';
import 'dart:io' show Platform;

import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flowy_infra/platform_extension.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:universal_platform/universal_platform.dart';
// fluwx 仅在 iOS 端使用 (Android 端因腾讯 SDK 6.8.34 的 PendingIntent bug,
// 改用 MainActivity.kt 内自写的 WeChatBridge 通过 MethodChannel 调用)
import 'package:fluwx/fluwx.dart' as fluwx;

/// Service for handling WeChat login
///
/// Platform routing:
/// - **Android**: 通过 MethodChannel `com.xiaomabiji.app.note/wechat` 调用原生
///   WeChatBridge.kt。绕开腾讯 SDK 6.8.34 的 PendingIntent bug。
/// - **iOS**: 继续使用 fluwx (iOS 上没有这个 bug)。
/// - **Desktop**: Web-based authorization (qrconnect + deep link 回调)。
class WeChatLoginService {
  WeChatLoginService._();

  static final WeChatLoginService instance = WeChatLoginService._();

  static const _channel = MethodChannel('com.xiaomabiji.app.note/wechat');

  /// Sentinel prefix used by [getAuthorizationCode] when the user dismisses the
  /// WeChat auth dialog without granting access. Callers (e.g. SignInBloc) use
  /// it to distinguish a benign user-initiated cancel from a real failure and
  /// avoid surfacing an error toast.
  static const String cancelledPrefix = 'CANCELLED:';

  /// Sentinel value returned in [FlowyResult.failure] when the device does not
  /// have the WeChat app installed. Callers (e.g. SignInBloc) match this exact
  /// string to display a friendly installation hint instead of the generic
  /// "please try again" error.
  static const String notInstalledError =
      'WeChat is not installed on this device';

  Completer<String>? _codeWaiter;
  String? _expectedState;

  /// Gets the authorization code from WeChat
  ///
  /// Returns the authorization code that can be used to exchange for access token
  Future<FlowyResult<String, String>> getAuthorizationCode() async {
    try {
      if (PlatformInfo.isDesktopOrTablet) {
        return await _getCodeFromDesktop();
      } else if (PlatformInfo.isMobile) {
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
  /// Android: MethodChannel → WeChatBridge → 自构造 PendingIntent 绕开腾讯 SDK bug
  /// iOS: fluwx
  Future<FlowyResult<String, String>> _getCodeFromMobileSDK() async {
    try {
      // Android 走自写桥接 (绕过腾讯 SDK 6.8.34 的 PendingIntent bug)
      if (UniversalPlatform.isAndroid) {
        return await _getCodeFromAndroidBridge();
      }
      // iOS 继续用 fluwx
      if (UniversalPlatform.isIOS) {
        return await _getCodeFromIOSFluwx();
      }
      return FlowyResult.failure(
          'WeChat login is only supported on Android/iOS');
    } on TimeoutException catch (e) {
      Log.error('🟢[WeChatLoginService] WeChat login timed out: $e');
      return FlowyResult.failure('WeChat login timed out');
    } catch (e) {
      Log.error('🟢[WeChatLoginService] Error getting authorization code: $e');
      return FlowyResult.failure('Failed to get WeChat authorization code: $e');
    }
  }

  /// Android 端：通过 MethodChannel 调用自写 WeChatBridge
  Future<FlowyResult<String, String>> _getCodeFromAndroidBridge() async {
    // 检查微信是否安装
    final isInstalled = await isWeChatInstalled();
    if (!isInstalled) {
      return FlowyResult.failure(notInstalledError);
    }

    final state = DateTime.now().microsecondsSinceEpoch.toString();

    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'auth',
        <String, dynamic>{'state': state},
      ).timeout(
        const Duration(minutes: 2),
        onTimeout: () => throw TimeoutException('WeChat login timed out'),
      );

      final errCode = (result?['errCode'] as int?) ?? -1;
      final code = result?['code'] as String?;
      final returnedState = result?['state'] as String?;

      Log.info(
        '🟢[WeChatLoginService] Android bridge response: '
        'errCode=$errCode, code=${code == null ? "null" : "${code.substring(0, code.length.clamp(0, 8))}..."}, '
        'state=$returnedState',
      );

      if (errCode == 0 && code != null && code.isNotEmpty) {
        return FlowyResult.success(code);
      }
      // WeChat SDK errCode=-2 / BaseResp.ErrCode.ERR_USER_CANCEL means the user
      // dismissed the auth dialog. Treat it as a benign cancel rather than an error.
      if (errCode == -2) {
        Log.info(
            '🟢[WeChatLoginService] WeChat auth cancelled by user (errCode=-2)');
        return FlowyResult.failure('${cancelledPrefix}WeChat auth cancelled');
      }
      return FlowyResult.failure('WeChat login failed: errCode=$errCode');
    } on PlatformException catch (e) {
      Log.error(
          '🟢[WeChatLoginService] WeChat PlatformException: ${e.code} ${e.message}');
      // The native WeChatBridge raises a PlatformException with code "CANCELLED"
      // when the user backs out of the WeChat auth flow without confirming.
      if (e.code == 'CANCELLED') {
        Log.info(
            '🟢[WeChatLoginService] WeChat auth cancelled by user (PlatformException CANCELLED)');
        return FlowyResult.failure('${cancelledPrefix}WeChat auth cancelled');
      }
      return FlowyResult.failure('WeChat login failed: ${e.message ?? e.code}');
    }
  }

  /// iOS 端：继续用 fluwx (iOS 没有 Android 14 PendingIntent 问题)
  Future<FlowyResult<String, String>> _getCodeFromIOSFluwx() async {
    // Initialize WeChat SDK
    await _initializeWeChatSDK();

    // Check if WeChat is installed
    final isInstalled = await isWeChatInstalled();
    if (!isInstalled) {
      return FlowyResult.failure(notInstalledError);
    }

    // Create a completer to wait for the authorization code
    final codeCompleter = Completer<String>();

    // Set up event handler for WeChat response
    final subscription = fluwx.Fluwx().addSubscriber((event) {
      if (event is fluwx.WeChatAuthResponse) {
        final errCode = event.errCode;
        final errStr = event.errStr ?? '<null>';
        final codePreview = (event.code != null && event.code!.isNotEmpty)
            ? '${event.code!.substring(0, event.code!.length.clamp(0, 8))}...'
            : 'null';
        Log.info(
          '🟢[WeChatLoginService] WeChat response: '
          'errCode=$errCode, errStr=$errStr, code=$codePreview',
        );
        if (errCode == 0) {
          final code = event.code;
          if (code != null && code.isNotEmpty) {
            codeCompleter.complete(code);
          } else {
            codeCompleter.completeError(
              'Invalid authorization code (errCode=0 but code is empty, errStr=$errStr)',
            );
          }
        } else if (errCode == -2) {
          // WeChat SDK ERR_USER_CANCEL: user dismissed the auth dialog.
          Log.info(
              '🟢[WeChatLoginService] WeChat auth cancelled by user (errCode=-2)');
          codeCompleter
              .completeError('${cancelledPrefix}WeChat auth cancelled');
        } else {
          codeCompleter.completeError(
            'WeChat login failed: errCode=$errCode, errStr=$errStr',
          );
        }
      }
    });

    await fluwx.Fluwx().authBy(
      which: fluwx.PhoneLogin(
        scope: 'snsapi_userinfo',
        state: DateTime.now().microsecondsSinceEpoch.toString(),
      ),
    );

    try {
      final code = await codeCompleter.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () => throw TimeoutException('WeChat login timed out'),
      );
      subscription.cancel();
      return FlowyResult.success(code);
    } on TimeoutException {
      subscription.cancel();
      rethrow;
    } catch (e) {
      subscription.cancel();
      // Preserve the cancellation sentinel from the WeChatAuthResponse handler
      // so SignInBloc can recognise user-initiated cancels.
      if (e is String && e.startsWith(cancelledPrefix)) {
        return FlowyResult.failure(e);
      }
      rethrow;
    }
  }

  /// Initializes WeChat SDK (iOS only)
  Future<void> _initializeWeChatSDK() async {
    try {
      const appId = 'wx3b1a7737f52a004b';
      const universalLink = 'https://www.xiaomabiji.com/ponynotes/';

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
  /// Opens the WeChat OAuth URL in the system browser and waits for deep link callback.
  Future<FlowyResult<String, String>> _getCodeFromDesktop() async {
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
    final url =
        'https://open.weixin.qq.com/connect/qrconnect?$query#wechat_redirect';

    try {
      await launchUrlString(url, mode: LaunchMode.externalApplication);

      _codeWaiter = Completer<String>();
      final codeFuture = _codeWaiter!.future;
      final timeout = Future.delayed(
        const Duration(minutes: 2),
        () => throw TimeoutException('WeChat login timed out'),
      );
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
      if (UniversalPlatform.isAndroid) {
        final isInstalled = await _channel.invokeMethod<bool>('isInstalled');
        Log.info(
            '🟢[WeChatLoginService] WeChat installed (android bridge): $isInstalled');
        return isInstalled ?? false;
      }
      // iOS: fluwx
      final isInstalled = await fluwx.Fluwx().isWeChatInstalled;
      Log.info(
          '🟢[WeChatLoginService] WeChat installed (ios fluwx): $isInstalled');
      return isInstalled;
    } catch (e) {
      Log.error(
          '🟢[WeChatLoginService] Error checking if WeChat is installed: $e');
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
