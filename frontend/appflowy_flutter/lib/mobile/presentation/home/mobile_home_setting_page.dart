import 'dart:io' as io;

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/features/workspace/logic/workspace_state.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/util/int64_extension.dart';
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
              onPressed: isMenu ? () => Navigator.pop(context) : () => _scaffoldKey.currentState?.openDrawer(),
              icon: FlowySvg(
                isMenu ? FlowySvgs.mobile_return_s : FlowySvgs.m_settings_more_s,
                size: isMenu ? const Size(7, 12) : const Size(24, 24),
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
    return Scaffold(
      key: _scaffoldKey,
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
          if (_currentSection == MobileSettingsSection.menu && _userProfile != null)
            _UserProfileHeader(userProfile: _userProfile!),
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
                selected: currentSection == MobileSettingsSection.account,
                onTap: () => onNavigate(MobileSettingsSection.account),
              ),
              _DrawerMenuItem(
                label: '通用设置',
                selected: currentSection == MobileSettingsSection.workspace,
                onTap: () => onNavigate(MobileSettingsSection.workspace),
              ),
              _DrawerMenuItem(
                label: '空间管理',
                selected: currentSection == MobileSettingsSection.workspaceManagement,
                onTap: () => onNavigate(MobileSettingsSection.workspaceManagement),
              ),
              _DrawerMenuItem(
                label: '人员管理',
                selected: currentSection == MobileSettingsSection.member,
                onTap: () => onNavigate(MobileSettingsSection.member),
              ),
              _DrawerMenuItem(
                label: '共享发布',
                selected: currentSection == MobileSettingsSection.sharing,
                onTap: () => onNavigate(MobileSettingsSection.sharing),
              ),
              _DrawerMenuItem(
                label: '通知设置',
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
                selected: currentSection == MobileSettingsSection.storage,
                onTap: () => onNavigate(MobileSettingsSection.storage),
              ),

              if (isServerWorkspace &&
                  currentWorkspace?.role != null &&
                  currentWorkspace?.role != AFRolePB.Guest)
                _DrawerMenuItem(
                  label: LocaleKeys.settings_sites_title.tr(),
                  selected: currentSection == MobileSettingsSection.sites,
                  onTap: () => onNavigate(MobileSettingsSection.sites),
                ),

              if (isBillingEnabled) ...[
                _DrawerMenuItem(
                  label: LocaleKeys.settings_planPage_menuLabel.tr(),
                  selected: currentSection == MobileSettingsSection.plan,
                  onTap: () => onNavigate(MobileSettingsSection.plan),
                ),
                _DrawerMenuItem(
                  label: LocaleKeys.settings_billingPage_menuLabel.tr(),
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
                selected: currentSection == MobileSettingsSection.about,
                onTap: () => onNavigate(MobileSettingsSection.about),
              ),

              if (!isQuickEntryUser)
                _DrawerMenuItem(
                  label: LocaleKeys.settings_billingPage_membershipUpgrades.tr(),
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
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return Material(
      color: selected
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
              if (selected)
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
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surfaceContainerColorScheme.layer01,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.borderColorScheme.primary.withValues(alpha: 0.1),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 快捷入口
            _QuickEntryCard(
              label: '我的账户',
              onTap: () => onNavigate(MobileSettingsSection.account),
            ),
            const VSpace(12),
            _QuickEntryCard(
              label: '通用设置',
              onTap: () => onNavigate(MobileSettingsSection.workspace),
            ),
            const VSpace(12),
            _QuickEntryCard(
              label: '空间管理',
              onTap: () => onNavigate(MobileSettingsSection.workspaceManagement),
            ),
            const VSpace(12),
            _QuickEntryCard(
              label: '人员管理',
              onTap: () => onNavigate(MobileSettingsSection.member),
            ),

            const VSpace(24),
            FlowyText(
              '其他设置',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: theme.textColorScheme.secondary,
            ),
            const VSpace(8),
            _QuickEntryCard(
              label: '共享发布',
              onTap: () => onNavigate(MobileSettingsSection.sharing),
            ),
            const VSpace(12),
            _QuickEntryCard(
              label: '通知设置',
              onTap: () => onNavigate(MobileSettingsSection.notifications),
            ),
            const VSpace(12),
            _QuickEntryCard(
              label: '存储设置',
              onTap: () => onNavigate(MobileSettingsSection.storage),
            ),

            if (isServerWorkspace &&
                currentWorkspace?.role != null &&
                currentWorkspace?.role != AFRolePB.Guest) ...[
              const VSpace(24),
              FlowyText(
                '订阅服务',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: theme.textColorScheme.secondary,
              ),
              const VSpace(8),
              _QuickEntryCard(
                label: LocaleKeys.settings_sites_title.tr(),
                onTap: () => onNavigate(MobileSettingsSection.sites),
              ),
              if (isBillingEnabled) ...[
                const VSpace(12),
                _QuickEntryCard(
                  label: LocaleKeys.settings_planPage_menuLabel.tr(),
                  onTap: () => onNavigate(MobileSettingsSection.plan),
                ),
                const VSpace(12),
                _QuickEntryCard(
                  label: LocaleKeys.settings_billingPage_menuLabel.tr(),
                  onTap: () => onNavigate(MobileSettingsSection.billing),
                ),
              ],
            ],

            const VSpace(24),
            FlowyText(
              '关于',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: theme.textColorScheme.secondary,
            ),
            const VSpace(8),
            _QuickEntryCard(
              label: LocaleKeys.legal_aboutXiaoma.tr(),
              onTap: () => onNavigate(MobileSettingsSection.about),
            ),

            if (userProfile.userAuthType == AuthTypePB.Server) ...[
              const VSpace(12),
              _QuickEntryCard(
                label: LocaleKeys.settings_billingPage_membershipUpgrades.tr(),
                onTap: () => onNavigate(MobileSettingsSection.accountManagement),
              ),
            ],

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _QuickEntryCard extends StatelessWidget {
  const _QuickEntryCard({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return Material(
      color: theme.surfaceContainerColorScheme.layer01,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(
              color: theme.borderColorScheme.primary.withValues(alpha: 0.08),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
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
