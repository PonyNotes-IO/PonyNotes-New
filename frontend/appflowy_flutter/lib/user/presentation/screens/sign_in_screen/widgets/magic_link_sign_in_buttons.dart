import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/user/application/sign_in_bloc.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/slider_captcha.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/size.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:string_validator/string_validator.dart';
import 'package:universal_platform/universal_platform.dart';

class SignInWithMagicLinkButtons extends StatefulWidget {
  const SignInWithMagicLinkButtons({super.key});

  @override
  State<SignInWithMagicLinkButtons> createState() =>
      _SignInWithMagicLinkButtonsState();
}

class _SignInWithMagicLinkButtonsState
    extends State<SignInWithMagicLinkButtons> {
  final controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _sliderVerified = false;
  // ignore: prefer_final_fields — 在 setState 中会重新赋值用于重置滑块
  Object _sliderResetKey = Object();

  @override
  void dispose() {
    controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: UniversalPlatform.isMobile ? 38.0 : 48.0,
          child: FlowyTextField(
            autoFocus: false,
            focusNode: _focusNode,
            controller: controller,
            borderRadius: BorderRadius.circular(4.0),
            hintText: LocaleKeys.signIn_pleaseInputYourEmail.tr(),
            hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 14.0,
                  color: Theme.of(context).hintColor,
                ),
            textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 14.0,
                ),
            keyboardType: TextInputType.emailAddress,
            onSubmitted: (_) => _focusNode.unfocus(),
            onTapOutside: (_) => _focusNode.unfocus(),
          ),
        ),
        const VSpace(12),
        SliderCaptcha(
          resetKey: _sliderResetKey,
          onVerified: () => setState(() => _sliderVerified = true),
        ),
        const VSpace(12),
        _ConfirmButton(
          enabled: _sliderVerified,
          onTap: () => _sendMagicLink(context, controller.text),
        ),
      ],
    );
  }

  void _sendMagicLink(BuildContext context, String email) {
    if (!isEmail(email)) {
      showToastNotification(
        message: LocaleKeys.signIn_invalidEmail.tr(),
        type: ToastificationType.error,
      );
      return;
    }

    context
        .read<SignInBloc>()
        .add(SignInEvent.signInWithMagicLink(email: email));

    // 发送成功后重置滑块，防止用户在同一会话中无需再次验证就能重发
    setState(() {
      _sliderVerified = false;
      _sliderResetKey = Object();
    });

    showConfirmDialog(
      context: context,
      title: LocaleKeys.signIn_magicLinkSent.tr(),
      description: LocaleKeys.signIn_magicLinkSentDescription.tr(),
    );
  }
}

class _ConfirmButton extends StatelessWidget {
  const _ConfirmButton({
    required this.onTap,
    this.enabled = true,
  });

  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SignInBloc, SignInState>(
      builder: (context, state) {
        final name = switch (state.loginType) {
          LoginType.signIn => LocaleKeys.signIn_signInWithMagicLink.tr(),
          LoginType.signUp => LocaleKeys.signIn_signUpWithMagicLink.tr(),
        };
        if (UniversalPlatform.isMobile) {
          return ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 32),
              maximumSize: const Size(double.infinity, 38),
            ),
            onPressed: enabled ? onTap : null,
            child: FlowyText(
              name,
              fontSize: 14,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          );
        } else {
          return SizedBox(
            height: 48,
            child: FlowyButton(
              isSelected: true,
              onTap: enabled ? onTap : () {},
              hoverColor: enabled
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
              text: FlowyText.medium(
                name,
                textAlign: TextAlign.center,
                color: enabled
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.5),
              ),
              radius: Corners.s6Border,
            ),
          );
        }
      },
    );
  }
}
