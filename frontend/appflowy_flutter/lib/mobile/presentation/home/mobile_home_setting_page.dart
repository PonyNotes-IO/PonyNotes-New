import 'dart:io' as io;

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/features/workspace/logic/workspace_state.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/show_mobile_bottom_sheet.dart';
import 'package:appflowy/shared/appflowy_network_image.dart';
import 'package:appflowy/mobile/presentation/setting/about/about_setting_group.dart';
import 'package:appflowy/mobile/presentation/setting/about/mobile_about_xiaoma_page.dart';
import 'package:appflowy/mobile/presentation/setting/ai/ai_settings_group.dart';
import 'package:appflowy/workspace/application/settings/ai/settings_ai_bloc.dart';
import 'package:appflowy/mobile/presentation/setting/cloud/cloud_setting_group.dart';
import 'package:appflowy/mobile/presentation/setting/datetime/datetime_page.dart';
import 'package:appflowy/mobile/presentation/setting/font/font_picker_screen.dart';
import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/widgets/font_size_stepper.dart';
import 'package:appflowy/mobile/presentation/setting/notifications_setting_group.dart';
import 'package:appflowy/mobile/presentation/setting/personal_info/personal_info_setting_group.dart';
import 'package:appflowy/mobile/presentation/setting/self_host_setting_group.dart';
import 'package:appflowy/mobile/presentation/setting/storage/storage_setting_group.dart';
import 'package:appflowy/mobile/presentation/setting/support_setting_group.dart';
import 'package:appflowy/mobile/presentation/setting/user_session_setting_group.dart';
import 'package:appflowy/mobile/presentation/setting/workspace/workspace_setting_group.dart';
import 'package:appflowy/mobile/presentation/setting/workspace/mobile_space_management_page.dart';
import 'package:appflowy/mobile/presentation/setting/workspace/mobile_sharing_page.dart';
import 'package:appflowy/mobile/presentation/widgets/widgets.dart';
import 'package:appflowy/mobile/presentation/setting/widgets/mobile_setting_item_widget.dart';
import 'package:appflowy/mobile/presentation/home/widgets/mobile_upgrade_plan_page.dart';
import 'package:appflowy/shared/appflowy_cache_manager.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/device_info_task.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/user/application/auth/logout_relauncher.dart';
import 'package:appflowy/user/application/sign_in_bloc.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/sign_in_screen.dart';
import 'package:appflowy/util/int64_extension.dart';
import 'package:appflowy/util/share_log_files.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/util/font_family_extension.dart';
import 'package:appflowy/util/theme_mode_extension.dart';
import 'package:appflowy/workspace/application/settings/plan/workspace_subscription_ext.dart';
import 'package:appflowy/workspace/application/workspace/workspace_service.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:get_it/get_it.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/workspace/application/settings/plan/settings_plan_bloc.dart';
import 'package:appflowy/workspace/application/subscription/storage_usage_formatter.dart';
import 'package:appflowy/workspace/application/subscription/subscription_service.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/workspace.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/language.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../ai/service/ai_usage_summary.dart';

enum MobileSettingsSection {
  menu,
  account,
  workspace,
  workspaceManagement,
  member,
  sharing,
  notifications,
  storage,
  sites,
  plan,
  billing,
  about,
  accountManagement,
}

class MobileHomeSettingPage extends StatefulWidget {
  const MobileHomeSettingPage({
    super.key,
    this.workspaceState,
  });

  static const routeName = '/settings';
  static const argWorkspaceState = 'workspaceState';

  final UserWorkspaceState? workspaceState;

  @override
  State<MobileHomeSettingPage> createState() => _MobileHomeSettingPageState();
}

class _MobileHomeSettingPageState extends State<MobileHomeSettingPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  MobileSettingsSection _currentSection = MobileSettingsSection.menu;
  UserProfilePB? _userProfile;
  WorkspaceSubscriptionInfoPB? _subscriptionInfo;
  WorkspaceUsagePB? _workspaceUsage;
  CurrentSubscription? _currentSubscription;
  bool _subscriptionLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final authResult = await getIt<AuthService>().getUser();
    authResult.fold(
      (user) async {
        if (mounted) {
          setState(() => _userProfile = user);
          await _loadSubscriptionInfo();
        }
      },
      (error) => Log.error('Failed to get user: ${error.msg}'),
    );
  }

  Future<void> _refreshUserProfile() async {
    final authResult = await getIt<AuthService>().getUser();
    authResult.fold(
      (user) {
        if (mounted) {
          setState(() => _userProfile = user);
        }
      },
      (error) => Log.error('Failed to refresh user: ${error.msg}'),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_userProfile != null) {
      _loadSubscriptionInfo();
    }
  }

  Future<void> _loadSubscriptionInfo() async {
    if (_userProfile == null || _subscriptionLoaded) return;
    _subscriptionLoaded = true;

    UserWorkspaceState? state;
    if (widget.workspaceState != null) {
      state = widget.workspaceState;
    } else {
      try {
        state = context.read<UserWorkspaceBloc>().state;
      } catch (_) {
        return;
      }
    }
    final workspaceId = state!.currentWorkspace?.workspaceId ?? '';
    if (workspaceId.isEmpty) return;

    final service = WorkspaceService(
      workspaceId: workspaceId,
      userId: _userProfile!.id,
    );

    try {
      // 分别等待每个 Future，避免 Future.wait 可能的问题
      final subscriptionResult =
          await UserBackendService.getWorkspaceSubscriptionInfo(workspaceId);
      if (!mounted) return;

      final usageResult = await service.getWorkspaceUsage();
      if (!mounted) return;

      final subscriptionService = SubscriptionService();
      final cachedCurrentSubscription =
          subscriptionService.cachedCurrentSubscription;
      final refreshedCurrentSubscription =
          await subscriptionService.getCurrentSubscription(
        userProfile: _userProfile!,
        caller: 'MobileHomeSettingPage._loadSubscriptionInfo',
        forceRefresh: true,
      );
      final currentSubscription =
          refreshedCurrentSubscription ?? cachedCurrentSubscription;

      subscriptionResult.fold(
        (info) {
          if (mounted) {
            setState(
              () => _subscriptionInfo = info as WorkspaceSubscriptionInfoPB,
            );
          }
        },
        (error) => Log.error('Failed to load subscription info: ${error.msg}'),
      );

      usageResult.fold(
        (usage) {
          if (mounted) {
            setState(() => _workspaceUsage = usage as WorkspaceUsagePB?);
          }
        },
        (error) => Log.error('Failed to load workspace usage: ${error.msg}'),
      );

      if (mounted && currentSubscription != null) {
        setState(() => _currentSubscription = currentSubscription);
      }
    } catch (e, s) {
      Log.error('Error loading subscription info: $e', e, s);
    }
  }

  String _getTitle() {
    switch (_currentSection) {
      case MobileSettingsSection.menu:
        return LocaleKeys.settings_title.tr();
      case MobileSettingsSection.account:
        return '我的账户';
      case MobileSettingsSection.workspace:
        return '通用设置';
      case MobileSettingsSection.workspaceManagement:
        return '空间管理';
      case MobileSettingsSection.member:
        return '人员管理';
      case MobileSettingsSection.sharing:
        return '笔记共享';
      case MobileSettingsSection.notifications:
        return '通知设置';
      case MobileSettingsSection.storage:
        return '存储设置';
      case MobileSettingsSection.sites:
        return LocaleKeys.settings_sites_title.tr();
      case MobileSettingsSection.plan:
        return LocaleKeys.settings_planPage_menuLabel.tr();
      case MobileSettingsSection.billing:
        return LocaleKeys.settings_billingPage_menuLabel.tr();
      case MobileSettingsSection.about:
        return LocaleKeys.legal_aboutXiaoma.tr();
      case MobileSettingsSection.accountManagement:
        return LocaleKeys.settings_billingPage_membershipUpgrades.tr();
    }
  }

  Widget _buildAppBar(BuildContext context) {
    final afTheme = AppFlowyTheme.of(context);
    final isMenu = _currentSection == MobileSettingsSection.menu;

    return IconButton(
      tooltip: LocaleKeys.button_back.tr(),
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      onPressed: () {
        if (isMenu) {
          Navigator.pop(context);
        } else {
          setState(() => _currentSection = MobileSettingsSection.menu);
        }
      },
      icon: FlowySvg(
        FlowySvgs.mobile_return_s,
        size: const Size(7, 12),
        color: afTheme.iconColorScheme.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    final isSpaceManagement =
        _currentSection == MobileSettingsSection.workspaceManagement;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: isLightMode
          ? isSpaceManagement
              ? Colors.white
              : const Color(0xFFF9F9F9)
          : null,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 8),
              child: _buildAppBar(context),
            ),
            Expanded(
              child: _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_userProfile == null) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (_currentSection == MobileSettingsSection.menu) {
      return _MobileSettingsMenuContent(
        userProfile: _userProfile!,
        subscriptionInfo: _subscriptionInfo,
        currentSubscription: _currentSubscription,
        currentWorkspace: widget.workspaceState?.currentWorkspace,
        workspaceUsage: _workspaceUsage,
        onNavigate: (section) {
          setState(() => _currentSection = section);
        },
      );
    }

    return _buildSettingsSection();
  }

  Widget _buildSettingsSection() {
    // 关于小马页面需要特殊处理，跳转到独立页面
    if (_currentSection == MobileSettingsSection.about) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (ctx) => const MobileAboutXiaomaPage(),
          ),
        );
        // 重置回菜单
        setState(() => _currentSection = MobileSettingsSection.menu);
      });
      return const SizedBox.shrink();
    }

    final isServerWorkspace =
        _userProfile!.workspaceType == WorkspaceTypePB.ServerW;
    final isBillingEnabled = isServerWorkspace &&
        FeatureFlag.planBilling.isOn &&
        _subscriptionInfo != null;
    final isQuickEntryUser = _userProfile!.userAuthType != AuthTypePB.Server;
    final workspaceId =
        widget.workspaceState?.currentWorkspace?.workspaceId ?? '';

    // _GeneralSettingsContent handles its own scroll + padding
    if (_currentSection == MobileSettingsSection.workspace) {
      return _GeneralSettingsContent(
        userProfile: _userProfile!,
        workspaceId: widget.workspaceState?.currentWorkspace?.workspaceId ?? '',
      );
    }

    // Space management page handles its own layout in embed mode
    if (_currentSection == MobileSettingsSection.workspaceManagement) {
      return const MobileSpaceManagementPage(showAppBar: false);
    }

    if (_currentSection == MobileSettingsSection.account) {
      final isServerUser = _userProfile!.userAuthType == AuthTypePB.Server;
      return Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: PersonalInfoSettingGroup(
                  userProfile: _userProfile!,
                  showDeleteAccountButton: false,
                  onUserProfileUpdated: _refreshUserProfile,
                ),
              ),
            ),
          ),
          if (isServerUser)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: AFOutlinedTextButton.destructive(
                  alignment: Alignment.center,
                  text: LocaleKeys.button_closeAccount.tr(),
                  onTap: () {
                    showMobileDeleteAccountDialog(context);
                  },
                  size: AFButtonSize.l,
                ),
              ),
            ),
        ],
      );
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            switch (_currentSection) {
              MobileSettingsSection.account => PersonalInfoSettingGroup(
                  userProfile: _userProfile!,
                  onUserProfileUpdated: () {
                    // Refresh user profile to update cached iconUrl
                    _refreshUserProfile();
                  },
                ),
              MobileSettingsSection.workspace =>
                const SizedBox.shrink(), // handled above
              MobileSettingsSection.workspaceManagement =>
                const MobileSpaceManagementPage(showAppBar: false),
              MobileSettingsSection.member => WorkspaceSettingGroup(
                  memberCount: widget
                      .workspaceState?.currentWorkspace?.memberCount
                      .toInt(),
                ),
              MobileSettingsSection.sharing => const SizedBox.shrink(),
              MobileSettingsSection.notifications =>
                NotificationsSettingGroup(),
              MobileSettingsSection.storage => const StorageSettingGroup(),
              MobileSettingsSection.sites => _ComingSoonGroup(
                  title: LocaleKeys.settings_sites_title.tr(),
                  description: '站点功能开发中',
                ),
              MobileSettingsSection.plan => _ComingSoonGroup(
                  title: LocaleKeys.settings_planPage_menuLabel.tr(),
                  description: '订阅计划功能开发中',
                ),
              MobileSettingsSection.billing => _ComingSoonGroup(
                  title: LocaleKeys.settings_billingPage_menuLabel.tr(),
                  description: '账单功能开发中',
                ),
              MobileSettingsSection.about =>
                const SizedBox.shrink(), // handled above with navigation
              MobileSettingsSection.accountManagement =>
                UserSessionSettingGroup(
                  userProfile: _userProfile!,
                  showThirdPartyLogin: false,
                ),
              MobileSettingsSection.menu => const SizedBox.shrink(),
            },
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 菜单首页内容
// ============================================================================

class _MobileSettingsMenuContent extends StatelessWidget {
  const _MobileSettingsMenuContent({
    required this.userProfile,
    required this.subscriptionInfo,
    required this.currentSubscription,
    required this.currentWorkspace,
    required this.onNavigate,
    this.workspaceUsage,
  });

  final UserProfilePB userProfile;
  final WorkspaceSubscriptionInfoPB? subscriptionInfo;
  final CurrentSubscription? currentSubscription;
  final UserWorkspacePB? currentWorkspace;
  final void Function(MobileSettingsSection) onNavigate;
  final WorkspaceUsagePB? workspaceUsage;

  /// 对应电脑端 `_isBillingEnabled` 的拦截逻辑：匿名登录（[WorkspaceTypePB.LocalW]
  /// 或 [AuthTypePB.Local]）不展示订阅/套餐卡片。云端登录的工作空间才会显示。
  static bool _isBillingVisible(UserProfilePB userProfile) {
    if (userProfile.workspaceType == WorkspaceTypePB.LocalW) {
      return false;
    }
    if (userProfile.userAuthType != AuthTypePB.Server) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            _UserProfileHeader(
              userProfile: userProfile,
              onTap: () => onNavigate(MobileSettingsSection.account),
            ),
            const SizedBox(height: 16),
            if (subscriptionInfo != null && _isBillingVisible(userProfile)) ...[
              _MobileUpgradePlanCard(
                subscriptionInfo: subscriptionInfo!,
                workspaceUsage: workspaceUsage,
                onUpgrade: () => _showUpgradeDialog(context),
                currentSubscription: currentSubscription,
              ),
              const SizedBox(height: 16),
            ],
            _SettingsGroupCard(
              items: [
                _SettingsItem(
                  label: '我的账户',
                  onTap: () => onNavigate(MobileSettingsSection.account),
                ),
                _SettingsItem(
                  label: '通用设置',
                  onTap: () => onNavigate(MobileSettingsSection.workspace),
                ),
                _SettingsItem(
                  label: '空间管理',
                  onTap: () =>
                      onNavigate(MobileSettingsSection.workspaceManagement),
                ),
                _SettingsItem(
                  label: '人员管理',
                  onTap: () {
                    // 直接跳转到人员管理页面
                    context.push('/invite_member');
                  },
                ),
                _SettingsItem(
                  label: '笔记共享',
                  onTap: () {
                    UserWorkspaceState? workspaceState;
                    try {
                      workspaceState = context.read<UserWorkspaceBloc>().state;
                    } catch (_) {}
                    context.push(MobileSharingPage.routeName,
                        extra: workspaceState);
                  },
                ),
                _SettingsItem(
                  label: '通知设置',
                  onTap: () => onNavigate(MobileSettingsSection.notifications),
                ),
                _SettingsItem(
                  label: '存储设置',
                  onTap: () => onNavigate(MobileSettingsSection.storage),
                ),
                _SettingsItem(
                  label: LocaleKeys.legal_aboutXiaoma.tr(),
                  onTap: () => onNavigate(MobileSettingsSection.about),
                  showBottomDivider: false,
                ),
              ],
              workspaceUsage: workspaceUsage,
            ),
            const VSpace(16),
            _SettingsGroupCard(
              items: [
                if (userProfile.userAuthType == AuthTypePB.Server) ...[
                  _SettingsItem(
                    label: '切换账号',
                    onTap: () => _showSwitchAccountDialog(context),
                    showArrow: false,
                  ),
                  _SettingsItem(
                    label: '退出登录',
                    onTap: () => _showLogoutDialog(context),
                    textColor: const Color(0xFFFF0000),
                    showBottomDivider: false,
                    showArrow: false,
                  ),
                ] else ...[
                  _SettingsItem(
                    label: '登录',
                    onTap: () => _showLoginDialog(context),
                    textColor: const Color(0xFF00AA00),
                    showBottomDivider: false,
                    showArrow: false,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _showUpgradeDialog(BuildContext context) {
    final workspaceId = currentWorkspace?.workspaceId ?? '';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => MobileUpgradePlanPage(
          subscriptionInfo: subscriptionInfo,
          workspaceId: workspaceId,
          userProfile: userProfile,
          currentSubscription: currentSubscription,
        ),
      ),
    );
  }

  void _showSwitchAccountDialog(BuildContext context) {
    showCancelAndConfirmDialog(
      context: context,
      title: '切换账号',
      description: '确定要切换账号吗？',
      confirmLabel: '确定',
      onConfirm: (_) async {
        // 不在这里 pop 对话框，ConfirmPopup 的 closeOnAction 默认为 true
        // 会自动关闭对话框。若此处再 pop 一次会导致设置页被一起 pop 掉。
        await appLogoutRelauncher().logoutAndRelaunch();
      },
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showCancelAndConfirmDialog(
      context: context,
      title: LocaleKeys.settings_accountPage_login_logoutLabel.tr(),
      description: LocaleKeys.settings_menu_logoutPrompt.tr(),
      confirmLabel: LocaleKeys.button_yes.tr(),
      onConfirm: (_) async {
        // 不在这里 pop 对话框，ConfirmPopup 的 closeOnAction 默认为 true
        // 会自动关闭对话框。若此处再 pop 一次会导致设置页被一起 pop 掉，
        // 用户会看到首页而不是登录页。
        await appLogoutRelauncher().logoutAndRelaunch();
      },
    );
  }

  void _showLoginDialog(BuildContext context) {
    showCancelAndConfirmDialog(
      context: context,
      title: '提示',
      description: '确定要跳转到登录页面吗？',
      confirmLabel: '确定',
      onConfirm: (_) {
        // 关闭设置页面
        Navigator.popUntil(context, (route) => route.isFirst);
        // 跳转到登录页面
        context.push(SignInScreen.routeName);
      },
    );
  }
}

class _SettingsItem {
  final String label;
  final VoidCallback onTap;
  final bool showBottomDivider;
  final Color? textColor;
  final bool showArrow;

  const _SettingsItem({
    required this.label,
    required this.onTap,
    this.showBottomDivider = true,
    this.textColor,
    this.showArrow = true,
  });
}

class _SettingsGroupCard extends StatelessWidget {
  const _SettingsGroupCard({
    required this.items,
    this.workspaceUsage,
  });

  final List<_SettingsItem> items;
  final WorkspaceUsagePB? workspaceUsage;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final isLightMode = Theme.of(context).brightness == Brightness.light;

    return Container(
      decoration: BoxDecoration(
        color: theme.surfaceColorScheme.layer01,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.borderColorScheme.primary,
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < items.length; i++) ...[
            _SettingsItemRow(
              label: items[i].label,
              onTap: items[i].onTap,
              textColor: items[i].textColor,
              showArrow: items[i].showArrow,
            ),
            if (i < items.length - 1 && items[i].showBottomDivider)
              Divider(
                color: theme.borderColorScheme.primary.withValues(alpha: 0.5),
                height: 0.5,
                indent: 16,
                endIndent: 16,
              ),
          ],
        ],
      ),
    );
  }
}

class _SettingsItemRow extends StatelessWidget {
  const _SettingsItemRow({
    required this.label,
    required this.onTap,
    this.textColor,
    this.showArrow = true,
  });

  final String label;
  final VoidCallback onTap;
  final Color? textColor;
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    final splashColor = isLightMode
        ? Colors.black.withValues(alpha: 0.04)
        : Colors.white.withValues(alpha: 0.08);
    final highlightColor = isLightMode
        ? Colors.black.withValues(alpha: 0.02)
        : Colors.white.withValues(alpha: 0.04);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: splashColor,
        highlightColor: highlightColor,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textStyle.heading4.standard(
                    color: textColor ?? theme.textColorScheme.primary,
                  ),
                  textAlign: showArrow ? TextAlign.start : TextAlign.center,
                ),
              ),
              if (showArrow)
                FlowySvg(
                  FlowySvgs.toolbar_arrow_right_m,
                  size: const Size.square(24),
                  color: theme.iconColorScheme.tertiary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserProfileHeader extends StatelessWidget {
  const _UserProfileHeader({
    required this.userProfile,
    required this.onTap,
  });

  final UserProfilePB userProfile;
  final VoidCallback onTap;

  String get _displayName {
    if (userProfile.name.isNotEmpty) return userProfile.name;
    if (userProfile.hasPhone() && userProfile.phone.isNotEmpty) {
      return userProfile.phone;
    }
    if (userProfile.email.isNotEmpty) return userProfile.email;
    return '小马AI笔记的用户';
  }

  Widget _buildAvatar(double size) {
    final iconUrl = userProfile.iconUrl;

    if (iconUrl.isEmpty) return _buildDefaultAvatar(size);

    if (iconUrl.startsWith('http://') || iconUrl.startsWith('https://')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: FlowyNetworkImage(
          url: iconUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          userProfilePB: userProfile,
          errorWidgetBuilder: (_, __, ___) => _buildDefaultAvatar(size),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: Image.file(
        io.File(iconUrl),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildDefaultAvatar(size),
      ),
    );
  }

  Widget _buildDefaultAvatar(double size) {
    return AFAvatar(
      name: _displayName,
      size: AFAvatarSize.s,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    const double avatarSize = 48;
    const double horizontalPadding = 16.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(
          horizontalPadding,
          16,
          horizontalPadding,
          16,
        ),
        child: Row(
          children: [
            _buildAvatar(avatarSize),
            const HSpace(16),
            Text(
              _displayName,
              style: theme.textStyle.heading4.standard(
                color: theme.textColorScheme.primary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileUpgradePlanCard extends StatelessWidget {
  const _MobileUpgradePlanCard({
    required this.subscriptionInfo,
    this.workspaceUsage,
    required this.onUpgrade,
    this.currentSubscription,
  });

  final WorkspaceSubscriptionInfoPB subscriptionInfo;
  final WorkspaceUsagePB? workspaceUsage;
  final VoidCallback onUpgrade;
  final CurrentSubscription? currentSubscription;

  String _formatDateRange(int endDate, RecurringIntervalPB? interval) {
    final end = DateTime.fromMillisecondsSinceEpoch(endDate * 1000);
    DateTime start;

    if (interval == RecurringIntervalPB.Year) {
      start = DateTime(end.year - 1, end.month, end.day);
    } else {
      if (end.month == 1) {
        start = DateTime(end.year - 1, 12, end.day);
      } else {
        start = DateTime(end.year, end.month - 1, end.day);
      }
    }

    final startStr =
        '${start.year}.${start.month.toString().padLeft(2, '0')}.${start.day.toString().padLeft(2, '0')}';
    final endStr =
        '${end.year}.${end.month.toString().padLeft(2, '0')}.${end.day.toString().padLeft(2, '0')}';
    return '$startStr至$endStr';
  }

  String _getPlanDisplayName() {
    final summary = currentSubscription?.subscription;
    final planNameFromSummary = summary?.planNameCn?.isNotEmpty == true
        ? summary!.planNameCn!
        : (summary?.planCode?.isNotEmpty == true ? summary!.planCode! : null);

    if (planNameFromSummary != null) {
      return planNameFromSummary;
    }

    return subscriptionInfo.label;
  }

  String? _getValidityText() {
    final summary = currentSubscription?.subscription;
    if (summary?.endDate != null) {
      final endDate = summary!.endDate!;
      if (summary.startDate != null) {
        final startDate = summary.startDate!;
        return '有效期：${startDate.year}.${startDate.month.toString().padLeft(2, '0')}.${startDate.day.toString().padLeft(2, '0')}至${endDate.year}.${endDate.month.toString().padLeft(2, '0')}.${endDate.day.toString().padLeft(2, '0')}';
      }
      return '有效期：${endDate.year}.${endDate.month.toString().padLeft(2, '0')}.${endDate.day.toString().padLeft(2, '0')}';
    }

    if (subscriptionInfo.planSubscription.endDate.toInt() > 0 &&
        subscriptionInfo.plan.value != 0) {
      return _formatDateRange(subscriptionInfo.planSubscription.endDate.toInt(),
          subscriptionInfo.planSubscription.interval);
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    final planName = _getPlanDisplayName();
    final validityText = _getValidityText();

    return DecoratedBox(
        decoration: BoxDecoration(
          color: isLightMode ? Colors.white : const Color(0xFF28262E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: theme.borderColorScheme.primary.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/navigation/m_setting_profile.png'),
                  fit: BoxFit.fill,
                ),
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
              padding: const EdgeInsets.only(
                  top: 18, bottom: 13, left: 22, right: 16),
              child: AspectRatio(
                aspectRatio: 353 / 134,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      planName,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (validityText != null)
                      Text(
                        validityText,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 12,
                        ),
                      ),
                    const SizedBox(height: 2),
                    if (subscriptionInfo.plan.value == 0 &&
                        validityText == null)
                      Text(
                        subscriptionInfo.info,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 12,
                        ),
                        maxLines: 2,
                      ),
                    Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Text(
                              _buildStorageText(workspaceUsage),
                              style: TextStyle(
                                  color: const Color(0xFF4B1B03),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: null,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.transparent,
                                  border: Border.all(
                                    color: const Color(0xFFB57E5E),
                                    width: 1,
                                  ),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  '剩余空间',
                                  style: theme.textStyle.heading4
                                      .standard(
                                        color: const Color(0xFF4B1B03),
                                      )
                                      .copyWith(fontSize: 10),
                                ),
                              ),
                            ),
                          ],
                        ),
                        GestureDetector(
                          onTap: onUpgrade,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFADECA),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '会员升级',
                              style: theme.textStyle.heading4
                                  .standard(
                                    color: const Color(0xFF4B1B03),
                                  )
                                  .copyWith(
                                      fontSize: 12.0,
                                      fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (workspaceUsage != null) ...[
              Divider(
                color: theme.borderColorScheme.primary.withValues(alpha: 0.5),
                height: 0.5,
                indent: 16,
                endIndent: 16,
              ),
              _buildAIUsageRow(theme),
            ],
          ],
        ));
  }

  String _buildStorageText(WorkspaceUsagePB? usage) {
    final subscriptionUsage = currentSubscription?.usage;
    final usedGb = subscriptionUsage?.storageUsedGb;
    final totalGb = subscriptionUsage?.storageTotalGb;
    if (usedGb != null && totalGb != null) {
      return formatRemainingStorageUsage(
        usedGb: usedGb,
        totalGb: totalGb,
        gbUnit: 'GB',
        mbUnit: 'MB',
        separator: ' / ',
      );
    }

    if (usage == null) {
      return '加载中...';
    }
    if (usage.storageBytesUnlimited) {
      return '不限';
    }
    if (usage.storageBytesLimit.toInt() == 0) {
      return '0GB / 0GB';
    }

    return formatRemainingStorageUsage(
      usedGb: usage.storageBytes.toInt() / (1024 * 1024 * 1024),
      totalGb: usage.storageBytesLimit.toInt() / (1024 * 1024 * 1024),
      gbUnit: 'GB',
      mbUnit: 'MB',
      separator: ' / ',
    );
  }

  Widget _buildAIUsageRow(AppFlowyThemeData theme) {
    final aiUsage = AiUsageSummary.fromUsage(workspaceUsage!);

    String usageText;
    Color usageColor;

    if (aiUsage.isUnlimited) {
      usageText = '不限';
      usageColor = const Color(0xFFE85D04);
    } else if (aiUsage.isUnsubscribed) {
      usageText = '未订阅';
      usageColor = theme.textColorScheme.secondary;
    } else if (!aiUsage.hasUsage) {
      usageText = '--';
      usageColor = theme.textColorScheme.secondary;
    } else {
      usageText = '${aiUsage.remaining}次';
      usageColor = const Color(0xFFC46B3F);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 16, right: 16, bottom: 16),
      child: Row(
        children: [
          Text(
            '剩余',
            style: theme.textStyle.heading4.standard(
              color: theme.textColorScheme.primary,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            usageText,
            style: theme.textStyle.heading4
                .standard(
                  color: usageColor,
                )
                .copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
          ),
          const SizedBox(width: 4),
          Text(
            'AI对话次数',
            style: theme.textStyle.heading4.standard(
              color: theme.textColorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// General Settings Content (通用设置)
// ============================================================================

class _GeneralSettingsContent extends StatelessWidget {
  const _GeneralSettingsContent({
    required this.userProfile,
    required this.workspaceId,
  });

  final UserProfilePB userProfile;
  final String workspaceId;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          children: [
            _GeneralSettingsCard(),
            const SizedBox(height: 12),
            _LanguageSettingsCard(),
            const SizedBox(height: 12),
            _AISettingsCard(
              userProfile: userProfile,
              workspaceId: workspaceId,
            ),
            const SizedBox(height: 12),
            const _SupportCard(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _GeneralSettingsCard extends StatelessWidget {
  const _GeneralSettingsCard();

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    return Container(
      decoration: BoxDecoration(
        color: theme.surfaceColorScheme.layer01,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.borderColorScheme.primary
              .withValues(alpha: isLightMode ? 0.3 : 0.08),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              '外观',
              style: theme.textStyle.heading4.standard(
                color: theme.textColorScheme.primary,
              ),
            ),
          ),
          _ThemeModeSettingItem(),
          _FontFamilySettingItem(),
          _FontSizeSettingItem(),
          _TextDirectionSettingItem(),
        ],
      ),
    );
  }
}

class _LanguageSettingsCard extends StatelessWidget {
  const _LanguageSettingsCard();

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    return Container(
      decoration: BoxDecoration(
        color: theme.surfaceColorScheme.layer01,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.borderColorScheme.primary
              .withValues(alpha: isLightMode ? 0.3 : 0.08),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              LocaleKeys.settings_menu_language.tr(),
              style: theme.textStyle.heading4.standard(
                color: theme.textColorScheme.primary,
              ),
            ),
          ),
          _LanguageSettingItem(),
        ],
      ),
    );
  }
}

class _AISettingsCard extends StatelessWidget {
  const _AISettingsCard({
    required this.userProfile,
    required this.workspaceId,
  });

  final UserProfilePB userProfile;
  final String workspaceId;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    return BlocProvider(
      create: (context) => SettingsAIBloc(
        userProfile,
        workspaceId,
      )..add(const SettingsAIEvent.started()),
      child: Container(
        decoration: BoxDecoration(
          color: theme.surfaceColorScheme.layer01,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.borderColorScheme.primary
                .withValues(alpha: isLightMode ? 0.3 : 0.08),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                LocaleKeys.settings_aiPage_title.tr(),
                style: theme.textStyle.heading4.standard(
                  color: theme.textColorScheme.primary,
                ),
              ),
            ),
            const _AISettingItem(),
          ],
        ),
      ),
    );
  }
}

class _AISettingItem extends StatelessWidget {
  const _AISettingItem();

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return BlocBuilder<SettingsAIBloc, SettingsAIState>(
      builder: (ctx, state) {
        final models = state.availableModels?.models ?? [];
        final selectedModelName = state.availableModels?.selectedModel.name;
        final isLoading = state.availableModels == null;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: models.isEmpty ? null : () => _showModelPicker(ctx, state),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      LocaleKeys.settings_aiPage_keys_llmModelType.tr(),
                      style: theme.textStyle.heading4.standard(
                        color: theme.textColorScheme.primary,
                      ),
                    ),
                  ),
                  Text(
                    isLoading
                        ? '加载中...'
                        : (selectedModelName?.isNotEmpty == true
                            ? selectedModelName!
                            : '暂无可用模型'),
                    style: theme.textStyle.body.standard(
                      color: theme.textColorScheme.secondary,
                    ),
                  ),
                  if (models.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    FlowySvg(
                      FlowySvgs.toolbar_arrow_right_m,
                      size: const Size.square(24),
                      color: theme.iconColorScheme.tertiary,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showModelPicker(BuildContext ctx, SettingsAIState state) {
    final availableModels = state.availableModels;
    if (availableModels == null || availableModels.models.isEmpty) {
      // 如果没有可用模型，显示提示
      showMobileBottomSheet(
        ctx,
        showHeader: true,
        showDragHandle: true,
        showDivider: false,
        title: LocaleKeys.settings_aiPage_keys_llmModelType.tr(),
        builder: (_) {
          return Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 48,
                  color: Colors.grey,
                ),
                const SizedBox(height: 16),
                Text(
                  '暂无可用模型',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '请联系管理员配置AI模型',
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey,
                      ),
                ),
              ],
            ),
          );
        },
      );
      return;
    }

    showMobileBottomSheet(
      ctx,
      showHeader: true,
      showDragHandle: true,
      showDivider: false,
      title: LocaleKeys.settings_aiPage_keys_llmModelType.tr(),
      builder: (_) {
        return Column(
          children: availableModels.models
              .asMap()
              .entries
              .map(
                (entry) => FlowyOptionTile.checkbox(
                  text: entry.value.name,
                  showTopBorder: entry.key == 0,
                  isSelected:
                      availableModels.selectedModel.name == entry.value.name,
                  onTap: () {
                    ctx
                        .read<SettingsAIBloc>()
                        .add(SettingsAIEvent.selectModel(entry.value));
                    ctx.pop();
                  },
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _LanguageSettingItem extends StatelessWidget {
  const _LanguageSettingItem();

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return BlocBuilder<AppearanceSettingsCubit, AppearanceSettingsState>(
      builder: (ctx, state) {
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _showLanguagePicker(ctx, state.locale),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      LocaleKeys.settings_menu_language.tr(),
                      style: theme.textStyle.heading4.standard(
                        color: theme.textColorScheme.primary,
                      ),
                    ),
                  ),
                  Text(
                    languageFromLocale(state.locale),
                    style: theme.textStyle.body.standard(
                      color: theme.textColorScheme.secondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FlowySvg(
                    FlowySvgs.toolbar_arrow_right_m,
                    size: const Size.square(24),
                    color: theme.iconColorScheme.tertiary,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showLanguagePicker(BuildContext ctx, Locale currentLocale) async {
    final newLocale = await ctx.push<Locale>('/language_picker');
    if (newLocale != null && newLocale != currentLocale && ctx.mounted) {
      ctx.read<AppearanceSettingsCubit>().setLocale(ctx, newLocale);
    }
  }
}

class _SupportCard extends StatelessWidget {
  const _SupportCard();

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    return Container(
      decoration: BoxDecoration(
        color: theme.surfaceColorScheme.layer01,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.borderColorScheme.primary
              .withValues(alpha: isLightMode ? 0.3 : 0.08),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              '支持',
              style: theme.textStyle.heading4.standard(
                color: theme.textColorScheme.primary,
              ),
            ),
          ),
          _SettingsActionItem(
            label: '清除缓存',
            onTap: () async {
              await getIt<FlowyCacheManager>().clearAllCache();
              if (context.mounted) {
                showToastNotification(
                  message: LocaleKeys
                      .settings_manageDataPage_cache_dialog_successHint
                      .tr(),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

class _ThemeModeSettingItem extends StatelessWidget {
  const _ThemeModeSettingItem();

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final themeMode = context.watch<AppearanceSettingsCubit>().state.themeMode;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showThemePicker(context),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '主题模式',
                  style: theme.textStyle.heading4.standard(
                    color: theme.textColorScheme.primary,
                  ),
                ),
              ),
              Text(
                themeMode.labelText,
                style: theme.textStyle.heading4.standard(
                  color: theme.textColorScheme.secondary,
                ),
              ),
              const SizedBox(width: 8),
              FlowySvg(
                FlowySvgs.toolbar_arrow_right_m,
                size: const Size.square(24),
                color: theme.iconColorScheme.tertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showThemePicker(BuildContext context) {
    showMobileBottomSheet(
      context,
      showDragHandle: true,
      showHeader: true,
      title: '主题模式',
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) {
        final themeMode = ctx.read<AppearanceSettingsCubit>().state.themeMode;
        return Column(
          children: [
            FlowyOptionTile.checkbox(
              text: LocaleKeys.settings_appearance_themeMode_light.tr(),
              leftIcon: const FlowySvg(FlowySvgs.m_theme_mode_light_s),
              isSelected: themeMode == ThemeMode.light,
              onTap: () {
                ctx
                    .read<AppearanceSettingsCubit>()
                    .setThemeMode(ThemeMode.light);
                Navigator.pop(ctx);
              },
            ),
            FlowyOptionTile.checkbox(
              showTopBorder: false,
              text: LocaleKeys.settings_appearance_themeMode_dark.tr(),
              leftIcon: const FlowySvg(FlowySvgs.m_theme_mode_dark_s),
              isSelected: themeMode == ThemeMode.dark,
              onTap: () {
                ctx
                    .read<AppearanceSettingsCubit>()
                    .setThemeMode(ThemeMode.dark);
                Navigator.pop(ctx);
              },
            ),
            FlowyOptionTile.checkbox(
              showTopBorder: false,
              text: LocaleKeys.settings_appearance_themeMode_system.tr(),
              leftIcon: const FlowySvg(FlowySvgs.m_theme_mode_system_s),
              isSelected: themeMode == ThemeMode.system,
              onTap: () {
                ctx
                    .read<AppearanceSettingsCubit>()
                    .setThemeMode(ThemeMode.system);
                Navigator.pop(ctx);
              },
            ),
          ],
        );
      },
    );
  }
}

class _FontFamilySettingItem extends StatelessWidget {
  const _FontFamilySettingItem();

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final selectedFont = context.watch<AppearanceSettingsCubit>().state.font;
    final name = selectedFont.fontFamilyDisplayName;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push(FontPickerScreen.routeName),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '字体系列',
                  style: theme.textStyle.heading4.standard(
                    color: theme.textColorScheme.primary,
                  ),
                ),
              ),
              Text(
                name,
                style: theme.textStyle.heading4.standard(
                  color: theme.textColorScheme.secondary,
                ),
              ),
              const SizedBox(width: 8),
              FlowySvg(
                FlowySvgs.toolbar_arrow_right_m,
                size: const Size.square(24),
                color: theme.iconColorScheme.tertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FontSizeSettingItem extends StatefulWidget {
  const _FontSizeSettingItem();

  @override
  State<_FontSizeSettingItem> createState() => _FontSizeSettingItemState();
}

class _FontSizeSettingItemState extends State<_FontSizeSettingItem> {
  static const _minValue = 0.8;
  static const _maxValue = 1.2;
  static const _divisions = 4;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final textScaleFactor =
        context.watch<AppearanceSettingsCubit>().state.textScaleFactor;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showFontSizePicker(context, textScaleFactor),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '字号',
                  style: theme.textStyle.heading4.standard(
                    color: theme.textColorScheme.primary,
                  ),
                ),
              ),
              Text(
                textScaleFactor.toStringAsFixed(1),
                style: theme.textStyle.heading4.standard(
                  color: theme.textColorScheme.secondary,
                ),
              ),
              const SizedBox(width: 8),
              FlowySvg(
                FlowySvgs.toolbar_arrow_right_m,
                size: const Size.square(24),
                color: theme.iconColorScheme.tertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFontSizePicker(BuildContext context, double currentValue) {
    showMobileBottomSheet(
      context,
      showHeader: true,
      showDragHandle: true,
      showDivider: false,
      title: '字号',
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: FontSizeStepper(
            value: currentValue.clamp(_minValue, _maxValue),
            minimumValue: _minValue,
            maximumValue: _maxValue,
            divisions: _divisions,
            onChanged: (newValue) {
              ctx.read<AppearanceSettingsCubit>().setTextScaleFactor(newValue);
            },
          ),
        );
      },
    );
  }
}

class _TextDirectionSettingItem extends StatelessWidget {
  const _TextDirectionSettingItem();

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final textDirection =
        context.watch<AppearanceSettingsCubit>().state.textDirection;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showTextDirectionPicker(context),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '默认文本方向',
                  style: theme.textStyle.heading4.standard(
                    color: theme.textColorScheme.primary,
                  ),
                ),
              ),
              Text(
                _textDirectionLabelText(textDirection),
                style: theme.textStyle.heading4.standard(
                  color: theme.textColorScheme.secondary,
                ),
              ),
              const SizedBox(width: 8),
              FlowySvg(
                FlowySvgs.toolbar_arrow_right_m,
                size: const Size.square(24),
                color: theme.iconColorScheme.tertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _textDirectionLabelText(AppFlowyTextDirection textDirection) {
    switch (textDirection) {
      case AppFlowyTextDirection.auto:
        return '自动';
      case AppFlowyTextDirection.rtl:
        return '从右到左';
      case AppFlowyTextDirection.ltr:
        return '从左到右';
    }
  }

  void _showTextDirectionPicker(BuildContext context) {
    showMobileBottomSheet(
      context,
      showHeader: true,
      showDragHandle: true,
      showDivider: false,
      title: '默认文本方向',
      builder: (ctx) {
        final textDirection =
            ctx.read<AppearanceSettingsCubit>().state.textDirection;
        return Column(
          children: [
            FlowyOptionTile.checkbox(
              text: '从左到右',
              isSelected: textDirection == AppFlowyTextDirection.ltr,
              onTap: () => _applyAndPop(ctx, AppFlowyTextDirection.ltr),
            ),
            FlowyOptionTile.checkbox(
              showTopBorder: false,
              text: '从右到左',
              isSelected: textDirection == AppFlowyTextDirection.rtl,
              onTap: () => _applyAndPop(ctx, AppFlowyTextDirection.rtl),
            ),
            FlowyOptionTile.checkbox(
              showTopBorder: false,
              text: '自动',
              isSelected: textDirection == AppFlowyTextDirection.auto,
              onTap: () => _applyAndPop(ctx, AppFlowyTextDirection.auto),
            ),
          ],
        );
      },
    );
  }

  void _applyAndPop(BuildContext ctx, AppFlowyTextDirection direction) {
    ctx.read<AppearanceSettingsCubit>().setTextDirection(direction);
    ctx
        .read<DocumentAppearanceCubit>()
        .syncDefaultTextDirection(direction.name);
    Navigator.pop(ctx);
  }
}

class _SettingsLinkItem extends StatelessWidget {
  const _SettingsLinkItem({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textStyle.heading4.standard(
                    color: theme.textColorScheme.primary,
                  ),
                ),
              ),
              FlowySvg(
                FlowySvgs.toolbar_arrow_right_m,
                size: const Size.square(24),
                color: theme.iconColorScheme.tertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsActionItem extends StatelessWidget {
  const _SettingsActionItem({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            label,
            style: theme.textStyle.heading4.standard(
              color: theme.textColorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Coming Soon Placeholder
// ============================================================================

class _ComingSoonGroup extends StatelessWidget {
  const _ComingSoonGroup({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        VSpace(theme.spacing.s),
        Text(
          title,
          style: theme.textStyle.heading4.enhanced(
            color: theme.textColorScheme.primary,
          ),
        ),
        VSpace(theme.spacing.m),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.surfaceColorScheme.layer01,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.borderColorScheme.primary.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              FlowySvg(
                FlowySvgs.icon_plan_info_indicator_s,
                size: const Size.square(32),
                color: theme.iconColorScheme.tertiary,
              ),
              const SizedBox(height: 12),
              Text(
                description,
                style: theme.textStyle.body.standard(
                  color: theme.textColorScheme.secondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
