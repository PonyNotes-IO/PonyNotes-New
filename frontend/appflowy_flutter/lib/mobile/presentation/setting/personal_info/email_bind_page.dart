import 'dart:async';

import 'package:appflowy/mobile/presentation/base/app_bar/mobile_app_bar.dart';
import 'package:appflowy/user/application/contact_binding_service.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

class MobileEmailBindPage extends StatefulWidget {
  const MobileEmailBindPage({super.key});

  static const routeName = '/settings/email-bind';

  @override
  State<MobileEmailBindPage> createState() => _MobileEmailBindPageState();
}

class _MobileEmailBindPageState extends State<MobileEmailBindPage> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  bool _isSending = false;
  bool _isBinding = false;
  bool _hasRequestedCode = false;
  int _countdown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  bool get _canSendCode {
    final email = _emailController.text.trim();
    return email.isNotEmpty &&
           email.contains('@') &&
           _countdown == 0;
  }

  bool get _canBind {
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();
    return email.isNotEmpty &&
           email.contains('@') &&
           code.length == 6 &&
           _hasRequestedCode;
  }

  String get _codeButtonText {
    if (_countdown > 0) {
      return '$_countdown s';
    } else if (_hasRequestedCode) {
      return 'Resend';
    } else {
      return 'Get code';
    }
  }

  Future<void> _sendCode() async {
    if (!_canSendCode || _isSending) return;

    final email = _emailController.text.trim();
    setState(() => _isSending = true);

    // Check if email is already registered
    final checkResult = await ContactBindingService.checkEmailRegistered(email);
    final isRegistered = checkResult.fold(
      (_) => false,
      (error) => error.msg.contains('已被其他账号注册'),
    );

    if (isRegistered) {
      if (!mounted) return;
      setState(() => _isSending = false);
      showToastNotification(message: 'This email is already registered');
      return;
    }

    // Send verification code
    final result = await ContactBindingService.sendEmailVerificationCode(email);

    result.fold(
      (success) {
        if (!mounted) return;
        setState(() {
          _isSending = false;
          _countdown = 60;
          _hasRequestedCode = true;
        });
        _startCountdown();
        showToastNotification(message: 'Code sent to $email');
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

  Future<void> _bindEmail() async {
    if (!_canBind || _isBinding) return;

    final email = _emailController.text.trim();
    final code = _codeController.text.trim();

    setState(() => _isBinding = true);

    final result = await ContactBindingService.bindEmail(email, code);

    if (!mounted) return;
    setState(() => _isBinding = false);

    result.fold(
      (success) {
        Navigator.pop(context, true);
        showToastNotification(message: 'Binding successful');
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
        title: 'Bind Email',
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
                'Email Address',
                style: theme.textStyle.body.standard(
                  color: theme.textColorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'Enter email address',
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
              const SizedBox(height: 24),
              Text(
                'Verification Code',
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
                        hintText: '6-digit code',
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
                  text: _isBinding ? 'Binding...' : 'Bind Email',
                  onTap: () {
                    if (!_isBinding) _bindEmail();
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
