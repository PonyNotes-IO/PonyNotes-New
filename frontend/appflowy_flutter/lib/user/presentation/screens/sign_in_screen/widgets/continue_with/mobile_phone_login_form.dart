import 'package:appflowy/user/application/sign_in_bloc.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/continue_with_magic_link_or_passcode_page.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/continue_with_password_page.dart';
import 'package:appflowy/util/validator.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../env/cloud_env.dart';
import '../../../../../../generated/locale_keys.g.dart';
import '../../../../../../startup/startup.dart';
import '../../../legal_document_screen.dart';

class MobilePhoneLoginForm extends StatefulWidget {
  const MobilePhoneLoginForm({
    super.key,
    required this.onAgreeChanged,
    this.initialAgreed = false,
  });

  final ValueChanged<bool> onAgreeChanged;
  final bool initialAgreed;

  @override
  State<MobilePhoneLoginForm> createState() => _MobilePhoneLoginFormState();
}

class _MobilePhoneLoginFormState extends State<MobilePhoneLoginForm> {
  final controller = TextEditingController();
  final focusNode = FocusNode();
  final emailKey = GlobalKey<AFTextFieldState>();

  bool _hasPushedContinueWithMagicLinkOrPasscodePage = false;
  late bool _agreed;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _agreed = widget.initialAgreed;
  }

  @override
  void didUpdateWidget(covariant MobilePhoneLoginForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialAgreed != widget.initialAgreed) {
      setState(() {
        _agreed = widget.initialAgreed;
      });
    }
  }

  @override
  void dispose() {
    controller.dispose();
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Email/Phone input
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: "输入邮箱或者手机号",
              hintStyle: TextStyle(
                color: const Color(0xFF999999),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            keyboardType: TextInputType.emailAddress,
            onSubmitted: (value) => _handleSubmit(context, value),
          ),
        ),
        const SizedBox(height: 16),
        
        // Login/Register button
        GestureDetector(
          onTap: _isLoading
              ? () {}
              : () {
                  final phone = controller.text.trim();
                  _handleSubmit(context, phone);
                },
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: primaryColor,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              _isLoading
                  ? "登录中..."
                  : "登录/注册",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _handleSubmit(BuildContext context, String emailOrPhone) {
    if (_isLoading) return;

    if (!Validator.isValidEmailOrPhone(emailOrPhone)) {
      // 显示错误提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('请输入有效的邮箱或手机号'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    if (!_agreed) {
      showAgreementDialog(context);
      return;
    }

    if (Validator.isValidEmail(emailOrPhone)) {
      _signInWithEmail(context, emailOrPhone);
    } else if (Validator.isValidPhone(emailOrPhone)) {
      // 清理手机号格式（移除+86等国际区号）
      final cleanPhone = Validator.cleanPhoneNumber(emailOrPhone);
      _signInWithPhone(context, cleanPhone);
    }
  }

  Future<void> _signInWithEmail(BuildContext context, String email) async {
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
          email: email,
        ),
      );
      
      // 等待密码状态检查完成
      final passwordIsSet = await _waitForPasswordStatus(signInBloc);
      if (!mounted) return;

      if (passwordIsSet == true) {
        // 用户已设置密码，跳转到密码登录页面
        _pushContinueWithPasswordPage(context, email);
      } else {
        // 用户未设置密码，发送验证码并跳转到验证码输入页面
        signInBloc.add(SignInEvent.signInWithMagicLink(email: email));
        _pushContinueWithMagicLinkOrPasscodePage(context, email);
      }
    } catch (e) {
      // 处理异常
      if (mounted) {
        _showUserCheckFailedDialog(context, email, e.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signInWithPhone(BuildContext context, String phone) async {
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
      final passwordIsSet = await _waitForPasswordStatus(signInBloc);
      if (!mounted) return;

      if (passwordIsSet == true) {
        // 用户已设置密码，跳转到密码登录页面
        _pushContinueWithPasswordPage(context, phone);
      } else {
        // 用户未设置密码，发送验证码并跳转到验证码输入页面
        signInBloc.add(SignInEvent.signInWithMagicLink(email: phone));
        _pushContinueWithMagicLinkOrPasscodePage(context, phone);
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

  /// 等待 passwordIsSet 有结果，最多 2 秒；超时或异常返回 null
  Future<bool?> _waitForPasswordStatus(SignInBloc signInBloc) async {
    try {
      // 如果当前已有值，直接返回
      if (signInBloc.state.passwordIsSet != null) {
        return signInBloc.state.passwordIsSet;
      }

      final state = await signInBloc.stream
          .where((s) => s.passwordIsSet != null)
          .first
          .timeout(const Duration(seconds: 2));
      return state.passwordIsSet;
    } catch (_) {
      return null;
    }
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
              if (Navigator.of(context).canPop()) {
                Navigator.pop(context);
              }
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
              // TODO: implement forgot password
            },
          ),
        ),
      ),
    );
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
            child: const Text('取消'),
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

  void showAgreementDialog(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    showDialog(
      context: context,
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
            children: [
              Text(
                '为了更好的使用服务\n登录前请阅读并同意以下协议',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 20),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 12,
                  ),
                  children: [
                    TextSpan(text:LocaleKeys.appName.tr()),
                    TextSpan(
                      text: '《${LocaleKeys.settings_mobile_userAgreement.tr()}》',
                      style: TextStyle(
                        color: primaryColor,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () {
                          Navigator.of(dialogContext).pop();
                          _navigateToUserAgreement(context);
                        },
                    ),
                    TextSpan(text: LocaleKeys.web_and.tr()),
                    TextSpan(
                      text: '《${LocaleKeys.settings_mobile_privacyPolicy.tr()}》',
                      style: TextStyle(
                        color: primaryColor,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () {
                          Navigator.of(dialogContext).pop();
                          _navigateToPrivacyPolicy(context);
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
                  widget.onAgreeChanged(true);
                  Navigator.of(dialogContext).pop();
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: primaryColor,
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
  }
} 
