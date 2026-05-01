import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/user/application/sign_in_bloc.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/mobile_phone_login_form.dart';
import 'package:appflowy/user/presentation/widgets/flowy_logo_title.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 30),
              child: Column(
                children: [
                  VSpace(40),
                  // Logo and welcome text
                  FlowyLogoTitle(
                    title: LocaleKeys.welcomeToPonyNotes.tr(),
                    logoSize: Size.square(60),
                  ),
                  VSpace(40),

                  // Phone input and login button
                  MobilePhoneLoginForm(
                    onAgreeChanged: (value) {
                      setState(() {
                        _agreedToTerms = value;
                      });
                    },
                    initialAgreed: _agreedToTerms,
                  ),
                  const SizedBox(height: 12),

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
                  const SizedBox(height: 16),

                  // 第三方登录按钮
                  _buildThirdPartyButtons(context),

                  Spacer(),
                  
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

  Widget _buildThirdPartyButtons(BuildContext context) {
    return Column(
      children: [
        // 微信登录按钮
        GestureDetector(
          onTap: () => _signInWithWeChat(context),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(24),
            ),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  "assets/images/login/icon_login_wx.png",
                  width: 16,
                  height: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  '微信登录',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        // 抖音登录按钮
        GestureDetector(
          onTap: () => _signInWithDouYin(context),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(24),
            ),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  "assets/images/login/icon_login_dy.png",
                  width: 16,
                  height: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  '抖音登录',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _signInWithWeChat(BuildContext context) async {
    if (!_agreedToTerms) {
      showToastNotification(
        message: "请先同意用户协议和隐私政策",
        type: ToastificationType.error,
      );
      return;
    }
    context.read<SignInBloc>().add(const SignInEvent.signInWithWeChat());
  }

  Future<void> _signInWithDouYin(BuildContext context) async {
    if (!_agreedToTerms) {
      showToastNotification(
        message: "请先同意用户协议和隐私政策",
        type: ToastificationType.error,
      );
      return;
    }
    context.read<SignInBloc>().add(const SignInEvent.signInWithDouYin());
  }
}
