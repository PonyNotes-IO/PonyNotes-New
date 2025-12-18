import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/user/application/contact_binding_service.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/user/application/sign_in_bloc.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/back_to_login_in_button.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/continue_with_button.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/title_logo.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/verifying_button.dart';
import 'package:appflowy/util/validator.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flowy_infra_ui/widget/spacing.dart';
import 'package:flutter/material.dart';

/// 首次绑定手机号的完整页面（非弹窗）
class PhoneBindScreen extends StatefulWidget {
  const PhoneBindScreen({
    super.key,
    this.logoutOnBack = false,
  });

  /// 是否在点击“返回登录”时执行退出登录并回到登录页。
  ///
  /// - 从登录页进入的绑定流程：为 `false`，仅 `pop` 当前页面回到登录页。
  /// - 从应用内部（DeepLink）强制绑定手机号：为 `true`，点击返回时会：
  ///   1. 调用 `AuthService.signOut()` 退出登录
  ///   2. 调用 `runAppFlowy()` 回到登录入口
  final bool logoutOnBack;

  @override
  State<PhoneBindScreen> createState() => _PhoneBindScreenState();
}

class _PhoneBindScreenState extends State<PhoneBindScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _phoneKey = GlobalKey<AFTextFieldState>();
  final _codeKey = GlobalKey<AFTextFieldState>();

  bool _isSending = false;
  bool _isBinding = false;
  bool _hasRequestedCode = false;
  int _countdown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final spacing = theme.spacing.xxl;

    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 340,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLogoAndTitle(),
              _buildPhoneField(),
              VSpace(spacing),
              _buildCodeField(),
              VSpace(spacing),
              _buildNextButton(),
              VSpace(spacing),
              BackToLoginButton(
                onTap: () async {
                  // 无论是从登录页还是从应用内部进入的绑定流程，都使用相同的处理方式：
                  // 1. 退出登录
                  // 2. 重启 AppFlowy，回到登录入口
                  // 这样可以确保完全清除登录状态，不会进入主界面
                  try {
                    await getIt<AuthService>().signOut();
                  } catch (e, stack) {
                    Log.error(
                      '🔵 [PhoneBindScreen] signOut failed on backToLogin: $e',
                      stack,
                    );
                  }

                  // 使用 runAppFlowy 重启应用，确保不会停留在主界面
                  await runAppFlowy();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogoAndTitle() {
    return const TitleLogo(
      title: '绑定手机号',
      description: '根据国家相关法律规定及网络安全管理要求，请验证有效手机号码',
    );
  }

  Widget _buildPhoneField() {
    return AFTextField(
      key: _phoneKey,
      controller: _phoneController,
      hintText: '输入手机号',
      keyboardType: TextInputType.phone,
    );
  }

  Widget _buildCodeField() {
    final theme = AppFlowyTheme.of(context);
    final canResend = _canResendCode() && !_isSending;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AFTextField(
          key: _codeKey,
          controller: _codeController,
          hintText: '请输入6位验证码',
          keyboardType: TextInputType.number,
          maxLength: 6,
        ),
        VSpace(theme.spacing.s),
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: canResend ? _sendCode : null,
            child: MouseRegion(
              cursor: canResend ? SystemMouseCursors.click : SystemMouseCursors.basic,
              child: Text(
                _getButtonText(),
                style: theme.textStyle.body.standard(
                  color: canResend
                      ? theme.textColorScheme.action
                      : theme.textColorScheme.tertiary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNextButton() {
    return _isBinding
        ? const VerifyingButton()
        : ContinueWithButton(
            text: LocaleKeys.web_continue.tr(),
            onTap: _bindPhone,
          );
  }

  bool _canResendCode() => _countdown == 0 && !_isSending;

  String _getButtonText() {
    if (_countdown > 0) return '重新获取(${_countdown}s)';
    if (_hasRequestedCode) return '重新获取';
    return '获取验证码';
  }

  Future<void> _sendCode() async {
    final cleanPhone = Validator.cleanPhoneNumber(_phoneController.text);
    if (!Validator.isValidPhone(cleanPhone)) {
      _toast('手机号格式不正确');
      return;
    }
    setState(() {
      _isSending = true;
    });
    final result =
        await ContactBindingService.sendPhoneVerificationCode(cleanPhone);
    if (!mounted) return;
    result.fold(
      (_) {
        setState(() {
          _isSending = false;
          _hasRequestedCode = true;
          _countdown = 60;
        });
        _startCountdown();
      },
      (error) {
        setState(() {
          _isSending = false;
        });
        _toast('发送失败: ${error.msg}');
      },
    );
  }

  void _startCountdown() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 0) {
        setState(() => _countdown--);
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _bindPhone() async {
    final cleanPhone = Validator.cleanPhoneNumber(_phoneController.text);
    if (!Validator.isValidPhone(cleanPhone)) {
      _toast('手机号格式不正确');
      return;
    }
    if (_codeController.text.length != 6) {
      _toast('请输入6位验证码');
      return;
    }
    setState(() {
      _isBinding = true;
    });
    final result = await ContactBindingService.bindPhoneNumber(
      cleanPhone,
      _codeController.text,
    );
    if (!mounted) return;
    setState(() {
      _isBinding = false;
    });
    result.fold(
      (_) async {
        // 绑定成功后刷新用户信息
        final profileResult = await UserBackendService.getCurrentUserProfile();
        profileResult.fold(
          (profile) {
            // 通过 SignInBloc 设置登录成功状态（如果可用）
            try {
              final signInBloc = BlocProvider.of<SignInBloc>(context);
              signInBloc.add(SignInEvent.phoneBindingComplete(profile));
            } catch (e) {
              // SignInBloc 不可用（例如在 appflowy_cloud_task 中），
              // 让 desktop_sign_in_screen 处理导航
              Log.info('🔵 [PhoneBindScreen] SignInBloc not available, letting parent handle navigation');
            }
            // 返回 profile，让 desktop_sign_in_screen 处理导航
            Navigator.of(context).pop(profile);
          },
          (error) {
            _toast(error.msg);
          },
        );
      },
      (error) {
        _toast(error.msg);
      },
    );
  }

  void _toast(String msg) {
    showToastNotification(
      message: msg,
      type: ToastificationType.info,
    );
  }
}

