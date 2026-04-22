import 'dart:io';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/setting/launch_settings_page.dart';
import 'package:appflowy/user/application/sign_in_bloc.dart';
import 'package:appflowy/user/application/wechat/wechat_login_service.dart';
import 'package:appflowy/user/application/douyin/douyin_login_service.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/anonymous_sign_in_button.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/mobile_phone_login_form.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/widgets.dart';
import 'package:appflowy/user/presentation/widgets/flowy_logo_title.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../workspace/presentation/widgets/dialogs.dart';
import 'widgets/agreement/terms_and_conditions_section.dart';
import 'widgets/quick_start/quick_start_button.dart';

class MobileSignInScreen extends StatefulWidget {
  const MobileSignInScreen({
    super.key,
  });

  @override
  State<MobileSignInScreen> createState() => _MobileSignInScreenState();
}

class _MobileSignInScreenState extends State<MobileSignInScreen> {
  bool _agreedToTerms = false;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SignInBloc, SignInState>(
      builder: (context, state) {
        final theme = AppFlowyTheme.of(context);
        return Scaffold(
          resizeToAvoidBottomInset: false,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 38, horizontal: 30),
              child: Column(
                children: [
                  VSpace(80),
                  // Logo and welcome text
                  FlowyLogoTitle(
                    title: LocaleKeys.welcomeToPonyNotes.tr(),
                    logoSize: Size.square(80),
                  ),
                  VSpace(theme.spacing.xxl),
                  
                  // Phone input and login button
                  MobilePhoneLoginForm(
                    onAgreeChanged: (value) {
                      setState(() {
                        _agreedToTerms = value;
                      });
                    },
                    initialAgreed: _agreedToTerms,
                  ),
                  VSpace(theme.spacing.l),

                  QuickStartButton(
                    onTap: () {
                      context
                          .read<SignInBloc>()
                          .add(const SignInEvent.signInAsGuest());
                    },
                    checkTermsAgreement: () {
                      if (!_agreedToTerms) {
                        showToastNotification(
                          message: "请先同意用户协议和隐私政策",
                          type: ToastificationType.error,
                        );
                        return false;
                      }
                      return true;
                    },
                  ),
                  Spacer(),
                  
                  // Third party login
                  if (isAuthEnabled) ...[
                    _buildThirdPartySignInButtons(context),
                    VSpace(theme.spacing.xl),
                  ],
                  
                  // Agreement checkbox
                  // SignInAgreement(),
                  TermsAndConditionsSection(
                    agreedToTerms: _agreedToTerms,
                    onAgreedToTermsChanged: (value) {
                      setState(() {
                        _agreedToTerms = value;
                      });
                    },
                  ),
                ],
              ),
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
                const SizedBox(width: 40,child: Divider(),),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '其他登录方式',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.textColorScheme.secondary,
                    ),
                  ),
                ),
                const SizedBox(width: 40,child: Divider(),),
              ],
            ),
            const VSpace(16),
            // Custom third party buttons with 40dp size
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildThirdPartyButton(context, 'wechat'),
                const HSpace(40),
                _buildThirdPartyButton(context, 'douyin'),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildThirdPartyButton(BuildContext context, String type) {
    final theme = AppFlowyTheme.of(context);
    return GestureDetector(
      onTap: () async {
        if (type == 'wechat') {
          await _signInWithWeChat(context);
        } else if (type == 'douyin') {
          await _signInWithDouYin(context);
        }
      },
      child: SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: FlowySvg(
            type == 'wechat' ? FlowySvgs.icon_login_wx_xl : FlowySvgs.icon_login_dy_xl,
            blendMode: null,
          ),
        ),
      ),
    );
  }

  Future<void> _signInWithWeChat(BuildContext context) async {
    try {
      if (!_agreedToTerms) {
        showToastNotification(
          message: "请先同意用户协议和隐私政策",
          type: ToastificationType.error,
        );
        return;
      }
      // 执行微信登录
      context.read<SignInBloc>().add(const SignInEvent.signInWithWeChat());
    } catch (e) {
      showToastNotification(
        message: '微信登录失败，请稍后重试',
        type: ToastificationType.error,
      );
    }
  }

  Future<void> _signInWithDouYin(BuildContext context) async {
    try {
      if (!_agreedToTerms) {
        showToastNotification(
          message: "请先同意用户协议和隐私政策",
          type: ToastificationType.error,
        );
        return;
      }
      // 执行抖音登录
      context.read<SignInBloc>().add(const SignInEvent.signInWithDouYin());
    } catch (e) {
      showToastNotification(
        message: '抖音登录失败，请稍后重试',
        type: ToastificationType.error,
      );
    }
  }




}
