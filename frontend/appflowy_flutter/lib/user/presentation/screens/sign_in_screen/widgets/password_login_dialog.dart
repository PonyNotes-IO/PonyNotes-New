import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/sign_in_bloc.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/forgot_password_flow_page.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';

/// 密码登录对话框组件
/// 按照设计图二实现：账号密码登录页面
class PasswordLoginDialog extends StatefulWidget {
  const PasswordLoginDialog({
    super.key,
    required this.phoneOrEmail,
    required this.onPasswordLogin,
    required this.onSwitchToVerificationCode,
  });

  final String phoneOrEmail;
  final ValueChanged<String> onPasswordLogin;
  final VoidCallback onSwitchToVerificationCode;

  @override
  State<PasswordLoginDialog> createState() => _PasswordLoginDialogState();
}

class _PasswordLoginDialogState extends State<PasswordLoginDialog> {
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _passwordFocusNode = FocusNode();
  String _errorMessage = '';

  @override
  void dispose() {
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  void _handlePasswordLogin() {
    final password = _passwordController.text.trim();
    
    if (password.isEmpty) {
      setState(() {
        _errorMessage = '请输入密码';
      });
      return;
    }

    setState(() {
      _errorMessage = '';
    });

    widget.onPasswordLogin(password);
  }

  void _handleForgotPassword(BuildContext context) {
    
    final signInBloc = context.read<SignInBloc>();
    
    // 判断是邮箱还是手机号
    final isEmail = widget.phoneOrEmail.contains('@');
    
    // 发送验证码
    // forgotPassword API 支持邮箱和手机号（GoTrue 会自动检测）
    signInBloc.add(
      SignInEvent.forgotPassword(email: widget.phoneOrEmail),
    );
    
    // 关闭密码登录对话框
    Navigator.of(context).pop();
    
    // 跳转到忘记密码流程页面
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (context) => BlocProvider.value(
          value: signInBloc,
          child: ForgotPasswordFlowPage(
            phoneOrEmail: widget.phoneOrEmail,
            backToLogin: widget.onSwitchToVerificationCode,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return BlocListener<SignInBloc, SignInState>(
      listener: (context, state) {
        // 监听登录错误
        if (state.passwordError != null) {
          setState(() {
            _errorMessage = state.passwordError ?? '账号和密码不匹配,请重新输入';
          });
        } else if (state.successOrFail != null && state.successOrFail!.isFailure) {
          state.successOrFail!.fold(
            (_) {},
            (error) {
              setState(() {
                _errorMessage = error.msg.contains('Invalid login credentials') 
                    ? '账号和密码不匹配,请重新输入'
                    : error.msg;
              });
            },
          );
        } else if (state.successOrFail != null && state.successOrFail!.isSuccess) {
          // 登录成功，关闭对话框
          // 检查 context 是否仍然有效
          if (context.mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Container(
          width: 500,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题和验证码登录按钮行
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题
                  Text(
                    '账号密码登录',
                    style: textTheme.headlineSmall?.copyWith(
                      fontSize: 28,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  // 验证码登录按钮
                  TextButton(
                    onPressed: widget.onSwitchToVerificationCode,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: colorScheme.outlineVariant),
                      ),
                      foregroundColor: colorScheme.onSurface,
                    ),
                    child: Text(
                      '验证码登录',
                      style: TextStyle(
                        fontSize: 16,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const VSpace(8),
              
              // 说明文字
              Text(
                '使用已经注册过的账号登录',
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const VSpace(32),
              
              // 手机号输入框（只读，显示已输入的手机号）
              Container(
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceVariant,
                  border: Border.all(color: colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.phoneOrEmail,
                        style: TextStyle(
                          fontSize: 16,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const VSpace(16),
              
              // 密码输入框
              Container(
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceVariant,
                  border: Border.all(
                    color: _errorMessage.isNotEmpty 
                        ? colorScheme.error 
                        : colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TextField(
                  controller: _passwordController,
                  focusNode: _passwordFocusNode,
                  obscureText: true,
                  style: TextStyle(
                    fontSize: 16,
                    color: colorScheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: '输入设置的密码',
                    hintStyle: TextStyle(
                      fontSize: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onSubmitted: (_) => _handlePasswordLogin(),
                  onChanged: (_) {
                    if (_errorMessage.isNotEmpty) {
                      setState(() {
                        _errorMessage = '';
                      });
                    }
                  },
                ),
              ),
              
              // 错误提示和忘记密码链接行
              if (_errorMessage.isNotEmpty) ...[
                const VSpace(8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        _errorMessage,
                        style: TextStyle(
                          fontSize: 14,
                          color: colorScheme.error,
                        ),
                      ),
                    ),
                    BlocBuilder<SignInBloc, SignInState>(
                      builder: (context, state) {
                        return TextButton(
                          onPressed: state.isSubmitting ? null : () => _handleForgotPassword(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        '忘记密码?',
                        style: TextStyle(
                          fontSize: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                        );
                      },
                    ),
                  ],
                ),
              ] else ...[
                const VSpace(8),
                Align(
                  alignment: Alignment.centerRight,
                  child: BlocBuilder<SignInBloc, SignInState>(
                    builder: (context, state) {
                      return TextButton(
                        onPressed: state.isSubmitting ? null : () => _handleForgotPassword(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      '忘记密码?',
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                      );
                    },
                  ),
                ),
              ],
              
              const VSpace(32),
              
              // 确定按钮
              BlocBuilder<SignInBloc, SignInState>(
                builder: (context, state) {
                  return SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      onPressed: state.isSubmitting ? null : _handlePasswordLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF89575),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child: state.isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              '确定',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

