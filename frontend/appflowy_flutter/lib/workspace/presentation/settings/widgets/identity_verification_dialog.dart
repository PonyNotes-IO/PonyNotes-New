import 'dart:async';

import 'package:appflowy/user/application/contact_binding_service.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/util/validator.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/slide_verification_widget.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:flutter/material.dart';

/// 身份验证方式枚举
enum VerificationMethod {
  phone,
  email,
}

/// 身份验证对话框
/// 支持手机短信和邮箱验证码两种验证方式，可通过"切换验证"按钮切换
class IdentityVerificationDialog extends StatefulWidget {
  const IdentityVerificationDialog({
    super.key,
    required this.phoneNumber,
    this.onVerificationComplete,
    this.emailAddress,
  });

  final String phoneNumber;
  /// 用户已绑定的邮箱地址（可选，用于邮箱验证）
  final String? emailAddress;
  final VoidCallback? onVerificationComplete;

  @override
  State<IdentityVerificationDialog> createState() => _IdentityVerificationDialogState();
}

class _IdentityVerificationDialogState extends State<IdentityVerificationDialog> {
  // 当前验证方式
  VerificationMethod _currentMethod = VerificationMethod.phone;
  // 邮箱输入（用于邮箱验证）
  final _emailController = TextEditingController();
  // 验证码
  final _codeController = TextEditingController();
  final _codeFocusNode = FocusNode();
  bool _isVerified = false;
  bool _isSending = false;
  bool _isSlideVerified = false;
  bool _hasRequestedCode = false;
  int _countdown = 0;
  Timer? _timer;
  // 验证方式切换弹层控制器
  final _switchController = PopoverController();

  String get _effectiveEmail =>
      widget.emailAddress ?? _emailController.text.trim();

  bool get _canUseEmail =>
      widget.emailAddress != null && widget.emailAddress!.isNotEmpty;

  bool get _canSwitch => _canUseEmail;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _codeFocusNode.dispose();
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
            _buildHeader(theme),
            const VSpace(8),
            _buildDescription(theme),
            const VSpace(24),
            // 验证方式切换区
            _buildMethodSelector(theme),
            const VSpace(16),
            // 验证通过提示
            if (_isVerified) _buildVerifiedBanner(theme),
            if (_isVerified) const VSpace(16),
            // 邮箱输入（仅邮箱验证时显示）
            if (_currentMethod == VerificationMethod.email &&
                widget.emailAddress == null)
              _buildEmailInput(theme),
            if (_currentMethod == VerificationMethod.email &&
                widget.emailAddress == null)
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
            // 验证码输入区
            _buildCodeInput(theme),
            const VSpace(32),
            // 底部按钮
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(dynamic theme) {
    return Row(
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
            child: const Icon(Icons.close, size: 16, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Widget _buildDescription(dynamic theme) {
    return FlowyText(
      '为了你的账户安全，请先验证身份',
      fontSize: 14,
      color: theme.textColorScheme.secondary,
    );
  }

  /// 验证方式选择器：显示当前方式 + 切换按钮（仅邮箱可用时显示）
  Widget _buildMethodSelector(dynamic theme) {
    final isPhone = _currentMethod == VerificationMethod.phone;
    final label = isPhone ? '使用手机' : '使用邮箱';

    return Row(
      children: [
        FlowyText(
          label,
          fontSize: 16,
          color: theme.textColorScheme.primary,
        ),
        const HSpace(8),
        if (isPhone)
          FlowyText(
            _formatPhoneNumber(widget.phoneNumber),
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: theme.textColorScheme.primary,
          )
        else if (widget.emailAddress != null)
          FlowyText(
            _formatEmail(widget.emailAddress!),
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
        if (_canSwitch)
          AppFlowyPopover(
            controller: _switchController,
            direction: PopoverDirection.bottomWithLeftAligned,
            offset: const Offset(0, 8),
            margin: EdgeInsets.zero,
            constraints: const BoxConstraints(maxWidth: 180),
            popupBuilder: (_) => _MethodSwitchPopover(
              current: _currentMethod,
              onSelected: (method) {
                _switchController.close();
                if (method != _currentMethod) {
                  setState(() {
                    _currentMethod = method;
                    _isSlideVerified = false;
                    _hasRequestedCode = false;
                    _countdown = 0;
                    _timer?.cancel();
                    _codeController.clear();
                  });
                }
              },
            ),
            child: GestureDetector(
              onTap: () => _switchController.show(),
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
          ),
      ],
    );
  }

  Widget _buildVerifiedBanner(dynamic theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, size: 16, color: Color(0xFF10B981)),
          const HSpace(8),
          FlowyText(
            '验证通过',
            fontSize: 14,
            color: const Color(0xFF059669),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() => _isVerified = false),
            child: const Icon(Icons.close, size: 16, color: Color(0xFF9CA3AF)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailInput(dynamic theme) {
    return TextField(
      controller: _emailController,
      decoration: InputDecoration(
        hintText: '请输入邮箱地址',
        hintStyle: TextStyle(color: theme.textColorScheme.secondary, fontSize: 14),
        border: OutlineInputBorder(
          borderSide: BorderSide(color: theme.textColorScheme.secondary),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: theme.textColorScheme.primary),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      keyboardType: TextInputType.emailAddress,
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _buildCodeInput(dynamic theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _codeController,
                focusNode: _codeFocusNode,
                decoration: const InputDecoration(
                  hintText: '6位短信/邮件验证码',
                  border: OutlineInputBorder(),
                  counterText: '',
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
                maxLength: 6,
                onChanged: (value) => setState(() {}),
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
        if (_hasRequestedCode)
          FlowyText(
            _currentMethod == VerificationMethod.phone
                ? '短信验证码已发送至您的手机'
                : '邮件验证码已发送至您的邮箱',
            fontSize: 12,
            color: theme.textColorScheme.secondary,
          ),
      ],
    );
  }

  Widget _buildActions() {
    return Row(
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
            onPressed: _codeController.text.length == 6 ? _verifyCode : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4285F4),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: const Text('完成'),
          ),
        ),
      ],
    );
  }

  bool _canResendCode() {
    if (_currentMethod == VerificationMethod.phone) {
      return _countdown == 0 && (_hasRequestedCode || _isSlideVerified);
    } else {
      final email = _effectiveEmail;
      return _countdown == 0 &&
          (_hasRequestedCode || _isSlideVerified) &&
          email.isNotEmpty &&
          email.contains('@');
    }
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
      return;
    }

    setState(() => _isSending = true);

    final result = await ContactBindingService.sendPhoneVerificationCode(cleanPhone);
    result.fold(
      (success) {
        if (mounted) {
          setState(() {
            _countdown = 60;
            _isSending = false;
            _hasRequestedCode = true;
          });
          _startCountdown();
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
      return;
    }

    setState(() => _isSending = true);

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
    if (_codeController.text.length != 6) {
      showToastNotification(message: '请输入6位验证码');
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
    setState(() => _isVerified = true);
    showToastNotification(message: '身份验证成功');

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted && _isVerified) {
        Navigator.of(context).pop();
        widget.onVerificationComplete?.call();
      }
    });
  }

  void _onVerificationFailure(error) {
    setState(() => _isVerified = false);
    showToastNotification(message: '验证码错误: ${error.msg}');
  }

  @override
  void initState() {
    super.initState();
  }
}

/// 验证方式切换弹层内容
class _MethodSwitchPopover extends StatelessWidget {
  const _MethodSwitchPopover({
    required this.current,
    required this.onSelected,
  });

  final VerificationMethod current;
  final void Function(VerificationMethod) onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final borderColor = theme.surfaceColorScheme.layer02;

    return Container(
      decoration: BoxDecoration(
        color: theme.surfaceColorScheme.layer01,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: borderColor,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildOption(
            context: context,
            theme: theme,
            method: VerificationMethod.phone,
            icon: Icons.phone_android,
            label: '手机验证',
          ),
          Container(
            height: 1,
            color: borderColor.withOpacity(0.5),
          ),
          _buildOption(
            context: context,
            theme: theme,
            method: VerificationMethod.email,
            icon: Icons.email_outlined,
            label: '邮箱验证',
          ),
        ],
      ),
    );
  }

  Widget _buildOption({
    required BuildContext context,
    required dynamic theme,
    required VerificationMethod method,
    required IconData icon,
    required String label,
  }) {
    final isSelected = method == current;
    final isDisabled = method == current;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isDisabled ? null : () => onSelected(method),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected
                    ? const Color(0xFF4285F4)
                    : theme.textColorScheme.primary,
              ),
              const HSpace(12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: isSelected
                        ? const Color(0xFF4285F4)
                        : theme.textColorScheme.primary,
                    fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check,
                  size: 16,
                  color: const Color(0xFF4285F4),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
