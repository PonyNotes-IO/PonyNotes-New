import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_backend/log.dart';
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
import 'package:appflowy/workspace/presentation/settings/widgets/phone_bind_dialog.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/phone_change_dialog.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
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
                ],
                bottomWidget: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: _buildAccountActionButton(context),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // 根据用户类型构建登录或退出登录按钮
  Widget _buildAccountActionButton(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final latestProfile =
        context.read<SettingsDialogBloc>().state.userProfile;
    final isQuickEntryUser =
        latestProfile.userAuthType != AuthTypePB.Server;

    if (isQuickEntryUser) {
      // 匿名用户（快速进入）：显示"登录"按钮，点击弹出登录窗口
      return GestureDetector(
        onTap: () async {
          await AccountSignInOutButton.showSignInDialog(context);
        },
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(vertical: theme.spacing.m),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(theme.spacing.s),
          ),
          child: Center(
            child: FlowyText(
              '登录',
              fontSize: 16,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
        ),
      );
    }

    // 云端登录用户：显示"退出登录"按钮
    return GestureDetector(
      onTap: () async {
        await showCancelAndConfirmDialog(
          context: context,
          title: '退出登录',
          description: '确定要退出当前账号吗？',
          confirmLabel: '退出登录',
          cancelLabel: '取消',
          onConfirm: (ctx) async {
            try {
              await getIt<AuthService>().signOut();
            } catch (_) {}
            widget.didLogout();
          },
        );
      },
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: theme.spacing.m),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.primary,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(theme.spacing.s),
        ),
        child: Center(
          child: FlowyText(
            '退出登录',
            fontSize: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
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
    final isCloudSignedIn = context
        .read<SettingsDialogBloc>()
        .state
        .userProfile
        .userAuthType ==
        AuthTypePB.Server;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRow(
          context,
          title: LocaleKeys.settings_billingPage_storageSpace.tr(),
          trailing: isLoadingSubscription ? '--' : storageUsage,
          showArrow: false,
        ),
        _buildRow(
          context,
          title: 'AI使用次数',
          trailing: isLoadingSubscription ? '--' : aiUsage,
          showArrow: false,
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
        if (isCloudSignedIn) ...[
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
              title: '绑定邮箱',
              trailing: '修改',
              showArrow: true,
            ),
          ),
        ],
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
      return '--';
    }
    return '本月剩余$remaining次';
  }

  String _buildStorageUsageSubtitle() {
    final usage = currentSubscription?.usage;
    final usedGb = usage?.storageUsedGb;
    final totalGb = usage?.storageTotalGb;
    if (usedGb == null || totalGb == null) {
      return '--';
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
    final settingsBloc = context.read<SettingsDialogBloc>();
    final latestUserProfile = settingsBloc.state.userProfile;

    final emailAddress = latestUserProfile.email;

    if (emailAddress.isNotEmpty && emailAddress.contains('@')) {
      // 已有邮箱 → 先身份验证，再换绑
      final outerContext = context;
      showDialog(
        context: context,
        builder: (dialogContext) =>
            IdentityVerificationDialog(
              phoneNumber: latestUserProfile.phone.isNotEmpty
                  ? latestUserProfile.phone
                  : '',
              emailAddress: emailAddress,
              onVerificationComplete: () => _showEmailBindingDialog(outerContext, isChange: true),
            ),
      );
    } else {
      // 未绑定邮箱 → 直接进入绑定流程
      _showEmailBindingDialog(context, isChange: false);
    }
  }

  void _showEmailBindingDialog(BuildContext context, {required bool isChange}) {
    final settingsBloc = context.read<SettingsDialogBloc>();

    showDialog(
      context: context,
      builder: (context) =>
          EmailBindingDialog(
            title: isChange ? '更换邮箱' : '绑定邮箱',
            onBindingComplete: () async {
              showToastNotification(message: isChange ? '邮箱更换成功' : '邮箱绑定成功');

              Log.info('📧 开始刷新用户资料...');
              final result = await UserBackendService.getCurrentUserProfile();
              result.fold(
                    (newProfile) {
                  settingsBloc.add(
                      SettingsDialogEvent.didReceiveUserProfile(newProfile));
                  Log.info('✅ 用户资料已刷新');
                },
                    (error) {
                  Log.error('❌ 刷新用户资料失败: ${error.msg}');
                },
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
      // 没有手机号 → 直接进入手机号绑定流程，无需先做身份验证
      // IdentityVerificationDialog 仅用于验证已有手机号，不可用于绑定新手机号
      _showPhoneBindingDialog(context);
      return;
    }

    final outerContext = context;
    showDialog(
      context: context,
      builder: (dialogContext) =>
          IdentityVerificationDialog(
            phoneNumber: phoneNumber,
            emailAddress: latestUserProfile.email,
            onVerificationComplete: () => _showPhoneChangeDialog(outerContext),
          ),
    );
  }

  /// 邮箱用户首次绑定手机号时直接进入绑定弹窗
  /// 使用 PhoneBindDialog（send-phone-otp + confirmPhoneBind），不走身份再认证流程
  void _showPhoneBindingDialog(BuildContext context) {
    final settingsBloc = context.read<SettingsDialogBloc>();
    showDialog(
      context: context,
      builder: (_) => PhoneBindDialog(
        onBindComplete: () async {
          showToastNotification(message: '手机号绑定成功');
          final result = await UserBackendService.getCurrentUserProfile();
          result.fold(
            (newProfile) => settingsBloc
                .add(SettingsDialogEvent.didReceiveUserProfile(newProfile)),
            (error) => Log.error('刷新用户资料失败: ${error.msg}'),
          );
        },
      ),
    );
  }

  void _showPhoneChangeDialog(BuildContext context) {
    final settingsBloc = context.read<SettingsDialogBloc>();

    showDialog(
      context: context,
      builder: (dialogContext) =>
          PhoneChangeDialog(
            onChangeComplete: () async {
              showToastNotification(message: '手机号更改成功');

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
