import 'dart:async';

import 'package:appflowy/user/application/contact_binding_service.dart';
import 'package:appflowy/util/validator.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/slide_verification_widget.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

class EmailBindingDialog extends StatefulWidget {
  const EmailBindingDialog({
    super.key,
    this.onBindingComplete,
    this.title = '绑定邮箱',
  });

  final VoidCallback? onBindingComplete;
  final String title;

  @override
  State<EmailBindingDialog> createState() => _EmailBindingDialogState();
}

class _EmailBindingDialogState extends State<EmailBindingDialog> {
  final emailController = TextEditingController();
  final codeController = TextEditingController();
  final emailFocusNode = FocusNode();
  final codeFocusNode = FocusNode();
  bool _isBinding = false;
  bool _isSending = false;
  bool _isSlideVerified = false;  // 滑块是否已验证（首次发码必须通过）
  bool _hasRequestedCode = false; // 是否已经请求过验证码
  int _countdown = 0;
  Timer? _timer;

  @override
  void dispose() {
    emailController.dispose();
    codeController.dispose();
    emailFocusNode.dispose();
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
            // 标题和关闭按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                FlowyText(
                  widget.title,
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
                      color: theme.surfaceColorScheme.layer02,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: theme.textColorScheme.secondary,
                    ),
                  ),
                ),
              ],
            ),
            
            const VSpace(32),
            
            // 邮箱输入框
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: emailController,
                  focusNode: emailFocusNode,
                  style: TextStyle(color: theme.textColorScheme.primary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: '请输入你的邮箱',
                    hintStyle: TextStyle(
                      color: theme.textColorScheme.secondary,
                      fontSize: 14,
                    ),
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: theme.textColorScheme.secondary),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: theme.textColorScheme.primary),
                    ),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (value) {
                    setState(() {});
                  },
                ),
              ],
            ),
            
            const VSpace(16),

            // 滑块验证组件（首次发码必须先通过）
            SlideVerificationWidget(
              onVerificationSuccess: () {
                setState(() {
                  _isSlideVerified = true;
                });
              },
            ),

            const VSpace(16),

            // 验证码输入框
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: codeController,
                        focusNode: codeFocusNode,
                        style: TextStyle(color: theme.textColorScheme.primary, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: '6位验证码',
                          hintStyle: TextStyle(
                            color: theme.textColorScheme.secondary,
                            fontSize: 14,
                          ),
                          border: OutlineInputBorder(
                            borderSide: BorderSide(color: theme.textColorScheme.secondary),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: theme.textColorScheme.primary),
                          ),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          counterText: '',
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        onChanged: (value) {
                          setState(() {});
                        },
                      ),
                    ),
                    const HSpace(12),
                    GestureDetector(
                      onTap: _canSendCode() ? _sendVerificationCode : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          border: Border.all(
                            color: _canSendCode()
                                ? theme.textColorScheme.primary
                                : theme.textColorScheme.secondary,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: _isSending
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      theme.textColorScheme.secondary),
                                ),
                              )
                            : FlowyText(
                                _getButtonText(),
                                fontSize: 14,
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            
            const VSpace(32),
            
            // 底部按钮
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.surfaceColorScheme.layer02,
                      foregroundColor: theme.textColorScheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: Text(
                      '取消',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                const HSpace(12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: (_canComplete() && !_isBinding) ? _completeBinding : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _canComplete() ? const Color(0xFFFF6B47) : theme.surfaceColorScheme.layer02,
                      foregroundColor:
                          _canComplete() ? Colors.white : theme.textColorScheme.secondary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: _isBinding
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            '完成',
                            style: TextStyle(fontSize: 16),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _canSendCode() {
    // 第一次发送：需要邮箱有效 + 滑块已验证 + 没有倒计时
    // 重新发送：需要邮箱有效 + 没有倒计时（不需要再次验证滑块）
    return emailController.text.isNotEmpty &&
           Validator.isValidEmail(emailController.text) &&
           _countdown == 0 &&
           (_hasRequestedCode || _isSlideVerified);
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

  bool _canComplete() {
    return emailController.text.isNotEmpty &&
           Validator.isValidEmail(emailController.text) &&
           codeController.text.length == 6 &&
           _hasRequestedCode;  // 必须先发送过验证码才能完成绑定
  }

  Future<void> _sendVerificationCode() async {
    if (!_canSendCode() || _isSending) return;

    // 验证邮箱格式
    if (!Validator.isValidEmail(emailController.text)) {
      showToastNotification(message: '请输入有效的邮箱地址');
      return;
    }

    setState(() {
      _isSending = true;
    });

    // 步骤1: 先检测邮箱是否已被其他账号注册
    final checkResult = await ContactBindingService.checkEmailRegistered(
      emailController.text,
    );

    if (!mounted) return;

    final isRegistered = checkResult.fold(
      (_) => false,
      (error) => error.msg.contains('已被其他账号注册'),
    );

    if (isRegistered) {
      setState(() {
        _isSending = false;
      });
      showToastNotification(message: '该邮箱已被其他账号注册');
      return;
    }

    // 步骤2: 邮箱未注册，发送验证码
    final result = await ContactBindingService.sendEmailVerificationCode(
      emailController.text,
    );

    result.fold(
      (success) {
        if (mounted) {
          setState(() {
            _countdown = 60;
            _isSending = false;
            _hasRequestedCode = true;  // 标记已请求过，后续重发不需要再过滑块
          });

          _startCountdown();

          showToastNotification(message: '验证码已发送到 ${emailController.text}');
        }
      },
      (error) {
        if (mounted) {
          setState(() {
            _isSending = false;
          });

          showToastNotification(message: '发送失败: ${error.msg}');
        }
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

  Future<void> _completeBinding() async {
    if (!_canComplete() || _isBinding) return;
    
    if (!_canComplete()) {
      showToastNotification(message: '请输入有效的邮箱地址和6位验证码');
      return;
    }
    
    setState(() {
      _isBinding = true;
    });
    
    // 调用真实的API绑定邮箱
    final result = await ContactBindingService.bindEmail(
      emailController.text,
      codeController.text,
    );
    
    result.fold(
      (success) {
        if (mounted) {
          widget.onBindingComplete?.call();
          Navigator.of(context).pop();
          
          showToastNotification(message: '邮箱 ${emailController.text} 绑定成功');
        }
      },
      (error) {
        if (mounted) {
          setState(() {
            _isBinding = false;
          });
          
          showToastNotification(message: '绑定失败: ${error.msg}');
        }
      },
    );
  }
}




