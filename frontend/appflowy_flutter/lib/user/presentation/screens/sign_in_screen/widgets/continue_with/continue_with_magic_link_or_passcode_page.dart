import 'dart:async';
import 'package:appflowy/user/application/sign_in_bloc.dart';
import 'package:appflowy/user/presentation/router.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:appflowy_ui/appflowy_ui.dart';

class ContinueWithMagicLinkOrPasscodePage extends StatefulWidget {
  const ContinueWithMagicLinkOrPasscodePage({
    super.key,
    required this.backToLogin,
    required this.email,
    this.onEnterPasscode,
  });

  final String email;
  final VoidCallback backToLogin;
  final ValueChanged<String>? onEnterPasscode;

  @override
  State<ContinueWithMagicLinkOrPasscodePage> createState() =>
      _ContinueWithMagicLinkOrPasscodePageState();
}

class _ContinueWithMagicLinkOrPasscodePageState
    extends State<ContinueWithMagicLinkOrPasscodePage> {
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
    // 自动聚焦到第一个验证码输入框
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
      // 清空当前验证码输入
      for (final controller in _codeControllers) {
        controller.clear();
      }
      setState(() => _errorMessage = '');
      
      // 聚焦到第一个输入框
      _codeFocusNodes[0].requestFocus();
      
      // 调用SignInBloc重新发送邮箱验证码
      if (!mounted) return;
      context
          .read<SignInBloc>()
          .add(SignInEvent.signInWithMagicLink(email: widget.email));
      
      // 重新开始倒计时
      _startCountdown();
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('验证码已重新发送到您的邮箱'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      setState(() => _errorMessage = '重新发送失败: $e');
    }
  }

  void _validateAndSubmit() {
    // 防止重复提交
    if (_isLoading) {
      return;
    }
    
    final code = _codeControllers.map((c) => c.text).join();
    
    if (code.length != 6) {
      setState(() => _errorMessage = '验证码错误，请重新输入');
      return;
    }

    // 检查 context 是否仍然有效
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    
    // 优先使用 context.read<SignInBloc>() 来获取 bloc，避免使用已关闭的 bloc
    try {
      final signInBloc = context.read<SignInBloc>();
      
      // 检查 bloc 是否已关闭
      // 如果 bloc 已关闭，说明登录可能已经成功，Deep Link Handler 正在处理
      if (signInBloc.isClosed) {
        // Bloc 已关闭，清除 loading 状态
        // Deep Link Handler 会自动处理导航，这里不需要保持 loading
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = '';
          });
        }
        return;
      }
      
      signInBloc.add(
        SignInEvent.signInWithPasscode(
          email: widget.email,
          passcode: code,
        ),
      );
    } catch (e) {
      // 如果 bloc 已关闭或发生其他错误，尝试使用回调（向后兼容）
      if (widget.onEnterPasscode != null) {
        try {
          widget.onEnterPasscode!(code);
        } catch (e2) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _errorMessage = '登录失败，请重试';
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = '登录失败，请重试';
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Scaffold(
      backgroundColor: theme.surfaceColorScheme.layer01,
      body: BlocListener<SignInBloc, SignInState>(
      listener: (context, state) {
        // 监听登录状态变化
        final successOrFail = state.successOrFail;
        
        // 优先检查登录成功状态（无论 isSubmitting 如何）
        if (successOrFail != null && successOrFail.isSuccess) {
          // 登录成功，清除 loading 状态
          if (mounted && _isLoading) {
            setState(() {
              _isLoading = false;
              _errorMessage = '';
            });
          }
          
          // Deep Link Handler 会自动处理导航，但为了确保导航成功，
          // 我们也可以在这里尝试导航（如果 Deep Link Handler 没有处理）
          successOrFail.fold(
            (userProfile) {
              // 登录成功，尝试导航到主界面
              // 使用 Future.microtask 确保在下一个事件循环中执行，避免在 listener 中直接导航
              Future.microtask(() {
                if (mounted && context.mounted) {
                  try {
                    Log.info('🟢 [ContinueWithMagicLinkOrPasscodePage] 尝试导航到主界面');
                    
                    // 先关闭当前页面（验证码页面）
                    final navigator = Navigator.of(context, rootNavigator: true);
                    if (navigator.canPop()) {
                      Log.info('🟢 [ContinueWithMagicLinkOrPasscodePage] 关闭验证码页面');
                      navigator.pop();
                    }
                    
                    // 然后导航到主界面
                    final rootContext = navigator.context;
                    if (rootContext.mounted) {
                      Log.info('🟢 [ContinueWithMagicLinkOrPasscodePage] 调用 goHomeScreen');
                      getIt<AuthRouter>().goHomeScreen(rootContext, userProfile);
                    } else {
                      Log.error('🟢 [ContinueWithMagicLinkOrPasscodePage] rootContext 未 mounted');
                    }
                  } catch (e, stackTrace) {
                    Log.error('🟢 [ContinueWithMagicLinkOrPasscodePage] 导航失败: $e', stackTrace);
                  }
                } else {
                  Log.error('🟢 [ContinueWithMagicLinkOrPasscodePage] context 未 mounted');
                }
              });
            },
            (_) {},
          );
          return;
        }
        
        // 监听 isSubmitting 的变化
        if (_isLoading && !state.isSubmitting) {
          // 从loading变为非loading状态
          if (mounted) {
            setState(() => _isLoading = false);
          }
          
          // 检查是否有错误
          if (successOrFail != null && successOrFail.isFailure) {
            // 有错误，显示错误信息
            successOrFail.fold(
              (_) {},
              (error) {
                if (mounted) {
                  setState(() => _errorMessage = error.msg);
                }
              },
            );
          }
        }
        },
        child: SafeArea(
          child: Column(
            children: [
              // 返回按钮
              _buildBackButton(),
              
              // 主要内容
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    children: [
                      const VSpace(40),
                      
                      // 标题
                      Text(
                        '请输入验证码',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w500,
                          color: theme.textColorScheme.primary,
                        ),
                      ),
                      const VSpace(20),
                      
                      // 验证码发送信息
                      RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 20,
                            color: theme.textColorScheme.secondary,
                            height: 1.4,
                          ),
                          children: [
                            const TextSpan(text: '6位验证码已发送至 '),
                            TextSpan(
                              text: widget.email,
                              style: TextStyle(
                                color: theme.textColorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const TextSpan(text: '，有效期15分钟。'),
                          ],
                        ),
                      ),
                      const VSpace(80),
                      
                      // 验证码输入框
                      _buildVerificationCodeInputs(),
                      
                      const VSpace(20),
                      
                      // 错误提示
                      if (_errorMessage.isNotEmpty)
                        Container(
                          width: double.infinity,
                          alignment: Alignment.center,
                          child: Text(
                            _errorMessage,
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: 20,
                            ),
                          ),
                        ),
                      
                      const VSpace(40),
                      
                      // 重新发送验证码
                      _buildResendSection(),
                      
                      const VSpace(40),
                      
                      // 下一步按钮
                      _buildNextButton(),
                      
                      const Spacer(),
                    ],
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
    final theme = AppFlowyTheme.of(context);
    return Container(
      alignment: Alignment.centerLeft,
      margin: const EdgeInsets.only(left: 32, top: 20),
      child: IconButton(
        icon: Icon(
          Icons.arrow_back,
          size: 24,
          color: theme.textColorScheme.primary,
        ),
        onPressed: widget.backToLogin,
      ),
    );
  }

  Widget _buildVerificationCodeInputs() {
    final theme = AppFlowyTheme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (index) {
        return Container(
          margin: EdgeInsets.only(right: index < 5 ? 12 : 0),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: theme.surfaceColorScheme.layer02,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: theme.borderColorScheme.primary,
                width: 1,
              ),
            ),
            child: KeyboardListener(
              focusNode: FocusNode(),
              onKeyEvent: (KeyEvent event) {
                if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.backspace) {
                  if (_codeControllers[index].text.isEmpty && index > 0) {
                    // 如果当前输入框为空且不是第一个，则跳到前一个输入框并清空
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
                textInputAction: index < 5 ? TextInputAction.next : TextInputAction.done,
                expands: true,
                // ignore: avoid_redundant_argument_values
                minLines: null,
                // ignore: avoid_redundant_argument_values
                maxLines: null,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: theme.textColorScheme.primary,
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
                      color: const Color(0xFFF89575),
                      width: 1.5,
                    ),
                  ),
                ),
                onChanged: (value) {
                  // 清除错误信息
                  if (_errorMessage.isNotEmpty) {
                    setState(() => _errorMessage = '');
                  }
                  
                  // 只保留最后一个字符
                  if (value.length > 1) {
                    _codeControllers[index].text = value.substring(value.length - 1);
                    _codeControllers[index].selection = TextSelection.fromPosition(
                      TextPosition(offset: _codeControllers[index].text.length),
                    );
                  }
                  if (value.isNotEmpty && index < 5) {
                    _codeFocusNodes[index + 1].requestFocus();
                  }
                  // 移除自动提交逻辑，改为由"下一步"按钮触发
                },
                onTap: () {
                  // 点击时清空当前输入框并聚焦
                  _codeControllers[index].clear();
                  _codeFocusNodes[index].requestFocus();
                },
                onSubmitted: (_) {
                  if (index < 5) {
                    _codeFocusNodes[index + 1].requestFocus();
                  }
                  // 移除自动提交逻辑，改为由"下一步"按钮触发
                },
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildResendSection() {
    final theme = AppFlowyTheme.of(context);
    final primaryColor = const Color(0xFFF89575);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '收不到验证码？',
          style: TextStyle(
            color: theme.textColorScheme.secondary,
            fontSize: 20,
          ),
        ),
        const HSpace(12),
        if (_countdown > 0)
          SizedBox(
            width: 211,
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: TextStyle(
                  fontSize: 20,
                  height: 1.4,
                ),
                children: [
                  TextSpan(
                    text: '$_countdown',
                    style: TextStyle(
                      color: primaryColor,
                    ),
                  ),
                  TextSpan(
                    text: '秒后重新获取验证码',
                    style: TextStyle(
                      color: theme.textColorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          GestureDetector(
            onTap: _resendCode,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '重新获取验证码',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildNextButton() {
    final primaryColor = const Color(0xFFF89575);
    return SizedBox(
      width: 418,
      height: 52,
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
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                ),
              ),
      ),
    );
  }
}
