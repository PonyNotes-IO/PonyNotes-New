import 'dart:async';

import 'package:appflowy/mobile/presentation/base/app_bar/mobile_app_bar.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

class MobilePhoneBindPage extends StatefulWidget {
  const MobilePhoneBindPage({super.key});

  static const routeName = '/settings/phone-bind';

  @override
  State<MobilePhoneBindPage> createState() => _MobilePhoneBindPageState();
}

class _MobilePhoneBindPageState extends State<MobilePhoneBindPage> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  bool _isSending = false;
  bool _isBinding = false;
  bool _hasRequestedCode = false;
  int _countdown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  bool get _canSendCode {
    final phone = _phoneController.text.trim();
    return phone.isNotEmpty && _countdown == 0;
  }

  bool get _canBind {
    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();
    return phone.isNotEmpty && code.length == 6 && _hasRequestedCode;
  }

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

    final phone = _phoneController.text.trim();
    setState(() => _isSending = true);

    final result = await UserBackendService.sendPhoneBindCode(phone);

    result.fold(
      (data) {
        if (!mounted) return;
        setState(() {
          _isSending = false;
          _countdown = 60;
          _hasRequestedCode = true;
        });
        _startCountdown();
      },
      (error) {
        if (!mounted) return;
        setState(() => _isSending = false);
        showToastNotification(message: error.msg);
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
    if (!_canBind || _isBinding) return;

    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();

    setState(() => _isBinding = true);

    final result = await UserBackendService.confirmPhoneBind(
      phone: phone,
      token: code,
      merge: false,
    );

    if (!mounted) return;
    setState(() => _isBinding = false);

    result.fold(
      (data) {
        Navigator.pop(context, true);
        showToastNotification(message: '绑定成功');
      },
      (error) {
        showToastNotification(message: error.msg);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return Scaffold(
      appBar: MobileAppBar(
        title: '绑定手机号',
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
                '手机号',
                style: theme.textStyle.body.standard(
                  color: theme.textColorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.surfaceColorScheme.secondary),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '+86',
                          style: theme.textStyle.body.standard(),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.keyboard_arrow_down,
                          size: 16,
                          color: theme.textColorScheme.secondary,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        hintText: '请输入手机号',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
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
                        hintText: '请输入验证码',
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
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
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: AFFilledTextButton.primary(
                  text: _isBinding ? '绑定中...' : '绑定手机号',
                  onTap: () {
                    if (!_isBinding) _bindPhone();
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
