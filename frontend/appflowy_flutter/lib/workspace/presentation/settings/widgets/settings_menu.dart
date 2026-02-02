import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/util/int64_extension.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/settings_menu_element.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class SettingsMenu extends StatefulWidget {
  const SettingsMenu({
    super.key,
    required this.changeSelectedPage,
    required this.currentPage,
    required this.userProfile,
    required this.isBillingEnabled,
    required this.currentUserRole,
    required this.workspaceId,
    this.currentSubscription,
  });

  final void Function(SettingsPage page) changeSelectedPage;
  final SettingsPage currentPage;
  final UserProfilePB userProfile;
  final bool isBillingEnabled;
  final AFRolePB? currentUserRole;
  final String workspaceId;
  final CurrentSubscription? currentSubscription;

  @override
  State<SettingsMenu> createState() => _SettingsMenuState();
}

class _SettingsMenuState extends State<SettingsMenu> {
  WorkspaceSubscriptionInfoPB? _subscriptionInfo;

  @override
  void initState() {
    super.initState();
    _loadSubscriptionInfo();
  }

  Future<void> _loadSubscriptionInfo() async {
    final result = await UserBackendService.getWorkspaceSubscriptionInfo(widget.workspaceId);
    
    result.fold(
      (info) {
        if (mounted) {
          setState(() {
            _subscriptionInfo = info;
          });
        }
      },
      (error) {
        Log.error('Failed to load subscription info: ${error.msg}');
      },
    );
  }

  // 按枚举数值判断，兼容旧/新生成的 Dart 枚举名。0=Free, 1=Stand/Standard, 2=Pro/Student, 3=Hiclass/Team
  String _getPlanName(WorkspacePlanPB? plan) {
    if (plan == null) return '免费版';
    switch (plan.value) {
      case 0:
        return '免费版';
      case 1:
        return '标准版';
      case 2:
        return '学生版';
      case 3:
        return '团队版';
      default:
        return '免费版';
    }
  }

  // 获取显示名称：优先显示昵称，其次显示手机号
  String _getUserDisplayName() {
    // debug logs removed
    
    // 优先显示用户名
    if (widget.userProfile.name.isNotEmpty) {
      // debug log removed
      return widget.userProfile.name;
    }
    // 其次显示手机号
    if (widget.userProfile.hasPhone() && widget.userProfile.phone.isNotEmpty) {
      // debug log removed
      return widget.userProfile.phone;
    }
    // 再显示邮箱
    if (widget.userProfile.email.isNotEmpty) {
      // debug log removed
      return widget.userProfile.email;
    }
    // 最后显示默认值
    // debug log removed
    return '小马笔记的笔记';
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final storageUsage = _buildStorageUsageText();

    return Container(
      decoration: BoxDecoration(
        color: theme.surfaceContainerColorScheme.layer01,
        borderRadius: BorderRadiusDirectional.horizontal(
          start: Radius.circular(theme.spacing.m),
        ),
      ),
      height: double.infinity,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          top: 12,
          bottom: 24,
          left: theme.spacing.l,
          right: theme.spacing.l,
        ),
        physics: const ClampingScrollPhysics(),
        child: Column(
          spacing: theme.spacing.xs,
          children: [
            // 账号标题 + 用户信息卡片
            Container(
              margin: EdgeInsets.only(top: 20,left: 20),
              alignment: Alignment.centerLeft,
              child: FlowyText(
                '账号',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: theme.textColorScheme.secondary,
              ),
            ),
            const VSpace(8),
            _buildUserInfoCard(context),
            const VSpace(16),
            SettingsMenuElement(
              page: SettingsPage.account,
              selectedPage: widget.currentPage,
              label: "我的账户",
              trailingText: storageUsage,
              changeSelectedPage: widget.changeSelectedPage,
              showArrow: false,
            ),
            SettingsMenuElement(
              page: SettingsPage.workspace,
              selectedPage: widget.currentPage,
              label: "通用设置",
              changeSelectedPage: widget.changeSelectedPage,
            ),
            SettingsMenuElement(
              page: SettingsPage.workspaceManagement,
              selectedPage: widget.currentPage,
              label: "空间管理",
              changeSelectedPage: widget.changeSelectedPage,
            ),
            SettingsMenuElement(
              page: SettingsPage.member,
              selectedPage: widget.currentPage,
              label: "人员管理",
              changeSelectedPage: widget.changeSelectedPage,
            ),
            SettingsMenuElement(
              page: SettingsPage.sharing,
              selectedPage: widget.currentPage,
              label: "共享发布",
              changeSelectedPage: widget.changeSelectedPage,
            ),
            SettingsMenuElement(
              page: SettingsPage.notifications,
              selectedPage: widget.currentPage,
              label: "通知设置",
              changeSelectedPage: widget.changeSelectedPage,
            ),
            SettingsMenuElement(
              page: SettingsPage.storage,
              selectedPage: widget.currentPage,
              label: "存储设置",
              changeSelectedPage: widget.changeSelectedPage,
            ),

            if (widget.userProfile.workspaceType == WorkspaceTypePB.ServerW &&
                widget.currentUserRole != null &&
                widget.currentUserRole != AFRolePB.Guest)
              SettingsMenuElement(
                page: SettingsPage.sites,
                selectedPage: widget.currentPage,
                label: LocaleKeys.settings_sites_title.tr(),
                changeSelectedPage: widget.changeSelectedPage,
              ),
            if (FeatureFlag.planBilling.isOn && widget.isBillingEnabled) ...[
              SettingsMenuElement(
                page: SettingsPage.plan,
                selectedPage: widget.currentPage,
                label: LocaleKeys.settings_planPage_menuLabel.tr(),
                changeSelectedPage: widget.changeSelectedPage,
              ),
              SettingsMenuElement(
                page: SettingsPage.billing,
                selectedPage: widget.currentPage,
                label: LocaleKeys.settings_billingPage_menuLabel.tr(),
                changeSelectedPage: widget.changeSelectedPage,
              ),
            ],

            // 关于小马按钮
            SettingsMenuElement(
              page: SettingsPage.aboutXiaoma,
              selectedPage: widget.currentPage,
              label: LocaleKeys.legal_aboutXiaoma.tr(),
              changeSelectedPage: widget.changeSelectedPage,
            ),
            
            // 会员升级入口
            SettingsMenuElement(
              page: SettingsPage.accountManagement,
              selectedPage: widget.currentPage,
              label: LocaleKeys.settings_billingPage_membershipUpgrades.tr(),
              changeSelectedPage: widget.changeSelectedPage,
              showIcon: true,
              showArrow: false,
            ),
          ],
        ),
      ),
    );
  }

  String _buildStorageUsageText() {
    final usage = widget.currentSubscription?.usage;
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

    return '剩余空间${fmt(remainingGb)}/${fmt(totalGb)}';
  }

  Widget _buildUserInfoCard(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    // 优先使用新接口的订阅信息，其次回退 workspace 订阅信息
    final sub = widget.currentSubscription;
    final summary = sub?.subscription;
    final planDetails = sub?.planDetails;

    final currentPlan =
        _subscriptionInfo?.plan;
    final planName = summary?.planNameCn?.isNotEmpty == true
        ? summary!.planNameCn!
        : (summary?.planCode?.isNotEmpty == true
            ? summary!.planCode!
            : (planDetails?.planNameCn?.isNotEmpty == true
                ? planDetails!.planNameCn!
                : _getPlanName(currentPlan)));

    final hasValidity = summary?.endDate != null ||
        (_subscriptionInfo?.planSubscription.endDate != null &&
            (currentPlan?.value ?? 0) != 0);

    Widget buildAvatar() {
      final double size = 48;
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: widget.userProfile.iconUrl.isNotEmpty
            ? Image.network(
                widget.userProfile.iconUrl,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildDefaultAvatar(size),
              )
            : _buildDefaultAvatar(size),
      );
    }

    return Container(
      padding: EdgeInsets.all(theme.spacing.l),
      decoration: BoxDecoration(
        color: theme.surfaceContainerColorScheme.layer01,
        borderRadius: BorderRadius.circular(theme.spacing.m),
        border: Border.all(
          color: theme.borderColorScheme.primary.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildAvatar(),
              const HSpace(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const VSpace(6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: FlowyText(
                                  _getUserDisplayName(),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: theme.textColorScheme.primary,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const HSpace(8),
                              Builder(
                                builder: (context) {
                                  final primaryColor = Theme.of(context).colorScheme.primary;
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: primaryColor.withOpacity(0.11),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: primaryColor,
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      planName,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: primaryColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const VSpace(6),
                    if (hasValidity)
                      _buildValidityPeriod(context,
                          start: summary?.startDate, end: summary?.endDate)
                    else
                      SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildDefaultAvatar(double size) {
    return Container(
      color: Colors.white,
      width: size,
      height: size,
      alignment: Alignment.center,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.asset(
          'assets/images/about_logo.png',
          width: 80,
          height: 80,
          fit: BoxFit.cover,
        ),
      ),
    );
  }


  Widget _buildValidityPeriod(
    BuildContext context, {
    DateTime? start,
    DateTime? end,
  }) {
    final theme = AppFlowyTheme.of(context);
    final endDateInt64 = _subscriptionInfo?.planSubscription.endDate;
    final interval = _subscriptionInfo?.planSubscription.interval;
    DateTime? endDate = end;
    DateTime? startDate = start;

    if (endDate == null && endDateInt64 != null && endDateInt64.toInt() != 0) {
      endDate = endDateInt64.toDateTime();
    }

    if (startDate == null && endDate != null) {
      if (interval == RecurringIntervalPB.Year) {
        startDate = DateTime(endDate.year - 1, endDate.month, endDate.day);
      } else {
        if (endDate.month == 1) {
          startDate = DateTime(endDate.year - 1, 12, endDate.day);
        } else {
          startDate = DateTime(endDate.year, endDate.month - 1, endDate.day);
        }
      }
    }

    if (endDate == null) {
      return const SizedBox.shrink();
    }
    
    // 格式化日期为 yyyy.MM.dd 格式
    final dateFormat = 'yyyy.MM.dd';
    final startDateStr =
        startDate != null ? DateFormat(dateFormat).format(startDate) : '--';
    final endDateStr = DateFormat(dateFormat).format(endDate);
    
    return FittedBox(
      child: FlowyText(
        '有效期: $startDateStr至$endDateStr',
        fontSize: 12,
        color: theme.textColorScheme.secondary,
      ),
    );
  }

}

class SimpleSettingsMenu extends StatelessWidget {
  const SimpleSettingsMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8) +
                const EdgeInsets.only(left: 8, right: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                bottomLeft: Radius.circular(8),
              ),
            ),
            child: SingleChildScrollView(
              // Right padding is added to make the scrollbar centered
              // in the space between the menu and the content
              padding: const EdgeInsets.only(right: 4) +
                  const EdgeInsets.symmetric(vertical: 16),
              physics: const ClampingScrollPhysics(),
              child: SeparatedColumn(
                separatorBuilder: () => const VSpace(16),
                children: [
                  SettingsMenuElement(
                    page: SettingsPage.cloud,
                    selectedPage: SettingsPage.cloud,
                    label: LocaleKeys.settings_menu_cloudSettings.tr(),
                    changeSelectedPage: (_) {},
                  ),
                  if (kDebugMode)
                    SettingsMenuElement(
                      page: SettingsPage.featureFlags,
                      selectedPage: SettingsPage.cloud,
                      label: LocaleKeys.settings_menu_featureFlags.tr(),
                      changeSelectedPage: (_) {},
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
