import 'dart:async';

import 'package:appflowy/user/application/contact_binding_service.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/util/validator.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

/// 首次绑定手机号的完整页面（非弹窗）
class PhoneBindScreen extends StatefulWidget {
  const PhoneBindScreen({super.key});

  @override
  State<PhoneBindScreen> createState() => _PhoneBindScreenState();
}

class _PhoneBindScreenState extends State<PhoneBindScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

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
    final width = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: theme.surfaceColorScheme.layer01,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Text(
                  '绑定手机号',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: theme.textColorScheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '根据国家相关法律规定及网络安全管理要求，请验证有效手机号码',
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.textColorScheme.secondary,
                  ),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  style: TextStyle(
                    color: theme.textColorScheme.primary,
                  ),
                  decoration: InputDecoration(
                    hintText: '输入手机号',
                    hintStyle: TextStyle(
                      color: theme.textColorScheme.tertiary,
                    ),
                    filled: true,
                    fillColor: theme.surfaceColorScheme.layer02,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: theme.borderColorScheme.primary,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: theme.borderColorScheme.primary,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _codeController,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        style: TextStyle(
                          color: theme.textColorScheme.primary,
                        ),
                        decoration: InputDecoration(
                          hintText: '请输入6位验证码',
                          hintStyle: TextStyle(
                            color: theme.textColorScheme.tertiary,
                          ),
                          counterText: '',
                          filled: true,
                          fillColor: theme.surfaceColorScheme.layer02,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: theme.borderColorScheme.primary,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: theme.borderColorScheme.primary,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: width > 500 ? 140 : 120,
                      child: FlowyButton(
                        text: Text(_getButtonText()),
                        onTap: _sendCode,
                        disable: !_canResendCode() || _isSending,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: FlowyButton(
                    text: const Text('下一步'),
                    onTap: _bindPhone,
                    disable: _isBinding,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
        // 绑定成功后刷新用户信息并返回
        final profileResult = await UserBackendService.getCurrentUserProfile();
        profileResult.fold(
          (profile) {
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

