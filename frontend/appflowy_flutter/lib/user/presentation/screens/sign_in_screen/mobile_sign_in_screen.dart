import 'dart:io';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/setting/launch_settings_page.dart';
import 'package:appflowy/user/application/sign_in_bloc.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/anonymous_sign_in_button.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/widgets.dart';
import 'package:appflowy/user/presentation/widgets/flowy_logo_title.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class MobileSignInScreen extends StatelessWidget {
  const MobileSignInScreen({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SignInBloc, SignInState>(
      builder: (context, state) {
        final theme = AppFlowyTheme.of(context);
        return Scaffold(
          resizeToAvoidBottomInset: false,
          body: Padding(
            padding: const EdgeInsets.symmetric(vertical: 38, horizontal: 40),
            child: Column(
              children: [
                const Spacer(),
                FlowyLogoTitle(title: LocaleKeys.welcomeText.tr()),
                VSpace(theme.spacing.xxl),
                isLocalAuthEnabled
                    ? const SignInAnonymousButtonV3()
                    : const ContinueWithEmailAndPassword(),
                VSpace(theme.spacing.xxl),
                if (isAuthEnabled) ...[
                  _buildThirdPartySignInButtons(context),
                  VSpace(theme.spacing.xxl),
                ],
                const SignInAgreement(),
                const Spacer(),
                _buildSettingsButton(context),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildThirdPartySignInButtons(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return BlocBuilder<SignInBloc, SignInState>(
      builder: (context, state) {
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    LocaleKeys.signIn_or.tr(),
                    style: TextStyle(
                      fontSize: 16,
                      color: theme.textColorScheme.secondary,
                    ),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const VSpace(16),
            // 微信登录按钮（自定义）
            _buildWeChatLoginButton(context, state),
            const VSpace(16),
            // expand third-party sign in buttons on Android by default.
            // on iOS, the github and discord buttons are collapsed by default.
            ThirdPartySignInButtons(
              expanded: Platform.isAndroid,
            ),
          ],
        );
      },
    );
  }

  Widget _buildWeChatLoginButton(BuildContext context, SignInState state) {
    final theme = AppFlowyTheme.of(context);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: state.isSubmitting
            ? null
            : () {
                context.read<SignInBloc>().add(
                      const SignInEvent.signInWithWeChat(),
                    );
              },
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          side: BorderSide(color: theme.borderColorScheme.primary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: state.isSubmitting
            ? SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    theme.textColorScheme.primary,
                  ),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: const Color(0xFF09BB07),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Center(
                      child: Text(
                        '微',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '微信登录',
                    style: TextStyle(
                      fontSize: 16,
                      color: theme.textColorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSettingsButton(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AFGhostIconTextButton(
          text: LocaleKeys.signIn_settings.tr(),
          textColor: (context, isHovering, disabled) {
            return theme.textColorScheme.secondary;
          },
          size: AFButtonSize.s,
          padding: EdgeInsets.symmetric(
            horizontal: theme.spacing.m,
            vertical: theme.spacing.xs,
          ),
          onTap: () => context.push(MobileLaunchSettingsPage.routeName),
          iconBuilder: (context, isHovering, disabled) {
            return FlowySvg(
              FlowySvgs.settings_s,
              size: Size.square(20),
              color: theme.textColorScheme.secondary,
            );
          },
        ),
        const HSpace(24),
        // Server configuration is now compile-time only
        // Always show anonymous button regardless of auth mode
        const SignInAnonymousButtonV2(),
      ],
    );
  }
}
