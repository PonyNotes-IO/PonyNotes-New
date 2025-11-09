import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/appflowy_cloud_task.dart';
import 'package:appflowy/startup/tasks/deeplink/deeplink_handler.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/user/application/password/password_http_service.dart';
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
          validateResetPasswordToken: (email, token) async =>
              _onValidateResetPasswordToken(
            emit,
            email: email,
            token: token,
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
    Log.info('[SignInBloc] DeepLink状态变化: $deepLinkState');

    switch (deepLinkState) {
      case DeepLinkState.none:
        Log.info('[SignInBloc] DeepLink状态: none');
        break;
      case DeepLinkState.loading:
        Log.info('[SignInBloc] DeepLink状态: loading');
        emit(
          state.copyWith(
            isSubmitting: true,
            emailError: null,
            passwordError: null,
            successOrFail: null,
          ),
        );
      case DeepLinkState.finish:
        Log.info('[SignInBloc] DeepLink状态: finish');
        Log.info('  - result.result: ${result.result}');
        final newState = result.result?.fold(
          (s) {
            Log.info('[SignInBloc] DeepLink成功，设置successOrFail: ${s.email}');
            return state.copyWith(
              isSubmitting: false,
              successOrFail: FlowyResult.success(s),
            );
          },
          (f) {
            Log.info('[SignInBloc] DeepLink失败: ${f.msg}');
            return _stateFromCode(f);
          },
        );
        if (newState != null) {
          Log.info('[SignInBloc] emit新状态，successOrFail: ${newState.successOrFail}');
          emit(newState);
        }
      case DeepLinkState.error:
        Log.info('[SignInBloc] DeepLink状态: error');
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
      Log.info('🦋[SignInBloc] 使用手机号密码登录: $email');
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

              Log.info('🦋[SignInBloc] 手机号密码登录成功');
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
      Log.info('🦋[SignInBloc] 使用邮箱密码登录: $email');
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

    Log.info('Sign in with magic link: $email');

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

    Log.info('Sign in with passcode: $email, $passcode');

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

    Log.info('🟣 [SignInBloc] signInWithPasscode result: ${result.isSuccess ? "success" : "failure"}');

    emit(
      result.fold(
        (gotrueTokenResponse) {
          Log.info('🟣 [SignInBloc] 验证码登录成功，传递token给DeepLink');
          Log.info('🟣 [SignInBloc] access_token: ${gotrueTokenResponse.hasAccessToken() ? "present" : "missing"}');
          Log.info('🟣 [SignInBloc] refresh_token: ${gotrueTokenResponse.hasRefreshToken() ? "present" : "missing"}');
          
          getIt<AppFlowyCloudDeepLink>().passGotrueTokenResponse(
            gotrueTokenResponse,
          );
          
          Log.info('🟣 [SignInBloc] emit state with isSubmitting=false');
          return state.copyWith(
            isSubmitting: false,
          );
        },
        (error) {
          Log.error('🟣 [SignInBloc] 验证码登录失败: ${error.msg}');
          return _stateFromCode(error);
        },
      ),
    );
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

    final result = await passwordService?.forgotPassword(email: email);

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
  }) async {
    if (state.isSubmitting) {
      Log.error('Validate reset password token is already in progress');
      return;
    }

    Log.info('Validate reset password token: $email, $token');

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
    );

    result?.fold(
      (authToken) {
        Log.info('Validate reset password token success: $authToken');

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

    Log.info('Reset password: $email, ${newPassword.hashCode}');

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
        Log.info('Reset password success');
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
  }) = ValidateResetPasswordToken;

  const factory SignInEvent.resetPassword({
    required String email,
    required String newPassword,
  }) = ResetPassword;

  const factory SignInEvent.checkPasswordStatus({
    String? email,
    String? phone,
  }) = CheckPasswordStatus;
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
      );
}
