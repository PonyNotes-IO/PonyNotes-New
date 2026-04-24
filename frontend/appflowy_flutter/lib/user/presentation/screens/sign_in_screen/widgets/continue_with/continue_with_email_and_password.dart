import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/user/application/sign_in_bloc.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/continue_with_magic_link_or_passcode_page.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/continue_with_password_page.dart';
import 'package:appflowy/user/presentation/screens/legal_document_screen.dart';
import 'package:appflowy/util/validator.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../env/cloud_env.dart';
import '../../../../../../startup/startup.dart';

class ContinueWithEmailAndPassword extends StatefulWidget {
  const ContinueWithEmailAndPassword({super.key});

  @override
  State<ContinueWithEmailAndPassword> createState() =>
      _ContinueWithEmailAndPasswordState();
}

class _ContinueWithEmailAndPasswordState
    extends State<ContinueWithEmailAndPassword> {
  final controller = TextEditingController();
  final focusNode = FocusNode();
  final emailKey = GlobalKey<AFTextFieldState>();

  bool _hasPushedContinueWithMagicLinkOrPasscodePage = false;
  bool _agreed = false;
  bool _isLoading = false;

  @override
  void dispose() {
    controller.dispose();
    focusNode.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 与 desktop_sign_in_screen 中 _TermsAndConditionsSection 一致：正文用主题反转色，链接用 primary
    final agreementPlainTextStyle =
        Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: 12,
              fontFamily: 'PingFangSC-Regular',
            );

    return BlocListener<SignInBloc, SignInState>(
      listener: (context, state) {
        final successOrFail = state.successOrFail;
        if (successOrFail != null) {
          successOrFail.fold(
            (userProfile) async {
              emailKey.currentState?.clearError();
              // 登录成功，不在这里处理导航
              // 导航由验证码页面和外层的Settings弹窗处理
            },
            (error) => emailKey.currentState?.syncError(
              errorText: error.msg,
            ),
          );
        } else if (successOrFail == null && !state.isSubmitting) {
          emailKey.currentState?.clearError();
        }
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFDBDBDB)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: TextField(
              key: ValueKey(emailKey),
              controller: controller,
              decoration: InputDecoration(
                hintText: "输入邮箱或者手机号",
                hintStyle: TextStyle(
                  color: const Color(0xFF999999),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 19, vertical: 10),
              ),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              onSubmitted: (value) => _signInWithEmail(context, value),
            ),
          ),
          VSpace(20),
          GestureDetector(
            onTap: _isLoading
                ? () {}
                : () {
                    final emailOrPhone = controller.text.trim();
                    
                    if (!Validator.isValidEmailOrPhone(emailOrPhone)) {
                      emailKey.currentState?.syncError(
                        errorText: '请输入有效的邮箱或手机号',
                      );
                      return;
                    }
                    if (!_agreed) {
                      final parentContext = context;
                      showDialog(
                        context: parentContext,
                        barrierDismissible: false,
                        builder: (dialogContext) => Container(
                          alignment: Alignment.center,
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 40),
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  '为了更好的使用服务\n登录前请阅读并同意以下协议',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                RichText(
                                  textAlign: TextAlign.center,
                                  text: TextSpan(
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 14,
                                    ),
                                    children: [
                                      TextSpan(text: '小马AI笔记 '),
                                      TextSpan(
                                        text: '《${LocaleKeys.settings_mobile_userAgreement.tr()}》',
                                        style: TextStyle(
                                          color: const Color(0xFFFF4D4F),
                                        ),
                                        recognizer: TapGestureRecognizer()
                                          ..onTap = () {
                                            Navigator.of(dialogContext).pop();
                                            _navigateToUserAgreement(parentContext);
                                          },
                                      ),
                                      TextSpan(text: ' 和 '),
                                      TextSpan(
                                        text: '《${LocaleKeys.settings_mobile_privacyPolicy.tr()}》',
                                        style: TextStyle(
                                          color: const Color(0xFFFF4D4F),
                                        ),
                                        recognizer: TapGestureRecognizer()
                                          ..onTap = () {
                                            Navigator.of(dialogContext).pop();
                                            _navigateToPrivacyPolicy(parentContext);
                                          },
                                      ),
                                    ],
                                  ),
                                  softWrap: true,
                                  overflow: TextOverflow.visible,
                                ),
                                const SizedBox(height: 30),
                                // 同意并继续按钮
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _agreed = true;
                                    });
                                    Navigator.of(dialogContext).pop();
                                  },
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFF4D4F),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      '同意并继续',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                // 不同意按钮
                                GestureDetector(
                                  onTap: () {
                                    Navigator.of(dialogContext).pop();
                                  },
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      border: Border.all(
                                        color: const Color(0xFFD0D0D0),
                                        width: 1,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      '不同意',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                      return;
                    }
                    if (Validator.isValidEmail(emailOrPhone)) {
                      _signInWithEmail(context, emailOrPhone);
                    } else if (Validator.isValidPhone(emailOrPhone)) {
                      // 清理手机号格式（移除+86等国际区号）
                      final cleanPhone = Validator.cleanPhoneNumber(emailOrPhone);
                      _signInWithPhone(context, cleanPhone);
                    }
                  },
            child: Builder(
              builder: (context) {
                final primaryColor = Theme.of(context).colorScheme.primary;
                return Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: primaryColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    _isLoading
                        ? "登录中..."
                        : "登录/注册",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              },
            ),
          ),
          VSpace(20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () {
                  setState(() {
                    _agreed = !_agreed;
                  });
                },
                child: Builder(
                  builder: (context) {
                    final primaryColor = Theme.of(context).colorScheme.primary;
                    return Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _agreed ? primaryColor : const Color(0xFF979797),
                          width: 2,
                        ),
                        color: _agreed ? primaryColor : Colors.transparent,
                      ),
                      child: _agreed
                          ? Icon(
                              Icons.check,
                              size: 12,
                              color: Colors.white,
                            )
                          : null,
                    );
                  },
                ),
              ),
              const HSpace(4.0),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2.0),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.start,
                    children: [
                      Text(
                        "我已阅读并同意",
                        style: agreementPlainTextStyle,
                      ),
                      GestureDetector(
                        onTap: () {
                          _navigateToUserAgreement(context);
                        },
                        child: Builder(
                          builder: (context) {
                            final primaryColor = Theme.of(context).colorScheme.primary;
                            return Text(
                              "《用户协议》",
                              style: TextStyle(
                                color: primaryColor,
                                fontSize: 12,
                                fontFamily: 'PingFangSC-Regular',
                              ),
                            );
                          },
                        ),
                      ),
                      Text(
                        "与",
                        style: agreementPlainTextStyle,
                      ),
                      GestureDetector(
                        onTap: () {
                          _navigateToPrivacyPolicy(context);
                        },
                        child: Builder(
                          builder: (context) {
                            final primaryColor = Theme.of(context).colorScheme.primary;
                            return Text(
                              "《隐私政策》",
                              style: TextStyle(
                                color: primaryColor,
                                fontSize: 12,
                                fontFamily: 'PingFangSC-Regular',
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _signInWithEmail(BuildContext context, String input) async {
    if (_isLoading) return;

    // 重置SignInBloc状态，确保没有进行中的操作阻止新的请求
    final signInBloc = context.read<SignInBloc>();
    signInBloc.add(const SignInEvent.cancel());
    
    setState(() {
      _isLoading = true;
    });

    try {
      // 先检查用户是否设置了密码
      signInBloc.add(
        SignInEvent.checkPasswordStatus(
          email: input,
        ),
      );
      
      // 等待密码状态检查完成
      await Future.delayed(const Duration(milliseconds: 800));
      
      // 获取当前状态
      final currentState = signInBloc.state;
      if (mounted) {
        if (currentState.passwordIsSet == true) {
          // 用户已设置密码，跳转到密码登录页面
          _pushContinueWithPasswordPage(context, input);
        } else {
          // 用户未设置密码，发送验证码并跳转到验证码输入页面
          signInBloc.add(SignInEvent.signInWithMagicLink(email: input));
          _pushContinueWithMagicLinkOrPasscodePage(context, input);
        }
      }
    } catch (e) {
      // 处理异常
      if (mounted) {
        _showUserCheckFailedDialog(context, input, e.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _signInWithPhone(BuildContext context, String phone) async {
    if (_isLoading) return;
    
    // 重置SignInBloc状态，确保没有进行中的操作阻止新的请求
    final signInBloc = context.read<SignInBloc>();
    signInBloc.add(const SignInEvent.cancel());
    
    setState(() {
      _isLoading = true;
    });

    try {
      // 先检查用户是否设置了密码
      signInBloc.add(
        SignInEvent.checkPasswordStatus(
          phone: phone,
        ),
      );
      
      // 等待密码状态检查完成
      await Future.delayed(const Duration(milliseconds: 800));
      
      // 获取当前状态
      final currentState = signInBloc.state;
      if (mounted) {
        if (currentState.passwordIsSet == true) {
          // 用户已设置密码，跳转到密码登录页面
          _pushContinueWithPasswordPage(context, phone);
        } else {
          // 用户未设置密码，发送验证码并跳转到验证码输入页面
          signInBloc.add(SignInEvent.signInWithMagicLink(email: phone));
          _pushContinueWithMagicLinkOrPasscodePage(context, phone);
        }
      }
    } catch (e) {
      // 处理异常
      if (mounted) {
        _showUserCheckFailedDialog(context, phone, e.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showUserCheckFailedDialog(
    BuildContext context,
    String email,
    String errorMessage,
  ) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('用户检查失败'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '无法检查用户状态，请选择继续方式：',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                errorMessage,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (Navigator.of(dialogContext).canPop()) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: Text(LocaleKeys.button_cancel.tr()),
          ),
          TextButton(
            onPressed: () {
              if (Navigator.of(dialogContext).canPop()) {
                Navigator.of(dialogContext).pop();
              }
              _signInWithEmail(context, email);
            },
            child: const Text('重试'),
          ),
          TextButton(
            onPressed: () {
              if (Navigator.of(dialogContext).canPop()) {
                Navigator.of(dialogContext).pop();
              }
              _pushContinueWithPasswordPage(context, email);
            },
            child: const Text('密码登录'),
          ),
          TextButton(
            onPressed: () {
              if (Navigator.of(dialogContext).canPop()) {
                Navigator.of(dialogContext).pop();
              }
              context
                  .read<SignInBloc>()
                  .add(SignInEvent.signInWithMagicLink(email: email));
              _pushContinueWithMagicLinkOrPasscodePage(context, email);
            },
            child: const Text('验证码登录'),
          ),
        ],
      ),
    );
  }

  void _pushContinueWithMagicLinkOrPasscodePage(
    BuildContext context,
    String email,
  ) {
    if (_hasPushedContinueWithMagicLinkOrPasscodePage) {
      return;
    }

    final signInBloc = context.read<SignInBloc>();

    Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: '/continue-with-email-verification'),
        builder: (context) => BlocProvider.value(
          value: signInBloc,
          child: ContinueWithMagicLinkOrPasscodePage(
            email: email,
            backToLogin: () {
              // 先重置状态，避免重复推送
              _hasPushedContinueWithMagicLinkOrPasscodePage = false;

              // 清理邮箱输入框的错误状态
              emailKey.currentState?.clearError();

              // 最后执行导航
              if (Navigator.of(context).canPop()) {
                Navigator.pop(context);
              }
            },
            onEnterPasscode: (passcode) {
              // 重置SignInBloc状态，确保没有进行中的操作阻止新的请求
              signInBloc.add(const SignInEvent.cancel());
              
              // 给一点时间让cancel事件处理完成
              Future.delayed(const Duration(milliseconds: 100), () {
                signInBloc.add(
                  SignInEvent.signInWithPasscode(
                    email: email,
                    passcode: passcode,
                  ),
                );
              });
            },
          ),
        ),
      ),
    );

    _hasPushedContinueWithMagicLinkOrPasscodePage = true;
  }

  void _pushContinueWithPasswordPage(
    BuildContext context,
    String email,
  ) {
    final signInBloc = context.read<SignInBloc>();
    Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: '/continue-with-password'),
        builder: (context) => BlocProvider.value(
          value: signInBloc,
          child: ContinueWithPasswordPage(
            email: email,
            backToLogin: () {
              emailKey.currentState?.clearError();
              Navigator.pop(context);
            },
            onEnterPassword: (password) {
              signInBloc.add(
                SignInEvent.signInWithEmailAndPassword(
                  email: email,
                  password: password,
                ),
              );
            },
            onForgotPassword: () {
              // todo: implement forgot password
            },
          ),
        ),
      ),
    );
  }

  // TODO: 手机号验证功能需要后端支持
  // void _pushContinueWithPhoneSmsPage(
  //   BuildContext context,
  //   String phone,
  // ) {
  //   // 暂未实现
  // }

  void _navigateToUserAgreement(BuildContext context) {
    final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
    final base_web_domain = cloudEnv.appflowyCloudConfig.base_web_domain;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => LegalDocumentScreen(
          title: LocaleKeys.settings_mobile_userAgreement.tr(),
          url: '$base_web_domain/agreement',
        ),
      ),
    );
  }

  void _navigateToPrivacyPolicy(BuildContext context) {
    final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
    final base_web_domain = cloudEnv.appflowyCloudConfig.base_web_domain;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => LegalDocumentScreen(
          title: LocaleKeys.settings_mobile_privacyPolicy.tr(),
          url: '$base_web_domain/privacy',
        ),
      ),
    );
  }
}
