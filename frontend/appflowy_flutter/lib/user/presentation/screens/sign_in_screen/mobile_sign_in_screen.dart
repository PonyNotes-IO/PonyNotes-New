// ignore_for_file: undefined_getter

import 'dart:async' show unawaited;

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/user/application/douyin/douyin_login_service.dart';
import 'package:appflowy/user/application/sign_in_bloc.dart';
import 'package:appflowy/user/presentation/router.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/mobile_phone_login_form.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/phone_bind_screen.dart';
import 'package:appflowy/user/presentation/widgets/flowy_logo_title.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:appflowy/startup/startup.dart';

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
  static const double _thirdPartyButtonSize = 28;

  bool _agreedToTerms = false;
  bool _phoneDialogOpen = false;
  bool _phoneBindingCancelled = false;
  bool _isNavigatingToHome = false;

  @override
  Widget build(BuildContext context) {
    return BlocListener<SignInBloc, SignInState>(
      listener: (context, state) {
        _handleSignInStateChange(context, state);
      },
      child: BlocBuilder<SignInBloc, SignInState>(
        builder: (context, state) {
          final theme = AppFlowyTheme.of(context);
          final isDark = Theme.of(context).brightness == Brightness.dark;
          // 浅色：保留原浅粉渐变；深色：与 Material scaffoldBackgroundColor (#121212) 一致
          final gradientColors = isDark
              ? [
                  Theme.of(context).scaffoldBackgroundColor,
                  Theme.of(context).scaffoldBackgroundColor,
                ]
              : const [
                  Color(0xFFFFF8F6),
                  Colors.white,
                ];
          return Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            resizeToAvoidBottomInset: false,
            body: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: gradientColors,
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 36,
                    vertical: 10,
                  ),
                  child: Column(
                    children: [
                      const VSpace(45),
                      // Logo and welcome text
                      FlowyLogoTitle(
                        title: LocaleKeys.welcomeToPonyNotes.tr(),
                        logoSize: const Size.square(48),
                        titleStyle: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: theme.textColorScheme.primary,
                        ),
                      ),
                      // 标题字号放大后保持输入框的垂直位置不变。
                      const VSpace(29),

                      // Phone input and login button
                      MobilePhoneLoginForm(
                        onAgreeChanged: (value) {
                          setState(() {
                            _agreedToTerms = value;
                          });
                        },
                        initialAgreed: _agreedToTerms,
                      ),
                      const SizedBox(height: 10),

                      QuickStartButton(
                        onTap: () {
                          context
                              .read<SignInBloc>()
                              .add(const SignInEvent.signInAsGuest());
                        },
                        checkTermsAgreement: () {
                          if (!_agreedToTerms) {
                            showToastNotification(
                              message:
                                  LocaleKeys.signIn_pleaseAgreeToTerms.tr(),
                              type: ToastificationType.error,
                            );
                            return false;
                          }
                          return true;
                        },
                      ),

                      const Spacer(),

                      // 第三方登录按钮
                      _buildThirdPartyButtons(context),

                      // Agreement checkbox
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
            ),
          );
        },
      ),
    );
  }

  Widget _buildThirdPartyButtons(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Column(
      children: [
        // 分割线带文字（左右线条渐变过渡）
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        theme.borderColorScheme.primary.withValues(alpha: 0),
                        theme.borderColorScheme.primary,
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  LocaleKeys.signIn_otherLoginMethods.tr(),
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textColorScheme.secondary,
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        theme.borderColorScheme.primary,
                        theme.borderColorScheme.primary.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // 第三方登录按钮
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildThirdPartyIconButton(
              icon: FlowySvg(
                FlowySvgs.icon_login_wx_xl,
                size: const Size.square(_thirdPartyButtonSize),
                blendMode: null,
              ),
              onPressed: () => _signInWithWeChat(context),
            ),
            const SizedBox(width: 20),
            _buildThirdPartyIconButton(
              icon: FlowySvg(
                FlowySvgs.icon_login_dy_xl,
                size: const Size.square(_thirdPartyButtonSize),
                blendMode: null,
              ),
              onPressed: () => _signInWithDouYin(context),
            ),
            if (Theme.of(context).platform == TargetPlatform.iOS) ...[
              const SizedBox(width: 20),
              _buildThirdPartyIconButton(
                icon: Builder(
                  builder: (context) {
                    final theme = AppFlowyTheme.of(context);
                    return Container(
                      width: _thirdPartyButtonSize,
                      height: _thirdPartyButtonSize,
                      decoration: BoxDecoration(
                        color: theme.surfaceColorScheme.layer01,
                        border: Border.all(
                          color: theme.borderColorScheme.primary,
                        ),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: FlowySvg(
                        FlowySvgs.m_apple_icon_xl,
                        size: const Size.square(16),
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : Colors.black,
                        blendMode: BlendMode.srcIn,
                      ),
                    );
                  },
                ),
                onPressed: () => _signInWithApple(context),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildThirdPartyIconButton({
    required Widget icon,
    required VoidCallback onPressed,
  }) {
    return SizedBox.square(
      dimension: _thirdPartyButtonSize,
      child: IconButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(
          width: _thirdPartyButtonSize,
          height: _thirdPartyButtonSize,
        ),
        iconSize: _thirdPartyButtonSize,
        icon: icon,
      ),
    );
  }

  Future<void> _signInWithApple(BuildContext context) async {
    if (!_agreedToTerms) {
      showToastNotification(
        message: LocaleKeys.signIn_pleaseAgreeToTerms.tr(),
        type: ToastificationType.error,
      );
      return;
    }
    context.read<SignInBloc>().add(
          const SignInEvent.signInWithOAuth(platform: 'apple'),
        );
  }

  Future<void> _signInWithWeChat(BuildContext context) async {
    if (!_agreedToTerms) {
      showToastNotification(
        message: LocaleKeys.signIn_pleaseAgreeToTerms.tr(),
        type: ToastificationType.error,
      );
      return;
    }
    context.read<SignInBloc>().add(const SignInEvent.signInWithWeChat());
  }

  Future<void> _signInWithDouYin(BuildContext context) async {
    if (!_agreedToTerms) {
      showToastNotification(
        message: LocaleKeys.signIn_pleaseAgreeToTerms.tr(),
        type: ToastificationType.error,
      );
      return;
    }

    // 检查抖音是否安装
    final isInstalled = await DouYinLoginService.instance.isDouYinInstalled();
    if (!isInstalled) {
      showToastNotification(
        message: LocaleKeys.signIn_douYinNotInstalledMessage.tr(),
        type: ToastificationType.error,
      );
      return;
    }

    context.read<SignInBloc>().add(const SignInEvent.signInWithDouYin());
  }

  Future<void> _handleSignInStateChange(
      BuildContext context, SignInState state) async {
    // 检查是否需要绑定手机号（第三方登录但未绑定手机号）
    final dynamic dynState = state;
    final needBind = (dynState.requiresPhoneBinding == true) ||
        state.toString().contains('requiresPhoneBinding: true');
    if (needBind && !_phoneDialogOpen) {
      _phoneDialogOpen = true;
      _phoneBindingCancelled = false;
      final signInBloc = context.read<SignInBloc>();
      final profile = await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BlocProvider.value(
            value: signInBloc,
            child: PhoneBindScreen(pendingToken: state.pendingToken),
          ),
        ),
      );
      _phoneDialogOpen = false;

      if (profile != null) {
        if (!context.mounted || _isNavigatingToHome) {
          return;
        }

        _isNavigatingToHome = true;

        try {
          final signInBloc = context.read<SignInBloc>();
          if (!signInBloc.isClosed) {
            signInBloc.add(SignInEvent.phoneBindingComplete(profile));
          }
        } catch (e) {
          // SignInBloc 不可用，直接导航
        }

        final rootNavigator = Navigator.of(context, rootNavigator: true);
        if (rootNavigator != null) {
          final rootContext = rootNavigator.context;
          if (rootContext.mounted) {
            unawaited(runAppFlowy());
          }
        }
      } else {
        _phoneBindingCancelled = true;
        showToastNotification(
          message: '请先绑定手机号再继续',
          type: ToastificationType.info,
        );
        if (context.mounted) {
          context
              .read<SignInBloc>()
              .add(SignInEvent.clearPhoneBindingRequirement());
          context.read<SignInBloc>().add(const SignInEvent.reset());
        }
      }

      if (context.mounted) {
        context
            .read<SignInBloc>()
            .add(SignInEvent.clearPhoneBindingRequirement());
      }
      return;
    }

    if (_phoneBindingCancelled && state.successOrFail == null) {
      return;
    }

    final successOrFail = state.successOrFail;
    if (successOrFail != null) {
      if (successOrFail.isSuccess) {
        successOrFail.onSuccess((userProfile) async {
          if (!context.mounted) {
            return;
          }

          if (_phoneBindingCancelled) {
            if (context.mounted) {
              try {
                final signInBloc = context.read<SignInBloc>();
                if (!signInBloc.isClosed) {
                  signInBloc.add(const SignInEvent.reset());
                }
              } catch (e) {
                // SignInBloc 不可用或已关闭，忽略
              }
            }
            return;
          }

          final needBind = (state.requiresPhoneBinding == true);
          if (needBind &&
              _needBindPhone(userProfile.phone) &&
              !_phoneDialogOpen) {
            _phoneDialogOpen = true;
            _phoneBindingCancelled = false;
            final signInBloc = context.read<SignInBloc>();
            final profile = await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BlocProvider.value(
                  value: signInBloc,
                  child: PhoneBindScreen(pendingToken: state.pendingToken),
                ),
              ),
            );
            _phoneDialogOpen = false;
            if (profile != null) {
              if (!context.mounted) {
                return;
              }
              final rootNavigator = Navigator.of(context, rootNavigator: true);
              if (rootNavigator != null) {
                final rootContext = rootNavigator.context;
                if (rootContext.mounted) {
                  unawaited(runAppFlowy());
                }
              }
            } else {
              _phoneBindingCancelled = true;
              showToastNotification(
                message: '请先绑定手机号再继续',
                type: ToastificationType.info,
              );
              if (context.mounted) {
                context
                    .read<SignInBloc>()
                    .add(SignInEvent.clearPhoneBindingRequirement());
                context.read<SignInBloc>().add(const SignInEvent.reset());
              }
            }
            return;
          }

          if (_phoneBindingCancelled) {
            return;
          }

          if (_needBindPhone(userProfile.phone)) {
            if (!_phoneDialogOpen) {
              _phoneDialogOpen = true;
              _phoneBindingCancelled = false;
              final signInBloc = context.read<SignInBloc>();
              final profile = await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BlocProvider.value(
                    value: signInBloc,
                    child: PhoneBindScreen(pendingToken: state.pendingToken),
                  ),
                ),
              );
              _phoneDialogOpen = false;
              if (profile != null) {
                if (!context.mounted) {
                  return;
                }
                final rootNavigator =
                    Navigator.of(context, rootNavigator: true);
                if (rootNavigator != null) {
                  final rootContext = rootNavigator.context;
                  if (rootContext.mounted) {
                    unawaited(runAppFlowy());
                  }
                }
              } else {
                _phoneBindingCancelled = true;
                showToastNotification(
                  message: '请先绑定手机号再继续',
                  type: ToastificationType.info,
                );
                if (context.mounted) {
                  context
                      .read<SignInBloc>()
                      .add(SignInEvent.clearPhoneBindingRequirement());
                  context.read<SignInBloc>().add(const SignInEvent.reset());
                }
              }
              return;
            } else {
              return;
            }
          }

          if (_phoneBindingCancelled) {
            return;
          }

          if (!context.mounted) {
            return;
          }
          final rootNavigator = Navigator.of(context, rootNavigator: true);
          final rootContext = rootNavigator?.context;
          if (rootContext == null || !rootContext.mounted) {
            return;
          }
          if (rootContext.mounted) {
            unawaited(runAppFlowy());
          }
        });
      } else {
        successOrFail.onFailure((error) {
          if (context.mounted) {
            showToastNotification(
              message: error.msg,
              type: ToastificationType.error,
            );
          }
        });
      }
    }
  }

  bool _needBindPhone(String? phone) {
    if (phone == null) return false;
    if (phone.isEmpty) return false;
    return phone.startsWith('+86temp');
  }
}
