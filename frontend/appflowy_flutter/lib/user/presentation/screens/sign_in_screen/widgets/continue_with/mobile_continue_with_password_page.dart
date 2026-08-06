import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/user/application/sign_in_bloc.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/continue_with_magic_link_or_passcode_page.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/forgot_password_flow_page.dart';
import 'package:appflowy/workspace/presentation/settings/pages/account/password/password_suffix_icon.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class MobileContinueWithPasswordPage extends StatefulWidget {
  const MobileContinueWithPasswordPage({
    super.key,
    required this.backToLogin,
    required this.email,
    required this.onEnterPassword,
    required this.onForgotPassword,
  });

  final String email;
  final VoidCallback backToLogin;
  final ValueChanged<String> onEnterPassword;
  final VoidCallback onForgotPassword;

  @override
  State<MobileContinueWithPasswordPage> createState() =>
      _MobileContinueWithPasswordPageState();
}

class _MobileContinueWithPasswordPageState
    extends State<MobileContinueWithPasswordPage> {
  final passwordController = TextEditingController();
  final inputPasswordKey = GlobalKey<AFTextFieldState>();

  bool isSubmitting = false;

  @override
  void dispose() {
    passwordController.dispose();
    super.dispose();
  }

  void _switchToVerificationCode() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        settings:
            const RouteSettings(name: '/continue-with-email-verification'),
        builder: (context) => BlocProvider.value(
          value: context.read<SignInBloc>(),
          child: ContinueWithMagicLinkOrPasscodePage(
            email: widget.email,
            backToLogin: widget.backToLogin,
          ),
        ),
      ),
    );
  }

  Future<void> _pushForgotPasswordPage() async {
    final signInBloc = context.read<SignInBloc>();
    signInBloc.add(
      SignInEvent.forgotPassword(email: widget.email),
    );

    if (mounted && context.mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          settings: const RouteSettings(name: '/forgot-password'),
          builder: (context) => BlocProvider.value(
            value: signInBloc,
            child: ForgotPasswordFlowPage(
              phoneOrEmail: widget.email,
              backToLogin: widget.backToLogin,
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            color: theme.textColorScheme.primary,
          ),
          onPressed: widget.backToLogin,
        ),
        title: Text(
          '账号密码登录',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: theme.textColorScheme.primary,
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _switchToVerificationCode,
              child: FlowyText(
                LocaleKeys.signIn_verificationLogin.tr(),
                fontSize: 14,
                color: theme.textColorScheme.primary,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: BlocListener<SignInBloc, SignInState>(
          listener: (context, state) {
            final successOrFail = state.successOrFail;
            if (successOrFail != null && successOrFail.isFailure) {
              successOrFail.onFailure((error) {
                inputPasswordKey.currentState?.syncError(
                  errorText: LocaleKeys.signIn_invalidLoginCredentials.tr(),
                );
              });
            } else if (state.passwordError != null) {
              inputPasswordKey.currentState?.syncError(
                errorText: LocaleKeys.signIn_invalidLoginCredentials.tr(),
              );
            } else {
              inputPasswordKey.currentState?.clearError();
            }

            if (isSubmitting != state.isSubmitting) {
              setState(() {
                isSubmitting = state.isSubmitting;
              });
            }
          },
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),

                  // 说明文字
                  FlowyText.semibold(
                    "使用已经注册过的账号登录",
                    fontSize: 14,
                    color: theme.textColorScheme.secondary,
                  ),
                  const SizedBox(height: 20),

                  // 账号显示框（只读）
                  Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: theme.surfaceColorScheme.layer01,
                      border: Border.all(
                        color: theme.borderColorScheme.primary,
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: FlowyText(
                            widget.email,
                            fontSize: 14,
                            color: theme.textColorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 密码输入框
                  AFTextField(
                    key: inputPasswordKey,
                    controller: passwordController,
                    hintText: LocaleKeys.signIn_enterPassword.tr(),
                    autoFocus: true,
                    obscureText: true,
                    borderRadius: 18.0,
                    suffixIconConstraints: BoxConstraints.tightFor(
                      width: 20.0 + theme.spacing.m,
                      height: 20.0,
                    ),
                    suffixIconBuilder: (context, isObscured) =>
                        PasswordSuffixIcon(
                      isObscured: isObscured,
                      onTap: () {
                        inputPasswordKey.currentState
                            ?.syncObscured(!isObscured);
                      },
                    ),
                    onSubmitted: widget.onEnterPassword,
                  ),

                  const SizedBox(height: 8),

                  // 忘记密码按钮
                  Align(
                    alignment: Alignment.centerRight,
                    child: AFGhostTextButton(
                      text: LocaleKeys.signIn_forgotPassword.tr(),
                      size: AFButtonSize.m,
                      padding: EdgeInsets.zero,
                      onTap: () => _pushForgotPasswordPage(),
                      textStyle: theme.textStyle.body.standard(
                        color: theme.textColorScheme.secondary,
                      ),
                      textColor: (context, isHovering, disabled) {
                        final theme = AppFlowyTheme.of(context);
                        return theme.textColorScheme.secondary;
                      },
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 确定按钮
                  _buildSubmitButton(),

                  const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    final theme = AppFlowyTheme.of(context);
    final primaryColor = theme.textColorScheme.primary;

    if (isSubmitting) {
      return Container(
        height: 44,
        width: double.infinity,
        decoration: BoxDecoration(
          color: primaryColor.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => widget.onEnterPassword(passwordController.text),
      child: Container(
        height: 44,
        width: double.infinity,
        decoration: BoxDecoration(
          color: primaryColor,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Center(
          child: FlowyText.semibold(
            '确定',
            fontSize: 14,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
