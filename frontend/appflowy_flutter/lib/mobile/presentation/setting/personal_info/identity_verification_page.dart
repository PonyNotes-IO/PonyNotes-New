import 'dart:async';

import 'package:appflowy/mobile/presentation/base/app_bar/mobile_app_bar.dart';
import 'package:appflowy/user/application/contact_binding_service.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/util/validator.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

enum VerificationMethod { phone, email }

class MobileIdentityVerificationPage extends StatefulWidget {
  const MobileIdentityVerificationPage({
    super.key,
    required this.phoneNumber,
    this.emailAddress,
    required this.onVerificationComplete,
  });

  static const routeName = '/settings/identity-verification';

  final String phoneNumber;
  final String? emailAddress;
  final VoidCallback onVerificationComplete;

  @override
  State<MobileIdentityVerificationPage> createState() => _MobileIdentityVerificationPageState();
}

class _MobileIdentityVerificationPageState extends State<MobileIdentityVerificationPage> {
  VerificationMethod _currentMethod = VerificationMethod.phone;
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  bool _isSending = false;
  bool _hasRequestedCode = false;
  int _countdown = 0;
  Timer? _timer;

  String get _effectiveEmail => widget.emailAddress ?? _emailController.text.trim();

  bool get _canUseEmail => widget.emailAddress != null && widget.emailAddress!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // 如果有手机号，默认使用手机验证；否则使用邮箱
    if (widget.phoneNumber.isEmpty && _canUseEmail) {
      _currentMethod = VerificationMethod.email;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  String _formatPhoneNumber(String phone) {
    final cleanPhone = Validator.cleanPhoneNumber(phone);
    if (cleanPhone.length >= 11) {
      return '${cleanPhone.substring(0, 3)}******${cleanPhone.substring(cleanPhone.length - 2)}';
    }
    return phone;
  }

  String _formatEmail(String email) {
    if (!email.contains('@')) return email;
    final parts = email.split('@');
    if (parts[0].length <= 3) {
      return '${parts[0]}***@${parts[1]}';
    }
    return '${parts[0].substring(0, 3)}***@${parts[1]}';
  }

  bool get _canSendCode {
    if (_countdown > 0 || _isSending) return false;
    if (_currentMethod == VerificationMethod.email) {
      final email = _effectiveEmail;
      return email.isNotEmpty && email.contains('@');
    }
    return widget.phoneNumber.isNotEmpty;
  }

  bool get _canVerify => _codeController.text.length == 6;

  String get _codeButtonText {
    if (_countdown > 0) {
      return '${_countdown}s';
    } else if (_hasRequestedCode) {
      return '重新获取';
    } else {
      return '获取验证码';
    }
  }

  Future<void> _sendCode() async {
    if (!_canSendCode || _isSending) return;

    setState(() => _isSending = true);

    if (_currentMethod == VerificationMethod.phone) {
      await _sendPhoneCode();
    } else {
      await _sendEmailCode();
    }
  }

  Future<void> _sendPhoneCode() async {
    final cleanPhone = Validator.cleanPhoneNumber(widget.phoneNumber);
    if (!Validator.isValidPhone(cleanPhone)) {
      showToastNotification(message: '手机号格式不正确');
      setState(() => _isSending = false);
      return;
    }

    final result = await ContactBindingService.sendPhoneReauthCode(cleanPhone);
    result.fold(
      (success) {
        if (mounted) {
          setState(() {
            _countdown = 60;
            _isSending = false;
            _hasRequestedCode = true;
          });
          _startCountdown();
          showToastNotification(message: '验证码已发送至您的手机');
        }
      },
      (error) {
        if (mounted) {
          setState(() => _isSending = false);
          showToastNotification(message: '发送失败: ${error.msg}');
        }
      },
    );
  }

  Future<void> _sendEmailCode() async {
    final email = _effectiveEmail;
    if (!Validator.isValidEmail(email)) {
      showToastNotification(message: '请输入有效的邮箱地址');
      setState(() => _isSending = false);
      return;
    }

    final result = await ContactBindingService.sendEmailReauthenticationCode(email);
    result.fold(
      (success) {
        if (mounted) {
          setState(() {
            _countdown = 60;
            _isSending = false;
            _hasRequestedCode = true;
          });
          _startCountdown();
          showToastNotification(message: '验证码已发送至 $email');
        }
      },
      (error) {
        if (mounted) {
          setState(() => _isSending = false);
          showToastNotification(message: '发送失败: ${error.msg}');
        }
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

  Future<void> _verifyCode() async {
    if (!(_canVerify && _hasRequestedCode)) {
      showToastNotification(message: '请先获取验证码');
      return;
    }

    if (_currentMethod == VerificationMethod.phone) {
      await _verifyPhoneCode();
    } else {
      await _verifyEmailCode();
    }
  }

  Future<void> _verifyPhoneCode() async {
    final cleanPhone = Validator.cleanPhoneNumber(widget.phoneNumber);
    final result = await UserBackendService.verifyPhoneReauthentication(
      cleanPhone,
      _codeController.text,
    );

    result.fold(
      (_) => _onVerificationSuccess(),
      (error) => _onVerificationFailure(error),
    );
  }

  Future<void> _verifyEmailCode() async {
    final email = _effectiveEmail;
    final result = await ContactBindingService.verifyEmailReauthentication(
      email,
      _codeController.text,
    );

    result.fold(
      (_) => _onVerificationSuccess(),
      (error) => _onVerificationFailure(error),
    );
  }

  void _onVerificationSuccess() {
    showToastNotification(message: '身份验证成功');

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        Navigator.pop(context);
        widget.onVerificationComplete();
      }
    });
  }

  void _onVerificationFailure(error) {
    showToastNotification(message: '验证码错误');
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return Scaffold(
      appBar: MobileAppBar(
        title: '身份验证',
        onBackPressed: () => Navigator.pop(context),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Text(
                '为了你的账户安全，请先验证身份',
                style: theme.textStyle.body.standard(
                  color: theme.textColorScheme.secondary,
                ),
              ),
              const SizedBox(height: 24),
              // 验证方式切换
              Text(
                _currentMethod == VerificationMethod.phone ? '使用手机验证' : '使用邮箱验证',
                style: theme.textStyle.body.standard(
                  color: theme.textColorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: theme.surfaceColorScheme.layer02,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _currentMethod == VerificationMethod.phone ? Icons.phone_android : Icons.email_outlined,
                      size: 20,
                      color: theme.textColorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _currentMethod == VerificationMethod.phone
                          ? _formatPhoneNumber(widget.phoneNumber)
                          : _formatEmail(widget.emailAddress ?? ''),
                      style: theme.textStyle.body.enhanced(
                        color: theme.textColorScheme.primary,
                      ),
                    ),
                    const Spacer(),
                    if (_canUseEmail || widget.phoneNumber.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _currentMethod = _currentMethod == VerificationMethod.phone
                                ? VerificationMethod.email
                                : VerificationMethod.phone;
                            _hasRequestedCode = false;
                            _countdown = 0;
                            _timer?.cancel();
                            _codeController.clear();
                          });
                        },
                        child: Text(
                          '切换',
                          style: theme.textStyle.body.standard(
                            color: const Color(0xFF4285F4),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // 邮箱输入（仅邮箱验证且未预置邮箱时显示）
              if (_currentMethod == VerificationMethod.email && widget.emailAddress == null) ...[
                const SizedBox(height: 16),
                Text(
                  '邮箱地址',
                  style: theme.textStyle.body.standard(
                    color: theme.textColorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: '请输入邮箱地址',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: 24),
              // 验证码输入
              Text(
                '验证码',
                style: theme.textStyle.body.standard(
                  color: theme.textColorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: InputDecoration(
                        hintText: '6位验证码',
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _canSendCode ? _sendCode : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _canSendCode
                              ? theme.textColorScheme.primary
                              : theme.textColorScheme.secondary,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _isSending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _codeButtonText,
                              style: TextStyle(
                                color: _canSendCode
                                    ? theme.textColorScheme.primary
                                    : theme.textColorScheme.secondary,
                                fontSize: 14,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
              if (_hasRequestedCode) ...[
                const SizedBox(height: 8),
                Text(
                  _currentMethod == VerificationMethod.phone
                      ? '短信验证码已发送至您的手机'
                      : '邮件验证码已发送至您的邮箱',
                  style: theme.textStyle.caption.standard(
                    color: theme.textColorScheme.secondary,
                  ),
                ),
              ],
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: AFFilledTextButton.primary(
                  text: '完成验证',
                  onTap: () {
                    if (_canVerify && _hasRequestedCode) _verifyCode();
                  },
                  size: AFButtonSize.l,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
