import 'package:appflowy/core/frameless_window.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/settings/show_settings.dart';
import 'package:appflowy/shared/window_title_bar.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/sign_in_bloc.dart';
import 'package:appflowy/user/presentation/router.dart';
import 'package:appflowy/user/presentation/screens/legal_document_screen.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/continue_with_magic_link_or_passcode_page.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/password_login_dialog.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:window_manager/window_manager.dart';

class DesktopSignInScreen extends StatefulWidget {
  const DesktopSignInScreen({
    super.key,
  });

  @override
  State<DesktopSignInScreen> createState() => _DesktopSignInScreenState();
}

class _DesktopSignInScreenState extends State<DesktopSignInScreen>
    with WindowListener {
  @override
  Widget build(BuildContext context) {
    return BlocListener<SignInBloc, SignInState>(
      listener: (context, state) async {
        final successOrFail = state.successOrFail;
        if (successOrFail != null) {
          if (successOrFail.isSuccess) {
            successOrFail.onSuccess((userProfile) async {
              // 检查 context 是否仍然有效
              if (!context.mounted) {
                return;
              }
              // 使用根导航器确保导航不会因为 context 失效而失败
              final rootContext = Navigator.of(context, rootNavigator: true).context;
              if (rootContext.mounted) {
                // 匿名登录成功，导航到主页
                getIt<AuthRouter>().goHomeScreen(rootContext, userProfile);
              }
            });
          } else {
            // 显示错误Toast
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
      },
      child: BlocBuilder<SignInBloc, SignInState>(
      builder: (context, state) {
        return Scaffold(
          appBar: _buildAppBar(),
            backgroundColor: Colors.white,
            body: Container(
              width: double.infinity,
              height: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFFFF8F6), // 浅色渐变背景，更贴近设计稿
                    Colors.white,
                  ],
                ),
              ),
              child: Center(
                child: SingleChildScrollView(
                  child: Container(
                    width: 380,
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                      // Logo部分 - 小马笔记 Logo
                      const _PonyNotesLogo(
                        size: Size.square(80),
                      ),
                      const VSpace(30),

                      // 标题 - 中文化
                      Text(
                        LocaleKeys.welcomeToPonyNotes.tr(),
                        style: const TextStyle(
                          color: Color(0xFF333333),
                          fontSize: 24,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                      const VSpace(40),

                      // 快速开始按钮
                      _QuickStartButton(
                        onTap: () {
                          context
                              .read<SignInBloc>()
                              .add(const SignInEvent.signInAsGuest());
                        },
                      ),
                      const VSpace(10),

                      // 分割线
                      const _OrDivider(),
                      const VSpace(10),

                      // 邮箱输入框和登录按钮
                      _EmailLoginSection(),

                      // 第三方登录部分
                if (isAuthEnabled) ...[
                        const VSpace(40),
                        const _CustomOrDivider(text: "其他登录方式"),
                        const VSpace(40),
                        _CustomThirdPartyButtons(),
                      ],

                      const VSpace(40),
                    ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  PreferredSize _buildAppBar() {
    return PreferredSize(
      preferredSize: Size.fromHeight(UniversalPlatform.isWindows ? 40 : 60),
      child: UniversalPlatform.isWindows
          ? const WindowTitleBar()
          : const MoveWindowDetector(),
    );
  }

  @override
  void onWindowFocus() {
    // https://pub.dev/packages/window_manager#windows
    // must call setState once when the window is focused
    setState(() {});
  }
}

class DesktopSignInSettingsButton extends StatelessWidget {
  const DesktopSignInSettingsButton({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return AFGhostIconTextButton(
      text: "设置",
      textColor: (context, isHovering, disabled) {
        return theme.textColorScheme.secondary;
      },
      size: AFButtonSize.s,
      padding: EdgeInsets.symmetric(
        horizontal: theme.spacing.m,
        vertical: theme.spacing.xs,
      ),
      onTap: () => showSimpleSettingsDialog(context),
      iconBuilder: (context, isHovering, disabled) {
        return FlowySvg(
          FlowySvgs.settings_s,
          size: Size.square(20),
          color: theme.textColorScheme.secondary,
        );
      },
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            color: const Color(0xFFE0E0E0),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 17),
          child: Text(
            "或",
            style: TextStyle(
              color: const Color(0xFF999999),
              fontSize: 18,
              fontWeight: FontWeight.normal,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            color: const Color(0xFFE0E0E0),
          ),
        ),
      ],
    );
  }
}

class _CustomOrDivider extends StatelessWidget {
  const _CustomOrDivider({required this.text});
  
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Container(
            height: 1,
            color: const Color(0xFFE0E0E0),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 17),
          child: Text(
            text,
            style: TextStyle(
              color: const Color(0xFF333333),
              fontSize: 18,
            ),
          ),
        ),
        Flexible(
          child: Container(
            height: 1,
            color: const Color(0xFFE0E0E0),
          ),
        ),
      ],
    );
  }
}

// 快速开始按钮组件
class _QuickStartButton extends StatelessWidget {
  const _QuickStartButton({required this.onTap});
  
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFFFF4F0),
          border: Border.all(color: const Color(0xFFF89575)),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: const Text(
          "快速开始",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFFF89575),
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// 邮箱/手机号登录部分组件（PonyNotes 风格）
class _EmailLoginSection extends StatefulWidget {
  const _EmailLoginSection();

  @override
  State<_EmailLoginSection> createState() => _EmailLoginSectionState();
}

class _EmailLoginSectionState extends State<_EmailLoginSection> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _agreedToTerms = true; // 默认选中协议

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // 验证手机号格式（中国手机号）
  bool _isValidPhone(String phone) {
    final phoneRegex = RegExp(r'^1[3-9]\d{9}$');
    return phoneRegex.hasMatch(phone);
  }

  // 验证邮箱格式
  bool _isValidEmail(String email) {
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return emailRegex.hasMatch(email);
  }

  // 验证邮箱或手机号
  bool _isValidEmailOrPhone(String input) {
    return _isValidEmail(input) || _isValidPhone(input);
  }

  Future<void> _handleSubmit(BuildContext context) async {
    final input = _controller.text.trim();
    
    if (input.isEmpty) {
      showToastNotification(
        message: "请输入邮箱或手机号",
        type: ToastificationType.error,
      );
      return;
    }

    if (!_isValidEmailOrPhone(input)) {
      showToastNotification(
        message: "请输入有效的邮箱地址或手机号",
        type: ToastificationType.error,
      );
      return;
    }

    if (!_agreedToTerms) {
      showToastNotification(
        message: "请先同意用户协议和隐私政策",
        type: ToastificationType.error,
      );
      return;
    }

    // 区分邮箱和手机号
    final bool isEmail = _isValidEmail(input);
    final bool isPhone = _isValidPhone(input);
    
    // 清理手机号格式（移除+86等国际区号）
    final String emailOrPhone = isPhone ? _cleanPhoneNumber(input) : input;
    
    final signInBloc = context.read<SignInBloc>();
    
    // 先检查用户是否设置了密码
    signInBloc.add(
      SignInEvent.checkPasswordStatus(
        email: isEmail ? emailOrPhone : null,
        phone: isPhone ? emailOrPhone : null,
      ),
    );
    
    // 等待密码状态检查完成
    await Future.delayed(const Duration(milliseconds: 800));
    
    // 获取当前状态
    final currentState = signInBloc.state;
    if (currentState.passwordIsSet == true) {
      // 用户已设置密码，弹出密码登录对话框
      _showPasswordLoginDialog(context, emailOrPhone, signInBloc);
    } else {
      // 用户未设置密码，直接发送验证码并跳转到验证码输入页面
      _sendVerificationCodeAndNavigate(context, emailOrPhone, isEmail, signInBloc);
    }
  }

  void _showPasswordLoginDialog(
    BuildContext context,
    String emailOrPhone,
    SignInBloc signInBloc,
  ) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => BlocProvider.value(
        value: signInBloc,
        child: PasswordLoginDialog(
          phoneOrEmail: emailOrPhone,
          onPasswordLogin: (password) {
            // 使用密码登录
            signInBloc.add(
              SignInEvent.signInWithEmailAndPassword(
                email: emailOrPhone,
                password: password,
              ),
            );
          },
          onSwitchToVerificationCode: () {
            // 关闭密码登录对话框，切换到验证码登录
            Navigator.of(dialogContext).pop();
            final bool isEmail = _isValidEmail(emailOrPhone);
            _sendVerificationCodeAndNavigate(context, emailOrPhone, isEmail, signInBloc);
          },
        ),
      ),
    );
  }

  void _sendVerificationCodeAndNavigate(
    BuildContext context,
    String emailOrPhone,
    bool isEmail,
    SignInBloc signInBloc,
  ) {
    // 发送登录请求（GoTrue 会自动识别是邮箱还是手机号）
    signInBloc.add(
      SignInEvent.signInWithMagicLink(email: emailOrPhone),
    );

    // 根据输入类型显示不同的提示信息
    showToastNotification(
      message: isEmail 
          ? "验证码已发送，请查看您的邮箱" 
          : "验证码已发送，请查看您的手机短信",
      type: ToastificationType.success,
    );

    // 跳转到验证码输入页面
    final navigator = Navigator.of(context);
    navigator.push(
      MaterialPageRoute(
        builder: (context) => BlocProvider.value(
          value: signInBloc,
          child: ContinueWithMagicLinkOrPasscodePage(
            email: emailOrPhone,
            backToLogin: () {
              navigator.pop();
            },
            onEnterPasscode: (code) {
              // 使用验证码登录
              signInBloc.add(
                SignInEvent.signInWithPasscode(
                  email: emailOrPhone,
                  passcode: code,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // 清理手机号格式，移除国际区号
  String _cleanPhoneNumber(String phone) {
    String cleanPhone = phone.trim();
    if (cleanPhone.startsWith('+86')) {
      cleanPhone = cleanPhone.substring(3);
    } else if (cleanPhone.startsWith('86') && cleanPhone.length == 13) {
      cleanPhone = cleanPhone.substring(2);
    }
    return cleanPhone;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 输入框
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE0E0E0)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            style: const TextStyle(
              fontSize: 16,
              color: Color(0xFF333333),
            ),
            decoration: const InputDecoration(
              hintText: "输入邮箱或手机号",
              hintStyle: TextStyle(
                fontSize: 16,
                color: Color(0xFF999999),
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            onSubmitted: (_) => _handleSubmit(context),
          ),
        ),
        const VSpace(12),

        // 登录/注册按钮
        GestureDetector(
          onTap: () => _handleSubmit(context),
          child: Container(
            width: double.infinity,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF89575),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Text(
                "登录/注册",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
        const VSpace(8),

        // 复选框和同意协议
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: Checkbox(
                value: _agreedToTerms,
                onChanged: (value) {
                  setState(() {
                    _agreedToTerms = value ?? false;
                  });
                },
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                side: const BorderSide(color: Color(0xFFE0E0E0)),
                activeColor: const Color(0xFFF89575),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF999999),
                  ),
                  children: [
                    const TextSpan(text: "我已阅读并同意 "),
                    TextSpan(
                      text: "《${LocaleKeys.legal_userAgreement.tr()}》",
                      style: const TextStyle(
                        color: Color(0xFFF89575),
                      ),
                      mouseCursor: SystemMouseCursors.click,
                      recognizer: TapGestureRecognizer()
                        ..onTap = () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => LegalDocumentScreen(
                                title: LocaleKeys.sidebar_appName.tr() + LocaleKeys.legal_userAgreement.tr(),
                                content: LocaleKeys.legal_userAgreementContent.tr(),
                              ),
                            ),
                          );
                        },
                    ),
                    TextSpan(text: LocaleKeys.and.tr()),
                    TextSpan(
                      text: "《${LocaleKeys.legal_privacyPolicy.tr()}》",
                      style: const TextStyle(
                        color: Color(0xFFF89575),
                      ),
                      mouseCursor: SystemMouseCursors.click,
                      recognizer: TapGestureRecognizer()
                        ..onTap = () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => LegalDocumentScreen(
                                title: LocaleKeys.legal_privacyPolicy.tr(),
                                content: LocaleKeys.legal_privacyPolicyContent.tr(),
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
        ),
      ],
    );
  }
}

// 自定义第三方登录按钮组（简化版 - 只显示图标）
class _CustomThirdPartyButtons extends StatelessWidget {
  const _CustomThirdPartyButtons();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 微信登录
        _ThirdPartyIconButton(
          label: "微信",
          backgroundColor: const Color(0xFF09BB07),
          onTap: () {
            showToastNotification(
              message: "微信登录功能开发中",
              type: ToastificationType.info,
            );
          },
        ),
        const SizedBox(width: 32),

        // 抖音登录
        _ThirdPartyIconButton(
          label: "抖音",
          backgroundColor: Colors.black,
          onTap: () {
            showToastNotification(
              message: "抖音登录功能开发中",
              type: ToastificationType.info,
            );
          },
        ),
        const SizedBox(width: 32),

        // QQ 登录
        _ThirdPartyIconButton(
          label: "QQ",
          backgroundColor: const Color(0xFF12B7F5),
          onTap: () {
            showToastNotification(
              message: "QQ登录功能开发中",
              type: ToastificationType.info,
            );
          },
        ),
      ],
    );
  }
}

// 小马笔记 Logo 组件
class _PonyNotesLogo extends StatelessWidget {
  const _PonyNotesLogo({
    this.size = const Size.square(80),
  });

  final Size size;

  @override
  Widget build(BuildContext context) {
    return FlowySvg(
      FlowySvgs.pony_notes_logo_xl,
      blendMode: null, // 保持原始颜色
      size: size,
    );
  }
}

// 第三方登录图标按钮（带文字标签）
class _ThirdPartyIconButton extends StatelessWidget {
  const _ThirdPartyIconButton({
    required this.label,
    required this.backgroundColor,
    required this.onTap,
  });

  final String label;
  final Color backgroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE0E0E0)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
