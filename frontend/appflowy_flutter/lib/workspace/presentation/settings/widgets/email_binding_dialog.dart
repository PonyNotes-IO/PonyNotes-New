import 'dart:async';

import 'package:appflowy/user/application/contact_binding_service.dart';
import 'package:appflowy/util/validator.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

class EmailBindingDialog extends StatefulWidget {
  const EmailBindingDialog({
    super.key,
    this.onBindingComplete,
  });

  final VoidCallback? onBindingComplete;

  @override
  State<EmailBindingDialog> createState() => _EmailBindingDialogState();
}

class _EmailBindingDialogState extends State<EmailBindingDialog> {
  final emailController = TextEditingController();
  final codeController = TextEditingController();
  final emailFocusNode = FocusNode();
  final codeFocusNode = FocusNode();
  bool _isCodeSent = false;
  bool _isBinding = false;
  bool _isSending = false;
  int _countdown = 0;  // 初始为0，允许立即发送验证码
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
                  '绑定邮箱',
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
            
            const VSpace(32),
            
            // 邮箱输入框
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: emailController,
                  focusNode: emailFocusNode,
                  decoration: const InputDecoration(
                    hintText: '请输入你的邮箱',
                    hintStyle: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF4285F4)),
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
                        decoration: const InputDecoration(
                          hintText: '6位短信验证码',
                          hintStyle: TextStyle(
                            color: Colors.grey,
                            fontSize: 14,
                          ),
                          border: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFF4285F4)),
                          ),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          counterText: '', // 隐藏字符计数
                          isDense: true, // 使输入框更紧凑
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
                                ? Colors.grey 
                                : Colors.grey.withOpacity(0.3),
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: _isSending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
                                ),
                              )
                            : FlowyText(
                                _canSendCode() ? '重新获取' : '重新获取(${_countdown}s)',
                                fontSize: 14,
                                color: _canSendCode() ? Colors.black : Colors.grey,
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
                      backgroundColor: Colors.grey[300],
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: const Text(
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
                      backgroundColor: _canComplete() 
                          ? const Color(0xFFFF6B47) 
                          : Colors.grey[300],
                      foregroundColor: _canComplete() 
                          ? Colors.white 
                          : Colors.grey,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: _isBinding
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
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
    return emailController.text.isNotEmpty && 
           emailController.text.contains('@') && 
           _countdown == 0;
  }

  bool _canComplete() {
    return emailController.text.isNotEmpty && 
           emailController.text.contains('@') && 
           codeController.text.length == 6;
  }

  Future<void> _sendVerificationCode() async {
    if (!_canSendCode() || _isSending) return;
    
    // 验证邮箱格式
    if (!Validator.isValidEmail(emailController.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入有效的邮箱地址'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    
    setState(() {
      _isSending = true;
    });
    
    // 调用真实的API发送验证码
    final result = await ContactBindingService.sendEmailVerificationCode(
      emailController.text,
    );
    
    result.fold(
      (success) {
        if (mounted) {
          setState(() {
            _isCodeSent = true;
            _countdown = 60;
            _isSending = false;
          });
          
          _startCountdown();
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('验证码已发送到 ${emailController.text}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      (error) {
        if (mounted) {
          setState(() {
            _isSending = false;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('发送失败: ${error.msg}'),
              duration: const Duration(seconds: 2),
            ),
          );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入有效的邮箱地址和6位验证码'),
          duration: Duration(seconds: 2),
        ),
      );
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
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('邮箱 ${emailController.text} 绑定成功'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      (error) {
        if (mounted) {
          setState(() {
            _isBinding = false;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('绑定失败: ${error.msg}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
    );
  }
}




