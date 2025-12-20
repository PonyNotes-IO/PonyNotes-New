import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/password/password_http_service.dart';
import 'package:appflowy/user/presentation/router.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

/// 设置密码页面
/// 在验证码登录成功后，如果用户未设置密码，会跳转到此页面
class SetPasswordPage extends StatefulWidget {
  const SetPasswordPage({
    super.key,
    required this.userProfile,
    required this.phoneOrEmail,
    required this.accessToken,
  });

  final UserProfilePB userProfile;
  final String phoneOrEmail;
  final String accessToken;

  @override
  State<SetPasswordPage> createState() => _SetPasswordPageState();
}

class _SetPasswordPageState extends State<SetPasswordPage> {
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final FocusNode _newPasswordFocusNode = FocusNode();
  final FocusNode _confirmPasswordFocusNode = FocusNode();

  bool _isNewPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isSubmitting = false;
  String _errorMessage = '';

  PasswordHttpService? _passwordService;

  @override
  void initState() {
    super.initState();
    _initializePasswordService();
  }

  void _initializePasswordService() {
    if (isAppFlowyCloudEnabled) {
      final sharedEnv = getIt<AppFlowyCloudSharedEnv>();
      _passwordService = PasswordHttpService(
        baseUrl: sharedEnv.appflowyCloudConfig.gotrue_url,
        authToken: widget.accessToken,
      );
    }
  }

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _newPasswordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Scaffold(
      backgroundColor: theme.surfaceColorScheme.layer01,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部导航栏
            _buildTopBar(context),
            
            // 主要内容
            Expanded(
              child: SingleChildScrollView(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const VSpace(40),
                          
                          // 标题
                          Text(
                            '设置密码',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const VSpace(20),
                          
                          // 密码要求说明
                          Text(
                            '请输入8位以上的密码,需包含大小写字母、数字和特殊字符',
                            style: TextStyle(
                              fontSize: 16,
                              color: theme.textColorScheme.secondary,
                              height: 1.5,
                            ),
                          ),
                          const VSpace(40),
                          
                          // 手机号/邮箱显示（只读）
                          _buildPhoneOrEmailField(),
                          const VSpace(20),
                          
                          // 新密码输入框
                          _buildNewPasswordField(),
                          const VSpace(20),
                          
                          // 确认密码输入框
                          _buildConfirmPasswordField(),
                          const VSpace(20),
                          
                          // 错误提示
                          if (_errorMessage.isNotEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                _errorMessage,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          
                          const VSpace(40),
                          
                          // 确定按钮
                          _buildConfirmButton(),
                          
                          const VSpace(20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // 返回按钮
          IconButton(
            icon: Icon(
              Icons.arrow_back,
              size: 24,
              color: theme.textColorScheme.primary,
            ),
            onPressed: () {
              // 返回按钮暂时不做任何操作，因为用户已经登录成功
              // 如果用户想返回，应该直接进入系统
              _handleSkip();
            },
          ),
          const Spacer(),
          // 跳过按钮
          TextButton(
            onPressed: _isSubmitting ? null : _handleSkip,
            child: Text(
              '跳过',
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneOrEmailField() {
    final theme = AppFlowyTheme.of(context);
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: theme.surfaceColorScheme.layer02,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.borderColorScheme.primary),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.phoneOrEmail,
              style: TextStyle(
                fontSize: 16,
                color: theme.textColorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewPasswordField() {
    final theme = AppFlowyTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '新密码',
          style: TextStyle(
            fontSize: 14,
            color: theme.textColorScheme.primary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const VSpace(8),
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: theme.surfaceColorScheme.layer02,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.borderColorScheme.primary),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newPasswordController,
                  focusNode: _newPasswordFocusNode,
                  obscureText: !_isNewPasswordVisible,
                  style: TextStyle(
                    fontSize: 16,
                    color: theme.textColorScheme.primary,
                  ),
                  decoration: InputDecoration(
                    hintText: '请输入新密码',
                    hintStyle: TextStyle(
                      fontSize: 16,
                      color: theme.textColorScheme.tertiary,
                    ),
                    border: InputBorder.none,
                  ),
                  onChanged: (_) {
                    if (_errorMessage.isNotEmpty) {
                      setState(() => _errorMessage = '');
                    }
                  },
                ),
              ),
              IconButton(
                icon: Icon(
                  _isNewPasswordVisible
                      ? Icons.visibility_off
                      : Icons.visibility,
                  size: 20,
                  color: theme.textColorScheme.tertiary,
                ),
                onPressed: () {
                  setState(() {
                    _isNewPasswordVisible = !_isNewPasswordVisible;
                  });
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmPasswordField() {
    final theme = AppFlowyTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '确认密码',
          style: TextStyle(
            fontSize: 14,
            color: theme.textColorScheme.primary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const VSpace(8),
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: theme.surfaceColorScheme.layer02,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.borderColorScheme.primary),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _confirmPasswordController,
                  focusNode: _confirmPasswordFocusNode,
                  obscureText: !_isConfirmPasswordVisible,
                  style: TextStyle(
                    fontSize: 16,
                    color: theme.textColorScheme.primary,
                  ),
                  decoration: InputDecoration(
                    hintText: '再次输入你的新密码',
                    hintStyle: TextStyle(
                      fontSize: 16,
                      color: theme.textColorScheme.tertiary,
                    ),
                    border: InputBorder.none,
                  ),
                  onChanged: (_) {
                    if (_errorMessage.isNotEmpty) {
                      setState(() => _errorMessage = '');
                    }
                  },
                  onSubmitted: (_) {
                    _handleConfirm();
                  },
                ),
              ),
              IconButton(
                icon: Icon(
                  _isConfirmPasswordVisible
                      ? Icons.visibility_off
                      : Icons.visibility,
                  size: 20,
                  color: theme.textColorScheme.tertiary,
                ),
                onPressed: () {
                  setState(() {
                    _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                  });
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmButton() {
    final theme = AppFlowyTheme.of(context);
    final materialTheme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _handleConfirm,
        style: ElevatedButton.styleFrom(
          backgroundColor: materialTheme.colorScheme.primary,
          foregroundColor: materialTheme.colorScheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 0,
        ),
        child: _isSubmitting
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    materialTheme.colorScheme.onPrimary,
                  ),
                ),
              )
            : const Text(
                '确定',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
      ),
    );
  }

  void _handleSkip() {
    // 直接进入系统
    _enterSystem();
  }

  Future<void> _handleConfirm() async {
    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    // 验证输入
    if (newPassword.isEmpty) {
      setState(() {
        _errorMessage = '请输入新密码';
      });
      _newPasswordFocusNode.requestFocus();
      return;
    }

    if (confirmPassword.isEmpty) {
      setState(() {
        _errorMessage = '请再次输入新密码';
      });
      _confirmPasswordFocusNode.requestFocus();
      return;
    }

    if (newPassword != confirmPassword) {
      setState(() {
        _errorMessage = '两次输入的密码不一致';
      });
      _confirmPasswordFocusNode.requestFocus();
      return;
    }

    // 验证密码强度
    if (newPassword.length < 8) {
      setState(() {
        _errorMessage = '密码长度至少为8位';
      });
      _newPasswordFocusNode.requestFocus();
      return;
    }

    // 检查密码是否包含大小写字母、数字和特殊字符
    final hasUpperCase = newPassword.contains(RegExp(r'[A-Z]'));
    final hasLowerCase = newPassword.contains(RegExp(r'[a-z]'));
    final hasDigit = newPassword.contains(RegExp(r'[0-9]'));
    final hasSpecialChar = newPassword.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));

    if (!hasUpperCase || !hasLowerCase || !hasDigit || !hasSpecialChar) {
      setState(() {
        _errorMessage = '密码需包含大小写字母、数字和特殊字符';
      });
      _newPasswordFocusNode.requestFocus();
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = '';
    });

    // 调用设置密码接口
    if (_passwordService == null) {
      Log.error('🟢 [SetPasswordPage] PasswordService 未初始化');
      setState(() {
        _isSubmitting = false;
        _errorMessage = '系统错误，请稍后重试';
      });
      return;
    }

    // TODO: 需要设置正确的 authToken
    // 从登录响应中获取 access_token 并设置到 passwordService
    // 目前先尝试调用，如果失败再处理

    final result = await _passwordService!.setupPassword(
      newPassword: newPassword,
    );

    setState(() {
      _isSubmitting = false;
    });

    result.fold(
      (success) {
        // 设置密码成功，进入系统
        _enterSystem();
      },
      (error) {
        Log.error('🟢 [SetPasswordPage] 设置密码失败: ${error.msg}');
        setState(() {
          _errorMessage = error.msg;
        });
      },
    );
  }

  void _enterSystem() {
    // 使用正确的导航方式，而不是调用 runAppFlowy()
    // runAppFlowy() 会导致应用重启并可能引发 Navigator 相关的错误
    if (mounted && context.mounted) {
      try {
        // 先关闭设置密码页面
        final navigator = Navigator.of(context, rootNavigator: true);
        if (navigator.canPop()) {
          navigator.pop();
        }
        
        // 然后导航到主界面
        final rootContext = navigator.context;
        if (rootContext.mounted) {
          // 使用 AuthRouter.goHomeScreen 进行导航
          // 这与 SignInScreen 中的导航逻辑一致
          getIt<AuthRouter>().goHomeScreen(rootContext, widget.userProfile);
        }
      } catch (e, stackTrace) {
        Log.error('🟢 [SetPasswordPage] 导航失败: $e', stackTrace);
      }
    }
  }
}

