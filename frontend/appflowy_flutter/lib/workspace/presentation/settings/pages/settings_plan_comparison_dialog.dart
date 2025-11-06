import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/shared/loading.dart';
import 'package:appflowy/util/theme_extension.dart';
import 'package:appflowy/workspace/application/settings/plan/settings_plan_bloc.dart';
import 'package:appflowy/workspace/application/settings/plan/workspace_subscription_ext.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/shared_widget.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/cancel_plan_survey_dialog.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../generated/locale_keys.g.dart';

class SettingsPlanComparisonDialog extends StatefulWidget {
  const SettingsPlanComparisonDialog({
    super.key,
    required this.workspaceId,
    required this.subscriptionInfo,
  });

  final String workspaceId;
  final WorkspaceSubscriptionInfoPB subscriptionInfo;

  @override
  State<SettingsPlanComparisonDialog> createState() =>
      _SettingsPlanComparisonDialogState();
}

class _SettingsPlanComparisonDialogState
    extends State<SettingsPlanComparisonDialog> {
  final horizontalController = ScrollController();
  final verticalController = ScrollController();

  late WorkspaceSubscriptionInfoPB currentInfo = widget.subscriptionInfo;

  Loading? loadingIndicator;

  @override
  void dispose() {
    horizontalController.dispose();
    verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLM = Theme.of(context).isLightMode;

    return BlocConsumer<SettingsPlanBloc, SettingsPlanState>(
      listener: (context, state) {
        final readyState = state.mapOrNull(ready: (state) => state);

        if (readyState == null) {
          return;
        }

        if (readyState.downgradeProcessing) {
          loadingIndicator = Loading(context)..start();
        } else {
          loadingIndicator?.stop();
          loadingIndicator = null;
        }

        if (readyState.successfulPlanUpgrade != null) {
          showConfirmDialog(
            context: context,
            title: LocaleKeys.settings_comparePlanDialog_paymentSuccess_title
                .tr(args: [readyState.successfulPlanUpgrade!.label]),
            description: LocaleKeys
                .settings_comparePlanDialog_paymentSuccess_description
                .tr(args: [readyState.successfulPlanUpgrade!.label]),
            confirmLabel: LocaleKeys.button_close.tr(),
            onConfirm: (_) {},
          );
        }

        setState(() => currentInfo = readyState.subscriptionInfo);
      },
      builder: (context, state) => FlowyDialog(
        constraints: const BoxConstraints(maxWidth: 784, minWidth: 674),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 24, left: 24, right: 24),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FlowyText.semibold(
                    LocaleKeys.settings_comparePlanDialog_title.tr(),
                    fontSize: 24,
                    color: AFThemeExtension.of(context).strongText,
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(
                      currentInfo.plan != widget.subscriptionInfo.plan,
                    ),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: FlowySvg(
                        FlowySvgs.m_close_m,
                        size: const Size.square(20),
                        color: AFThemeExtension.of(context).strongText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const VSpace(16),
            Flexible(
              child: SingleChildScrollView(
                controller: horizontalController,
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  controller: verticalController,
                  padding: const EdgeInsets.only(
                    left: 24,
                    right: 24,
                    bottom: 24,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 250,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const VSpace(30),
                                SizedBox(
                                  height: 116,
                                  child: FlowyText.semibold(
                                    LocaleKeys
                                        .settings_comparePlanDialog_planFeatures
                                        .tr(),
                                    fontSize: 24,
                                    maxLines: 2,
                                    color: isLM
                                        ? const Color(0xFF5C3699)
                                        : const Color(0xFFE8E0FF),
                                  ),
                                ),
                                const SizedBox(height: 116),
                                const SizedBox(height: 56),
                                ..._planLabels.map(
                                  (e) => _ComparisonCell(
                                    label: e.label,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _PlanTable(
                            title: LocaleKeys
                                .settings_comparePlanDialog_freePlan_title
                                .tr(),
                            description: LocaleKeys
                                .settings_comparePlanDialog_freePlan_description
                                .tr(),
                            price: LocaleKeys
                                .settings_comparePlanDialog_freePlan_price
                                .tr(
                              args: [
                                SubscriptionPlanPB.Free.priceMonthBilling,
                              ],
                            ),
                            priceInfo: LocaleKeys
                                .settings_comparePlanDialog_freePlan_priceInfo
                                .tr(),
                            cells: _freeLabels,
                            isCurrent:
                                currentInfo.plan == WorkspacePlanPB.FreePlan,
                            buttonType: WorkspacePlanPB.FreePlan.buttonTypeFor(
                              currentInfo.plan,
                            ),
                            onSelected: () async {
                              if (currentInfo.plan ==
                                      WorkspacePlanPB.FreePlan ||
                                  currentInfo.isCanceled) {
                                return;
                              }

                              final reason =
                                  await showCancelSurveyDialog(context);
                              if (reason == null || !context.mounted) {
                                return;
                              }

                              await showConfirmDialog(
                                context: context,
                                title: LocaleKeys
                                    .settings_comparePlanDialog_downgradeDialog_title
                                    .tr(args: [currentInfo.label]),
                                description: LocaleKeys
                                    .settings_comparePlanDialog_downgradeDialog_description
                                    .tr(),
                                confirmLabel: LocaleKeys
                                    .settings_comparePlanDialog_downgradeDialog_downgradeLabel
                                    .tr(),
                                style: ConfirmPopupStyle.cancelAndOk,
                                onConfirm: (_) =>
                                    context.read<SettingsPlanBloc>().add(
                                          SettingsPlanEvent.cancelSubscription(
                                            reason: reason,
                                          ),
                                        ),
                              );
                            },
                          ),
                          _PlanTable(
                            title: '学生版',
                            description: '适合学生使用的经济实惠方案',
                            price: '¥30/年',
                            priceInfo: '或 ¥3/月',
                            cells: _studentLabels,
                            isCurrent:
                                currentInfo.plan == WorkspacePlanPB.StudentPlan,
                            buttonType: WorkspacePlanPB.StudentPlan.buttonTypeFor(
                              currentInfo.plan,
                            ),
                            onSelected: () =>
                                context.read<SettingsPlanBloc>().add(
                                      const SettingsPlanEvent.addSubscription(
                                        SubscriptionPlanPB.Student,
                                      ),
                                    ),
                          ),
                          _PlanTable(
                            title: '标准版',
                            description: '适合个人和小团队的标准方案',
                            price: '¥80/年',
                            priceInfo: '或 ¥8/月',
                            cells: _standardLabels,
                            isCurrent:
                                currentInfo.plan == WorkspacePlanPB.StandardPlan,
                            buttonType: WorkspacePlanPB.StandardPlan.buttonTypeFor(
                              currentInfo.plan,
                            ),
                            onSelected: () =>
                                context.read<SettingsPlanBloc>().add(
                                      const SettingsPlanEvent.addSubscription(
                                        SubscriptionPlanPB.Standard,
                                      ),
                                    ),
                          ),
                          _PlanTable(
                            title: '团队版',
                            description: '适合团队协作的专业方案',
                            price: '¥180/年',
                            priceInfo: '或 ¥18/月',
                            cells: _teamLabels,
                            isCurrent:
                                currentInfo.plan == WorkspacePlanPB.TeamPlan,
                            buttonType: WorkspacePlanPB.TeamPlan.buttonTypeFor(
                              currentInfo.plan,
                            ),
                            onSelected: () =>
                                context.read<SettingsPlanBloc>().add(
                                      const SettingsPlanEvent.addSubscription(
                                        SubscriptionPlanPB.Team,
                                      ),
                                    ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _PlanButtonType {
  none,
  upgrade,
  downgrade;

  bool get isDowngrade => this == downgrade;
  bool get isUpgrade => this == upgrade;
}

extension _ButtonTypeFrom on WorkspacePlanPB {
  /// Returns the button type for the given plan, taking the
  /// current plan as [other].
  ///
  _PlanButtonType buttonTypeFor(WorkspacePlanPB other) {
    /// Current plan, no action
    if (this == other) {
      return _PlanButtonType.none;
    }

    // Compare plan levels: Free=0, Student=1, Standard=2, Team=3
    final thisLevel = _planLevel(this);
    final otherLevel = _planLevel(other);

    // If target plan level is lower than current plan, it's a downgrade
    if (thisLevel < otherLevel) {
      return _PlanButtonType.downgrade;
    }

    // Otherwise it's an upgrade
    return _PlanButtonType.upgrade;
  }
}

/// Returns the numeric level of a plan for comparison
/// Free=0, Student=1, Standard=2, Team=3
int _planLevel(WorkspacePlanPB plan) {
  return switch (plan) {
    WorkspacePlanPB.FreePlan => 0,
    WorkspacePlanPB.StudentPlan => 1,
    WorkspacePlanPB.StandardPlan => 2,
    WorkspacePlanPB.TeamPlan => 3,
    _ => 0, // Default to Free plan level for unknown plans
  };
}

class _PlanTable extends StatelessWidget {
  const _PlanTable({
    required this.title,
    required this.description,
    required this.price,
    required this.priceInfo,
    required this.cells,
    required this.isCurrent,
    required this.onSelected,
    this.buttonType = _PlanButtonType.none,
  });

  final String title;
  final String description;
  final String price;
  final String priceInfo;

  final List<_CellItem> cells;
  final bool isCurrent;
  final VoidCallback onSelected;
  final _PlanButtonType buttonType;

  @override
  Widget build(BuildContext context) {
    final highlightPlan = !isCurrent && buttonType == _PlanButtonType.upgrade;
    final isLM = Theme.of(context).isLightMode;

    return Container(
      width: 215,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: !highlightPlan
            ? null
            : LinearGradient(
                colors: [
                  isLM ? const Color(0xFF251D37) : const Color(0xFF7459AD),
                  isLM ? const Color(0xFF7547C0) : const Color(0xFFDDC8FF),
                ],
              ),
      ),
      padding: !highlightPlan
          ? const EdgeInsets.only(top: 4)
          : const EdgeInsets.all(4),
      child: Container(
        padding: isCurrent
            ? const EdgeInsets.only(bottom: 22)
            : const EdgeInsets.symmetric(vertical: 22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: Theme.of(context).cardColor,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isCurrent) const _CurrentBadge(),
            const VSpace(4),
            _Heading(
              title: title,
              description: description,
              isPrimary: !highlightPlan,
            ),
            _Heading(
              title: price,
              description: priceInfo,
              isPrimary: !highlightPlan,
            ),
            if (buttonType == _PlanButtonType.none) ...[
              const SizedBox(height: 56),
            ] else ...[
              Opacity(
                opacity: 1,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 12 + (buttonType.isUpgrade ? 12 : 0),
                  ),
                  child: _ActionButton(
                    label: buttonType.isUpgrade
                        ? LocaleKeys.settings_comparePlanDialog_actions_upgrade
                            .tr()
                        : LocaleKeys
                            .settings_comparePlanDialog_actions_downgrade
                            .tr(),
                    onPressed: onSelected,
                    isUpgrade: buttonType.isUpgrade,
                    useGradientBorder: buttonType.isUpgrade,
                  ),
                ),
              ),
            ],
            ...cells.map(
              (cell) => _ComparisonCell(
                label: cell.label,
                icon: cell.icon,
                isHighlighted: highlightPlan,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentBadge extends StatelessWidget {
  const _CurrentBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 12),
      height: 22,
      width: 72,
      decoration: BoxDecoration(
        color: Theme.of(context).isLightMode
            ? const Color(0xFF4F3F5F)
            : const Color(0xFFE8E0FF),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: FlowyText.medium(
          LocaleKeys.settings_comparePlanDialog_current.tr(),
          fontSize: 12,
          color: Theme.of(context).isLightMode ? Colors.white : Colors.black,
        ),
      ),
    );
  }
}

class _ComparisonCell extends StatelessWidget {
  const _ComparisonCell({
    this.label,
    this.icon,
    this.isHighlighted = false,
  });

  final String? label;
  final FlowySvgData? icon;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12) +
          EdgeInsets.only(left: isHighlighted ? 12 : 0),
      height: 36,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            FlowySvg(
              icon!,
              color: AFThemeExtension.of(context).strongText,
            ),
          ] else if (label != null) ...[
            Expanded(
              child: FlowyText.medium(
                label!,
                lineHeight: 1.2,
                color: AFThemeExtension.of(context).strongText,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onPressed,
    required this.isUpgrade,
    this.useGradientBorder = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isUpgrade;
  final bool useGradientBorder;

  @override
  Widget build(BuildContext context) {
    final isLM = Theme.of(context).isLightMode;

    return SizedBox(
      height: 56,
      child: Row(
        children: [
          GestureDetector(
            onTap: onPressed,
            child: MouseRegion(
              cursor: onPressed != null
                  ? SystemMouseCursors.click
                  : MouseCursor.defer,
              child: _drawBorder(
                context,
                isLM: isLM,
                isUpgrade: isUpgrade,
                child: Container(
                  height: 36,
                  width: 148,
                  decoration: BoxDecoration(
                    color: useGradientBorder
                        ? Theme.of(context).cardColor
                        : Colors.transparent,
                    border: Border.all(color: Colors.transparent),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(child: _drawText(label, isLM, isUpgrade)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _drawText(String text, bool isLM, bool isUpgrade) {
    final child = FlowyText(
      text,
      fontSize: 14,
      lineHeight: 1.2,
      fontWeight: useGradientBorder ? FontWeight.w600 : FontWeight.w500,
      color: isUpgrade ? const Color(0xFFC49BEC) : null,
    );

    if (!useGradientBorder || !isLM) {
      return child;
    }

    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => const LinearGradient(
        transform: GradientRotation(-1.55),
        stops: [0.4, 1],
        colors: [Color(0xFF251D37), Color(0xFF7547C0)],
      ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
      child: child,
    );
  }

  Widget _drawBorder(
    BuildContext context, {
    required bool isLM,
    required bool isUpgrade,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        gradient: isUpgrade
            ? LinearGradient(
                transform: const GradientRotation(-1.2),
                stops: const [0.4, 1],
                colors: [
                  isLM ? const Color(0xFF251D37) : const Color(0xFF7459AD),
                  isLM ? const Color(0xFF7547C0) : const Color(0xFFDDC8FF),
                ],
              )
            : null,
        border: isUpgrade ? null : Border.all(color: const Color(0xFF333333)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({
    required this.title,
    this.description,
    this.isPrimary = true,
  });

  final String title;
  final String? description;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 185,
      height: 116,
      child: Padding(
        padding: EdgeInsets.only(left: 12 + (!isPrimary ? 12 : 0)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: FlowyText.semibold(
                    title,
                    fontSize: 24,
                    overflow: TextOverflow.ellipsis,
                    color: isPrimary
                        ? AFThemeExtension.of(context).strongText
                        : Theme.of(context).isLightMode
                            ? const Color(0xFF5C3699)
                            : const Color(0xFFC49BEC),
                  ),
                ),
              ],
            ),
            if (description != null && description!.isNotEmpty) ...[
              const VSpace(4),
              Flexible(
                child: FlowyText.regular(
                  description!,
                  fontSize: 12,
                  maxLines: 5,
                  lineHeight: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlanItem {
  const _PlanItem({required this.label});

  final String label;
}

final _planLabels = [
  const _PlanItem(label: '页面/块数量'),
  const _PlanItem(label: '云存储空间'),
  const _PlanItem(label: '导入与导出'),
  const _PlanItem(label: '收件箱'),
  const _PlanItem(label: '多端同步（iPad、Mac、Windows、Web）'),
  const _PlanItem(label: '支持 API'),
  const _PlanItem(label: '版本历史'),
  const _PlanItem(label: 'AI对话'),
  const _PlanItem(label: '图片生成'),
  const _PlanItem(label: '分享链接'),
  const _PlanItem(label: '发布'),
  const _PlanItem(label: '工作区成员'),
  const _PlanItem(label: '协作工作区'),
  const _PlanItem(label: '页面权限管理'),
  const _PlanItem(label: '空间/成员管理'),
  const _PlanItem(label: '空间/成员分组'),
];

class _CellItem {
  const _CellItem({this.label, this.icon});

  final String? label;
  final FlowySvgData? icon;
}

final List<_CellItem> _freeLabels = [
  const _CellItem(label: '无限制'),  // 页面/块数量
  const _CellItem(label: '-'),       // 云存储
  const _CellItem(icon: FlowySvgs.check_m),  // 导入与导出
  const _CellItem(label: '-'),       // 收件箱
  const _CellItem(label: '-'),       // 多端同步
  const _CellItem(label: '-'),       // 支持 API
  const _CellItem(label: '-'),       // 版本历史
  const _CellItem(label: '-'),       // AI对话
  const _CellItem(label: '-'),       // 图片生成
  const _CellItem(label: '-'),       // 分享链接
  const _CellItem(label: '-'),       // 发布
  const _CellItem(label: '-'),       // 工作区成员
  const _CellItem(label: '-'),       // 协作工作区
  const _CellItem(label: '-'),       // 页面权限管理
  const _CellItem(label: '-'),       // 空间/成员管理
  const _CellItem(label: '-'),       // 空间/成员分组
];

final List<_CellItem> _studentLabels = [
  const _CellItem(label: '无限制'),  // 页面/块数量
  const _CellItem(label: '2GB'),      // 云存储
  const _CellItem(icon: FlowySvgs.check_m),  // 导入与导出
  const _CellItem(label: '-'),        // 收件箱
  const _CellItem(icon: FlowySvgs.check_m),  // 多端同步
  const _CellItem(label: '-'),        // 支持 API
  const _CellItem(label: '7天'),      // 版本历史
  const _CellItem(label: '10次/月'),  // AI对话
  const _CellItem(label: '-'),        // 图片生成
  const _CellItem(icon: FlowySvgs.check_m),  // 分享链接
  const _CellItem(icon: FlowySvgs.check_m),  // 发布
  const _CellItem(label: '2'),        // 工作区成员
  const _CellItem(label: '仅限1个'),  // 协作工作区
  const _CellItem(label: '仅查看'),   // 页面权限管理
  const _CellItem(icon: FlowySvgs.check_m),  // 空间/成员管理
  const _CellItem(label: '-'),        // 空间/成员分组
];

final List<_CellItem> _standardLabels = [
  const _CellItem(label: '无限制'),  // 页面/块数量
  const _CellItem(label: '10GB'),     // 云存储
  const _CellItem(icon: FlowySvgs.check_m),  // 导入与导出
  const _CellItem(icon: FlowySvgs.check_m),  // 收件箱
  const _CellItem(icon: FlowySvgs.check_m),  // 多端同步
  const _CellItem(icon: FlowySvgs.check_m),  // 支持 API
  const _CellItem(label: '7天'),      // 版本历史
  const _CellItem(label: '40次/月'),  // AI对话
  const _CellItem(label: '10张/月'),  // 图片生成
  const _CellItem(icon: FlowySvgs.check_m),  // 分享链接
  const _CellItem(icon: FlowySvgs.check_m),  // 发布
  const _CellItem(label: '5'),        // 工作区成员
  const _CellItem(icon: FlowySvgs.check_m),  // 协作工作区
  const _CellItem(label: '10个访客编辑'),  // 页面权限管理
  const _CellItem(icon: FlowySvgs.check_m),  // 空间/成员管理
  const _CellItem(label: '-'),        // 空间/成员分组
];

final List<_CellItem> _teamLabels = [
  const _CellItem(label: '无限制'),  // 页面/块数量
  const _CellItem(label: '20GB'),     // 云存储
  const _CellItem(icon: FlowySvgs.check_m),  // 导入与导出
  const _CellItem(icon: FlowySvgs.check_m),  // 收件箱
  const _CellItem(icon: FlowySvgs.check_m),  // 多端同步
  const _CellItem(icon: FlowySvgs.check_m),  // 支持 API
  const _CellItem(label: '30天'),     // 版本历史
  const _CellItem(label: '120次/月'), // AI对话
  const _CellItem(label: '20张/月'),  // 图片生成
  const _CellItem(icon: FlowySvgs.check_m),  // 分享链接
  const _CellItem(icon: FlowySvgs.check_m),  // 发布
  const _CellItem(label: '10'),       // 工作区成员
  const _CellItem(icon: FlowySvgs.check_m),  // 协作工作区
  const _CellItem(label: '50个访客编辑'),  // 页面权限管理
  const _CellItem(icon: FlowySvgs.check_m),  // 空间/成员管理
  const _CellItem(icon: FlowySvgs.check_m),  // 空间/成员分组
];
