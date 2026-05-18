import 'dart:io';
import 'package:flowy_infra/platform_extension.dart';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/user/application/sign_in_bloc.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/douyin_webview_dialog.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/wechat_webview_dialog.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/third_party_sign_in_button/third_party_sign_in_button.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:universal_platform/universal_platform.dart';

typedef _SignInCallback = void Function(ThirdPartySignInButtonType signInType);

@visibleForTesting
const Key signInWithGoogleButtonKey = Key('signInWithGoogleButton');

// 第三方登录图标按钮（与主登录页面风格一致）
class _ThirdPartyIconButton extends StatelessWidget {
  const _ThirdPartyIconButton({
    required this.label,
    required this.icon,
    this.onTap,
    this.isLoading = false,
  });

  final String label;
  final Widget icon;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Opacity(
        opacity: (onTap == null || isLoading) ? 0.6 : 1.0,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: theme.surfaceColorScheme.layer01,
            border: Border.all(color: theme.borderColorScheme.primary),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    icon,
                    HSpace(8),
                    Text(
                      label,
                      style: TextStyle(
                        color: theme.textColorScheme.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],),
          ),
        ),
      ),
    );
  }
}

class ThirdPartySignInButtons extends StatelessWidget {
  /// Used in DesktopSignInScreen, MobileSignInScreen and SettingThirdPartyLogin
  const ThirdPartySignInButtons({
    super.key,
    this.expanded = false,
  });

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    if (PlatformInfo.isDesktopOrTabletOrWeb) {
      return _DesktopThirdPartySignIn(
        onSignIn: (type) => _signIn(context, type),
      );
    } else {
      return _MobileThirdPartySignIn(
        isExpanded: expanded,
        onSignIn: (type) => _signIn(context, type),
      );
    }
  }

  Future<void> _signIn(BuildContext context, ThirdPartySignInButtonType type) async {
    final signInBloc = context.read<SignInBloc>();

    if (type == ThirdPartySignInButtonType.wechat) {
      if (UniversalPlatform.isWindows ||
          UniversalPlatform.isMacOS ||
          UniversalPlatform.isLinux) {
        final code = await showWeChatWebViewDialog(context);
        if (code != null && context.mounted) {
          signInBloc.add(SignInEvent.wechatCodeReceived(code));
        }
      } else {
        signInBloc.add(const SignInEvent.signInWithWeChat());
      }
    } else if (type == ThirdPartySignInButtonType.douyin) {
      if (UniversalPlatform.isWindows ||
          UniversalPlatform.isMacOS ||
          UniversalPlatform.isLinux) {
        final code = await showDouYinWebViewDialog(context);
        if (code != null && context.mounted) {
          signInBloc.add(SignInEvent.douyinCodeReceived(code));
        }
      } else {
        signInBloc.add(const SignInEvent.signInWithDouYin());
      }
    } else {
      // 其他平台使用通用的 OAuth 登录
      signInBloc.add(
        SignInEvent.signInWithOAuth(platform: type.provider),
      );
    }
  }
}

class _DesktopThirdPartySignIn extends StatelessWidget {
  const _DesktopThirdPartySignIn({
    required this.onSignIn,
  });

  final _SignInCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ThirdPartyIconButton(
          label: "微信登录",
          icon: Image.asset(
            "assets/images/login/icon_login_wx.png",
            width: 18,
            height: 18,
          ),
          onTap: () => onSignIn(ThirdPartySignInButtonType.wechat),
        ),
        const SizedBox(height: 12),
        _ThirdPartyIconButton(
          label: "抖音登录",
          icon: Image.asset(
            "assets/images/login/icon_login_dy.png",
            width: 18,
            height: 18,
          ),
          onTap: () => onSignIn(ThirdPartySignInButtonType.douyin),
        ),
      ],
    );
  }
}

class _MobileThirdPartySignIn extends StatelessWidget {
  const _MobileThirdPartySignIn({
    required this.isExpanded,
    required this.onSignIn,
  });

  final bool isExpanded;
  final _SignInCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularIconButton(
          icon: FlowySvg(
            ThirdPartySignInButtonType.wechat.icon,
            size: const Size.square(28),
          ),
          onTap: () => onSignIn(ThirdPartySignInButtonType.wechat),
        ),
        const SizedBox(width: 24),
        CircularIconButton(
          icon: FlowySvg(
            ThirdPartySignInButtonType.douyin.icon,
            size: const Size.square(28),
          ),
          onTap: () => onSignIn(ThirdPartySignInButtonType.douyin),
        ),
      ],
    );
  }
}

// 第三方登录图标按钮
class CircularIconButton extends StatelessWidget {
  const CircularIconButton({
    required this.icon,
    this.onTap,
    this.isLoading = false,
  });

  final Widget icon;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Opacity(
        opacity: (onTap == null || isLoading) ? 0.6 : 1.0,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: theme.surfaceColorScheme.layer01,
            border: Border.all(color: theme.borderColorScheme.primary),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(theme.textColorScheme.primary),
                    ),
                  )
                : icon,
          ),
        ),
      ),
    );
  }
}
