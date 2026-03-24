import 'dart:async';

import 'package:appflowy/user/application/contact_binding_service.dart';
import 'package:appflowy/util/validator.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/slide_verification_widget.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:flutter/material.dart';

/// 更改手机号码对话框
class PhoneChangeDialog extends StatefulWidget {
  const PhoneChangeDialog({
    super.key,
    this.onChangeComplete,
  });

  final VoidCallback? onChangeComplete;

  @override
  State<PhoneChangeDialog> createState() => _PhoneChangeDialogState();
}

class _PhoneChangeDialogState extends State<PhoneChangeDialog> {
  final phoneController = TextEditingController();
  final codeController = TextEditingController();
  final phoneFocusNode = FocusNode();
  final codeFocusNode = FocusNode();
  
  bool _isChanging = false;
  bool _isSending = false;
  bool _isSlideVerified = false;  // 滑块是否已验证
  bool _hasRequestedCode = false;  // 是否已经请求过验证码
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
            // 标题和关闭按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                FlowyText(
                  '更改手机号码',
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
              '请选择手机号导号码',
              fontSize: 14,
              color: theme.textColorScheme.secondary,
            ),
            
            const VSpace(24),
            
            // 手机号输入框
            Row(
              children: [
                // 国家代码选择器
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                // 手机号输入框
                Expanded(
                  child: TextField(
                    controller: phoneController,
                    focusNode: phoneFocusNode,
                    decoration: const InputDecoration(
                      hintText: '输入手机号码',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.phone,
                    onChanged: (value) {
                      setState(() {});
                    },
                  ),
                ),
              ],
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
            
            // 验证码输入和发送按钮
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: codeController,
                    focusNode: codeFocusNode,
                    decoration: const InputDecoration(
                      hintText: '6位短信验证码',
                      border: OutlineInputBorder(),
                      counterText: '',
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _canSendCode() 
                          ? const Color(0xFF00C853) 
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
                            color: _canSendCode() ? Colors.white : Colors.grey,
                          ),
                  ),
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
                    onPressed: _canComplete() ? _changePhone : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00C853),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: _isChanging
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text('确认'),
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
    // 第一次发送：需要手机号有效 + 滑块已验证 + 没有倒计时
    // 重新发送：需要手机号有效 + 没有倒计时（不需要再次验证滑块）
    return phoneController.text.isNotEmpty && 
           Validator.isValidPhone(phoneController.text) && 
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
    return phoneController.text.isNotEmpty && 
           codeController.text.length == 6 &&
           !_isChanging;
  }

  Future<void> _sendVerificationCode() async {
    if (!_canSendCode() || _isSending) return;
    
    final cleanPhone = Validator.cleanPhoneNumber(phoneController.text);
    
    setState(() {
      _isSending = true;
    });
    
    // 调用API发送验证码
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
          
          showToastNotification(
            message: '验证码已发送到 $cleanPhone',
          );
        }
      },
      (error) {
        if (mounted) {
          setState(() {
            _isSending = false;
          });
          
          showToastNotification(
            message: '发送失败: ${error.msg}',
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

  Future<void> _changePhone() async {
    if (!_canComplete()) return;
    
    final cleanPhone = Validator.cleanPhoneNumber(phoneController.text);
    
    setState(() {
      _isChanging = true;
    });
    
    // 调用API验证并绑定新手机号
    final result = await ContactBindingService.bindPhoneNumber(
      cleanPhone,
      codeController.text,
    );
    
    result.fold(
      (success) {
        if (mounted) {
          // 先关闭对话框
          Navigator.of(context).pop();
          
          // 然后调用回调（回调中会显示 SnackBar 和刷新数据）
          Future.delayed(const Duration(milliseconds: 100), () {
            widget.onChangeComplete?.call();
          });
        }
      },
      (error) {
        if (mounted) {
          setState(() {
            _isChanging = false;
          });
          
          showToastNotification(
            message: '更改失败: ${error.msg}',
          );
        }
      },
    );
  }
}
