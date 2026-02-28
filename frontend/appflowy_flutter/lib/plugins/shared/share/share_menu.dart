import 'package:appflowy/features/share_tab/presentation/share_tab.dart'
    as share_section;
import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/shared/share/export_tab.dart';
import 'package:appflowy/plugins/shared/share/share_bloc.dart';
import 'package:appflowy/workspace/application/settings/plan/settings_plan_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/shared_widget.dart';
import 'package:appflowy/workspace/presentation/settings/pages/settings_plan_comparison_dialog.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pbenum.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'publish_tab.dart';

enum ShareMenuTab {
  share,
  publish,
  exportAs;

  String get i18n {
    switch (this) {
      case ShareMenuTab.share:
        return LocaleKeys.shareAction_shareTab.tr();
      case ShareMenuTab.publish:
        return LocaleKeys.shareAction_publishTab.tr();
      case ShareMenuTab.exportAs:
        return LocaleKeys.shareAction_exportAsTab.tr();
    }
  }
}

class ShareMenu extends StatefulWidget {
  const ShareMenu({
    super.key,
    required this.tabs,
    required this.viewName,
    required this.onClose,
  });

  final List<ShareMenuTab> tabs;
  final String viewName;
  final VoidCallback onClose;

  @override
  State<ShareMenu> createState() => _ShareMenuState();
}

class _ShareMenuState extends State<ShareMenu> {
  late ShareMenuTab selectedTab = widget.tabs.first;

  @override
  Widget build(BuildContext context) {
    if (widget.tabs.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = AppFlowyTheme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        VSpace(theme.spacing.xs),
        _buildTabBar(context),
        const VSpace(12),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: theme.spacing.m),
          child: _buildTab(context),
        ),
      ],
    );
  }

  Widget _buildTabBar(BuildContext context) {
    final appflowyTheme = AppFlowyTheme.of(context);
    final surfaceColor = appflowyTheme.badgeColorScheme.color19Light1;
    final selectedBgColor =
        Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.white;
    final unselectedBgColor = Colors.transparent;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: surfaceColor.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          for (final tab in widget.tabs)
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    selectedTab = tab;
                  });
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selectedTab == tab
                        ? selectedBgColor
                        : unselectedBgColor,
                    borderRadius: BorderRadius.circular(10),
                    border: selectedTab == tab
                        ? Border.all(
                            color: Theme.of(context)
                                .dividerColor
                                .withValues(alpha: 0.2),
                          )
                        : null,
                    boxShadow: selectedTab == tab
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                    child: _Segment(
                      tab: tab,
                      isSelected: selectedTab == tab,
                      selectedTextColor:
                          appflowyTheme.textColorScheme.primary,
                      unselectedTextColor:
                          appflowyTheme.textColorScheme.secondary,
                    ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTab(BuildContext context) {
    bool isReadOnly = false;
    try {
      final pageAccessLevelBloc = context.read<PageAccessLevelBloc>();
      isReadOnly = !pageAccessLevelBloc.state.isLoadingLockStatus &&
          pageAccessLevelBloc.state.isReadOnly;
    } catch (_) {
      isReadOnly = false;
    }

    switch (selectedTab) {
      case ShareMenuTab.publish:
        if (isReadOnly) {
          return _buildReadonlyHint(context);
        }
        return PublishTab(
          viewName: widget.viewName,
        );
      case ShareMenuTab.exportAs:
        return const ExportTab();
      case ShareMenuTab.share:
        if (isReadOnly) {
          return _buildReadonlyHint(context);
        }
        final workspace =
            context.read<UserWorkspaceBloc>().state.currentWorkspace;
        final workspaceId = workspace?.workspaceId ??
            context.read<ShareBloc>().state.workspaceId;
        final pageId = context.read<ShareBloc>().state.viewId;
        // final isInProPlan = context
        //         .read<UserWorkspaceBloc>()
        //         .state
        //         .workspaceSubscriptionInfo
        //         ?.plan ==
        //     WorkspacePlanPB.StandPlan;

        return share_section.ShareTab(
          workspaceId: workspaceId,
          pageId: pageId,
          workspaceName: workspace?.name ?? '',
          workspaceIcon: workspace?.icon ?? '',
          isInProPlan: false,//isInProPlan,
          onUpgradeToPro: () {
            // widget.onClose();
            // _showUpgradeToProDialog(context);
          },
        );
    }
  }

  Widget _buildReadonlyHint(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: theme.spacing.m,
        vertical: theme.spacing.m,
      ),
      decoration: BoxDecoration(
        color: theme.surfaceContainerColorScheme.layer01,
        borderRadius: BorderRadius.circular(10),
      ),
      child: FlowyText.regular(
        '该文档为接收的只读发布内容，不能再次共享或发布。',
        color: theme.textColorScheme.secondary,
      ),
    );
  }

  void _showUpgradeToProDialog(BuildContext context) {
    final state = context.read<UserWorkspaceBloc>().state;
    final workspace = state.currentWorkspace;
    if (workspace == null) {
      Log.error('workspace is null');
      return;
    }

    final workspaceId = workspace.workspaceId;
    final subscriptionInfo = state.workspaceSubscriptionInfo;
    final userProfile = state.userProfile;
    if (subscriptionInfo == null) {
      Log.error('subscriptionInfo is null');
      return;
    }

    final role = workspace.role;
    final title = switch (role) {
      AFRolePB.Owner =>
        LocaleKeys.shareTab_upgradeToInviteGuest_title_owner.tr(),
      AFRolePB.Member =>
        LocaleKeys.shareTab_upgradeToInviteGuest_title_member.tr(),
      AFRolePB.Guest ||
      _ =>
        LocaleKeys.shareTab_upgradeToInviteGuest_title_guest.tr(),
    };
    final description = switch (role) {
      AFRolePB.Owner =>
        LocaleKeys.shareTab_upgradeToInviteGuest_description_owner.tr(),
      AFRolePB.Member =>
        LocaleKeys.shareTab_upgradeToInviteGuest_description_member.tr(),
      AFRolePB.Guest ||
      _ =>
        LocaleKeys.shareTab_upgradeToInviteGuest_description_guest.tr(),
    };
    final style = switch (role) {
      AFRolePB.Owner => ConfirmPopupStyle.cancelAndOk,
      AFRolePB.Member || AFRolePB.Guest || _ => ConfirmPopupStyle.onlyOk,
    };
    final confirmLabel = switch (role) {
      AFRolePB.Owner => LocaleKeys.shareTab_upgrade.tr(),
      AFRolePB.Member || AFRolePB.Guest || _ => LocaleKeys.button_ok.tr(),
    };

    if (role == AFRolePB.Owner) {
      showDialog(
        context: context,
        builder: (_) => BlocProvider<SettingsPlanBloc>(
          create: (_) => SettingsPlanBloc(
            workspaceId: workspaceId,
            userId: userProfile.id,
          )..add(const SettingsPlanEvent.started()),
          child: SettingsPlanComparisonDialog(
            workspaceId: workspaceId,
            subscriptionInfo: subscriptionInfo,
          ),
        ),
      );
    } else {
      showConfirmDialog(
        context: Navigator.of(context, rootNavigator: true).context,
        title: title,
        description: description,
        style: style,
        confirmLabel: confirmLabel,
        confirmButtonColor: Theme.of(context).colorScheme.primary,
        onConfirm: (context) {
          // fixme: show the upgrade to pro dialog
        },
      );
    }
  }
}

class _Segment extends StatefulWidget {
  const _Segment({
    required this.tab,
    required this.isSelected,
    required this.selectedTextColor,
    required this.unselectedTextColor,
  });

  final bool isSelected;
  final ShareMenuTab tab;
  final Color selectedTextColor;
  final Color unselectedTextColor;

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment> {
  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    final textStyle = theme.textStyle.body.enhanced(
      weight: widget.isSelected ? FontWeight.w600 : FontWeight.w500,
      color: widget.isSelected ? widget.selectedTextColor : widget.unselectedTextColor,
    );

    Widget child = Text(
      widget.tab.i18n,
      textAlign: TextAlign.center,
      style: textStyle,
    );

    if (widget.tab == ShareMenuTab.publish) {
      final isPublished = context.watch<ShareBloc>().state.isPublished;
      // show checkmark icon if published
      if (isPublished) {
        child = Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const FlowySvg(
              FlowySvgs.published_checkmark_s,
              blendMode: null,
            ),
            const HSpace(6),
            child,
          ],
        );
      }
    }

    return child;
  }
}
