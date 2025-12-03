import 'package:appflowy/generated/flowy_svgs.g.dart';
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
  });

  final void Function(SettingsPage page) changeSelectedPage;
  final SettingsPage currentPage;
  final UserProfilePB userProfile;
  final bool isBillingEnabled;
  final AFRolePB? currentUserRole;
  final String workspaceId;

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

  // 根据订阅计划返回对应的版本名称
  String _getPlanName(WorkspacePlanPB plan) {
    switch (plan) {
      case WorkspacePlanPB.FreePlan:
        return '免费版';
      case WorkspacePlanPB.StudentPlan:
        return '学生版';
      case WorkspacePlanPB.StandardPlan:
        return '标准版';
      case WorkspacePlanPB.TeamPlan:
        return '团队版';
      default:
        return '免费版';
    }
  }

  // 获取显示名称：优先显示昵称，其次显示手机号
  String _getDisplayName() {
    // 优先显示昵称
    if (widget.userProfile.name.isNotEmpty) {
      return widget.userProfile.name;
    }
    // 其次显示手机号
    if (widget.userProfile.hasPhone() && widget.userProfile.phone.isNotEmpty) {
      return widget.userProfile.phone;
    }
    // 再显示邮箱
    if (widget.userProfile.email.isNotEmpty) {
      return widget.userProfile.email;
    }
    // 最后显示默认值
    return '小马笔记的笔记';
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

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
              label: LocaleKeys.settings_menu_notifications.tr(),
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
          ],
        ),
      ),
    );
  }

  Widget _buildUserInfoCard(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final currentPlan = _subscriptionInfo?.plan ?? WorkspacePlanPB.FreePlan;
    final planName = _getPlanName(currentPlan);
    final isFreePlan = currentPlan == WorkspacePlanPB.FreePlan;
    
    final hasValidity =
        !isFreePlan && _subscriptionInfo?.planSubscription.endDate != null;

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
                                  horizontal: 10,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0x1CF89575),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: const Color(0xFFF89879),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  planName,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFF89879),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const VSpace(6),
                    if (hasValidity)
                      _buildValidityPeriod(context)
                    else
                      // FlowyText(
                      // '有效期: 2025-01-01至2025-12-31',
                      // fontSize: 12,
                      // color: theme.textColorScheme.secondary,
                      // ),
                      SizedBox(height: 24),
                    const VSpace(12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildUserInfoButton(
                            label: '空间补充包',
                            onTap: () =>
                                widget.changeSelectedPage(SettingsPage.billingPage),
                          ),
                        ),
                        const HSpace(12),
                        Expanded(
                          child: _buildUserInfoButton(
                            label: '会员升级',
                            onTap: () =>
                                widget.changeSelectedPage(SettingsPage.accountManagement),
                          ),
                        ),
                      ],
                    ),
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
      child: FlowySvg(
        FlowySvgs.pony_notes_logo_xl,
        size: Size(size * 0.6, size * 0.6),
        blendMode: null,
      ),
    );
  }

  Widget _buildUserInfoButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFF89575),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildValidityPeriod(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final endDateInt64 = _subscriptionInfo?.planSubscription.endDate;
    final interval = _subscriptionInfo?.planSubscription.interval;
    
    if (endDateInt64 == null || endDateInt64.toInt() == 0) {
      return const SizedBox.shrink();
    }
    
    // 将时间戳转换为 DateTime
    final endDate = endDateInt64.toDateTime();
    
    // 根据 interval 计算开始日期
    DateTime startDate;
    if (interval == RecurringIntervalPB.Year) {
      // 年付：开始日期 = 结束日期 - 1年
      startDate = DateTime(endDate.year - 1, endDate.month, endDate.day);
    } else {
      // 默认是月付：开始日期 = 结束日期 - 1个月
      if (endDate.month == 1) {
        // 处理跨年情况（1月）
        startDate = DateTime(endDate.year - 1, 12, endDate.day);
      } else {
        startDate = DateTime(endDate.year, endDate.month - 1, endDate.day);
      }
    }
    
    // 格式化日期为 yyyy.MM.dd 格式
    final dateFormat = 'yyyy.MM.dd';
    final startDateStr = DateFormat(dateFormat).format(startDate);
    final endDateStr = DateFormat(dateFormat).format(endDate);
    
    return FlowyText(
      '有效期: $startDateStr至$endDateStr',
      fontSize: 12,
      color: theme.textColorScheme.secondary,
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
                      // no need to translate this page
                      page: SettingsPage.featureFlags,
                      selectedPage: SettingsPage.cloud,
                      label: 'Feature Flags',
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
