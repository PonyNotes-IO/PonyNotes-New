import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/user/application/sign_in_bloc.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/back_to_login_in_button.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/continue_with_button.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/title_logo.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/verifying_button.dart';
import 'package:appflowy/workspace/presentation/settings/pages/account/password/password_suffix_icon.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/platform_extension.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/widget/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../generated/flowy_svgs.g.dart';

class SetNewPasswordWidget extends StatefulWidget {
  const SetNewPasswordWidget({
    super.key,
    required this.backToLogin,
    required this.email,
  });

  final String email;
  final VoidCallback backToLogin;

  @override
  State<SetNewPasswordWidget> createState() => _SetNewPasswordWidgetState();
}

class _SetNewPasswordWidgetState extends State<SetNewPasswordWidget> {
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final accountController = TextEditingController();

  final newPasswordKey = GlobalKey<AFTextFieldState>();
  final confirmPasswordKey = GlobalKey<AFTextFieldState>();

  bool isSubmitting = false;

  @override
  void initState() {
    super.initState();
    accountController.text = widget.email;
  }

  @override
  void dispose() {
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    accountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SignInBloc, SignInState>(
      listener: (context, state) {
        final successOrFail = state.resetPasswordSuccessOrFail;
        if (successOrFail != null) {
          successOrFail.fold(
            (success) {
              showToastNotification(
                message: LocaleKeys.signIn_resetPasswordSuccess.tr(),
              );
              // 重置密码成功，关闭忘记密码流程页面，返回登录页
              // 只 pop 当前页面，不调用传入的回调（可能持有已销毁的 context）
              // 使用同步方式 pop，避免在异步回调中访问可能已销毁的 context
              if (mounted) {
                final navigator = Navigator.of(context, rootNavigator: true);
                if (navigator.canPop()) {
                  navigator.pop();
                }
              }
            },
            (error) {
              if (error.code == ErrorCode.NewPasswordTooWeak) {
                newPasswordKey.currentState?.syncError(
                  errorText: LocaleKeys.signIn_passwordMustContain.tr(),
                );
              } else {
                newPasswordKey.currentState?.syncError(
                  errorText: error.msg,
                );
              }
            },
          );
        }
        // Handle state changes and validation results here
        if (state.isSubmitting != isSubmitting) {
          setState(() => isSubmitting = state.isSubmitting);
        }
      },
      builder: (context, state) {
        if (PlatformInfo.isMobile) {
          return _buildMobileLayout();
        }
        return _buildDesktopLayout();
      },
    );
  }

  // ===================== Mobile Layout =====================

  Widget _buildMobileLayout() {
    final theme = AppFlowyTheme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 返回按钮
            _buildMobileBackButton(),
            // 主内容区域
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const VSpace(28),
                    // 标题
                    Text(
                      LocaleKeys.signIn_resetPassword.tr(),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: theme.textColorScheme.primary,
                      ),
                    ),
                    const VSpace(8),
                    // 密码要求提示
                    Text(
                      LocaleKeys.signIn_passwordRequirementHint.tr(),
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.textColorScheme.secondary,
                      ),
                    ),
                    const VSpace(28),
                    // 账号只读显示
                    AFTextField(
                      controller: accountController,
                      hintText: '',
                      readOnly: true,
                      borderRadius: 18.0,
                    ),
                    const VSpace(16),
                    // 新密码输入
                    _buildMobilePasswordField(
                      key: newPasswordKey,
                      controller: newPasswordController,
                      hintText: LocaleKeys.signIn_enterNewPassword.tr(),
                    ),
                    const VSpace(16),
                    // 确认密码输入
                    _buildMobilePasswordField(
                      key: confirmPasswordKey,
                      controller: confirmPasswordController,
                      hintText: LocaleKeys.signIn_confirmNewPassword.tr(),
                    ),
                  ],
                ),
              ),
            ),
            // 底部确定按钮
            _buildMobileConfirmButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileBackButton() {
    final theme = AppFlowyTheme.of(context);
    return Container(
      alignment: Alignment.centerLeft,
      margin: const EdgeInsets.only(top: 8),
      child: IconButton(
        icon: FlowySvg(
          FlowySvgs.back_m,
          color: theme.textColorScheme.primary,
        ),
        onPressed: () {
          final navigator = Navigator.of(context, rootNavigator: true);
          if (navigator.canPop()) {
            navigator.pop();
          }
        },
      ),
    );
  }

  Widget _buildMobilePasswordField({
    required GlobalKey<AFTextFieldState> key,
    required TextEditingController controller,
    required String hintText,
  }) {
    final theme = AppFlowyTheme.of(context);
    final iconSize = 20.0;
    return AFTextField(
      key: key,
      controller: controller,
      obscureText: true,
      hintText: hintText,
      borderRadius: 18.0,
      suffixIconConstraints: BoxConstraints.tightFor(
        width: iconSize + theme.spacing.m,
        height: iconSize,
      ),
      suffixIconBuilder: (context, isObscured) => PasswordSuffixIcon(
        isObscured: isObscured,
        onTap: () {
          key.currentState?.syncObscured(!isObscured);
        },
      ),
      onSubmitted: (_) => _validateAndSubmit(),
    );
  }

  Widget _buildMobileConfirmButton() {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
      child: SizedBox(
        width: double.infinity,
        height: 46,
        child: isSubmitting
            ? const VerifyingButton(borderRadius: 23.0)
            : ContinueWithButton(
                text: LocaleKeys.button_ok.tr(),
                onTap: _validateAndSubmit,
                borderRadius: 18.0,
              ),
      ),
    );
  }

  // ===================== Desktop Layout (unchanged) =====================

  Widget _buildDesktopLayout() {
    final theme = AppFlowyTheme.of(context);
    final spacing = theme.spacing.xxl;
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 320,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildDesktopLogoAndTitle(),
              _buildDesktopPasswordFields(),
              VSpace(spacing),
              _buildDesktopResetButton(),
              VSpace(spacing),
              BackToLoginButton(
                onTap: () {
                  // 只 pop 当前页面，不调用传入的回调（可能持有已销毁的 context）
                  // 使用同步方式 pop，避免在异步回调中访问可能已销毁的 context
                  final navigator = Navigator.of(context, rootNavigator: true);
                  if (navigator.canPop()) {
                    navigator.pop();
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopLogoAndTitle() {
    final theme = AppFlowyTheme.of(context);
    return TitleLogo(
      title: LocaleKeys.signIn_resetPassword.tr(),
      informationBuilder: (context) => RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: LocaleKeys.signIn_enterNewPasswordFor.tr(),
              style: theme.textStyle.body.standard(
                color: theme.textColorScheme.primary,
              ),
            ),
            TextSpan(
              text: widget.email,
              style: theme.textStyle.body.enhanced(
                color: theme.textColorScheme.primary,
              ),
            ),
            TextSpan(
              text: LocaleKeys.signIn_enterNewPasswordSuffix.tr(),
              style: theme.textStyle.body.standard(
                color: theme.textColorScheme.primary,
              ),
            ),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildDesktopPasswordFields() {
    final theme = AppFlowyTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          LocaleKeys.signIn_newPassword.tr(),
          style: theme.textStyle.caption.enhanced(
            color: theme.textColorScheme.secondary,
          ),
        ),
        const VSpace(8),
        AFTextField(
          key: newPasswordKey,
          controller: newPasswordController,
          obscureText: true,
          hintText: LocaleKeys.signIn_enterNewPassword.tr(),
          onSubmitted: (_) => _validateAndSubmit(),
        ),
        const VSpace(16),
        Text(
          LocaleKeys.signIn_confirmPassword.tr(),
          style: theme.textStyle.caption.enhanced(
            color: theme.textColorScheme.secondary,
          ),
        ),
        const VSpace(8),
        AFTextField(
          key: confirmPasswordKey,
          controller: confirmPasswordController,
          obscureText: true,
          hintText: LocaleKeys.signIn_confirmNewPassword.tr(),
          onSubmitted: (_) => _validateAndSubmit(),
        ),
      ],
    );
  }

  Widget _buildDesktopResetButton() {
    return isSubmitting
        ? const VerifyingButton()
        : ContinueWithButton(
            text: LocaleKeys.signIn_resetPassword.tr(),
            onTap: () => _validateAndSubmit(),
          );
  }

  // ===================== Shared Logic =====================

  void _validateAndSubmit() {
    final newPassword = newPasswordController.text;
    final confirmPassword = confirmPasswordController.text;

    if (newPassword.isEmpty) {
      newPasswordKey.currentState?.syncError(
        errorText: LocaleKeys.signIn_newPasswordCannotBeEmpty.tr(),
      );
      return;
    }

    // 前端密码复杂度验证：至少8位，需包含大小写字母、数字和特殊字符
    if (!_isPasswordValid(newPassword)) {
      newPasswordKey.currentState?.syncError(
        errorText: LocaleKeys.signIn_passwordMustContain.tr(),
      );
      return;
    }

    if (confirmPassword.isEmpty) {
      confirmPasswordKey.currentState?.syncError(
        errorText: LocaleKeys.signIn_confirmPasswordCannotBeEmpty.tr(),
      );
      return;
    }

    if (newPassword != confirmPassword) {
      confirmPasswordKey.currentState?.syncError(
        errorText: LocaleKeys.signIn_passwordsDoNotMatch.tr(),
      );
      return;
    }

    // Add the reset password event to the bloc
    context.read<SignInBloc>().add(
          ResetPassword(
            email: widget.email,
            newPassword: newPassword,
          ),
        );
  }

  /// 密码复杂度验证
  /// 至少8位，需包含大写字母、小写字母、数字和特殊字符
  static final RegExp _uppercase = RegExp(r'[A-Z]');
  static final RegExp _lowercase = RegExp(r'[a-z]');
  static final RegExp _digit = RegExp(r'[0-9]');
  static final RegExp _special = RegExp(r'[^a-zA-Z0-9]');

  bool _isPasswordValid(String password) {
    if (password.length < 8) return false;
    if (!_uppercase.hasMatch(password)) return false;
    if (!_lowercase.hasMatch(password)) return false;
    if (!_digit.hasMatch(password)) return false;
    if (!_special.hasMatch(password)) return false;
    return true;
  }
}
