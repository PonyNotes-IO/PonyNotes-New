import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/appflowy_cloud_task.dart';
import 'package:appflowy/startup/tasks/deeplink/deeplink_handler.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/user/application/password/password_http_service.dart';
import 'package:appflowy/user/application/wechat/wechat_login_service.dart';
import 'package:appflowy/user/application/douyin/douyin_login_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/auth.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart'
    show UserProfilePB;
import 'package:fixnum/fixnum.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'sign_in_bloc.freezed.dart';

class SignInBloc extends Bloc<SignInEvent, SignInState> {
  SignInBloc(this.authService) : super(SignInState.initial()) {
    if (isAppFlowyCloudEnabled) {
      deepLinkStateListener =
          getIt<AppFlowyCloudDeepLink>().subscribeDeepLinkLoadingState((value) {
        if (isClosed) return;

        add(SignInEvent.deepLinkStateChange(value));
      });

      // 使用 gotrue_url 而不是 base_url，因为 PasswordHttpService 需要直接连接到 GoTrue 服务
      final sharedEnv = getIt<AppFlowyCloudSharedEnv>();
      passwordService = PasswordHttpService(
        baseUrl: sharedEnv.appflowyCloudConfig.gotrue_url,
        authToken:
            '', // the user is not signed in yet, the auth token should be empty
      );
    }

    on<SignInEvent>(
      (event, emit) async {
        await event.when(
          signInWithEmailAndPassword: (email, password) async =>
              _onSignInWithEmailAndPassword(
            emit,
            email: email,
            password: password,
          ),
          signInWithOAuth: (platform) async => _onSignInWithOAuth(
            emit,
            platform: platform,
          ),
          signInAsGuest: () async => _onSignInAsGuest(emit),
          signInWithMagicLink: (email) async => _onSignInWithMagicLink(
            emit,
            email: email,
          ),
          signInWithPasscode: (email, passcode) async => _onSignInWithPasscode(
            emit,
            email: email,
            passcode: passcode,
          ),
          deepLinkStateChange: (result) => _onDeepLinkStateChange(emit, result),
          cancel: () {
            emit(
              state.copyWith(
                isSubmitting: false,
                emailError: null,
                passwordError: null,
                successOrFail: null,
              ),
            );
          },
          emailChanged: (email) async {
            emit(
              state.copyWith(
                email: email,
                emailError: null,
                successOrFail: null,
              ),
            );
          },
          passwordChanged: (password) async {
            emit(
              state.copyWith(
                password: password,
                passwordError: null,
                successOrFail: null,
              ),
            );
          },
          switchLoginType: (type) {
            emit(state.copyWith(loginType: type));
          },
          forgotPassword: (email) => _onForgotPassword(emit, email: email),
          validateResetPasswordToken: (email, token, phone) async =>
              _onValidateResetPasswordToken(
            emit,
            email: email,
            token: token,
            phone: phone,
          ),
          resetPassword: (email, newPassword) async => _onResetPassword(
            emit,
            email: email,
            newPassword: newPassword,
          ),
          checkPasswordStatus: (email, phone) async => _onCheckPasswordStatus(
            emit,
            email: email,
            phone: phone,
          ),
          signInWithWeChat: () async => _onSignInWithWeChat(emit),
          signInWithDouYin: () async => _onSignInWithDouYin(emit),
          clearPhoneBindingRequirement: () {
            emit(
              state.copyWith(
                requiresPhoneBinding: false,
              ),
            );
          },
          wechatCodeReceived: (code) async {
            await _completeWeChatLogin(emit, code);
          },
          douyinCodeReceived: (code) async {
            await _completeDouYinLogin(emit, code);
          },
          phoneBindingComplete: (userProfile) {
            // 手机号绑定成功后，设置登录成功状态
            emit(
              state.copyWith(
                isSubmitting: false,
                requiresPhoneBinding: false,
                successOrFail: FlowyResult.success(userProfile),
              ),
            );
          },
          reset: () {
            // 重置登录状态（退出登录时使用）
            emit(SignInState.initial());
          },
        );
      },
    );
  }

  final AuthService authService;
  PasswordHttpService? passwordService;
  VoidCallback? deepLinkStateListener;

  @override
  Future<void> close() {
    deepLinkStateListener?.call();
    if (isAppFlowyCloudEnabled && deepLinkStateListener != null) {
      getIt<AppFlowyCloudDeepLink>().unsubscribeDeepLinkLoadingState(
        deepLinkStateListener!,
      );
    }
    return super.close();
  }

  Future<void> _onDeepLinkStateChange(
    Emitter<SignInState> emit,
    DeepLinkResult result,
  ) async {
    final deepLinkState = result.state;

    switch (deepLinkState) {
      case DeepLinkState.none:
        break;
      case DeepLinkState.loading:
        emit(
          state.copyWith(
            isSubmitting: true,
            emailError: null,
            passwordError: null,
            successOrFail: null,
          ),
        );
      case DeepLinkState.finish:
        final newState = result.result?.fold(
          (s) {
            // 检查是否需要绑定手机号（第三方登录且手机号是临时手机号）
            final needBindPhone = s.phone.isNotEmpty && s.phone.startsWith('+86temp');
            if (needBindPhone) {
              // 第三方登录需要绑定手机号，暂不设置 successOrFail
              // 等绑定成功后再设置
              return state.copyWith(
                isSubmitting: false,
                requiresPhoneBinding: true,
                successOrFail: null, // 不设置成功状态，等绑定完成后再设置
              );
            } else {
              // 不需要绑定手机号，直接设置成功状态
            return state.copyWith(
              isSubmitting: false,
              successOrFail: FlowyResult.success(s),
            );
            }
          },
          (f) => _stateFromCode(f),
        );
        if (newState != null) {
          emit(newState);
        }
      case DeepLinkState.error:
        emit(state.copyWith(isSubmitting: false));
    }
  }

  Future<void> _onSignInWithEmailAndPassword(
    Emitter<SignInState> emit, {
    required String email,
    required String password,
  }) async {
    emit(
      state.copyWith(
        isSubmitting: true,
        emailError: null,
        passwordError: null,
        successOrFail: null,
      ),
    );

    // 检测输入是手机号还是邮箱
    final bool isPhone = _isValidPhone(email);
    final bool isEmail = _isValidEmail(email);

    // 如果是手机号，直接调用 GoTrue API
    if (isPhone && passwordService != null) {
      final result = await passwordService!.signInWithPassword(
        phone: email,
        password: password,
      );

      emit(
        result.fold(
          (tokenMap) {
            // 将 JSON map 转换为 GotrueTokenResponsePB
            try {
              final gotrueTokenResponse = GotrueTokenResponsePB.create()
                ..accessToken = tokenMap['access_token'] as String? ?? ''
                ..tokenType = tokenMap['token_type'] as String? ?? 'bearer'
                ..expiresIn = Int64((tokenMap['expires_in'] as num?)?.toInt() ?? 3600)
                ..expiresAt = Int64((tokenMap['expires_at'] as num?)?.toInt() ?? 0)
                ..refreshToken = tokenMap['refresh_token'] as String? ?? ''
                ..providerAccessToken = tokenMap['provider_access_token'] as String? ?? ''
                ..providerRefreshToken = tokenMap['provider_refresh_token'] as String? ?? '';

              getIt<AppFlowyCloudDeepLink>().passGotrueTokenResponse(
                gotrueTokenResponse,
              );
              return state.copyWith(
                isSubmitting: false,
              );
            } catch (e) {
              Log.error('🦋[SignInBloc] 转换 token 响应失败: $e');
              return _stateFromCode(
                FlowyError.create()
                  ..code = ErrorCode.Internal
                  ..msg = 'Failed to parse token response: $e',
              );
            }
          },
          (error) => _stateFromCode(error),
        ),
      );
      return;
    }

    // 如果是邮箱，使用原有的方法
    if (isEmail) {
      final result = await authService.signInWithEmailPassword(
        email: email,
        password: password,
      );
      emit(
        result.fold(
          (gotrueTokenResponse) {
            getIt<AppFlowyCloudDeepLink>().passGotrueTokenResponse(
              gotrueTokenResponse,
            );
            return state.copyWith(
              isSubmitting: false,
            );
          },
          (error) => _stateFromCode(error),
        ),
      );
      return;
    }

    // 如果既不是手机号也不是邮箱，返回错误
    emit(
      _stateFromCode(
        FlowyError.create()
          ..code = ErrorCode.InvalidParams
          ..msg = 'Invalid email or phone format',
      ),
    );
  }

  // 验证手机号格式（中国手机号）
  bool _isValidPhone(String phone) {
    final phoneRegex = RegExp(r'^1[3-9]\d{9}$');
    return phoneRegex.hasMatch(phone);
  }

  // 验证邮箱格式
  bool _isValidEmail(String email) {
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return emailRegex.hasMatch(email);
  }

  Future<void> _onSignInWithOAuth(
    Emitter<SignInState> emit, {
    required String platform,
  }) async {
    emit(
      state.copyWith(
        isSubmitting: true,
        emailError: null,
        passwordError: null,
        successOrFail: null,
      ),
    );

    final result = await authService.signUpWithOAuth(platform: platform);
    emit(
      result.fold(
        (userProfile) => state.copyWith(
          isSubmitting: false,
          successOrFail: FlowyResult.success(userProfile),
        ),
        (error) => _stateFromCode(error),
      ),
    );
  }

  Future<void> _onSignInWithMagicLink(
    Emitter<SignInState> emit, {
    required String email,
  }) async {
    if (state.isSubmitting) {
      Log.error('Sign in with magic link is already in progress');
      return;
    }


    emit(
      state.copyWith(
        isSubmitting: true,
        emailError: null,
        passwordError: null,
        successOrFail: null,
      ),
    );

    final result = await authService.signInWithMagicLink(email: email);

    emit(
      result.fold(
        (userProfile) => state.copyWith(
          isSubmitting: false,
        ),
        (error) => _stateFromCode(error),
      ),
    );
  }

  Future<void> _onSignInWithPasscode(
    Emitter<SignInState> emit, {
    required String email,
    required String passcode,
  }) async {
    if (state.isSubmitting) {
      Log.error('Sign in with passcode is already in progress');
      return;
    }


    emit(
      state.copyWith(
        isSubmitting: true,
        emailError: null,
        passwordError: null,
        successOrFail: null,
      ),
    );

    final result = await authService.signInWithPasscode(
      email: email,
      passcode: passcode,
    );

    final newState = await result.fold(
      (gotrueTokenResponse) async {

        try {
          // 将 token 交给 Deep Link 处理（写入本地并触发登录流程）
          await getIt<AppFlowyCloudDeepLink>().passGotrueTokenResponse(
            gotrueTokenResponse,
          );
        } catch (e, s) {
          Log.error('🟣 [SignInBloc] passGotrueTokenResponse error: $e\n$s');
        }

        // 等待一小段时间，让 Deep Link Handler 有机会处理并更新状态
        await Future.delayed(const Duration(milliseconds: 100));

        // 如果 Deep Link 已经把登录完成的结果同步到 state（successOrFail 已经是成功），则不再重复请求
        if (!isClosed &&
            state.successOrFail != null &&
            state.successOrFail!.isSuccess) {
          return state.copyWith(
            isSubmitting: false,
          );
        }

        // 兜底：直接获取用户信息并返回成功状态，确保不会卡在验证码页
        final profileResult = await authService.getUser();
        return profileResult.fold(
          (userProfile) {
            return state.copyWith(
              isSubmitting: false,
              successOrFail: FlowyResult.success(userProfile),
          );
        },
        (error) {
            Log.error('🟣 [SignInBloc] 兜底获取用户信息失败: ${error.msg}');
            return _stateFromCode(error);
          },
        );
      },
      (error) async {
          Log.error('🟣 [SignInBloc] 验证码登录失败: ${error.msg}');
          return _stateFromCode(error);
        },
    );

    emit(newState);
  }

  Future<void> _onSignInAsGuest(
    Emitter<SignInState> emit,
  ) async {
    emit(
      state.copyWith(
        isSubmitting: true,
        emailError: null,
        passwordError: null,
        successOrFail: null,
      ),
    );

    final result = await authService.signUpAsGuest();
    emit(
      result.fold(
        (userProfile) => state.copyWith(
          isSubmitting: false,
          successOrFail: FlowyResult.success(userProfile),
        ),
        (error) => _stateFromCode(error),
      ),
    );
  }

  Future<void> _onForgotPassword(
    Emitter<SignInState> emit, {
    required String email,
  }) async {
    if (state.isSubmitting) {
      Log.error('Forgot password is already in progress');
      return;
    }

    emit(
      state.copyWith(
        isSubmitting: true,
        forgotPasswordSuccessOrFail: null,
        validateResetPasswordTokenSuccessOrFail: null,
        resetPasswordSuccessOrFail: null,
      ),
    );

    // 判断是手机号还是邮箱
    final bool isPhone = _isValidPhone(email);
    final bool isEmail = _isValidEmail(email);
    
    // 根据类型传递正确的参数
    final result = await passwordService?.forgotPassword(
      email: email,
      phone: isPhone ? email : null,
    );

    result?.fold(
      (success) {
        emit(
          state.copyWith(
            isSubmitting: false,
            forgotPasswordSuccessOrFail: FlowyResult.success(true),
          ),
        );
      },
      (error) {
        emit(
          state.copyWith(
            isSubmitting: false,
            forgotPasswordSuccessOrFail: FlowyResult.failure(error),
          ),
        );
      },
    );
  }

  Future<void> _onValidateResetPasswordToken(
    Emitter<SignInState> emit, {
    required String email,
    required String token,
    String? phone,
  }) async {
    if (state.isSubmitting) {
      Log.error('Validate reset password token is already in progress');
      return;
    }


    emit(
      state.copyWith(
        isSubmitting: true,
        validateResetPasswordTokenSuccessOrFail: null,
        resetPasswordSuccessOrFail: null,
      ),
    );

    final result = await passwordService?.verifyResetPasswordToken(
      email: email,
      token: token,
      phone: phone,
    );

    result?.fold(
      (authToken) {

        passwordService?.authToken = authToken;

        emit(
          state.copyWith(
            isSubmitting: false,
            validateResetPasswordTokenSuccessOrFail: FlowyResult.success(true),
          ),
        );
      },
      (error) {
        Log.error('Validate reset password token failed: $error');

        emit(
          state.copyWith(
            isSubmitting: false,
            validateResetPasswordTokenSuccessOrFail: FlowyResult.failure(error),
          ),
        );
      },
    );
  }

  Future<void> _onResetPassword(
    Emitter<SignInState> emit, {
    required String email,
    required String newPassword,
  }) async {
    if (state.isSubmitting) {
      Log.error('Reset password is already in progress');
      return;
    }


    emit(
      state.copyWith(
        isSubmitting: true,
        resetPasswordSuccessOrFail: null,
      ),
    );

    final result = await passwordService?.setupPassword(
      newPassword: newPassword,
    );

    result?.fold(
      (success) {
        emit(
          state.copyWith(
            isSubmitting: false,
            resetPasswordSuccessOrFail: FlowyResult.success(true),
          ),
        );
      },
      (error) {
        Log.error('Reset password failed: $error');
        emit(
          state.copyWith(
            isSubmitting: false,
            resetPasswordSuccessOrFail: FlowyResult.failure(error),
          ),
        );
      },
    );
  }

  Future<void> _onCheckPasswordStatus(
    Emitter<SignInState> emit, {
    String? email,
    String? phone,
  }) async {
    if (passwordService == null) {
      // 如果 passwordService 未初始化，尝试初始化
      // 使用 gotrue_url 而不是 base_url，因为 PasswordHttpService 需要直接连接到 GoTrue 服务
      final sharedEnv = getIt<AppFlowyCloudSharedEnv>();
      passwordService = PasswordHttpService(
        baseUrl: sharedEnv.appflowyCloudConfig.gotrue_url,
        authToken: '',
      );
    }

    final result = await passwordService?.checkPasswordStatus(
      email: email,
      phone: phone,
    );

    result?.fold(
      (passwordIsSet) {
        emit(
          state.copyWith(
            passwordIsSet: passwordIsSet,
          ),
        );
      },
      (error) {
        // 如果用户不存在，passwordIsSet 默认为 false
        emit(
          state.copyWith(
            passwordIsSet: false,
          ),
        );
      },
    );
  }

  Future<void> _onSignInWithWeChat(
    Emitter<SignInState> emit,
  ) async {
    emit(
      state.copyWith(
        isSubmitting: true,
        emailError: null,
        passwordError: null,
        successOrFail: null,
      ),
    );

    // 确保 passwordService 已初始化
    if (passwordService == null) {
      final sharedEnv = getIt<AppFlowyCloudSharedEnv>();
      passwordService = PasswordHttpService(
        baseUrl: sharedEnv.appflowyCloudConfig.gotrue_url,
        authToken: '',
      );
    }

    // 1. 获取微信授权码
    final codeResult = await WeChatLoginService.instance.getAuthorizationCode();
    
    await codeResult.fold(
      (code) async {
        await _completeWeChatLogin(emit, code);
      },
      (error) {
        Log.error('🟢[SignInBloc] Failed to get WeChat authorization code: $error');
        emit(
          _stateFromCode(
            FlowyError.create()
              ..code = ErrorCode.Internal
              ..msg = error,
          ),
        );
      },
    );
  }

  Future<void> _completeWeChatLogin(
    Emitter<SignInState> emit,
    String code,
  ) async {
    final loginResult = await passwordService!.signInWithThirdParty(
      platform: 'weixin',
      code: code,
    );

    emit(
      loginResult.fold(
        (tokenMap) {
          // 将 JSON map 转换为 GotrueTokenResponsePB
          try {
            final gotrueTokenResponse = GotrueTokenResponsePB.create()
              ..accessToken = tokenMap['access_token'] as String? ?? ''
              ..tokenType = tokenMap['token_type'] as String? ?? 'bearer'
              ..expiresIn = Int64((tokenMap['expires_in'] as num?)?.toInt() ?? 3600)
              ..expiresAt = Int64((tokenMap['expires_at'] as num?)?.toInt() ?? 0)
              ..refreshToken = tokenMap['refresh_token'] as String? ?? ''
              ..providerAccessToken = tokenMap['provider_access_token'] as String? ?? ''
              ..providerRefreshToken = tokenMap['provider_refresh_token'] as String? ?? '';

            Log.info('🟢[SignInBloc] WeChat login successful');
            getIt<AppFlowyCloudDeepLink>().passGotrueTokenResponse(
              gotrueTokenResponse,
            );

            // 判定是否需要绑定手机号
            String phone = '';
            final userMap = tokenMap['user'];
            if (userMap is Map<String, dynamic>) {
              phone = (userMap['phone'] as String?) ?? '';
            }
            final requiresPhoneBinding = phone.isEmpty;

            return state.copyWith(
              isSubmitting: false,
              requiresPhoneBinding: requiresPhoneBinding,
            );
          } catch (e) {
            Log.error('🟢[SignInBloc] Failed to parse token response: $e');
            return _stateFromCode(
              FlowyError.create()
                ..code = ErrorCode.Internal
                ..msg = 'Failed to parse token response: $e',
            );
          }
        },
        (error) {
          Log.error('🟢[SignInBloc] WeChat login failed: ${error.msg}');
          return _stateFromCode(error);
        },
      ),
    );
  }

  Future<void> _onSignInWithDouYin(
    Emitter<SignInState> emit,
  ) async {
    emit(
      state.copyWith(
        isSubmitting: true,
        emailError: null,
        passwordError: null,
        successOrFail: null,
      ),
    );

    // 确保 passwordService 已初始化
    if (passwordService == null) {
      final sharedEnv = getIt<AppFlowyCloudSharedEnv>();
      passwordService = PasswordHttpService(
        baseUrl: sharedEnv.appflowyCloudConfig.gotrue_url,
        authToken: '',
      );
    }

    // 1. 获取抖音授权码
    final codeResult = await DouYinLoginService.instance.getAuthorizationCode();
    
    await codeResult.fold(
      (code) async {
        await _completeDouYinLogin(emit, code);
      },
      (error) {
        Log.error('🟢[SignInBloc] Failed to get DouYin authorization code: $error');
        emit(
          _stateFromCode(
            FlowyError.create()
              ..code = ErrorCode.Internal
              ..msg = error,
          ),
        );
      },
    );
  }

  Future<void> _completeDouYinLogin(
    Emitter<SignInState> emit,
    String code,
  ) async {
    final loginResult = await passwordService!.signInWithThirdParty(
      platform: 'douyin',
      code: code,
    );

    emit(
      loginResult.fold(
        (tokenMap) {
          // 将 JSON map 转换为 GotrueTokenResponsePB
          try {
            final gotrueTokenResponse = GotrueTokenResponsePB.create()
              ..accessToken = tokenMap['access_token'] as String? ?? ''
              ..tokenType = tokenMap['token_type'] as String? ?? 'bearer'
              ..expiresIn = Int64((tokenMap['expires_in'] as num?)?.toInt() ?? 3600)
              ..expiresAt = Int64((tokenMap['expires_at'] as num?)?.toInt() ?? 0)
              ..refreshToken = tokenMap['refresh_token'] as String? ?? ''
              ..providerAccessToken = tokenMap['provider_access_token'] as String? ?? ''
              ..providerRefreshToken = tokenMap['provider_refresh_token'] as String? ?? '';

            getIt<AppFlowyCloudDeepLink>().passGotrueTokenResponse(
              gotrueTokenResponse,
            );

            // 判定是否需要绑定手机号
            String phone = '';
            final userMap = tokenMap['user'];
            if (userMap is Map<String, dynamic>) {
              phone = (userMap['phone'] as String?) ?? '';
            }
            final requiresPhoneBinding = phone.isEmpty;

            return state.copyWith(
              isSubmitting: false,
              requiresPhoneBinding: requiresPhoneBinding,
            );
          } catch (e) {
            Log.error('🟢[SignInBloc] Failed to parse token response: $e');
            return _stateFromCode(
              FlowyError.create()
                ..code = ErrorCode.Internal
                ..msg = 'Failed to parse token response: $e',
            );
          }
        },
        (error) {
          Log.error('🟢[SignInBloc] DouYin login failed: ${error.msg}');
          return _stateFromCode(error);
        },
      ),
    );
  }

  SignInState _stateFromCode(FlowyError error) {
    Log.error('SignInState _stateFromCode: ${error.msg}');

    switch (error.code) {
      case ErrorCode.EmailFormatInvalid:
        return state.copyWith(
          isSubmitting: false,
          emailError: error.msg,
          passwordError: null,
        );
      case ErrorCode.PasswordFormatInvalid:
        return state.copyWith(
          isSubmitting: false,
          passwordError: error.msg,
          emailError: null,
        );
      case ErrorCode.UserUnauthorized:
        final errorMsg = error.msg;
        String msg = LocaleKeys.signIn_generalError.tr();
        if (errorMsg.contains('rate limit') ||
            errorMsg.contains('For security purposes')) {
          msg = LocaleKeys.signIn_tooFrequentVerificationCodeRequest.tr();
        } else if (errorMsg.contains('invalid')) {
          msg = LocaleKeys.signIn_tokenHasExpiredOrInvalid.tr();
        } else if (errorMsg.contains('Invalid login credentials')) {
          msg = LocaleKeys.signIn_invalidLoginCredentials.tr();
        }
        return state.copyWith(
          isSubmitting: false,
          successOrFail: FlowyResult.failure(
            FlowyError(msg: msg),
          ),
        );
      default:
        return state.copyWith(
          isSubmitting: false,
          successOrFail: FlowyResult.failure(
            FlowyError(msg: LocaleKeys.signIn_generalError.tr()),
          ),
        );
    }
  }
}

@freezed
class SignInEvent with _$SignInEvent {
  // Sign in methods
  const factory SignInEvent.signInWithEmailAndPassword({
    required String email,
    required String password,
  }) = SignInWithEmailAndPassword;
  const factory SignInEvent.signInWithOAuth({
    required String platform,
  }) = SignInWithOAuth;
  const factory SignInEvent.signInAsGuest() = SignInAsGuest;
  const factory SignInEvent.signInWithMagicLink({
    required String email,
  }) = SignInWithMagicLink;
  const factory SignInEvent.signInWithPasscode({
    required String email,
    required String passcode,
  }) = SignInWithPasscode;

  // Event handlers
  const factory SignInEvent.emailChanged({
    required String email,
  }) = EmailChanged;
  const factory SignInEvent.passwordChanged({
    required String password,
  }) = PasswordChanged;
  const factory SignInEvent.deepLinkStateChange(DeepLinkResult result) =
      DeepLinkStateChange;

  const factory SignInEvent.cancel() = Cancel;
  const factory SignInEvent.switchLoginType(LoginType type) = SwitchLoginType;

  // password
  const factory SignInEvent.forgotPassword({
    required String email,
  }) = ForgotPassword;

  const factory SignInEvent.validateResetPasswordToken({
    required String email,
    required String token,
    String? phone,
  }) = ValidateResetPasswordToken;

  const factory SignInEvent.resetPassword({
    required String email,
    required String newPassword,
  }) = ResetPassword;

  const factory SignInEvent.checkPasswordStatus({
    String? email,
    String? phone,
  }) = CheckPasswordStatus;

  const factory SignInEvent.signInWithWeChat() = SignInWithWeChat;

  /// 清除“需要绑定手机号”状态，防止重复弹窗
  const factory SignInEvent.clearPhoneBindingRequirement() =
      ClearPhoneBindingRequirement;

  /// 收到微信回调的 code（通过 deep link）
  const factory SignInEvent.wechatCodeReceived(String code) =
      WeChatCodeReceived;

  const factory SignInEvent.signInWithDouYin() = SignInWithDouYin;

  /// 收到抖音回调的 code（通过 deep link）
  const factory SignInEvent.douyinCodeReceived(String code) =
      DouYinCodeReceived;

  /// 手机号绑定成功后，设置登录成功状态
  const factory SignInEvent.phoneBindingComplete(UserProfilePB userProfile) =
      PhoneBindingComplete;

  /// 重置登录状态（退出登录时使用）
  const factory SignInEvent.reset() = Reset;
}

// we support sign in directly without sign up, but we want to allow the users to sign up if they want to
// this type is only for the UI to know which form to show
enum LoginType {
  signIn,
  signUp,
}

@freezed
class SignInState with _$SignInState {
  const factory SignInState({
    String? email,
    String? password,
    required bool isSubmitting,
    required String? passwordError,
    required String? emailError,
    required FlowyResult<UserProfilePB, FlowyError>? successOrFail,
    required FlowyResult<bool, FlowyError>? forgotPasswordSuccessOrFail,
    required FlowyResult<bool, FlowyError>?
        validateResetPasswordTokenSuccessOrFail,
    required FlowyResult<bool, FlowyError>? resetPasswordSuccessOrFail,
    @Default(LoginType.signIn) LoginType loginType,
    bool? passwordIsSet,
    @Default(false) bool requiresPhoneBinding,
  }) = _SignInState;

  factory SignInState.initial() => const SignInState(
        isSubmitting: false,
        passwordError: null,
        emailError: null,
        successOrFail: null,
        forgotPasswordSuccessOrFail: null,
        validateResetPasswordTokenSuccessOrFail: null,
        resetPasswordSuccessOrFail: null,
        passwordIsSet: null,
        requiresPhoneBinding: false,
      );
}
