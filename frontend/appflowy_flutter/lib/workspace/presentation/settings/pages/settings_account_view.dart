import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/util/validator.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/workspace/application/user/settings_user_bloc.dart';
import 'package:appflowy/workspace/presentation/settings/pages/about/app_version.dart';
import 'package:appflowy/workspace/presentation/settings/pages/account/account.dart';
import 'package:appflowy/workspace/presentation/settings/pages/account/email/email_section.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_body.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_category.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/email_binding_dialog.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/identity_verification_dialog.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/phone_change_dialog.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SettingsAccountView extends StatefulWidget {
  const SettingsAccountView({
    super.key,
    required this.userProfile,
    required this.didLogin,
    required this.didLogout,
  });

  final UserProfilePB userProfile;

  // Called when the user signs in from the setting dialog
  final VoidCallback didLogin;

  // Called when the user logout in the setting dialog
  final VoidCallback didLogout;

  @override
  State<SettingsAccountView> createState() => _SettingsAccountViewState();
}

class _SettingsAccountViewState extends State<SettingsAccountView> {
  late String userName = widget.userProfile.name;

  @override
  Widget build(BuildContext context) {
    // 账号页的数据来源需要跟随 SettingsDialogBloc（会员刷新、用户资料更新等）
    return BlocBuilder<SettingsDialogBloc, SettingsDialogState>(
      builder: (context, settingsState) {
        final latestUserProfile = settingsState.userProfile;
        final currentSubscription = settingsState.currentSubscription;
        final isLoadingSubscription = settingsState.isLoadingCurrentSubscription;
        final theme = AppFlowyTheme.of(context);
        return BlocProvider<SettingsUserViewBloc>(
          create: (context) =>
              getIt<SettingsUserViewBloc>(param1: latestUserProfile)
                ..add(const SettingsUserEvent.initial()),
          child: BlocBuilder<SettingsUserViewBloc, SettingsUserState>(
            builder: (context, state) {
              return SettingsBody(
                title: LocaleKeys.newSettings_myAccount_title.tr(),
                children: [
                  _AccountQuickActionsSection(
                    currentSubscription: currentSubscription,
                    isLoadingSubscription: isLoadingSubscription,
                  ),
                  const VSpace(16),
                  // 保留原有账号设置内容（后续可以继续补充）
                  // Account(
                  //   userProfile: latestUserProfile,
                  //   didLogout: widget.didLogout,
                  //   didLogin: widget.didLogin,
                  // ),
                  // if (cloudEnabled) ...[
                  //   const VSpace(16),
                  //   const EmailSection(),
                  // ],
                  // const VSpace(16),
                  // const AppVersion(),
                  
                  // 添加足够的间距，将退出登录按钮推到页面底部
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.4, // 调整高度以适应不同屏幕
                  ),
                  
                  GestureDetector(
                    onTap: () async {
                      final latestProfile =
                          context.read<SettingsDialogBloc>().state.userProfile;
                      final isQuickEntryUser =
                          latestProfile.userAuthType != AuthTypePB.Server;

                      if (isQuickEntryUser) {
                        // 快速进入用户：先让用户选择是否清除本地数
                        await showCancelAndConfirmDialog(
                          context: context,
                          title: '退出快速进入',
                          description:
                              '是否清除当前快速进入产生的数据？\n\n选择“清除并退出”会删除本地快速进入数据，下次进入将从空白开始；\n选择“保留数据退出”则仅重启应用，下次快速进入会尝试继续加载当前数据。',
                          confirmLabel: '清除并退出',
                          cancelLabel: '保留并退出',
                          onConfirm: (ctx) async {
                            try {
                              await getIt<AuthService>().signOut();
                            } catch (_) {}
                            // 清除并退出后，重启应用到登录页面，不自动登录
                            await runAppFlowy();
                          },
                          onCancel: () async {
                            // 保留数据退出，不调用signOut()，重启应用到登录页面
                            await runAppFlowy(isAnon: true);
                          },
                        );
                        return;
                      }

                      // 云端登录用户：保持原有退出逻辑
                      try {
                        await getIt<AuthService>().signOut();
                      } catch (_) {}
                      widget.didLogout();
                    },
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(vertical: theme.spacing.m),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme
                              .of(context)
                              .colorScheme
                              .primary,
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(theme.spacing.s),
                      ),
                      child: Center(
                        child: FlowyText(
                          '退出登录',
                          fontSize: 16,
                          color: Theme
                              .of(context)
                              .colorScheme
                              .primary,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _AccountQuickActionsSection extends StatelessWidget {
  const _AccountQuickActionsSection({
    required this.currentSubscription,
    required this.isLoadingSubscription,
  });

  final CurrentSubscription? currentSubscription;
  final bool isLoadingSubscription;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final storageUsage = _buildStorageUsageSubtitle();
    final aiUsage = _buildAiUsageSubtitle();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRow(
          context,
          title: LocaleKeys.settings_billingPage_storageSpace.tr(),
          trailing: isLoadingSubscription ? '' : storageUsage,
          showArrow: true,
        ),
        _buildRow(
          context,
          title: 'AI使用次数',
          trailing: isLoadingSubscription ? '' : aiUsage,
          showArrow: true,
        ),
        GestureDetector(
          onTap: () =>
              context
                  .read<SettingsDialogBloc>()
                  .add(const SettingsDialogEvent.setSelectedPage(
                  SettingsPage.userProfile)),
          child: _buildRow(
            context,
            title: '个人资料',
            trailing: '',
            showArrow: true,
          ),
        ),
        GestureDetector(
          onTap: () => _showPhoneVerificationDialog(context),
          child: _buildRow(
            context,
            title: '绑定手机',
            trailing: '修改',
            showArrow: true,
          ),
        ),
        GestureDetector(
          onTap: () => _showEmailVerificationDialog(context),
          child: _buildRow(
            context,
            title: '邮箱',
            trailing: '修改',
            showArrow: true,
          ),
        ),
      ],
    );
  }

  Widget _buildRow(BuildContext context, {
    required String title,
    required String trailing,
    required bool showArrow,
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
          if (trailing.isNotEmpty)
            FlowyText(
              trailing,
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

  String _buildAiUsageSubtitle() {
    final usage = currentSubscription?.usage;
    final remaining = usage?.aiChatRemaining;
    if (remaining == null) {
      return '';
    }
    return '本月剩余$remaining次';
  }

  String _buildStorageUsageSubtitle() {
    final usage = currentSubscription?.usage;
    final usedGb = usage?.storageUsedGb;
    final totalGb = usage?.storageTotalGb;
    if (usedGb == null || totalGb == null) {
      return '';
    }

    double remainingGb = totalGb - usedGb;
    if (remainingGb < 0) remainingGb = 0;

    String fmt(double gb) {
      if (gb < 1) {
        final mb = gb * 1024;
        return '${mb.toStringAsFixed(0)}M';
      }
      return '${gb.toStringAsFixed(gb >= 10 ? 0 : 1)}G';
    }

    return '${fmt(remainingGb)}/${fmt(totalGb)}';
  }

  void _showEmailVerificationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) =>
          EmailBindingDialog(
            onBindingComplete: () {
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

  void _showPhoneVerificationDialog(BuildContext context) {
    final settingsBloc = context.read<SettingsDialogBloc>();
    final latestUserProfile = settingsBloc.state.userProfile;

    String phoneNumber = '';
    if (latestUserProfile.hasPhone() && latestUserProfile.phone.isNotEmpty) {
      phoneNumber = latestUserProfile.phone;
    } else if (latestUserProfile.email.isNotEmpty &&
        !latestUserProfile.email.contains('@') &&
        Validator.isValidPhone(latestUserProfile.email)) {
      phoneNumber = latestUserProfile.email;
    } else {
      _showPhoneInputDialog(context);
      return;
    }

    final outerContext = context;
    showDialog(
      context: context,
      builder: (dialogContext) =>
          IdentityVerificationDialog(
            phoneNumber: phoneNumber,
            onVerificationComplete: () => _showPhoneChangeDialog(outerContext),
          ),
    );
  }

  void _showPhoneInputDialog(BuildContext context) {
    final phoneController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) =>
          AlertDialog(
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
                    builder: (context) =>
                        IdentityVerificationDialog(
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
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final settingsBloc = context.read<SettingsDialogBloc>();

    showDialog(
      context: context,
      builder: (dialogContext) =>
          PhoneChangeDialog(
            onChangeComplete: () async {
              scaffoldMessenger.showSnackBar(
                const SnackBar(
                  content: Text('手机号更改成功'),
                  duration: Duration(seconds: 2),
                ),
              );

              Log.info('📱 开始刷新用户资料...');
              final result = await UserBackendService.getCurrentUserProfile();
              result.fold(
                    (newProfile) {
                  settingsBloc.add(
                      SettingsDialogEvent.didReceiveUserProfile(newProfile));
                },
                    (error) => Log.error('❌ 刷新用户资料失败: ${error.msg}'),
              );
            },
          ),
    );
  }
}
