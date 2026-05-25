import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../../env/cloud_env.dart';
import '../../../../../startup/startup.dart';

class SignInAgreement extends StatelessWidget {
  const SignInAgreement({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
    final base_web_domain = cloudEnv.appflowyCloudConfig.base_web_domain;
    final theme = AppFlowyTheme.of(context);
    final textStyle = theme.textStyle.caption.standard(
      color: theme.textColorScheme.secondary,
    );
    final underlinedTextStyle = theme.textStyle.caption.underline(
      color: theme.textColorScheme.secondary,
    );
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        children: [
          TextSpan(
            text: LocaleKeys.web_signInAgreement.tr(),
            style: textStyle,
          ),
          TextSpan(
            text: '${LocaleKeys.web_termOfUse.tr()} ',
            style: underlinedTextStyle,
            mouseCursor: SystemMouseCursors.click,
            recognizer: TapGestureRecognizer()
              ..onTap = () => afLaunchUrlString('$base_web_domain/agreement'),
          ),
          TextSpan(
            text: '${LocaleKeys.web_and.tr()} ',
            style: textStyle,
          ),
          TextSpan(
            text: LocaleKeys.web_privacyPolicy.tr(),
            style: underlinedTextStyle,
            mouseCursor: SystemMouseCursors.click,
            recognizer: TapGestureRecognizer()
              ..onTap = () => afLaunchUrlString('$base_web_domain/privacy'),
          ),
        ],
      ),
    );
  }
}
