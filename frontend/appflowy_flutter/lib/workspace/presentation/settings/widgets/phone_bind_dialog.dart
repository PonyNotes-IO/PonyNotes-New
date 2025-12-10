import 'dart:async';

import 'package:appflowy/user/application/contact_binding_service.dart';
import 'package:appflowy/util/validator.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/slide_verification_widget.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

/// 首次绑定手机号弹窗（用于微信登录后未绑定手机号的场景）
class PhoneBindDialog extends StatefulWidget {
  const PhoneBindDialog({
    super.key,
    this.onBindComplete,
  });

  final VoidCallback? onBindComplete;

  @override
  State<PhoneBindDialog> createState() => _PhoneBindDialogState();
}

class _PhoneBindDialogState extends State<PhoneBindDialog> {
  final phoneController = TextEditingController();
  final codeController = TextEditingController();
  final phoneFocusNode = FocusNode();
  final codeFocusNode = FocusNode();

  bool _isBinding = false;
  bool _isSending = false;
  bool _isSlideVerified = false;
  bool _hasRequestedCode = false;
  int _countdown = 0;
  Timer? _timer;

  @override
  void dispose() {
    phoneController.dispose();
    codeController.dispose();
    phoneFocusNode.dispose();
    codeFocusNode.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return Dialog(
      backgroundColor: theme.surfaceColorScheme.layer01,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                FlowyText(
                  '绑定手机号',
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: theme.textColorScheme.primary,
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 16,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
            const VSpace(8),
            FlowyText(
              '为保障账号安全，请先绑定手机号。',
              fontSize: 14,
              color: theme.textColorScheme.secondary,
            ),
            const VSpace(24),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      const FlowyText('+86', fontSize: 14),
                      const HSpace(4),
                      Icon(
                        Icons.keyboard_arrow_down,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                    ],
                  ),
                ),
                const HSpace(12),
                Expanded(
                  child: TextField(
                    controller: phoneController,
                    focusNode: phoneFocusNode,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: '手机号',
                      hintText: '请输入手机号',
                      labelStyle:
                          TextStyle(color: theme.textColorScheme.secondary),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onSubmitted: (_) => codeFocusNode.requestFocus(),
                  ),
                ),
              ],
            ),
            const VSpace(12),
            SlideVerificationWidget(
              onVerified: () {
                setState(() {
                  _isSlideVerified = true;
                });
              },
            ),
            const VSpace(12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: codeController,
                    focusNode: codeFocusNode,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: InputDecoration(
                      labelText: '验证码',
                      hintText: '请输入6位验证码',
                      counterText: '',
                      labelStyle:
                          TextStyle(color: theme.textColorScheme.secondary),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onSubmitted: (_) => _bindPhone(),
                  ),
                ),
                const HSpace(12),
                FlowyButton(
                  text: _getButtonText(),
                  onPressed: _canResendCode() ? _sendCode : null,
                  isLoading: _isSending,
                ),
              ],
            ),
            const VSpace(24),
            SizedBox(
              width: double.infinity,
              child: FlowyButton(
                text: '绑定手机号',
                onPressed: _isBinding ? null : _bindPhone,
                isLoading: _isBinding,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _canResendCode() {
    return _countdown == 0 && (_hasRequestedCode || _isSlideVerified);
  }

  String _getButtonText() {
    if (_countdown > 0) {
      return '重新获取(${_countdown}s)';
    } else if (_hasRequestedCode) {
      return '重新获取';
    } else {
      return '获取验证码';
    }
  }

  Future<void> _sendCode() async {
    if (!_canResendCode() || _isSending) return;

    final cleanPhone = Validator.cleanPhoneNumber(phoneController.text);
    if (!Validator.isValidPhone(cleanPhone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('手机号格式不正确'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _isSending = true;
    });

    final result =
        await ContactBindingService.sendPhoneVerificationCode(cleanPhone);

    result.fold(
      (_) {
        if (!mounted) return;
        setState(() {
          _countdown = 60;
          _isSending = false;
          _hasRequestedCode = true;
        });
        _startCountdown();
      },
      (error) {
        if (!mounted) return;
        setState(() {
          _isSending = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('发送失败: ${error.msg}'),
            duration: const Duration(seconds: 2),
          ),
        );
      },
    );
  }

  void _startCountdown() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 0) {
        setState(() {
          _countdown--;
        });
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _bindPhone() async {
    final cleanPhone = Validator.cleanPhoneNumber(phoneController.text);
    if (!Validator.isValidPhone(cleanPhone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('手机号格式不正确'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    if (codeController.text.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入6位验证码'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _isBinding = true;
    });

    final result = await ContactBindingService.bindPhoneNumber(
      cleanPhone,
      codeController.text,
    );

    if (!mounted) return;
    setState(() {
      _isBinding = false;
    });

    result.fold(
      (_) {
        Navigator.of(context).pop();
        widget.onBindComplete?.call();
      },
      (error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.msg),
            duration: const Duration(seconds: 2),
          ),
        );
      },
    );
  }
}

