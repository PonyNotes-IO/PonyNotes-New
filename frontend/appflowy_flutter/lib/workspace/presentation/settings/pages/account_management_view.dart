import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/util/validator.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_body.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/identity_verification_dialog.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/email_binding_dialog.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/phone_change_dialog.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AccountManagementView extends StatefulWidget {
  const AccountManagementView({
    super.key,
    required this.userProfile,
    required this.workspaceId,
    required this.changeSelectedPage,
  });

  final UserProfilePB userProfile;
  final String workspaceId;
  final void Function(SettingsPage page) changeSelectedPage;

  @override
  State<AccountManagementView> createState() => _AccountManagementViewState();
}

class _AccountManagementViewState extends State<AccountManagementView> {
  WorkspaceSubscriptionInfoPB? _subscriptionInfo;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSubscriptionInfo();
  }

  Future<void> _loadSubscriptionInfo() async {
    setState(() {
      _isLoading = true;
    });

    final result = await UserBackendService.getWorkspaceSubscriptionInfo(widget.workspaceId);
    
    result.fold(
      (info) {
        if (mounted) {
          setState(() {
            _subscriptionInfo = info;
            _isLoading = false;
          });
        }
      },
      (error) {
        Log.error('Failed to load subscription info: ${error.msg}');
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      },
    );
  }

  // 根据订阅计划返回对应的配置
  Map<String, dynamic> _getPlanConfig(WorkspacePlanPB plan) {
    switch (plan) {
      case WorkspacePlanPB.FreePlan:
        return {
          'title': '免费版',
          'color': const Color(0xFFFF6B47),
          'tag': '',
        };
      case WorkspacePlanPB.StudentPlan:
        return {
          'title': '学生版',
          'color': const Color(0xFF4CAF50),
          'tag': '学生专享',
        };
      case WorkspacePlanPB.StandardPlan:
        return {
          'title': '标准版',
          'color': const Color(0xFF2196F3),
          'tag': '最受欢迎',
        };
      case WorkspacePlanPB.TeamPlan:
        return {
          'title': '团队版',
          'color': const Color(0xFF9C27B0),
          'tag': '',
        };
      default:
        return {
          'title': '免费版',
          'color': const Color(0xFFFF6B47),
          'tag': '',
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    
    return Column(
      children: [
        Expanded(
          child: SettingsBody(
            title: "我的账户",
            headerTrailingBuilder: (_) => OutlinedRoundedButton(
              text: '充值记录',
              onTap: () => widget.changeSelectedPage(SettingsPage.rechargeRecords),
            ),
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isLoading)
                    const Center(
                      child: CircularProgressIndicator(),
                    )
                  else
                    _buildPlanStatusRow(context),
                  const VSpace(32),
                  _buildFeatureItem(context, '文档光标颜色', '购买', showArrow: true),
                  _buildFeatureItem(context, 'AI使用次数', '今日剩余20次升级', showArrow: true),
                  GestureDetector(
                    onTap: () => widget.changeSelectedPage(SettingsPage.userProfile),
                    child: _buildFeatureItem(context, '个人资料', '', showArrow: true),
                  ),
                  GestureDetector(
                    onTap: () => _showPhoneVerificationDialog(context),
                    child: _buildFeatureItem(context, '绑定手机', '修改', showButton: true, buttonText: '修改'),
                  ),
                  GestureDetector(
                    onTap: () => _showEmailVerificationDialog(context),
                    child: _buildFeatureItem(context, '邮箱', '修改', showButton: true, buttonText: '修改'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: GestureDetector(
            onTap: () async {
              await getIt<AuthService>().signOut();
              await runAppFlowy();
            },
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: theme.spacing.m),
              decoration: BoxDecoration(
                border: Border.all(
                  color: const Color(0xFFFF6B47),
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(theme.spacing.s),
              ),
              child: const Center(
                child: FlowyText(
                  '退出登录',
                  fontSize: 16,
                  color: Color(0xFFFF6B47),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 构建四个计划状态的行
  Widget _buildPlanStatusRow(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    
    // 定义所有计划的配置
    final allPlans = [
      WorkspacePlanPB.FreePlan,
      WorkspacePlanPB.StudentPlan,
      WorkspacePlanPB.StandardPlan,
      WorkspacePlanPB.TeamPlan,
    ];

    // 获取当前用户的计划
    final currentPlan = _subscriptionInfo?.plan ?? WorkspacePlanPB.FreePlan;

    return Row(
      children: allPlans.map((plan) {
        final config = _getPlanConfig(plan);
        final isCurrentPlan = plan == currentPlan;
        
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(
              right: plan != WorkspacePlanPB.TeamPlan ? theme.spacing.s : 0,
            ),
            child: Column(
              children: [
                // 圆圈指示器
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCurrentPlan 
                        ? config['color'].withOpacity(0.1) 
                        : Colors.transparent,
                    border: Border.all(
                      color: isCurrentPlan 
                          ? config['color'] 
                          : theme.borderColorScheme.primary.withOpacity(0.2),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: isCurrentPlan
                        ? Icon(
                            Icons.check,
                            color: config['color'],
                            size: 24,
                          )
                        : null,
                  ),
                ),
                const VSpace(8),
                // 计划名称
                FlowyText(
                  config['title'],
                  fontSize: 14,
                  fontWeight: isCurrentPlan ? FontWeight.w600 : FontWeight.normal,
                  color: isCurrentPlan 
                      ? theme.textColorScheme.primary 
                      : theme.textColorScheme.secondary,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
  
  Widget _buildFeatureItem(
    BuildContext context,
    String title,
    String subtitle, {
    bool showArrow = false,
    bool showButton = false,
    String buttonText = '',
  }) {
    final theme = AppFlowyTheme.of(context);
    
    return Container(
      padding: EdgeInsets.symmetric(vertical: theme.spacing.m),
      child: Row(
        children: [
          Expanded(
            child: FlowyText(
              title,
              fontSize: 16,
              color: theme.textColorScheme.primary,
            ),
          ),
          if (subtitle.isNotEmpty && !showButton)
            FlowyText(
              subtitle,
              fontSize: 14,
              color: theme.textColorScheme.secondary,
            ),
          if (showButton)
            FlowyText(
              buttonText,
              fontSize: 14,
              color: theme.textColorScheme.secondary,
            ),
          if (showArrow)
            const Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey,
            ),
        ],
      ),
    );
  }

  void _showPhoneVerificationDialog(BuildContext context) {
    // 调试：打印用户资料信息
    Log.info('用户资料 - email: ${widget.userProfile.email}, name: ${widget.userProfile.name}');
    
    // 从用户资料中获取手机号
    // 优先使用 phone 字段，如果没有则检查 email 字段
    String phoneNumber = '';
    
    if (widget.userProfile.hasPhone() && widget.userProfile.phone.isNotEmpty) {
      // 优先使用 phone 字段
      phoneNumber = widget.userProfile.phone;
      Log.info('从用户资料的 phone 字段获取到手机号: $phoneNumber');
    } else if (widget.userProfile.email.isNotEmpty && 
        !widget.userProfile.email.contains('@') &&
        Validator.isValidPhone(widget.userProfile.email)) {
      // 兼容旧数据：检查 email 字段是否包含手机号
      phoneNumber = widget.userProfile.email;
      Log.info('从用户资料的 email 字段获取到手机号: $phoneNumber');
    } else {
      Log.info('用户资料中没有有效的手机号，显示输入对话框');
      // 如果没有绑定手机号，显示提示让用户输入
      _showPhoneInputDialog(context);
      return;
    }
    
    // 保存外层的 context，避免在对话框关闭后访问失效的 context
    final outerContext = context;
        
    showDialog(
      context: context,
      builder: (dialogContext) => IdentityVerificationDialog(
        phoneNumber: phoneNumber,
        onVerificationComplete: () {
          // 身份验证成功后，打开更改手机号码对话框
          // 使用保存的外层 context
          _showPhoneChangeDialog(outerContext);
        },
      ),
    );
  }

  void _showPhoneInputDialog(BuildContext context) {
    final phoneController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('输入手机号'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('请输入您要绑定的手机号码'),
            const SizedBox(height: 16),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(
                hintText: '请输入手机号',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final phone = phoneController.text.trim();
              if (phone.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('请输入手机号'),
                    duration: Duration(seconds: 2),
                  ),
                );
                return;
              }
              
              // 验证手机号格式
              if (!Validator.isValidPhone(phone)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('请输入正确的手机号格式'),
                    duration: Duration(seconds: 2),
                  ),
                );
                return;
              }
              
              Navigator.of(context).pop();
              showDialog(
                context: context,
                builder: (context) => IdentityVerificationDialog(
                  phoneNumber: phone,
                  onVerificationComplete: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('手机验证完成'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              );
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showPhoneChangeDialog(BuildContext context) {
    // 保存 ScaffoldMessenger 和 SettingsDialogBloc 的引用，避免在对话框关闭后访问 context
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final settingsBloc = context.read<SettingsDialogBloc>();
    
    showDialog(
      context: context,
      builder: (dialogContext) => PhoneChangeDialog(
        onChangeComplete: () async {
          // 更改完成后的回调
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('手机号更改成功'),
              duration: Duration(seconds: 2),
            ),
          );
          
          // 刷新用户资料（Rust 后端会同步从云端刷新）
          Log.info('📱 开始刷新用户资料...');
          final result = await UserBackendService.getCurrentUserProfile();
          result.fold(
            (newProfile) {
              Log.info('✅ 刷新后的用户资料:');
              Log.info('   - name: ${newProfile.name}');
              Log.info('   - email: ${newProfile.email}');
              final hasPhone = newProfile.hasPhone() && newProfile.phone.isNotEmpty;
              final phoneValue = hasPhone ? newProfile.phone : '(null)';
              Log.info('   - phone: $phoneValue');
              Log.info('   - phone.isEmpty: ${!hasPhone}');
              
              if (!hasPhone) {
                Log.error('⚠️ 警告：刷新后的用户资料中 phone 字段为空！');
                Log.error('   这可能是因为：');
                Log.error('   1. 云端数据库没有更新成功');
                Log.error('   2. 云端 API 返回的数据中没有 phone 字段');
                Log.error('   3. 前端 Rust 代码没有正确映射 phone 字段');
                Log.error('   4. 本地数据库没有保存 phone 字段');
              } else {
                Log.info('✅ phone 字段正常: ${newProfile.phone}');
              }
              
              // 通知 SettingsDialogBloc 更新用户资料
              settingsBloc.add(
                SettingsDialogEvent.didReceiveUserProfile(newProfile),
              );
            },
            (error) {
              Log.error('❌ 刷新用户资料失败: ${error.msg}');
            },
          );
        },
      ),
    );
  }

  void _showEmailVerificationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => EmailBindingDialog(
        onBindingComplete: () {
          // 绑定完成后的回调
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('邮箱绑定完成'),
              duration: Duration(seconds: 2),
            ),
          );
        },
      ),
    );
  }
}
