import 'dart:async';

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
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/slider_captcha.dart';
import 'package:appflowy/util/validator.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
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
  bool _phoneIsRegistered = false; // 手机号是否已被注册
  int _countdown = 0;
  Timer? _timer;

  bool _sliderVerified = false;
  Object _sliderResetKey = Object();

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
              _buildSliderCaptcha(),
              VSpace(spacing),
              _buildCodeField(),
              VSpace(spacing),
              _buildNextButton(),
              VSpace(spacing),
              BackToLoginButton(
                onTap: () async {
                  try {
                    await getIt<AuthService>().signOut();
                  } catch (e, stack) {
                    Log.error(
                      '🔵 [PhoneBindScreen] signOut failed on backToLogin: $e',
                      stack,
                    );
                  }
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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: AFTextField(
            key: _codeKey,
            controller: _codeController,
            hintText: '请输入6位验证码',
            keyboardType: TextInputType.number,
            onChanged: (value) {
              if (value.length > 6) {
                _codeController.value = TextEditingValue(
                  text: value.substring(0, 6),
                  selection: TextSelection.collapsed(offset: 6),
                );
              }
            },
          ),
        ),
        HSpace(theme.spacing.s),
        SizedBox(
          width: 120,
          child: AFFilledTextButton(
            text: _getButtonText(),
            onTap: canResend ? _sendCode : () {},
            size: AFButtonSize.m,
            disabled: !canResend,
            padding: EdgeInsets.symmetric(
              horizontal: theme.spacing.xl,
              vertical: 10.0,
            ),
            backgroundColor: (context, isHovering, disabled) {
              if (disabled) {
                return theme.fillColorScheme.contentHover;
              }
              if (isHovering) {
                return theme.fillColorScheme.contentHover;
              }
              return theme.fillColorScheme.content;
            },
            textColor: (context, isHovering, disabled) {
              if (disabled) {
                return theme.textColorScheme.tertiary;
              }
              return theme.textColorScheme.primary;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNextButton() {
    return _isBinding
        ? const VerifyingButton()
        : ContinueWithButton(
            text: '下一步',
            onTap: _bindPhone,
          );
  }

  Widget _buildSliderCaptcha() {
    return SliderCaptcha(
      resetKey: _sliderResetKey,
      onVerified: () => setState(() => _sliderVerified = true),
    );
  }

  bool _canResendCode() => _sliderVerified && _countdown == 0 && !_isSending;

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
    final e164Phone =
        cleanPhone.startsWith('+86') ? cleanPhone : '+86$cleanPhone';
    setState(() {
      _isSending = true;
      _phoneIsRegistered = false;
    });

    // 从 SignInBloc 获取 pendingToken（OAuth pending 流程）
    final pendingToken = _getPendingTokenFromBloc();
    final result = await UserBackendService.sendPhoneBindCode(
      e164Phone,
      pendingToken: pendingToken,
    );
    if (!mounted) return;
    result.fold(
      (res) {
        setState(() {
          _isSending = false;
        });
        if (res.isOwnPhone) {
          _toast('该手机号已绑定当前账号');
          return;
        }
        if (res.phoneExists && res.codeSent) {
          // 手机号已注册，OTP 已发到该手机，用户需确认是否绑定
          setState(() {
            _hasRequestedCode = true;
            _phoneIsRegistered = true;
            _countdown = 60;
            _sliderVerified = false;
            _sliderResetKey = Object();
          });
          _startCountdown();
          _showExistingPhoneConfirmDialog(e164Phone);
        } else if (res.codeSent) {
          // 正常发送验证码，重置滑块防止免验证重发
          setState(() {
            _hasRequestedCode = true;
            _countdown = 60;
            _sliderVerified = false;
            _sliderResetKey = Object();
          });
          _startCountdown();
        }
      },
      (error) {
        setState(() {
          _isSending = false;
        });
        _toast('发送失败: ${error.msg}');
      },
    );
  }

  void _showExistingPhoneConfirmDialog(String phone) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('手机号已注册'),
        content: const Text(
          '该手机号已关联其他账号。绑定后，微信/抖音登录将可以使用该手机号登录，同时保留原有账号的所有数据。\n\n是否继续绑定？',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // 用户取消绑定，清除验证码状态
              setState(() {
                _phoneIsRegistered = false;
                _hasRequestedCode = false;
                _codeController.clear();
              });
            },
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // 用户确认绑定，提示输入验证码
              _toast('请输入发送到 $phone 的验证码完成绑定');
            },
            child: const Text('确认绑定'),
          ),
        ],
      ),
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

  String? _getPendingTokenFromBloc() {
    try {
      final bloc = context.read<SignInBloc>();
      final state = bloc.state;
      // pendingToken 存在于 SignInState 中
      final dynamic dynState = state;
      if (dynState is SignInState) {
        return dynState.pendingToken;
      }
      // 兜底：直接从 bloc 内部状态读取
      return (bloc.state as dynamic).pendingToken as String?;
    } catch (_) {
      return null;
    }
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
    final e164Phone =
        cleanPhone.startsWith('+86') ? cleanPhone : '+86$cleanPhone';

    // 从 SignInBloc 获取 pendingToken
    final pendingToken = _getPendingTokenFromBloc();
    if (pendingToken == null || pendingToken.isEmpty) {
      _toast('登录状态已过期，请重新登录');
      return;
    }

    setState(() {
      _isBinding = true;
    });

    // 绑定时传入 merge=true，让后端知道这是绑定到已注册手机号
    final result = await ContactBindingService.bindPhoneNumber(
      e164Phone,
      _codeController.text,
      pendingToken: pendingToken,
      merge: _phoneIsRegistered,
    );
    if (!mounted) return;
    setState(() {
      _isBinding = false;
    });
    result.fold(
      (res) async {
        // 无论是绑定到新手机号还是已注册手机号，confirmPhoneBind 都会返回 access_token
        // 因为新的 pending_token 流程下，新用户也是在 confirm 时才创建的
        if (res.accessToken != null && res.refreshToken != null) {
          await _updateAuthToken(
            res.accessToken!,
            res.refreshToken!,
            res.userId,
          );
        }
        if (res.bindToExisting) {
          _toast('绑定成功，现在可以使用该手机号登录');
        } else {
          _toast('注册成功');
        }
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        Navigator.of(context).pop();
      },
      (error) {
        if (mounted) {
          _toast('绑定失败: ${error.msg}');
        }
      },
    );
  }

  Future<void> _updateAuthToken(
    String accessToken,
    String refreshToken,
    String? userId,
  ) async {
    try {
      await getIt<AuthService>().updateAuthToken(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
      Log.info(
        '[PhoneBindScreen] Auth token updated for existing user: $userId',
      );
    } catch (e) {
      Log.error('[PhoneBindScreen] Failed to update auth token: $e');
    }
  }

  void _toast(String msg) {
    showToastNotification(
      message: msg,
      type: ToastificationType.info,
    );
  }
}

