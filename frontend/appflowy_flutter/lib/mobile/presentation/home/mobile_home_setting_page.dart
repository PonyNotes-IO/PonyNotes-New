import 'dart:io' as io;

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/features/workspace/logic/workspace_state.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/show_mobile_bottom_sheet.dart';
import 'package:appflowy/mobile/presentation/setting/about/about_setting_group.dart';
import 'package:appflowy/mobile/presentation/setting/ai/ai_settings_group.dart';
import 'package:appflowy/mobile/presentation/setting/cloud/cloud_setting_group.dart';
import 'package:appflowy/mobile/presentation/setting/datetime/datetime_page.dart';
import 'package:appflowy/mobile/presentation/setting/font/font_picker_screen.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/widgets/font_size_stepper.dart';
import 'package:appflowy/mobile/presentation/setting/notifications_setting_group.dart';
import 'package:appflowy/mobile/presentation/setting/personal_info/personal_info_setting_group.dart';
import 'package:appflowy/mobile/presentation/setting/self_host_setting_group.dart';
import 'package:appflowy/mobile/presentation/setting/storage/storage_setting_group.dart';
import 'package:appflowy/mobile/presentation/setting/support_setting_group.dart';
import 'package:appflowy/mobile/presentation/setting/user_session_setting_group.dart';
import 'package:appflowy/mobile/presentation/setting/workspace/workspace_setting_group.dart';
import 'package:appflowy/mobile/presentation/widgets/widgets.dart';
import 'package:appflowy/shared/appflowy_cache_manager.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/device_info_task.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/user/application/sign_in_bloc.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/sign_in_screen.dart';
import 'package:appflowy/util/int64_extension.dart';
import 'package:appflowy/util/share_log_files.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/util/font_family_extension.dart';
import 'package:appflowy/util/theme_mode_extension.dart';
import 'package:appflowy/workspace/application/settings/plan/workspace_subscription_ext.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:get_it/get_it.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/workspace.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

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
        }
      },
      (error) => Log.error('Failed to get user: ${error.msg}'),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_userProfile?.workspaceType == WorkspaceTypePB.ServerW) {
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
        // Bloc not available in context — skip loading subscription info
        return;
      }
    }
    final workspaceId = state!.currentWorkspace?.workspaceId ?? '';
    if (workspaceId.isEmpty) return;

    final result =
        await UserBackendService.getWorkspaceSubscriptionInfo(workspaceId);
    result.fold(
      (info) {
        if (mounted) {
          setState(() => _subscriptionInfo = info);
        }
      },
      (error) => Log.error('Failed to load subscription info: ${error.msg}'),
    );
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
        return '共享发布';
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
    final theme = Theme.of(context);
    final isMenu = _currentSection == MobileSettingsSection.menu;

    return SafeArea(
      bottom: false,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          border: Border(
            bottom: BorderSide(
              color: theme.dividerColor.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: () {
                if (isMenu) {
                  Navigator.pop(context);
                } else {
                  setState(() => _currentSection = MobileSettingsSection.menu);
                }
              },
              icon: FlowySvg(
                isMenu ? FlowySvgs.mobile_return_s : FlowySvgs.mobile_return_s,
                size: const Size(7, 12),
                color: afTheme.iconColorScheme.primary,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                _getTitle(),
                style: afTheme.textStyle.heading4.standard(
                  color: afTheme.textColorScheme.primary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLightMode = Theme.of(context).brightness == Brightness.light;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: isLightMode ? const Color(0xFFF9F9F9) : null,
      drawer: _userProfile != null
          ? _MobileSettingsDrawer(
              userProfile: _userProfile!,
              currentSection: _currentSection,
              currentSubscription: _currentSubscription,
              subscriptionInfo: _subscriptionInfo,
              currentWorkspace: widget.workspaceState?.currentWorkspace,
              onNavigate: (section) {
                setState(() => _currentSection = section);
                Navigator.pop(context);
              },
            )
          : null,
      body: Column(
        children: [
          _buildAppBar(context),
          Expanded(
            child: _buildContent(),
          ),
        ],
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
        onNavigate: (section) {
          setState(() => _currentSection = section);
        },
      );
    }

    return _buildSettingsSection();
  }

  Widget _buildSettingsSection() {
    final isServerWorkspace =
        _userProfile!.workspaceType == WorkspaceTypePB.ServerW;
    final isBillingEnabled =
        isServerWorkspace && FeatureFlag.planBilling.isOn && _subscriptionInfo != null;
    final isQuickEntryUser = _userProfile!.userAuthType != AuthTypePB.Server;
    final workspaceId = widget.workspaceState?.currentWorkspace?.workspaceId ?? '';

    // _GeneralSettingsContent handles its own scroll + padding
    if (_currentSection == MobileSettingsSection.workspace) {
      return const _GeneralSettingsContent();
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
                ),
              MobileSettingsSection.workspace => const SizedBox.shrink(), // handled above
              MobileSettingsSection.workspaceManagement =>
                WorkspaceSettingGroup(),
              MobileSettingsSection.member => WorkspaceSettingGroup(),
              MobileSettingsSection.sharing => _ComingSoonGroup(
                  title: '共享发布',
                  description: '分享与发布功能开发中',
                ),
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
              MobileSettingsSection.about => const AboutSettingGroup(),
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
// Drawer (侧边菜单，和桌面左侧栏对应)
// ============================================================================

class _MobileSettingsDrawer extends StatelessWidget {
  const _MobileSettingsDrawer({
    required this.userProfile,
    required this.currentSection,
    required this.currentSubscription,
    required this.subscriptionInfo,
    required this.currentWorkspace,
    required this.onNavigate,
  });

  final UserProfilePB userProfile;
  final MobileSettingsSection currentSection;
  final CurrentSubscription? currentSubscription;
  final WorkspaceSubscriptionInfoPB? subscriptionInfo;
  final UserWorkspacePB? currentWorkspace;

  final void Function(MobileSettingsSection) onNavigate;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final flutterTheme = Theme.of(context);
    final isQuickEntryUser = userProfile.userAuthType != AuthTypePB.Server;
    final isServerWorkspace =
        userProfile.workspaceType == WorkspaceTypePB.ServerW;
    final isBillingEnabled =
        isServerWorkspace && FeatureFlag.planBilling.isOn && subscriptionInfo != null;

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.78,
      backgroundColor: flutterTheme.colorScheme.surfaceContainerHighest,
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 账号标题
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: FlowyText(
                  '账号',
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: theme.textColorScheme.secondary,
                ),
              ),
              // 用户信息卡片
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _UserInfoCard(
                  userProfile: userProfile,
                  subscriptionInfo: subscriptionInfo,
                  currentSubscription: currentSubscription,
                ),
              ),
              const VSpace(16),
              Divider(color: theme.borderColorScheme.primary.withValues(alpha: 0.3), height: 0.5),
              const VSpace(8),

              // 菜单列表
              _DrawerMenuItem(
                label: '我的账户',
                icon: FlowySvgs.person_s,
                selected: currentSection == MobileSettingsSection.account,
                onTap: () => onNavigate(MobileSettingsSection.account),
              ),
              _DrawerMenuItem(
                label: '通用设置',
                icon: FlowySvgs.m_notification_settings_s,
                selected: currentSection == MobileSettingsSection.workspace,
                onTap: () => onNavigate(MobileSettingsSection.workspace),
              ),
              _DrawerMenuItem(
                label: '空间管理',
                icon: FlowySvgs.folder_m,
                selected: currentSection == MobileSettingsSection.workspaceManagement,
                onTap: () => onNavigate(MobileSettingsSection.workspaceManagement),
              ),
              _DrawerMenuItem(
                label: '人员管理',
                icon: FlowySvgs.m_settings_member_s,
                selected: currentSection == MobileSettingsSection.member,
                onTap: () => onNavigate(MobileSettingsSection.member),
              ),
              _DrawerMenuItem(
                label: '共享发布',
                icon: FlowySvgs.share_s,
                selected: currentSection == MobileSettingsSection.sharing,
                onTap: () => onNavigate(MobileSettingsSection.sharing),
              ),
              _DrawerMenuItem(
                label: '通知设置',
                icon: FlowySvgs.m_notification_settings_s,
                selected: currentSection == MobileSettingsSection.notifications,
                onTap: () {
                  if (isQuickEntryUser) {
                    _showQuickEntryHint(context);
                    return;
                  }
                  onNavigate(MobileSettingsSection.notifications);
                },
              ),
              _DrawerMenuItem(
                label: '存储设置',
                icon: FlowySvgs.icon_file_library_s,
                selected: currentSection == MobileSettingsSection.storage,
                onTap: () => onNavigate(MobileSettingsSection.storage),
              ),

              if (isServerWorkspace &&
                  currentWorkspace?.role != null &&
                  currentWorkspace?.role != AFRolePB.Guest)
                _DrawerMenuItem(
                  label: LocaleKeys.settings_sites_title.tr(),
                  icon: FlowySvgs.m_share_s,
                  selected: currentSection == MobileSettingsSection.sites,
                  onTap: () => onNavigate(MobileSettingsSection.sites),
                ),

              if (isBillingEnabled) ...[
                _DrawerMenuItem(
                  label: LocaleKeys.settings_planPage_menuLabel.tr(),
                  icon: FlowySvgs.upgrade_s,
                  selected: currentSection == MobileSettingsSection.plan,
                  onTap: () => onNavigate(MobileSettingsSection.plan),
                ),
                _DrawerMenuItem(
                  label: LocaleKeys.settings_billingPage_menuLabel.tr(),
                  icon: FlowySvgs.upgrade_storage_s,
                  selected: currentSection == MobileSettingsSection.billing,
                  onTap: () => onNavigate(MobileSettingsSection.billing),
                ),
              ],

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Divider(color: theme.borderColorScheme.primary.withValues(alpha: 0.3), height: 0.5),
              ),

              _DrawerMenuItem(
                label: LocaleKeys.legal_aboutXiaoma.tr(),
                icon: FlowySvgs.information_s,
                selected: currentSection == MobileSettingsSection.about,
                onTap: () => onNavigate(MobileSettingsSection.about),
              ),

              if (!isQuickEntryUser)
                _DrawerMenuItem(
                  label: LocaleKeys.settings_billingPage_membershipUpgrades.tr(),
                  icon: FlowySvgs.icon_setting_upgrade_s,
                  selected: currentSection == MobileSettingsSection.accountManagement,
                  onTap: () => onNavigate(MobileSettingsSection.accountManagement),
                ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _showQuickEntryHint(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('提示'),
        content: const Text('当前为快速进入模式，暂不支持修改通知设置。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }
}

class _DrawerMenuItem extends StatelessWidget {
  const _DrawerMenuItem({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.badge,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final FlowySvgData? icon;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return Column(
      children: [
        Material(
          color: selected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  if (icon != null) ...[
                    FlowySvg(
                      icon!,
                      size: const Size.square(22),
                      color: selected
                          ? theme.iconColorScheme.primary
                          : theme.iconColorScheme.tertiary,
                    ),
                    const HSpace(12),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textStyle.body.standard(
                        color: theme.textColorScheme.primary,
                      ),
                    ),
                  ),
                  if (badge != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        badge!,
                        style: theme.textStyle.caption.standard(
                          color: Theme.of(context).colorScheme.onSecondary,
                        ),
                      ),
                    ),
                    const HSpace(8),
                  ],
                  if (selected || badge != null)
                    FlowySvg(
                      FlowySvgs.toolbar_arrow_right_m,
                      size: const Size.square(20),
                      color: theme.iconColorScheme.tertiary,
                    ),
                ],
              ),
            ),
          ),
        ),
        Divider(
          color: theme.borderColorScheme.primary.withValues(alpha: 0.5),
          height: 0.5,
          indent: 20,
          endIndent: 20,
        ),
      ],
    );
  }
}

// ============================================================================
// 用户信息卡片 (和桌面端 SettingsMenu 一致)
// ============================================================================

class _UserInfoCard extends StatelessWidget {
  const _UserInfoCard({
    required this.userProfile,
    required this.subscriptionInfo,
    required this.currentSubscription,
  });

  final UserProfilePB userProfile;
  final WorkspaceSubscriptionInfoPB? subscriptionInfo;
  final CurrentSubscription? currentSubscription;

  String _getPlanName() {
    final summary = currentSubscription?.subscription;
    final planDetails = currentSubscription?.planDetails;
    final currentPlan = subscriptionInfo?.plan;

    if (summary?.planNameCn?.isNotEmpty == true) {
      return summary!.planNameCn!;
    }
    if (summary?.planCode?.isNotEmpty == true) {
      return summary!.planCode!;
    }
    if (planDetails?.planNameCn?.isNotEmpty == true) {
      return planDetails!.planNameCn!;
    }
    return _getPlanNameFromPB(currentPlan);
  }

  String _getPlanNameFromPB(WorkspacePlanPB? plan) {
    if (plan == null) return '免费版';
    switch (plan.value) {
      case 0: return '免费版';
      case 1: return '标准版';
      case 2: return '专业版';
      case 3: return '高级版';
      default: return '免费版';
    }
  }

  bool _hasValidity() {
    final summary = currentSubscription?.subscription;
    final endDate = subscriptionInfo?.planSubscription.endDate;
    final currentPlan = subscriptionInfo?.plan;
    return summary?.endDate != null ||
        (endDate != null &&
            endDate.toInt() != 0 &&
            (currentPlan?.value ?? 0) != 0);
  }

  String _getDisplayName() {
    if (userProfile.name.isNotEmpty) {
      return userProfile.name;
    }
    if (userProfile.hasPhone() &&
        userProfile.phone.isNotEmpty) {
      return userProfile.phone;
    }
    if (userProfile.email.isNotEmpty) {
      return userProfile.email;
    }
    return '小马AI笔记的笔记';
  }

  Widget _buildAvatar() {
    const double size = 48;
    final iconUrl = userProfile.iconUrl;

    if (iconUrl.isEmpty) {
      return _buildDefaultAvatar(size);
    }

    if (iconUrl.startsWith('http://') || iconUrl.startsWith('https://')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: Image.network(
          iconUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildDefaultAvatar(size),
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
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: Image.asset(
          'assets/images/about_logo.png',
          width: 80,
          height: 80,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(
            Icons.person,
            size: size,
            color: Colors.grey[400],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surfaceContainerColorScheme.layer01,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.borderColorScheme.primary
              .withValues(alpha: isLightMode ? 0.3 : 0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildAvatar(),
              const HSpace(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const VSpace(4),
                    Row(
                      children: [
                        Flexible(
                          child: FlowyText(
                            _getDisplayName(),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: theme.textColorScheme.primary,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const HSpace(8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 2),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.11),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: primaryColor, width: 1),
                          ),
                          child: Text(
                            _getPlanName(),
                            style: TextStyle(
                              fontSize: 12,
                              color: primaryColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_hasValidity()) ...[
                      const VSpace(6),
                      _ValidityPeriod(
                        subscriptionInfo: subscriptionInfo,
                        currentSubscription: currentSubscription,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ValidityPeriod extends StatelessWidget {
  const _ValidityPeriod({
    required this.subscriptionInfo,
    required this.currentSubscription,
  });

  final WorkspaceSubscriptionInfoPB? subscriptionInfo;
  final CurrentSubscription? currentSubscription;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final summary = currentSubscription?.subscription;
    final endDate = subscriptionInfo?.planSubscription.endDate;
    final interval = subscriptionInfo?.planSubscription.interval;
    DateTime? endDateTime = summary?.endDate;

    if (endDateTime == null && endDate != null && endDate.toInt() != 0) {
      endDateTime = endDate.toDateTime();
    }

    if (endDateTime == null) {
      return const SizedBox.shrink();
    }

    DateTime? startDateTime = summary?.startDate;
    if (startDateTime == null) {
      if (interval == RecurringIntervalPB.Year) {
        startDateTime = DateTime(
            endDateTime.year - 1, endDateTime.month, endDateTime.day);
      } else {
        if (endDateTime.month == 1) {
          startDateTime = DateTime(
              endDateTime.year - 1, 12, endDateTime.day);
        } else {
          startDateTime = DateTime(
              endDateTime.year, endDateTime.month - 1, endDateTime.day);
        }
      }
    }

    final dateFormat = 'yyyy.MM.dd';
    final startStr = DateFormat(dateFormat).format(startDateTime);
    final endStr = DateFormat(dateFormat).format(endDateTime);

    return FlowyText(
      '有效期: $startStr至$endStr',
      fontSize: 12,
      color: theme.textColorScheme.secondary,
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
  });

  final UserProfilePB userProfile;
  final WorkspaceSubscriptionInfoPB? subscriptionInfo;
  final CurrentSubscription? currentSubscription;
  final UserWorkspacePB? currentWorkspace;
  final void Function(MobileSettingsSection) onNavigate;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final isServerWorkspace =
        userProfile.workspaceType == WorkspaceTypePB.ServerW;
    final isBillingEnabled =
        isServerWorkspace && FeatureFlag.planBilling.isOn && subscriptionInfo != null;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _UserProfileHeader(userProfile: userProfile),
            const SizedBox(height: 16),
            if (subscriptionInfo != null)
              _MobileUpgradePlanCard(subscriptionInfo: subscriptionInfo!),
            if (subscriptionInfo != null) const SizedBox(height: 16),
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
                  onTap: () => onNavigate(MobileSettingsSection.workspaceManagement),
                ),
                _SettingsItem(
                  label: '人员管理',
                  onTap: () => onNavigate(MobileSettingsSection.member),
                ),
                _SettingsItem(
                  label: '共享发布',
                  onTap: () => onNavigate(MobileSettingsSection.sharing),
                ),
                _SettingsItem(
                  label: '通知设置',
                  onTap: () => onNavigate(MobileSettingsSection.notifications),
                ),
                _SettingsItem(
                  label: '存储设置',
                  onTap: () => onNavigate(MobileSettingsSection.storage),
                ),
                if (isServerWorkspace &&
                    currentWorkspace?.role != null &&
                    currentWorkspace?.role != AFRolePB.Guest)
                  _SettingsItem(
                    label: LocaleKeys.settings_sites_title.tr(),
                    onTap: () => onNavigate(MobileSettingsSection.sites),
                  ),
                if (isBillingEnabled)
                  _SettingsItem(
                    label: LocaleKeys.settings_planPage_menuLabel.tr(),
                    onTap: () => onNavigate(MobileSettingsSection.plan),
                  ),
                if (isBillingEnabled)
                  _SettingsItem(
                    label: LocaleKeys.settings_billingPage_menuLabel.tr(),
                    onTap: () => onNavigate(MobileSettingsSection.billing),
                  ),
                _SettingsItem(
                  label: LocaleKeys.legal_aboutXiaoma.tr(),
                  onTap: () => onNavigate(MobileSettingsSection.about),
                ),
                if (userProfile.userAuthType == AuthTypePB.Server)
                  _SettingsItem(
                    label: LocaleKeys.settings_billingPage_membershipUpgrades.tr(),
                    onTap: () => onNavigate(MobileSettingsSection.accountManagement),
                    showBottomDivider: false,
                  ),
              ],
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

  void _showSwitchAccountDialog(BuildContext context) {
    showCancelAndConfirmDialog(
      context: context,
      title: '切换账号',
      description: '确定要切换账号吗？',
      confirmLabel: '确定',
      onConfirm: (_) async {
        try {
          final signInBloc = getIt<SignInBloc>();
          if (!signInBloc.isClosed) {
            signInBloc.add(const SignInEvent.reset());
          }
        } catch (_) {}
        await getIt<AuthService>().signOut();
        if (context.mounted) {
          Navigator.popUntil(context, (route) => route.isFirst);
        }
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
        try {
          final signInBloc = getIt<SignInBloc>();
          if (!signInBloc.isClosed) {
            signInBloc.add(const SignInEvent.reset());
          }
        } catch (_) {}
        await getIt<AuthService>().signOut();
        if (context.mounted) {
          Navigator.popUntil(context, (route) => route.isFirst);
        }
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
  const _SettingsGroupCard({required this.items});

  final List<_SettingsItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final isLightMode = Theme.of(context).brightness == Brightness.light;

    return Container(
      decoration: BoxDecoration(
        color: theme.surfaceContainerColorScheme.layer01,
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
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
  const _UserProfileHeader({required this.userProfile});

  final UserProfilePB userProfile;

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
        child: Image.network(
          iconUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildDefaultAvatar(size),
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
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: Image.asset(
          'assets/images/about_logo.png',
          width: 80,
          height: 80,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(
            Icons.person,
            size: size,
            color: Colors.grey[400],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    const double avatarSize = 48;
    const double horizontalPadding = 16.0;

    return Container(
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
    );
  }
}

// ============================================================================
// 移动端会员升级卡片
// ============================================================================

class _MobileUpgradePlanCard extends StatelessWidget {
  const _MobileUpgradePlanCard({required this.subscriptionInfo});

  final WorkspaceSubscriptionInfoPB subscriptionInfo;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return GestureDetector(
      onTap: () => _showUpgradeDialog(context),
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF44326B),
                  Color(0xFF7547C0),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  blurRadius: 8,
                  color: const Color(0xFF7547C0).withValues(alpha: 0.3),
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subscriptionInfo.label,
                  style: theme.textStyle.heading2.standard(
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subscriptionInfo.info,
                  style: theme.textStyle.body.standard(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '立即升级',
                  style: theme.textStyle.heading4.standard(
                    color: const Color(0xFF44326B),
                  ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            child: Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF4F3F5F),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: Center(
                child: Text(
                  '当前方案',
                  style: theme.textStyle.body.standard(
                    color: Colors.white,
                  ).copyWith(fontSize: 11),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showUpgradeDialog(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const _MobileUpgradePlanPage(),
      ),
    );
  }
}

class _MobileUpgradePlanPage extends StatelessWidget {
  const _MobileUpgradePlanPage();

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return Scaffold(
      backgroundColor: theme.surfaceColorScheme.primary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: theme.iconColorScheme.primary,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          '会员升级',
          style: theme.textStyle.heading4.standard(
            color: theme.textColorScheme.primary,
          ),
        ),
        centerTitle: true,
      ),
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: theme.surfaceColorScheme.primary,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: const _UpgradePlanBody(),
      ),
    );
  }
}

class _UpgradePlanBody extends StatelessWidget {
  const _UpgradePlanBody();

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 24, bottom: 40),
      child: Column(
        children: [
          Text(
            '解锁全部高级功能',
            style: theme.textStyle.heading2.standard(
              color: theme.textColorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '选择一个适合您的方案',
            style: theme.textStyle.body.standard(
              color: theme.textColorScheme.secondary,
            ),
          ),
          const SizedBox(height: 32),
          _buildBenefitIcons(context),
          const SizedBox(height: 32),
          _buildUpgradePlanCards(),
        ],
      ),
    );
  }

  Widget _buildBenefitIcons(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final benefits = [
      {'label': '小马AI', 'icon': FlowySvgs.icon_rights_ai_xl},
      {'label': '小马日历', 'icon': FlowySvgs.icon_rights_calendar_xl},
      {'label': '小马收藏夹', 'icon': FlowySvgs.icon_rights_collect_xl},
      {'label': '云端同步', 'icon': FlowySvgs.icon_rights_cloud_xl},
      {'label': '云端空间', 'icon': FlowySvgs.icon_rights_storage_xl},
    ];

    return Wrap(
      spacing: 16,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: benefits.map((benefit) {
        return SizedBox(
          width: 70,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.white : null,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: FlowySvg(
                    benefit['icon'] as FlowySvgData,
                    size: const Size(48, 48),
                    blendMode: null,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                benefit['label'] as String,
                style: theme.textStyle.body.standard(
                  color: theme.textColorScheme.secondary,
                ).copyWith(fontSize: 11),
                textAlign: TextAlign.center,
                maxLines: 1,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildUpgradePlanCards() {
    return Column(
      children: [
        _UpgradePlanCard(
          planName: '标准版',
          price: '¥99',
          period: '/年',
          storage: '5GB',
          workspaces: '5个',
          aiQuota: '500次/月',
          priceColor: const Color(0xFF2EACB2),
        ),
        const SizedBox(height: 12),
        _UpgradePlanCard(
          planName: '专业版',
          price: '¥158',
          period: '/年',
          storage: '20GB',
          workspaces: '20个',
          aiQuota: '2000次/月',
          priceColor: const Color(0xFF343543),
          isHighlighted: true,
        ),
        const SizedBox(height: 12),
        _UpgradePlanCard(
          planName: '旗舰版',
          price: '¥298',
          period: '/年',
          storage: '100GB',
          workspaces: '100个',
          aiQuota: '无限次',
          priceColor: const Color(0xFF371A0D),
        ),
      ],
    );
  }
}

class _UpgradePlanCard extends StatelessWidget {
  const _UpgradePlanCard({
    required this.planName,
    required this.price,
    required this.period,
    required this.storage,
    required this.workspaces,
    required this.aiQuota,
    required this.priceColor,
    this.isHighlighted = false,
  });

  final String planName;
  final String price;
  final String period;
  final String storage;
  final String workspaces;
  final String aiQuota;
  final Color priceColor;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isHighlighted
            ? (Theme.of(context).brightness == Brightness.light
                ? const Color(0xFFFFF7F2)
                : theme.surfaceColorScheme.layer02)
            : theme.surfaceColorScheme.layer01,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isHighlighted
              ? Theme.of(context).colorScheme.primary
              : theme.borderColorScheme.primary,
          width: isHighlighted ? 1.6 : 1.0,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            planName,
            style: theme.textStyle.heading4.standard(
              color: theme.textColorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: priceColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: price,
                        style: theme.textStyle.heading2.standard(
                          color: priceColor == const Color(0xFF2EACB2)
                              ? Colors.white
                              : const Color(0xFFF9D8A7),
                        ),
                      ),
                      TextSpan(
                        text: period,
                        style: theme.textStyle.body.standard(
                          color: priceColor == const Color(0xFF2EACB2)
                              ? Colors.white
                              : const Color(0x99F9D8A7),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '按年支付',
                  style: theme.textStyle.body.standard(
                    color: priceColor == const Color(0xFF2EACB2)
                        ? Colors.white.withValues(alpha: 0.8)
                        : const Color(0x99F9D8A7),
                  ).copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 6,
                padding: const EdgeInsets.only(top: 2),
                child: FlowySvg(
                  FlowySvgs.icon_plan_info_indicator_s,
                  blendMode: null,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '云端空间 $storage',
                      style: theme.textStyle.body.standard(
                        color: theme.textColorScheme.secondary,
                      ).copyWith(fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '工作区限制 $workspaces',
                      style: theme.textStyle.body.standard(
                        color: theme.textColorScheme.secondary,
                      ).copyWith(fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '每月AI对话额度 $aiQuota',
                      style: theme.textStyle.body.standard(
                        color: theme.textColorScheme.secondary,
                      ).copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isHighlighted
                    ? Theme.of(context).colorScheme.primary
                    : theme.surfaceColorScheme.layer02,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  '选择此方案',
                  style: theme.textStyle.heading4.standard(
                    color: isHighlighted
                        ? Colors.white
                        : theme.textColorScheme.primary,
                  ),
                ),
              ),
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
  const _GeneralSettingsContent();

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
            const _SupportCard(),
            const SizedBox(height: 16),
            Text(
              '版本 ${ApplicationInfo.applicationVersion} (${ApplicationInfo.buildNumber})',
              style: theme.textStyle.body.standard(
                color: theme.textColorScheme.secondary,
              ),
            ),
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
        color: theme.surfaceContainerColorScheme.layer01,
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
          _SettingsCardDivider(),
          _FontFamilySettingItem(),
          _SettingsCardDivider(),
          _FontSizeSettingItem(),
          _SettingsCardDivider(),
          _SettingsLinkItem(
            label: '日期和时间',
            onTap: () => context.push(DateTimePage.routeName),
          ),
          _SettingsCardDivider(),
          _SettingsLinkItem(
            label: '语言',
            onTap: () => context.push('/language_picker'),
          ),
          _SettingsCardDivider(),
          _SettingsActionItem(
            label: '清除缓存',
            onTap: () => _showClearCacheDialog(context),
          ),
          _SettingsCardDivider(),
          _SettingsLinkItem(
            label: '隐私政策',
            onTap: () => afLaunchUrlString('https://appflowy.com/privacy'),
          ),
          _SettingsCardDivider(),
          _SettingsLinkItem(
            label: '关于',
            onTap: () => context.push('/settings/about'),
          ),
        ],
      ),
    );
  }

  void _showClearCacheDialog(BuildContext context) {
    showFlowyMobileConfirmDialog(
      context,
      title: const FlowyText('确定要清除缓存吗？', maxLines: 2),
      content: const FlowyText(
        '这将清除所有缓存数据，但不会删除您的笔记内容。',
        fontSize: 12,
        maxLines: 4,
      ),
      actionButtonTitle: '确定',
      onActionButtonPressed: () async {
        await getIt<FlowyCacheManager>().clearAllCache();
        if (context.mounted) {
          showToastNotification(message: '缓存已清除');
        }
      },
    );
  }
}

class _SettingsCardDivider extends StatelessWidget {
  const _SettingsCardDivider();

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Divider(
      color: theme.borderColorScheme.primary.withValues(alpha: 0.5),
      height: 0.5,
      indent: 16,
      endIndent: 16,
    );
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
        color: theme.surfaceContainerColorScheme.layer01,
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
              '联系与支持',
              style: theme.textStyle.heading4.standard(
                color: theme.textColorScheme.primary,
              ),
            ),
          ),
          _SettingsLinkItem(
            label: '加入 Discord',
            onTap: () => afLaunchUrlString('https://discord.gg/JucBXeU2FE'),
          ),
          _SettingsCardDivider(),
          _SettingsActionItem(
            label: '上报问题',
            onTap: () => _showReportIssueSheet(context),
          ),
        ],
      ),
    );
  }

  void _showReportIssueSheet(BuildContext context) {
    showMobileBottomSheet(
      context,
      showDragHandle: true,
      showHeader: true,
      title: '上报问题',
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FlowyOptionTile.text(
              showTopBorder: false,
              text: 'GitHub 上报问题',
              onTap: () {
                final String os = io.Platform.operatingSystem;
                afLaunchUrlString(
                  'https://github.com/AppFlowy-IO/AppFlowy/issues/new'
                  '?assignees=&labels=&projects=&template=bug_report.yaml'
                  '&title=[Bug]%20Mobile:%20&version=${ApplicationInfo.applicationVersion}&os=$os',
                );
                Navigator.pop(ctx);
              },
            ),
            FlowyOptionTile.text(
              showTopBorder: false,
              text: '导出日志文件',
              onTap: () {
                shareLogFiles(ctx);
                Navigator.pop(ctx);
              },
            ),
          ],
        );
      },
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                ctx.read<AppearanceSettingsCubit>().setThemeMode(ThemeMode.light);
                Navigator.pop(ctx);
              },
            ),
            FlowyOptionTile.checkbox(
              showTopBorder: false,
              text: LocaleKeys.settings_appearance_themeMode_dark.tr(),
              leftIcon: const FlowySvg(FlowySvgs.m_theme_mode_dark_s),
              isSelected: themeMode == ThemeMode.dark,
              onTap: () {
                ctx.read<AppearanceSettingsCubit>().setThemeMode(ThemeMode.dark);
                Navigator.pop(ctx);
              },
            ),
            FlowyOptionTile.checkbox(
              showTopBorder: false,
              text: LocaleKeys.settings_appearance_themeMode_system.tr(),
              leftIcon: const FlowySvg(FlowySvgs.m_theme_mode_system_s),
              isSelected: themeMode == ThemeMode.system,
              onTap: () {
                ctx.read<AppearanceSettingsCubit>().setThemeMode(ThemeMode.system);
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
    final selectedFont =
        context.watch<AppearanceSettingsCubit>().state.font;
    final name = selectedFont.fontFamilyDisplayName;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push(FontPickerScreen.routeName),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
