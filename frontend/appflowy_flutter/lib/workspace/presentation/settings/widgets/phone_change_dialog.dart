import 'dart:async';

import 'package:appflowy/user/application/contact_binding_service.dart';
import 'package:appflowy/util/validator.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
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
  int _countdown = 0;  // 初始为0，允许立即发送验证码
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
            
            // 滑动验证（简化版，实际项目中需要集成真实的滑动验证组件）
            Container(
              height: 40,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.withOpacity(0.3)),
              ),
              child: Center(
                child: FlowyText(
                  '按住滑块，拖动到右边',
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
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
                            _canSendCode() ? '获取验证码' : '获取验证码(${_countdown}s)',
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
    return phoneController.text.isNotEmpty && 
           Validator.isValidPhone(phoneController.text) && 
           _countdown == 0;
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
          });
          
          _startCountdown();
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('验证码已发送到 $cleanPhone'),
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('手机号更改成功'),
              duration: Duration(seconds: 2),
            ),
          );
          
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              widget.onChangeComplete?.call();
              Navigator.of(context).pop();
            }
          });
        }
      },
      (error) {
        if (mounted) {
          setState(() {
            _isChanging = false;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('更改失败: ${error.msg}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
    );
  }
}
