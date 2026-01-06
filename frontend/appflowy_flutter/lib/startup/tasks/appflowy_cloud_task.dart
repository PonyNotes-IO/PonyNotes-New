import 'dart:async';
import 'dart:convert';
import 'dart:io';
// platform-specific pending-invite processing (web uses `dart:html`)
import 'pending_invite_stub.dart'
    if (dart.library.html) 'pending_invite_web.dart';

import 'package:app_links/app_links.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/app_widget.dart';
import 'package:appflowy/startup/tasks/deeplink/deeplink_handler.dart';
import 'package:appflowy/startup/tasks/deeplink/expire_login_deeplink_handler.dart';
import 'package:appflowy/startup/tasks/deeplink/invitation_deeplink_handler.dart';
import 'package:appflowy/startup/tasks/deeplink/appflowy_invite_deeplink_handler.dart';
import 'package:appflowy/startup/tasks/deeplink/appflowy_invite_fallback_deeplink_handler.dart';
import 'package:appflowy/startup/tasks/deeplink/login_deeplink_handler.dart';
import 'package:appflowy/startup/tasks/deeplink/open_app_deeplink_handler.dart';
import 'package:appflowy/startup/tasks/deeplink/open_note_deeplink_handler.dart';
import 'package:appflowy/startup/tasks/deeplink/wechat_deeplink_handler.dart';
import 'package:appflowy/startup/tasks/deeplink/douyin_deeplink_handler.dart';
import 'package:appflowy/startup/tasks/deeplink/payment_deeplink_handler.dart';
import 'package:appflowy/user/application/auth/auth_error.dart';
import 'package:appflowy/user/application/password/password_http_service.dart';
import 'package:appflowy/user/application/user_auth_listener.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/set_password_page.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/phone_bind_screen.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter/material.dart';
import 'package:url_protocol/url_protocol.dart';
import 'package:window_manager/window_manager.dart';

const appflowyDeepLinkSchema = 'ponynotes';

class AppFlowyCloudDeepLink {
  AppFlowyCloudDeepLink() {
    _deepLinkHandlerRegistry = DeepLinkHandlerRegistry.instance
      ..register(LoginDeepLinkHandler())
      ..register(PaymentDeepLinkHandler())
      ..register(InvitationDeepLinkHandler())
      ..register(AppflowyInviteDeepLinkHandler())
      ..register(AppflowyInviteFallbackDeepLinkHandler())
      ..register(ExpireLoginDeepLinkHandler())
      ..register(OpenAppDeepLinkHandler())
      ..register(OpenNoteDeepLinkHandler())
      ..register(WeChatDeepLinkHandler())
      ..register(DouYinDeepLinkHandler());

    _deepLinkSubscription = _AppLinkWrapper.instance.listen(
      (Uri? uri) async {
        await _handleUri(uri);
      },
      onError: (Object err, StackTrace stackTrace) {
        Log.error('on DeepLink stream error: ${err.toString()}', stackTrace);
        _deepLinkSubscription.cancel();
      },
    );
    if (Platform.isWindows) {
      // register deep link for Windows
      registerProtocolHandler(appflowyDeepLinkSchema);
    }
  }

  ValueNotifier<DeepLinkResult?>? _stateNotifier = ValueNotifier(null);

  Completer<FlowyResult<UserProfilePB, FlowyError>>? _completer;

  set completer(Completer<FlowyResult<UserProfilePB, FlowyError>>? value) {
    // debug log removed
    _completer = value;
  }

  late final StreamSubscription<Uri?> _deepLinkSubscription;
  late final DeepLinkHandlerRegistry _deepLinkHandlerRegistry;

  Future<void> dispose() async {
    // debug log removed
    await _deepLinkSubscription.cancel();

    _stateNotifier?.dispose();
    _stateNotifier = null;
    completer = null;
  }

  void registerCompleter(
    Completer<FlowyResult<UserProfilePB, FlowyError>> completer,
  ) {
    this.completer = completer;
  }

  VoidCallback subscribeDeepLinkLoadingState(
    ValueChanged<DeepLinkResult> listener,
  ) {
    void listenerFn() {
      if (_stateNotifier?.value != null) {
        listener(_stateNotifier!.value!);
      }
    }

    _stateNotifier?.addListener(listenerFn);
    return listenerFn;
  }

  void unsubscribeDeepLinkLoadingState(VoidCallback listener) =>
      _stateNotifier?.removeListener(listener);

  Future<void> passGotrueTokenResponse(
    GotrueTokenResponsePB gotrueTokenResponse,
  ) async {
    final uri = _buildDeepLinkUri(gotrueTokenResponse);
    await _handleUri(uri);
  }

  Future<void> _handleUri(
    Uri? uri,
  ) async {
    _stateNotifier?.value = DeepLinkResult(state: DeepLinkState.none);

    if (uri == null) {
      Log.error('🔵 [DeepLink] onDeepLinkError: Unexpected empty deep link callback');
      _completer?.complete(FlowyResult.failure(AuthError.emptyDeepLink));
      completer = null;
      return;
    }

    await _deepLinkHandlerRegistry.processDeepLink(
      uri: uri,
      onStateChange: (handler, state) {
        // only handle the login deep link
        if (handler is LoginDeepLinkHandler) {
          _stateNotifier?.value = DeepLinkResult(state: state);
        }
      },
      onResult: (handler, result) async {
        if (handler is LoginDeepLinkHandler &&
            result is FlowyResult<UserProfilePB, FlowyError>) {
          // 先更新 _stateNotifier，让 SignInBloc 能收到结果
          _stateNotifier?.value = DeepLinkResult(
            state: DeepLinkState.finish,
            result: result,
          );
          
          // If there is no completer, runAppFlowy() will be called.
          if (_completer == null) {
            await result.fold(
              (userProfile) async {
                
                try {
                  // 检查用户是否设置了密码
                  // 从 URI 中提取 access_token
                  final accessToken = _extractAccessTokenFromUri(uri);
                  if (accessToken != null) {
                    // 从 userProfile 中提取手机号或邮箱
                    // 优先使用 phone 字段，如果为空则使用 email 字段
                    var hasPhone = userProfile.hasPhone() && userProfile.phone.isNotEmpty;
                    var phoneOrEmail = hasPhone ? userProfile.phone : userProfile.email;
                    var isEmail = !hasPhone;
                    
                    // 如果 phone 和 email 都为空，尝试从 token 中提取手机号
                    if (phoneOrEmail.isEmpty) {
                      try {
                        // 尝试从 JWT token 中提取手机号（token 格式：header.payload.signature）
                        final parts = accessToken.split('.');
                        if (parts.length >= 2) {
                          // 解码 payload（base64url）
                          final payload = parts[1];
                          // 补齐 padding
                          final normalized = payload.replaceAll('-', '+').replaceAll('_', '/');
                          final padding = (4 - normalized.length % 4) % 4;
                          final padded = normalized + ('=' * padding);
                          
                          try {
                            final decoded = base64Decode(padded);
                            final jsonString = utf8.decode(decoded);
                            final json = jsonDecode(jsonString) as Map<String, dynamic>;
                            
                            // 从 token 中提取手机号
                            final tokenPhone = json['phone'] as String?;
                            if (tokenPhone != null && tokenPhone.isNotEmpty) {
                              phoneOrEmail = tokenPhone;
                              hasPhone = true;
                              isEmail = false;
                            }
                          } catch (e) {
                            // 无法从 token 中提取手机号，忽略
                          }
                        }
                      } catch (e) {
                        // 解析 token 失败，忽略
                      }
                    }
                    
                    // 创建无需认证的 PasswordHttpService 实例（checkPasswordStatus 是公开接口）
                    final sharedEnv = getIt<AppFlowyCloudSharedEnv>();
                    final passwordService = PasswordHttpService(
                      baseUrl: sharedEnv.appflowyCloudConfig.gotrue_url,
                      authToken: '', // 公开接口不需要认证
                    );
                    
                    // 使用手机号或邮箱检查密码状态
                    final passwordStatusResult = isEmail
                        ? await passwordService.checkPasswordStatus(email: phoneOrEmail)
                        : await passwordService.checkPasswordStatus(phone: phoneOrEmail);
                    
                    // 处理密码状态检查结果
                    passwordStatusResult.fold(
                      (passwordIsSet) {
                        // 检查是否需要绑定手机号
                        final needBindPhone = _needBindPhone(userProfile.phone);
                        
                        if (!passwordIsSet) {
                          // 用户未设置密码，跳转到设置密码页面
                          // 使用 Future.microtask 确保在下一个事件循环中执行导航
                          Future.microtask(() {
                            final context = AppGlobals.rootNavKey.currentState?.context;
                            if (context != null && context.mounted) {
                              Navigator.of(context, rootNavigator: true).push(
                                MaterialPageRoute(
                                  builder: (context) => SetPasswordPage(
                                    userProfile: userProfile,
                                    phoneOrEmail: phoneOrEmail,
                                    accessToken: accessToken,
                                  ),
                                ),
                              );
                            } else {
                              // Context 不可用，记录错误但不调用 runAppFlowy
                              // 让正常的导航流程处理（SignInBloc 会触发）
                              Log.error('🔵 [DeepLink] Context not available for SetPasswordPage navigation');
                            }
                          });
                        } else if (needBindPhone) {
                          // 用户已设置密码但未绑定手机号，跳转到绑定手机号页面
                          Future.microtask(() {
                            final context = AppGlobals.rootNavKey.currentState?.context;
                            if (context != null && context.mounted) {
                              Navigator.of(context, rootNavigator: true).push(
                                MaterialPageRoute(
                                  // 从应用内部（而非登录页）进入绑定流程：
                                  // - 绑定成功：PhoneBindScreen 会返回 profile，DesktopSignInScreen 会导航到主界面
                                  // - 返回登录：PhoneBindScreen 会执行 signOut + runAppFlowy，回到登录入口
                                  builder: (context) => const PhoneBindScreen(
                                    logoutOnBack: true,
                                  ),
                                ),
                              );
                            } else {
                              Log.error('🔵 [DeepLink] Context not available for PhoneBindScreen navigation');
                            }
                          });
                        } else {
                          // 用户已设置密码且已绑定手机号，不做任何操作
                          // 让 SignInBloc 的状态变化触发正常的导航流程
                          // (见 SignInScreen 的 BlocConsumer listener)

                          // 检查是否有pending的邀请码需要自动加入
                          Future.microtask(() async {
                            await processPendingInvite();
                          });
                        }
                      },
                      (error) {
                        Log.error('[DeepLink] Failed to check password status: ${error.msg}');
                        // 检查密码状态失败，不做任何操作
                        // 让 SignInBloc 的状态变化触发正常的导航流程
                      },
                    );
                  }
                } catch (e, stackTrace) {
                  Log.error('[DeepLink] Exception during password check: $e', stackTrace);
                  // 发生异常，让正常的导航流程处理
                }
              },
              (err) {
                Log.error('🔵 [DeepLink] Login failed: ${err.msg}');
                final context = AppGlobals.rootNavKey.currentState?.context;
                if (context != null && context.mounted) {
                  showToastNotification(
                    message: err.msg,
                  );
                }
              },
            );
          } else {
            Log.info('🔵 [DeepLink] Completer present, completing it');
            _completer?.complete(result);
            completer = null;
          }
        } else if (handler is ExpireLoginDeepLinkHandler) {
          result.onFailure(
            (error) {
              final context = AppGlobals.rootNavKey.currentState?.context;
              if (context != null && context.mounted) {
                showToastNotification(
                  message: error.msg,
                  type: ToastificationType.error,
                );
              }
            },
          );
        } else if (handler is WeChatDeepLinkHandler) {
          // The handler already processed the code; just log
          Log.info('🔵 [DeepLink] WeChatDeepLinkHandler processed');
        } else if (handler is DouYinDeepLinkHandler) {
          // The handler already processed the code; just log
          Log.info('🔵 [DeepLink] DouYinDeepLinkHandler processed');
        }
      },
      onError: (error) {
        Log.error('onDeepLinkError: Unexpected deep link: $error');
        if (_completer == null) {
          final context = AppGlobals.rootNavKey.currentState?.context;
          if (context != null && context.mounted) {
            showToastNotification(
              message: error.msg,
              type: ToastificationType.error,
            );
          }
        } else {
          _completer?.complete(FlowyResult.failure(error));
          completer = null;
        }
      },
    );

    // 处理完 DeepLink 后，在桌面端确保窗口显示并获得焦点（例如应用被最小化时）。
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isFuchsia) {
      try {
        if (await windowManager.isMinimized()) {
          await windowManager.restore();
        }
        await windowManager.show();
        await windowManager.focus();
      } catch (e, stackTrace) {
        Log.error('🔵 [DeepLink] 恢复并聚焦窗口失败: $e', stackTrace);
      }
    }
  }

  Uri? _buildDeepLinkUri(GotrueTokenResponsePB gotrueTokenResponse) {
    final params = <String, String>{};

    if (gotrueTokenResponse.hasAccessToken() &&
        gotrueTokenResponse.accessToken.isNotEmpty) {
      params['access_token'] = gotrueTokenResponse.accessToken;
    }

    if (gotrueTokenResponse.hasExpiresAt()) {
      params['expires_at'] = gotrueTokenResponse.expiresAt.toString();
    }

    if (gotrueTokenResponse.hasExpiresIn()) {
      params['expires_in'] = gotrueTokenResponse.expiresIn.toString();
    }

    if (gotrueTokenResponse.hasProviderRefreshToken() &&
        gotrueTokenResponse.providerRefreshToken.isNotEmpty) {
      params['provider_refresh_token'] =
          gotrueTokenResponse.providerRefreshToken;
    }

    if (gotrueTokenResponse.hasProviderAccessToken() &&
        gotrueTokenResponse.providerAccessToken.isNotEmpty) {
      params['provider_token'] = gotrueTokenResponse.providerAccessToken;
    }

    if (gotrueTokenResponse.hasRefreshToken() &&
        gotrueTokenResponse.refreshToken.isNotEmpty) {
      params['refresh_token'] = gotrueTokenResponse.refreshToken;
    }

    if (gotrueTokenResponse.hasTokenType() &&
        gotrueTokenResponse.tokenType.isNotEmpty) {
      params['token_type'] = gotrueTokenResponse.tokenType;
    }

    if (params.isEmpty) {
      return null;
    }

    final fragment = params.entries
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
        )
        .join('&');

    return Uri.parse('ponynotes://login-callback#$fragment');
  }

  /// 从 URI 中提取 access_token
  String? _extractAccessTokenFromUri(Uri? uri) {
    if (uri == null) return null;
    
    final fragment = uri.fragment;
    if (fragment.isEmpty) return null;
    
    final params = Uri.splitQueryString(fragment);
    return params['access_token'];
  }

}

class InitAppFlowyCloudTask extends LaunchTask {
  UserAuthStateListener? _authStateListener;
  bool isLoggingOut = false;

  @override
  Future<void> initialize(LaunchContext context) async {
    await super.initialize(context);

    if (!isAppFlowyCloudEnabled) {
      return;
    }
    _authStateListener = UserAuthStateListener();

    _authStateListener?.start(
      didSignIn: () {
        isLoggingOut = false;
      },
      onInvalidAuth: (message) async {
        Log.error(message);
        if (!isLoggingOut) {
          await runAppFlowy();
        }
      },
    );
  }

  @override
  Future<void> dispose() async {
    await super.dispose();

    await _authStateListener?.stop();
    _authStateListener = null;
  }
}

// 检查是否需要绑定手机号
// 只有第三方登录（微信、抖音）的用户才有临时手机号（+86temp...），需要绑定
// 邮箱注册的用户手机号为空，不需要绑定
// 手机号注册的用户有正常手机号，不需要绑定
bool _needBindPhone(String? phone) {
  if (phone == null) return false;
  if (phone.isEmpty) return false;
  // 只有临时手机号（第三方登录）才需要绑定
  return phone.startsWith('+86temp');
}


// wrapper for AppLinks to support multiple listeners
class _AppLinkWrapper {
  _AppLinkWrapper._() {
    _appLinkSubscription = _appLinks.uriLinkStream.listen((event) {
      _streamSubscription.sink.add(event);
    });
  }

  static final _AppLinkWrapper instance = _AppLinkWrapper._();

  final AppLinks _appLinks = AppLinks();
  final _streamSubscription = StreamController<Uri?>.broadcast();
  late final StreamSubscription<Uri?> _appLinkSubscription;

  StreamSubscription<Uri?> listen(
    void Function(Uri?) listener, {
    Function? onError,
    bool? cancelOnError,
  }) {
    return _streamSubscription.stream.listen(
      listener,
      onError: onError,
      cancelOnError: cancelOnError,
    );
  }

  void dispose() {
    _streamSubscription.close();
    _appLinkSubscription.cancel();
  }
}
