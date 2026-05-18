import 'dart:async';
import 'package:flowy_infra/platform_extension.dart';

import 'package:appflowy/user/application/sign_in_bloc.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:universal_platform/universal_platform.dart';

class ContinueWithPhoneSmsPage extends StatefulWidget {
  const ContinueWithPhoneSmsPage({
    super.key,
    required this.phone,
    required this.backToLogin,
    required this.onVerifySms,
  });

  final String phone;
  final VoidCallback backToLogin;
  final Function(String code) onVerifySms;

  @override
  State<ContinueWithPhoneSmsPage> createState() =>
      _ContinueWithPhoneSmsPageState();
}

class _ContinueWithPhoneSmsPageState extends State<ContinueWithPhoneSmsPage> {
  final List<TextEditingController> _codeControllers = List.generate(
    6,
    (index) => TextEditingController(),
  );
  final List<FocusNode> _codeFocusNodes = List.generate(
    6,
    (index) => FocusNode(),
  );

  bool _isLoading = false;
  int _countdown = 60;
  Timer? _timer;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _startCountdown();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _codeFocusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    for (final controller in _codeControllers) {
      controller.dispose();
    }
    for (final focusNode in _codeFocusNodes) {
      focusNode.dispose();
    }
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: BlocListener<SignInBloc, SignInState>(
        listener: (context, state) {
          final successOrFail = state.successOrFail;
          if (successOrFail != null) {
            setState(() => _isLoading = false);
            successOrFail.fold(
              (userProfile) async {
                setState(() => _errorMessage = '');
              },
              (error) {
                setState(() => _errorMessage = error.msg);
              },
            );
          }
        },
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 返回按钮
              _buildBackButton(),

              // 主要内容居中展示
              Expanded(
                child: Center(
                  child: Container(
                    width: PlatformInfo.isDesktopOrTablet ? 450 : double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const VSpace(20),

                        // 标题
                        const Text(
                          '请输入验证码',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF333333),
                          ),
                        ),
                        const VSpace(20),

                        // 验证码发送信息
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF777777),
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                            children: [
                              const TextSpan(text: '6位验证码已发送至 '),
                              TextSpan(
                                text: widget.phone,
                                style: const TextStyle(
                                  color: Color(0xFF333333),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const TextSpan(text: '，有效期15分钟。'),
                            ],
                          ),
                        ),
                        const VSpace(40),

                        // 验证码输入框
                        _buildVerificationCodeInputs(),

                        const VSpace(14),

                        // 重新发送验证码
                        _buildResendSection(),

                        // 错误提示
                        if (_errorMessage.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _errorMessage,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),

                        const VSpace(42),

                        // 下一步按钮
                        _buildNextButton(),

                        const Spacer(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackButton() {
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 8),
      child: IconButton(
        icon: const Icon(
          Icons.arrow_back,
          size: 24,
          color: Color(0xFF333333),
        ),
        onPressed: widget.backToLogin,
      ),
    );
  }

  Widget _buildVerificationCodeInputs() {
    const spacing = 12.0;
    // 桌面端固定每个方块 56px，移动端按屏幕宽度自适应
    final inputWidth = PlatformInfo.isDesktopOrTablet
        ? 56.0
        : (MediaQuery.of(context).size.width - (5 * spacing) - 40) / 6;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (index) {
        return Container(
          margin: EdgeInsets.only(right: index < 5 ? spacing : 0),
          child: Container(
            width: inputWidth,
            height: inputWidth,
            decoration: BoxDecoration(
              color: const Color(0xFFEBEBEB),
              borderRadius: BorderRadius.circular(4),
            ),
            child: KeyboardListener(
              focusNode: FocusNode(),
              onKeyEvent: (KeyEvent event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.backspace) {
                  if (_codeControllers[index].text.isEmpty && index > 0) {
                    _codeFocusNodes[index - 1].requestFocus();
                    _codeControllers[index - 1].clear();
                  }
                }
              },
              child: TextField(
                controller: _codeControllers[index],
                focusNode: _codeFocusNodes[index],
                textAlign: TextAlign.center,
                textAlignVertical: TextAlignVertical.center,
                keyboardType: TextInputType.number,
                textInputAction:
                    index < 5 ? TextInputAction.next : TextInputAction.done,
                expands: true,
                // ignore: avoid_redundant_argument_values
                minLines: null,
                // ignore: avoid_redundant_argument_values
                maxLines: null,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF333333),
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(1),
                ],
                decoration: InputDecoration(
                  border: InputBorder.none,
                  counterText: '',
                  contentPadding: EdgeInsets.zero,
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 1.5,
                    ),
                  ),
                ),

                onChanged: (value) {
                  if (_errorMessage.isNotEmpty) {
                    setState(() => _errorMessage = '');
                  }
                  if (value.length > 1) {
                    _codeControllers[index].text =
                        value.substring(value.length - 1);
                    _codeControllers[index].selection =
                        TextSelection.fromPosition(
                      TextPosition(
                          offset: _codeControllers[index].text.length,),
                    );
                  }
                  if (value.isNotEmpty && index < 5) {
                    _codeFocusNodes[index + 1].requestFocus();
                  }
                  final isAllFilled =
                      _codeControllers.every((c) => c.text.isNotEmpty);
                  if (isAllFilled) {
                    _validateAndSubmit();
                  }
                },
                onTap: () {
                  _codeControllers[index].clear();
                  _codeFocusNodes[index].requestFocus();
                },
                onSubmitted: (_) {
                  if (index < 5) {
                    _codeFocusNodes[index + 1].requestFocus();
                  } else {
                    _validateAndSubmit();
                  }
                },
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildResendSection() {
    return Row(
      children: [
        Text(
          '收不到验证码？',
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 13,
          ),
        ),
        const HSpace(8),
        if (_countdown > 0)
          Text(
            '$_countdown秒后重新获取',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.primary,
            ),
          )
        else
          GestureDetector(
            onTap: _resendCode,
            child: Text(
              '重新获取验证码',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildNextButton() {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _validateAndSubmit,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
        child: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text(
                '下一步',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
      ),
    );
  }

  void _validateAndSubmit() {
    final code = _codeControllers.map((c) => c.text).join();

    if (code.length != 6) {
      setState(() => _errorMessage = '验证码错误，请重新输入');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    widget.onVerifySms(code);
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _countdown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 0) {
        setState(() => _countdown--);
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _resendCode() async {
    try {
      for (final controller in _codeControllers) {
        controller.clear();
      }
      setState(() => _errorMessage = '');
      _codeFocusNodes[0].requestFocus();
      _startCountdown();

      if (mounted) {
        showToastNotification(
          message: '验证码已重新发送到您的手机',
        );
      }
    } catch (e) {
      setState(() => _errorMessage = '重新发送失败: $e');
    }
  }
}
