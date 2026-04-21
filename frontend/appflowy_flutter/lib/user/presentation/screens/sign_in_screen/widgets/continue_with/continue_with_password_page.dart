import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/user/application/sign_in_bloc.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/back_to_login_in_button.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/continue_with_button.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/forgot_password_page.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/title_logo.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/verifying_button.dart';
import 'package:appflowy/workspace/presentation/settings/pages/account/password/password_suffix_icon.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/widget/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'continue_with_magic_link_or_passcode_page.dart';

class ContinueWithPasswordPage extends StatefulWidget {
  const ContinueWithPasswordPage({
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
  State<ContinueWithPasswordPage> createState() =>
      _ContinueWithPasswordPageState();
}

class _ContinueWithPasswordPageState extends State<ContinueWithPasswordPage> {
  final passwordController = TextEditingController();
  final accountController = TextEditingController();
  final inputPasswordKey = GlobalKey<AFTextFieldState>();

  bool isSubmitting = false;

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    accountController.text = widget.email;
  }

  @override
  void dispose() {
    passwordController.dispose();
    accountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 320,
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
            child: Column(
              children: [
                VSpace(120),
                // Logo and title
                _buildLogoAndTitle(),
                Align(
                  alignment: Alignment.centerLeft,
                    child: FlowyText.semibold(
                  "使用已经注册过的手机号登录",
                  fontSize: 14,
                  color: theme.textColorScheme.secondary,
                )),
                VSpace(20),

                // account show
                _buildAccountSection(),
                VSpace(12),
                // Password input and buttons
                ..._buildPasswordSection(),

                // Back to login
                BackToLoginButton(
                  onTap: widget.backToLogin,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoAndTitle() {
    final theme = AppFlowyTheme.of(context);
    // 标题
    return Row(
      children: [
        Text(
          LocaleKeys.signIn_signInPassword.tr(),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: theme.textColorScheme.primary,
          ),
        ),
        Spacer(),
        OutlinedButton(
          onPressed: () {
            final signInBloc = context.read<SignInBloc>();
            Navigator.push(
              context,
              MaterialPageRoute(
                settings: const RouteSettings(name: '/continue-with-email-verification'),
                builder: (context) => BlocProvider.value(
                  value: signInBloc,
                  child: ContinueWithMagicLinkOrPasscodePage(
                    email: widget.email,
                    backToLogin: widget.backToLogin,
                  ),
                ),
              ),
            );
          },
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30), // 设置圆角半径
            ),
          ),
          child: FlowyText.small(LocaleKeys.signIn_verificationLogin.tr()),
        ),
      ],
    );
    return TitleLogo(
      title: LocaleKeys.signIn_enterPassword.tr(),
      informationBuilder: (context) => // email display
          RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: LocaleKeys.signIn_loginAs.tr(),
              style: theme.textStyle.body.standard(
                color: theme.textColorScheme.primary,
              ),
            ),
            TextSpan(
              text: ' ${widget.email}',
              style: theme.textStyle.body.enhanced(
                color: theme.textColorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPasswordSection() {
    final theme = AppFlowyTheme.of(context);
    final iconSize = 20.0;

    return [
      // Password input
      AFTextField(
        key: inputPasswordKey,
        controller: passwordController,
        hintText: LocaleKeys.signIn_enterPassword.tr(),
        autoFocus: true,
        obscureText: true,
        suffixIconConstraints: BoxConstraints.tightFor(
          width: iconSize + theme.spacing.m,
          height: iconSize,
        ),
        suffixIconBuilder: (context, isObscured) => PasswordSuffixIcon(
          isObscured: isObscured,
          onTap: () {
            inputPasswordKey.currentState?.syncObscured(!isObscured);
          },
        ),
        onSubmitted: widget.onEnterPassword,
      ),
      // todo: ask designer to provide the spacing
      VSpace(8),

      // Forgot password button
      Align(
        alignment: Alignment.centerRight,
        child: AFGhostTextButton(
          text: LocaleKeys.signIn_forgotPassword.tr(),
          size: AFButtonSize.s,
          padding: EdgeInsets.zero,
          onTap: () => _pushForgotPasswordPage(),
          textStyle: theme.textStyle.body.standard(
            color: theme.textColorScheme.action,
          ),
          textColor: (context, isHovering, disabled) {
            final theme = AppFlowyTheme.of(context);
            if (isHovering) {
              return theme.textColorScheme.actionHover;
            }
            return theme.textColorScheme.action;
          },
        ),
      ),
      VSpace(theme.spacing.xxl),

      // Continue button
      isSubmitting
          ? const VerifyingButton()
          : ContinueWithButton(
              text: LocaleKeys.web_continue.tr(),
              onTap: () => widget.onEnterPassword(passwordController.text),
            ),
      VSpace(20),
    ];
  }

  Future<void> _pushForgotPasswordPage() async {
    final signInBloc = context.read<SignInBloc>();
    final baseUrl = await getAppFlowyCloudUrl();

    if (mounted && context.mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          settings: const RouteSettings(name: '/forgot-password'),
          builder: (context) => BlocProvider.value(
            value: signInBloc,
            child: ForgotPasswordPage(
              email: widget.email,
              backToLogin: widget.backToLogin,
              baseUrl: baseUrl,
            ),
          ),
        ),
      );
    }
  }

  AFTextField _buildAccountSection() {
    return // Password input
        AFTextField(
      controller: accountController,
      hintText: LocaleKeys.signIn_enterYourEmailOrPhone.tr(),
      autoFocus: true,
    );
  }
}
