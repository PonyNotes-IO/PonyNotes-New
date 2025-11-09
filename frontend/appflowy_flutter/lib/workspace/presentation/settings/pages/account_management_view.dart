import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_body.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/identity_verification_dialog.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/email_binding_dialog.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

class AccountManagementView extends StatefulWidget {
  const AccountManagementView({
    super.key,
    required this.userProfile,
    required this.workspaceId,
    required this.changeSelectedPage,
  });

  final UserProfilePB userProfile;
  final String workspaceId;
  final Function changeSelectedPage;

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
    
    return SettingsBody(
      title: "我的账户",
      children: [
        // 账户类型显示区域
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
              
              // 功能列表
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
              
              const VSpace(32),
              
              // 退出登录按钮
              Container(
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
            ],
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
    // 从用户资料中获取手机号，如果没有则使用默认值
    // TODO: UserProfilePB 暂不支持 phoneNumber 字段
    final phoneNumber = '185******70';
        
    showDialog(
      context: context,
      builder: (context) => IdentityVerificationDialog(
        phoneNumber: phoneNumber,
        onVerificationComplete: () {
          // 验证完成后的回调
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('手机验证完成'),
              duration: Duration(seconds: 2),
            ),
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
