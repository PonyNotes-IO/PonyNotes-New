import 'dart:async';
import 'dart:io' show Platform;

import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flowy_infra/platform_extension.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:universal_platform/universal_platform.dart';
// fluwx 用于保留 iOS 微信安装状态检查；iOS 登录授权由 Runner 原生桥接处理。
import 'package:fluwx/fluwx.dart' as fluwx;

/// Service for handling WeChat login
///
/// Platform routing:
/// - **Android**: 通过 MethodChannel `com.xiaomabiji.app.note/wechat` 调用原生
///   WeChatBridge.kt。绕开腾讯 SDK 6.8.34 的 PendingIntent bug。
/// - **iOS**: 通过 Runner 原生桥接调用微信 SDK 的 sendAuthReq。
/// - **Desktop**: Web-based authorization (qrconnect + deep link 回调)。
class WeChatLoginService {
  WeChatLoginService._() {
    _iosSDKChannel.setMethodCallHandler(_handleIOSSDKCallback);
  }

  static final WeChatLoginService instance = WeChatLoginService._();

  static const _channel = MethodChannel('com.xiaomabiji.app.note/wechat');
  static const _iosSDKChannel = MethodChannel('ponynotes/wechat_sdk');

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
  Completer<String>? _iosCodeWaiter;
  String? _iosExpectedState;

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
  /// iOS: Runner 原生微信授权桥接
  Future<FlowyResult<String, String>> _getCodeFromMobileSDK() async {
    try {
      // Android 走自写桥接 (绕过腾讯 SDK 6.8.34 的 PendingIntent bug)
      if (UniversalPlatform.isAndroid) {
        return await _getCodeFromAndroidBridge();
      }
      // iOS 使用原生微信授权桥接。
      if (UniversalPlatform.isIOS) {
        return await _getCodeFromIOSNativeSDK();
      }
      return FlowyResult.failure(
        'WeChat login is only supported on Android/iOS',
      );
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
          '🟢[WeChatLoginService] WeChat auth cancelled by user (errCode=-2)',
        );
        return FlowyResult.failure('${cancelledPrefix}WeChat auth cancelled');
      }
      return FlowyResult.failure('WeChat login failed: errCode=$errCode');
    } on PlatformException catch (e) {
      Log.error(
        '🟢[WeChatLoginService] WeChat PlatformException: ${e.code} ${e.message}',
      );
      // The native WeChatBridge raises a PlatformException with code "CANCELLED"
      // when the user backs out of the WeChat auth flow without confirming.
      if (e.code == 'CANCELLED') {
        Log.info(
          '🟢[WeChatLoginService] WeChat auth cancelled by user (PlatformException CANCELLED)',
        );
        return FlowyResult.failure('${cancelledPrefix}WeChat auth cancelled');
      }
      return FlowyResult.failure('WeChat login failed: ${e.message ?? e.code}');
    }
  }

  /// iOS 端：通过应用原生桥接调用 WXApi.sendAuthReq。
  ///
  /// fluwx 5.7.5 的 NormalAuth 最终调用 WXApi.sendReq。在当前真机上该
  /// 调用被 SDK 拒绝；而微信 SDK 为登录单独提供了需要当前页面控制器的
  /// sendAuthReq。由原生 AppDelegate 持有这个控制器并接收回调，避免插件
  /// 使用已废弃 keyWindow 的兼容性问题。
  Future<FlowyResult<String, String>> _getCodeFromIOSNativeSDK() async {
    final state = DateTime.now().microsecondsSinceEpoch.toString();
    final codeCompleter = Completer<String>();
    _iosCodeWaiter = codeCompleter;
    _iosExpectedState = state;
    try {
      final response = await _iosSDKChannel.invokeMapMethod<String, dynamic>(
        'requestAuth',
        <String, String>{
          'scope': 'snsapi_userinfo',
          'state': state,
        },
      );
      final registered = response?['registered'] == true;
      final installed = response?['installed'] == true;
      final canOpenWeChatScheme = response?['canOpenWeChatScheme'] == true;
      final requestSent = response?['requestSent'] == true;
      Log.info(
        '🟢[WeChatLoginService] iOS native WeChat auth result: '
        'registered=$registered, installed=$installed, requestSent=$requestSent, '
        'canOpenWeChatScheme=$canOpenWeChatScheme, '
        'sdkVersion=${response?['sdkVersion']}, '
        'supportsOpenApi=${response?['supportsOpenApi']}',
      );
      if (!installed) {
        return FlowyResult.failure(notInstalledError);
      }
      if (!requestSent) {
        return FlowyResult.failure(
          'WeChat native SDK rejected the authorization request '
          '(registered=$registered)',
        );
      }

      final code = await codeCompleter.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () => throw TimeoutException('WeChat login timed out'),
      );
      return FlowyResult.success(code);
    } on TimeoutException {
      rethrow;
    } catch (e) {
      // 保留取消标记，以便 SignInBloc 将用户取消识别为正常流程。
      if (e is String && e.startsWith(cancelledPrefix)) {
        return FlowyResult.failure(e);
      }
      rethrow;
    } finally {
      if (identical(_iosCodeWaiter, codeCompleter)) {
        _iosCodeWaiter = null;
        _iosExpectedState = null;
      }
    }
  }

  Future<void> _handleIOSSDKCallback(MethodCall call) async {
    if (call.method == 'onSDKDiagnostic') {
      final arguments = call.arguments as Map<dynamic, dynamic>?;
      if (arguments != null) {
        Log.info(
          '🟢[WeChatLoginService] iOS SDK diagnostic: '
          '${Map<String, dynamic>.from(arguments)}',
        );
      }
      return;
    }

    if (call.method != 'onAuthResponse') {
      return;
    }
    final arguments = call.arguments as Map<dynamic, dynamic>?;
    final waiter = _iosCodeWaiter;
    if (arguments == null || waiter == null || waiter.isCompleted) {
      return;
    }

    final errCode = arguments['errCode'] as int? ?? -1;
    final errStr = arguments['errStr'] as String? ?? '<null>';
    final code = arguments['code'] as String?;
    final state = arguments['state'] as String?;
    final codePreview = (code != null && code.isNotEmpty)
        ? '${code.substring(0, code.length.clamp(0, 8))}...'
        : 'null';
    Log.info(
      '🟢[WeChatLoginService] iOS native WeChat response: '
      'errCode=$errCode, errStr=$errStr, code=$codePreview, state=$state',
    );

    if (state != _iosExpectedState) {
      Log.warn(
        '🟢[WeChatLoginService] Ignored iOS WeChat response with unexpected state',
      );
      return;
    }
    if (errCode == 0 && code != null && code.isNotEmpty) {
      waiter.complete(code);
    } else if (errCode == -2) {
      waiter.completeError('${cancelledPrefix}WeChat auth cancelled');
    } else {
      waiter.completeError(
        'WeChat login failed: errCode=$errCode, errStr=$errStr',
      );
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
          '🟢[WeChatLoginService] WeChat installed (android bridge): $isInstalled',
        );
        return isInstalled ?? false;
      }
      // iOS: fluwx
      final isInstalled = await fluwx.Fluwx().isWeChatInstalled;
      Log.info(
        '🟢[WeChatLoginService] WeChat installed (ios fluwx): $isInstalled',
      );
      return isInstalled;
    } catch (e) {
      Log.error(
        '🟢[WeChatLoginService] Error checking if WeChat is installed: $e',
      );
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
