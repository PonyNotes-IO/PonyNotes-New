import 'dart:async';
import 'package:appflowy/user/application/sign_in_bloc.dart';
import 'package:appflowy/user/presentation/router.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_backend/log.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:universal_platform/universal_platform.dart';

import '../../../../../../generated/locale_keys.g.dart';
import 'set_password_page.dart';
import '../../../../../../generated/flowy_svgs.g.dart';

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

      if (!mounted) return;
      final signInBloc = context.read<SignInBloc>();

      SignInState stateAfterSend;
      try {
        stateAfterSend = await waitSignInBlocSubmittingCycle(
          signInBloc,
          () {
            if (widget.onEnterPasscode != null) {
              signInBloc.add(SignInEvent.forgotPassword(email: widget.email));
            } else {
              signInBloc.add(
                SignInEvent.signInWithMagicLink(email: widget.email),
              );
            }
          },
        );
      } catch (e) {
        if (!mounted) return;
        setState(() => _errorMessage = '重新发送失败: $e');
        return;
      }

      if (!mounted) return;

      if (widget.onEnterPasscode != null) {
        final fp = stateAfterSend.forgotPasswordSuccessOrFail;
        if (fp != null && fp.isFailure) {
          fp.onFailure((err) {
            if (mounted) {
              setState(() => _errorMessage = err.msg);
            }
          });
          return;
        }
      } else {
        if (stateAfterSend.emailError != null) {
          setState(
            () => _errorMessage =
                stateAfterSend.emailError ?? '发送失败，请检查邮箱或手机号',
          );
          return;
        }
        if (stateAfterSend.successOrFail?.isFailure == true) {
          // 限流等错误由登录页 BlocListener 以 Toast 展示，此处不再提示“已重新发送”
          return;
        }
      }

      _startCountdown();

      final isEmail = widget.email.contains('@');
      showToastNotification(
        message: isEmail
            ? '验证码已重新发送到您的邮箱'
            : '验证码已重新发送到您的手机',
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
    
    // 如果提供了 onEnterPasscode 回调，优先使用回调（用于忘记密码等场景）
    if (widget.onEnterPasscode != null) {
      try {
        widget.onEnterPasscode!(code);
        // 回调会处理验证码验证，这里不需要清除 loading
        // 验证结果会通过 BlocListener 处理
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = '验证失败，请重试';
          });
        }
      }
      return;
    }
    
    // 否则，使用正常的登录流程
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
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '登录失败，请重试';
        });
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
                    // 检查用户是否设置了密码
                    final passwordIsSet = state.passwordIsSet ?? false;
                    
                    // 先关闭当前页面（验证码页面）
                    final navigator = Navigator.of(context, rootNavigator: true);
                    if (navigator.canPop()) {
                      navigator.pop();
                    }
                    
                    // 检查是否需要设置密码
                    if (!passwordIsSet) {
                      // 跳转到设置密码页面
                      // 由于 DeepLinkHandler 会处理设置密码的导航，这里不再重复处理
                      // 直接进入主界面
                      Log.info('[ContinueWithMagicLinkOrPasscodePage] 用户未设置密码，由 DeepLinkHandler 处理设置密码流程');
                      final rootContext = navigator.context;
                      if (rootContext.mounted) {
                        getIt<AuthRouter>().goHomeScreen(rootContext, userProfile);
                      } else {
                        Log.error('🟢 [ContinueWithMagicLinkOrPasscodePage] rootContext 未 mounted');
                      }
                    } else {
                      // 用户已设置密码，直接进入主界面
                      final rootContext = navigator.context;
                      if (rootContext.mounted) {
                        getIt<AuthRouter>().goHomeScreen(rootContext, userProfile);
                      } else {
                        Log.error('🟢 [ContinueWithMagicLinkOrPasscodePage] rootContext 未 mounted');
                      }
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
        
        // 监听验证码验证结果（用于忘记密码流程）
        final validateResult = state.validateResetPasswordTokenSuccessOrFail;
        if (validateResult != null && _isLoading) {
          validateResult.fold(
            (_) {
              // 验证成功，清除 loading（页面会通过回调处理导航）
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _errorMessage = '';
                });
              }
            },
            (error) {
              // 验证失败，显示错误信息
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _errorMessage = error.msg;
                });
              }
            },
          );
        }
        
        // 监听 isSubmitting 的变化（用于登录流程）
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
                child: Center(
                  child: Container(
                    width: UniversalPlatform.isDesktop ? 450 : double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const VSpace(20),
                        // 标题
                        Text(
                          LocaleKeys.signIn_pleaseEnterVerificationCode.tr(),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: theme.textColorScheme.primary,
                          ),
                        ),
                        const VSpace(20),

                        // 验证码发送信息
                        RichText(
                          text: TextSpan(
                            style: TextStyle(
                              fontSize: 14,
                              color: theme.textColorScheme.secondary,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                            children: [
                              const TextSpan(text: '6位验证码已发送至 '),
                              TextSpan(
                                text: widget.email,
                                style: TextStyle(
                                  color: theme.textColorScheme.primary,
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
                          SizedBox(
                            width: double.infinity,
                            child: Text(
                              _errorMessage,
                              style: TextStyle(
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
    final theme = AppFlowyTheme.of(context);
    return Container(
      alignment: Alignment.centerLeft,
      margin: const EdgeInsets.only(top: 20),
      child: IconButton(
        icon: FlowySvg(
          FlowySvgs.back_m,
          color: theme.textColorScheme.primary,
        ),
        onPressed: widget.backToLogin,
      ),
    );
  }

  Widget _buildVerificationCodeInputs() {
    final appTheme = AppFlowyTheme.of(context);
    final theme = Theme.of(context);
    // 桌面端固定每个方块 52px，移动端按屏幕宽度自适应但不超过 52px
    // 避免在 macOS 窗口宽 1400px 时每个方块变成 230px 的问题
    const spacing = 12.0;
    final screenWidth = MediaQuery.of(context).size.width;
    final calculatedWidth = (screenWidth - (5 * spacing) - 40) / 6;
    final inputWidth = UniversalPlatform.isDesktop ? 56.0 : calculatedWidth;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (index) {
        return Container(
          margin: EdgeInsets.only(right: index < 5 ? spacing : 0),
          child: Container(
            width: inputWidth,
            height: inputWidth, // 保持正方形
            decoration: BoxDecoration(
              color: appTheme.badgeColorScheme.color19Light1,
              borderRadius: BorderRadius.circular(4),
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
                  color: appTheme.textColorScheme.primary,
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
                      color: theme.colorScheme.primary,
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
    final primaryColor = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '收不到验证码？',
          style: TextStyle(
            color: theme.textColorScheme.secondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        Spacer(),
        if (_countdown > 0)
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w600
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
          )
        else
          GestureDetector(
            onTap: _resendCode,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '重新获取验证码',
                style: TextStyle(
                  color: primaryColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildNextButton() {
    final primaryColor = Theme.of(context).colorScheme.primary;
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
