import 'dart:async';

import 'package:appflowy/user/application/contact_binding_service.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/util/validator.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/slide_verification_widget.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

class IdentityVerificationDialog extends StatefulWidget {
  const IdentityVerificationDialog({
    super.key,
    required this.phoneNumber,
    this.onVerificationComplete,
  });

  final String phoneNumber;
  final VoidCallback? onVerificationComplete;

  @override
  State<IdentityVerificationDialog> createState() => _IdentityVerificationDialogState();
}

class _IdentityVerificationDialogState extends State<IdentityVerificationDialog> {
  final codeController = TextEditingController();
  final codeFocusNode = FocusNode();
  bool _isVerified = false;
  bool _isSending = false;
  bool _isSlideVerified = false;  // 滑块是否已验证
  bool _hasRequestedCode = false;  // 是否已经请求过验证码
  int _countdown = 0;
  Timer? _timer;

  @override
  void dispose() {
    codeController.dispose();
    codeFocusNode.dispose();
    _timer?.cancel();
    super.dispose();
  }

  /// 格式化手机号显示（脱敏处理）
  String _formatPhoneNumber(String phone) {
    final cleanPhone = Validator.cleanPhoneNumber(phone);
    if (cleanPhone.length >= 11) {
      return '${cleanPhone.substring(0, 3)}******${cleanPhone.substring(cleanPhone.length - 2)}';
    }
    return phone;
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
                  '身份验证',
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
            
            // 描述文字
            FlowyText(
              '为了你的账户安全，请先验证身份',
              fontSize: 14,
              color: theme.textColorScheme.secondary,
            ),
            
            const VSpace(24),
            
            // 手机号显示
            Row(
              children: [
                FlowyText(
                  '使用手机',
                  fontSize: 16,
                  color: theme.textColorScheme.primary,
                ),
                const Spacer(),
                FlowyText(
                  _formatPhoneNumber(widget.phoneNumber),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: theme.textColorScheme.primary,
                ),
                const HSpace(8),
                FlowyText(
                  '验证',
                  fontSize: 16,
                  color: theme.textColorScheme.primary,
                ),
                const HSpace(8),
                GestureDetector(
                  onTap: () {
                    // TODO: 实现切换验证方式
                  },
                  child: Row(
                    children: [
                      FlowyText(
                        '切换验证',
                        fontSize: 14,
                        color: const Color(0xFF4285F4),
                      ),
                      const HSpace(4),
                      const Icon(
                        Icons.keyboard_arrow_down,
                        size: 16,
                        color: Color(0xFF4285F4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const VSpace(16),
            
            // 验证通过提示（动态显示）
            if (_isVerified)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F9FF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 16,
                      color: Color(0xFF10B981),
                    ),
                    const HSpace(8),
                    FlowyText(
                      '验证通过',
                      fontSize: 14,
                      color: const Color(0xFF059669),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _isVerified = false;
                        });
                      },
                      child: const Icon(
                        Icons.close,
                        size: 16,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
              ),
            
            const VSpace(16),
            
            // 滑块验证组件
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
                        decoration: const InputDecoration(
                          hintText: '6位短信验证码',
                          border: OutlineInputBorder(),
                          counterText: '', // 隐藏字符计数
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8), // 调整内边距
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
                      onTap: _canResendCode() ? _sendVerificationCode : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: _canResendCode() 
                              ? const Color(0xFF4285F4) 
                              : Colors.grey.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: _isSending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : FlowyText(
                                _getButtonText(),
                                fontSize: 14,
                                color: _canResendCode() ? Colors.white : Colors.grey,
                              ),
                      ),
                    ),
                  ],
                ),
                const VSpace(8),
                // 只有在已经请求过验证码时才显示提示信息
                if (_hasRequestedCode)
                  FlowyText(
                    '短信验证码已发送至您的手机',
                    fontSize: 12,
                    color: theme.textColorScheme.secondary,
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
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('取消'),
                  ),
                ),
                const HSpace(12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: codeController.text.length == 6 ? _verifyCode : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4285F4),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('完成'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _canResendCode() {
    // 第一次发送：需要滑块已验证 + 没有倒计时
    // 重新发送：需要没有倒计时（不需要再次验证滑块）
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

  Future<void> _sendVerificationCode() async {
    if (!_canResendCode() || _isSending) return;
    
    // 清理手机号格式
    final cleanPhone = Validator.cleanPhoneNumber(widget.phoneNumber);
    
    // 验证手机号格式
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
    
    // 调用真实的API发送验证码
    final result = await ContactBindingService.sendPhoneVerificationCode(cleanPhone);
    
    result.fold(
      (success) {
        if (mounted) {
          setState(() {
            _countdown = 60;
            _isSending = false;
            _hasRequestedCode = true;  // 标记已经请求过验证码
          });
          
          _startCountdown();
          
          // 移除多余的 SnackBar 提示，输入框下方已有提示文本
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

  Future<void> _verifyCode() async {
    if (codeController.text.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入6位验证码'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    
    // 清理手机号格式
    final cleanPhone = Validator.cleanPhoneNumber(widget.phoneNumber);
    
    print('[IdentityVerificationDialog] 开始验证: phone=$cleanPhone, code=${codeController.text}');
    
    // 验证旧手机号的验证码（用于身份验证，不绑定手机号）
    // 使用 verifyPhoneReauthentication 来验证 phoneReauthenticationOtp 类型的验证码
    final result = await UserBackendService.verifyPhoneReauthentication(
      cleanPhone,
      codeController.text,
    );
    
    result.fold(
      (_) {
        print('[IdentityVerificationDialog] 验证成功');
        if (mounted) {
          setState(() {
            _isVerified = true;
          });
          
          // 延迟一下让用户看到验证成功的提示
          Future.delayed(const Duration(milliseconds: 800), () {
            // 再次检查mounted状态和验证状态，防止用户在延迟期间关闭对话框
            if (mounted && _isVerified) {
              Navigator.of(context).pop();
              // 调用回调，让父组件打开"更改手机号码"对话框
              widget.onVerificationComplete?.call();
            }
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('身份验证成功'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      },
      (error) {
        print('[IdentityVerificationDialog] 验证失败: code=${error.code}, msg=${error.msg}');
        if (mounted) {
          // 确保验证失败时 _isVerified 为 false
          setState(() {
            _isVerified = false;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('验证码错误: ${error.msg}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
    );
  }

  @override
  void initState() {
    super.initState();
    // 不再自动发送验证码，需要用户先拖动滑块验证
  }
}



