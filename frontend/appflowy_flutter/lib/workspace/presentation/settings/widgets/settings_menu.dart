import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/user/application/user_service.dart';
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

  final Function changeSelectedPage;
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
        padding: EdgeInsets.symmetric(
          vertical: 24,
          horizontal: theme.spacing.l,
        ),
        physics: const ClampingScrollPhysics(),
        child: Column(
          spacing: theme.spacing.xs,
          children: [
            // User info card section at the top
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
    
    return GestureDetector(
      onTap: () => widget.changeSelectedPage(SettingsPage.accountManagement),
      child: Container(
        padding: EdgeInsets.all(theme.spacing.m),
        decoration: BoxDecoration(
          color: theme.surfaceContainerColorScheme.layer01,
          borderRadius: BorderRadius.circular(theme.spacing.m),
          border: Border.all(
            color: theme.borderColorScheme.primary.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // 左侧：头像和昵称（水平排列）
            Row(
              children: [
                // 用户头像
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: widget.userProfile.iconUrl.isNotEmpty
                        ? Image.network(
                            widget.userProfile.iconUrl,
                            fit: BoxFit.cover,
                            width: 24,
                            height: 24,
                            errorBuilder: (context, error, stackTrace) {
                              return FlowySvg(
                                FlowySvgs.pony_notes_logo_xl,
                                size: const Size(16, 16),
                                blendMode: null,
                              );
                            },
                          )
                        : FlowySvg(
                            FlowySvgs.pony_notes_logo_xl,
                            size: const Size(16, 16),
                            blendMode: null,
                          ),
                  ),
                ),
                const HSpace(6),
                // 昵称
                FlowyText(
                  widget.userProfile.name.isNotEmpty 
                      ? widget.userProfile.name 
                      : '小马笔记的笔记',
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: theme.textColorScheme.primary,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            // 右侧：版本信息
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: FlowyText(
                  planName,
                  fontSize: 14,
                  color: theme.textColorScheme.secondary,
                ),
              ),
            ),
          ],
        ),
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
                    changeSelectedPage: () {},
                  ),
                  if (kDebugMode)
                    SettingsMenuElement(
                      // no need to translate this page
                      page: SettingsPage.featureFlags,
                      selectedPage: SettingsPage.cloud,
                      label: 'Feature Flags',
                      changeSelectedPage: () {},
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
