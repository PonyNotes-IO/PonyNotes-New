import 'package:appflowy/user/application/sign_in_bloc.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/continue_with_magic_link_or_passcode_page.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/set_new_password.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum ForgotPasswordFlowState {
  enterVerificationCode,
  setNewPassword,
}

/// 忘记密码流程页面
/// 1. 输入验证码
/// 2. 设置新密码
class ForgotPasswordFlowPage extends StatefulWidget {
  const ForgotPasswordFlowPage({
    super.key,
    required this.phoneOrEmail,
    required this.backToLogin,
  });

  final String phoneOrEmail;
  final VoidCallback backToLogin;

  @override
  State<ForgotPasswordFlowPage> createState() => _ForgotPasswordFlowPageState();
}

class _ForgotPasswordFlowPageState extends State<ForgotPasswordFlowPage> {
  ForgotPasswordFlowState _state = ForgotPasswordFlowState.enterVerificationCode;

  @override
  Widget build(BuildContext context) {
    return _buildCurrentState();
  }

  Widget _buildCurrentState() {
    switch (_state) {
      case ForgotPasswordFlowState.enterVerificationCode:
        return _buildVerificationCodePage();
      case ForgotPasswordFlowState.setNewPassword:
        return SetNewPasswordWidget(
          email: widget.phoneOrEmail,
          backToLogin: widget.backToLogin,
        );
    }
  }

  Widget _buildVerificationCodePage() {
    return Scaffold(
      body: BlocListener<SignInBloc, SignInState>(
        listener: (context, state) {
          // 监听验证码验证结果
          final validateResult = state.validateResetPasswordTokenSuccessOrFail;
          if (validateResult != null) {
            validateResult.fold(
              (success) {
                // 验证成功，进入设置新密码页面
                if (mounted) {
                  setState(() {
                    _state = ForgotPasswordFlowState.setNewPassword;
                  });
                }
              },
              (error) {
                // 验证失败，ContinueWithMagicLinkOrPasscodePage 会显示错误
                Log.error('🟢 [ForgotPasswordFlowPage] 验证码验证失败: ${error.msg}');
              },
            );
          }
        },
        child: ContinueWithMagicLinkOrPasscodePage(
          email: widget.phoneOrEmail,
          // 忘记密码场景下，返回按钮只需要关闭当前流程页面，回到登录页/上层路由
          // 不再调用外层传入的 backToLogin（其中可能持有已销毁的对话框 context）
          backToLogin: () {
            final navigator = Navigator.of(context, rootNavigator: true);
            if (navigator.canPop()) {
              navigator.pop();
            }
          },
          onEnterPasscode: (code) {
            // 判断是邮箱还是手机号
            final isEmail = widget.phoneOrEmail.contains('@');
            
            context.read<SignInBloc>().add(
                  SignInEvent.validateResetPasswordToken(
                    email: widget.phoneOrEmail,
                    token: code,
                    phone: isEmail ? null : widget.phoneOrEmail,
                  ),
                );
          },
        ),
      ),
    );
  }
}

