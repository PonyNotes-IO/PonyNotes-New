// 用户协议部分组件
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../../../env/cloud_env.dart';
import '../../../../../../generated/locale_keys.g.dart';
import '../../../../../../startup/startup.dart';
import '../../../legal_document_screen.dart';

class TermsAndConditionsSection extends StatelessWidget {
  const TermsAndConditionsSection({
    required this.agreedToTerms,
    required this.onAgreedToTermsChanged,
  });

  final bool agreedToTerms;
  final ValueChanged<bool> onAgreedToTermsChanged;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
    final base_web_domain = cloudEnv.appflowyCloudConfig.base_web_domain;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: () {
            onAgreedToTermsChanged(!agreedToTerms);
          },
          child: Builder(
            builder: (context) {
              final primaryColor = Theme.of(context).colorScheme.primary;
              return Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: agreedToTerms ? primaryColor : const Color(0xFFD0D0D0),
                    width: 2,
                  ),
                  color: agreedToTerms ? primaryColor : Colors.transparent,
                ),
                child: agreedToTerms
                    ? Icon(
                        Icons.check,
                        size: 14,
                        color: Colors.white,
                      )
                    : null,
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 12,
              ),
              children: [
                const TextSpan(text: "我已阅读并同意 "),
                TextSpan(
                  text: "《${LocaleKeys.legal_userAgreement.tr()}》",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  mouseCursor: SystemMouseCursors.click,
                  recognizer: TapGestureRecognizer()
                    ..onTap = () {

                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => LegalDocumentScreen(
                            title: LocaleKeys.sidebar_appName.tr() +
                                LocaleKeys.legal_userAgreement.tr(),
                            url: "$base_web_domain/agreement",
                          ),
                        ),
                      );
                    },
                ),
                TextSpan(text: LocaleKeys.signIn_and.tr()),
                TextSpan(
                  text: "《${LocaleKeys.legal_privacyPolicy.tr()}》",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  mouseCursor: SystemMouseCursors.click,
                  recognizer: TapGestureRecognizer()
                    ..onTap = () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => LegalDocumentScreen(
                            title: LocaleKeys.legal_privacyPolicy.tr(),
                            url: "$base_web_domain/privacy",
                          ),
                        ),
                      );
                    },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}