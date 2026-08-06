import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/user/application/sign_in_bloc.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/back_to_login_in_button.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/continue_with_button.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/continue_with_magic_link_or_passcode_page.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/forgot_password_flow_page.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/verifying_button.dart';
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

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // AppBar with back button
            _buildAppBar(context),
            // Content
            Expanded(
              child: BlocListener<SignInBloc, SignInState>(
                listener: (context, state) {
                  final successOrFail = state.successOrFail;
                  if (successOrFail != null && successOrFail.isFailure) {
                    successOrFail.onFailure((error) {
                      inputPasswordKey.currentState?.syncError(
                        errorText:
                            LocaleKeys.signIn_invalidLoginCredentials.tr(),
                      );
                    });
                  } else if (state.passwordError != null) {
                    inputPasswordKey.currentState?.syncError(
                      errorText:
                          LocaleKeys.signIn_invalidLoginCredentials.tr(),
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
                      children: [
                        VSpace(20),
                        // Logo and title
                        _buildLogoAndTitle(),
                        VSpace(20),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FlowyText.semibold(
                            "使用已经注册过的账号登录",
                            fontSize: 14,
                            color: theme.textColorScheme.secondary,
                          ),
                        ),
                        VSpace(20),

                        // Account show
                        _buildAccountSection(),
                        VSpace(12),

                        // Password input and buttons
                        ..._buildPasswordSection(),

                        // Back to login
                        BackToLoginButton(
                          onTap: widget.backToLogin,
                        ),
                        VSpace(48),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: widget.backToLogin,
            icon: FlowySvg(
              FlowySvgs.mobile_return_s,
              size: const Size(7, 12),
              color: theme.iconColorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoAndTitle() {
    final theme = AppFlowyTheme.of(context);
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
        const Spacer(),
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
              borderRadius: BorderRadius.circular(30),
            ),
          ),
          child: FlowyText.small(LocaleKeys.signIn_verificationLogin.tr()),
        ),
      ],
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
        borderRadius: 18.0,
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
      VSpace(8),

      // Forgot password button
      Align(
        alignment: Alignment.centerRight,
        child: AFGhostTextButton(
          text: LocaleKeys.signIn_forgotPassword.tr(),
          size: AFButtonSize.m,
          padding: EdgeInsets.zero,
          onTap: () => _pushForgotPasswordPage(),
          textStyle: theme.textStyle.body.standard(
            color: theme.textColorScheme.action,
          ),
          textColor: (context, isHovering, disabled) {
            final theme = AppFlowyTheme.of(context);
            return theme.textColorScheme.primary;
          },
        ),
      ),
      VSpace(theme.spacing.xxl),

      // Continue button
      isSubmitting
          ? VerifyingButton(borderRadius: 18.0)
          : ContinueWithButton(
              text: LocaleKeys.web_continue.tr(),
              onTap: () => widget.onEnterPassword(passwordController.text),
              borderRadius: 18.0,
            ),
      VSpace(20),
    ];
  }

  Widget _buildAccountSection() {
    final theme = AppFlowyTheme.of(context);
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: theme.surfaceColorScheme.layer01,
        border: Border.all(color: theme.borderColorScheme.primary),
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
}
