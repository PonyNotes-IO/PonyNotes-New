import 'dart:async';

import 'package:appflowy/user/application/contact_binding_service.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/util/validator.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

/// 账号合并确认弹窗
/// 当第三方登录用户绑定手机号，但该手机号已被其他账号注册时显示此弹窗。
class AccountMergeDialog extends StatefulWidget {
  const AccountMergeDialog({
    super.key,
    required this.phone,
    this.onMergeComplete,
    this.onCancelled,
  });

  final String phone;
  final VoidCallback? onMergeComplete;
  final VoidCallback? onCancelled;

  @override
  State<AccountMergeDialog> createState() => _AccountMergeDialogState();
}

class _AccountMergeDialogState extends State<AccountMergeDialog> {
  final _codeController = TextEditingController();
  final _codeFocusNode = FocusNode();

  bool _isSending = false;
  bool _isMerging = false;
  bool _hasRequestedCode = false;
  int _countdown = 0;
  Timer? _timer;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    // 自动发送验证码
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sendCode();
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    _codeFocusNode.dispose();
    _timer?.cancel();
    super.dispose();
  }

  String _getButtonText() {
    if (_countdown > 0) return '重新获取(${_countdown}s)';
    if (_hasRequestedCode) return '重新获取';
    return '获取验证码';
  }

  bool _canResendCode() {
    return _countdown == 0 && _hasRequestedCode;
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

  Future<void> _sendCode() async {
    if (_isSending) return;

    final cleanPhone = Validator.cleanPhoneNumber(widget.phone);
    if (!Validator.isValidPhone(cleanPhone)) {
      _setError('手机号格式不正确');
      return;
    }

    setState(() => _isSending = true);

    final result =
        await ContactBindingService.sendPhoneVerificationCode(cleanPhone);

    if (!mounted) return;
    setState(() {
      _isSending = false;
    });

    result.fold(
      (_) {
        if (!mounted) return;
        setState(() {
          _countdown = 60;
          _hasRequestedCode = true;
          _errorMsg = null;
        });
        _startCountdown();
      },
      (error) {
        if (!mounted) return;
        setState(() => _errorMsg = error.msg);
      },
    );
  }

  Future<void> _mergeAccount() async {
    if (_isMerging) return;

    final cleanPhone = Validator.cleanPhoneNumber(widget.phone);
    final code = _codeController.text.trim();

    if (code.length != 6) {
      _setError('请输入6位验证码');
      return;
    }

    setState(() => _isMerging = true);

    final result = await UserBackendService.confirmPhoneBind(
      phone: cleanPhone,
      token: code,
      merge: true,
    );

    if (!mounted) return;
    setState(() => _isMerging = false);

    result.fold(
      (data) {
        if (data.merged) {
          final migratedCount = data.migratedWorkspaces ?? 0;
          final msg = migratedCount > 0
              ? '账号合并成功！$migratedCount 个工作区已迁移。'
              : '账号合并成功！';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
          Navigator.of(context).pop();
          widget.onMergeComplete?.call();
        } else {
          _setError(data.message ?? '合并失败');
        }
      },
      (error) => _setError(error.msg),
    );
  }

  void _setError(String msg) {
    setState(() => _errorMsg = msg);
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return Dialog(
      backgroundColor: theme.surfaceColorScheme.layer01,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.merge_type, color: Colors.orange, size: 20),
                ),
                const HSpace(12),
                Expanded(
                  child: FlowyText(
                    '账号合并',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: theme.textColorScheme.primary,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                    widget.onCancelled?.call();
                  },
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
            ),
            const VSpace(16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.orange, size: 18),
                  const HSpace(8),
                  Expanded(
                    child: FlowyText(
                      '该手机号已被其他账号注册。合并后，两个账号将成为一个账号，'
                      '原账号的所有数据将迁移到当前账号，原账号将被删除且无法登录。',
                      fontSize: 13,
                      color: theme.textColorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            const VSpace(8),
            FlowyText(
              '绑定手机号：${widget.phone}',
              fontSize: 13,
              color: theme.textColorScheme.secondary,
            ),
            const VSpace(16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeController,
                    focusNode: _codeFocusNode,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: InputDecoration(
                      labelText: '验证码',
                      hintText: '请输入6位验证码',
                      counterText: '',
                      labelStyle: TextStyle(color: theme.textColorScheme.secondary),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onSubmitted: (_) => _mergeAccount(),
                  ),
                ),
                const HSpace(12),
                FlowyButton(
                  text: _isSending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : FlowyText(_getButtonText(), fontSize: 14),
                  onTap: _canResendCode() ? _sendCode : null,
                ),
              ],
            ),
            if (_errorMsg != null) ...[
              const VSpace(8),
              FlowyText(
                _errorMsg!,
                fontSize: 12,
                color: Colors.red,
              ),
            ],
            const VSpace(20),
            Row(
              children: [
                Expanded(
                  child: FlowyButton(
                    text: FlowyText('取消', fontSize: 14),
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onCancelled?.call();
                    },
                  ),
                ),
                const HSpace(12),
                Expanded(
                  child: FlowyButton(
                    text: _isMerging
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2)),
                              HSpace(6),
                              FlowyText('合并中…', fontSize: 14),
                            ],
                          )
                        : const FlowyText('合并账号', fontSize: 14),
                    onTap: _isMerging ? null : _mergeAccount,
                  ),
                ),
              ],
            ),
            const VSpace(8),
            Center(
              child: FlowyText(
                '合并后原账号的第三方登录方式（微信/抖音等）将失效',
                fontSize: 11,
                color: theme.textColorScheme.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
