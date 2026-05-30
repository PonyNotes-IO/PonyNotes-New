import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/workspace/application/settings/plan/workspace_subscription_ext.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

import 'mobile_upgrade_plan_card.dart';

enum _BillingPeriod { monthly, yearly }

class MobileUpgradePlanPage extends StatefulWidget {
  const MobileUpgradePlanPage({
    super.key,
    required this.subscriptionInfo,
    required this.workspaceId,
  });

  final WorkspaceSubscriptionInfoPB? subscriptionInfo;
  final String workspaceId;

  @override
  State<MobileUpgradePlanPage> createState() => _MobileUpgradePlanPageState();
}

class _MobileUpgradePlanPageState extends State<MobileUpgradePlanPage> {
  _BillingPeriod _billingPeriod = _BillingPeriod.monthly;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _buildAppBar(theme),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _UpgradePlanBody(
                subscriptionInfo: widget.subscriptionInfo,
                billingPeriod: _billingPeriod,
                onBillingPeriodChanged: (period) {
                  setState(() => _billingPeriod = period);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(AppFlowyThemeData theme) {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: FlowySvg(
                FlowySvgs.mobile_return_s,
                size: const Size(7, 12),
                color: theme.iconColorScheme.primary,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '会员升级',
                style: theme.textStyle.heading4.standard(
                  color: theme.textColorScheme.primary,
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
}

class _UpgradePlanBody extends StatefulWidget {
  const _UpgradePlanBody({
    required this.subscriptionInfo,
    required this.billingPeriod,
    required this.onBillingPeriodChanged,
  });

  final WorkspaceSubscriptionInfoPB? subscriptionInfo;
  final _BillingPeriod billingPeriod;
  final void Function(_BillingPeriod) onBillingPeriodChanged;

  @override
  State<_UpgradePlanBody> createState() => _UpgradePlanBodyState();
}

class _UpgradePlanBodyState extends State<_UpgradePlanBody> {
  int _selectedPlanIndex = 2; // 默认选中专业版（第3个）

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 12, bottom: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBillingToggle(theme),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '手机 / 电脑 / 平板 均可使用',
                  style: theme.textStyle.body.standard(
                    color: theme.textColorScheme.secondary,
                  ).copyWith(fontSize: 12),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '充值记录',
                    style: theme.textStyle.body.standard(
                      color: theme.textColorScheme.secondary,
                    ).copyWith(fontSize: 12),
                  ),
                  const SizedBox(width: 4),
                  FlowySvg(
                    FlowySvgs.top_up_records_s,
                    size: const Size(4, 8),
                    color: theme.iconColorScheme.secondary,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildUpgradePlanCards(),
          const SizedBox(height: 24),
          _buildBenefitIcons(),
        ],
      ),
    );
  }

  Widget _buildUpgradePlanCards() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          UpgradePlanCard(
            planName: '学生版',
            priceMonthly: '¥5',
            priceAnnual: '¥50',
            storage: '1GB',
            workspaces: '3个',
            aiQuota: '50次/月',
            priceColor: const Color(0xFFFFFFFF),
            priceBgColor: const Color(0xFF2EACB2),
            isYearly: widget.billingPeriod == _BillingPeriod.yearly,
            isSelected: _selectedPlanIndex == 0,
            onTap: () => setState(() => _selectedPlanIndex = 0),
          ),
          const SizedBox(width: 12),
          UpgradePlanCard(
            planName: '标准版',
            priceMonthly: '¥9',
            priceAnnual: '¥99',
            storage: '10GB',
            workspaces: '5个工作区',
            aiQuota: '300次/月',
            priceColor: const Color(0xFFF9D8A7),
            priceBgColor: const Color(0xFF343543),
            priceColor2: Colors.white,
            isYearly: widget.billingPeriod == _BillingPeriod.yearly,
            isSelected: _selectedPlanIndex == 1,
            onTap: () => setState(() => _selectedPlanIndex = 1),
          ),
          const SizedBox(width: 12),
          UpgradePlanCard(
            planName: '专业版',
            priceMonthly: '¥15',
            priceAnnual: '¥158',
            storage: '50GB',
            workspaces: '10个工作区',
            aiQuota: '1200次/月',
            priceColor: const Color(0xFFFFE4C4),
            priceBgColor: const Color(0xFF371A0D),
            priceColor2: const Color(0xFFF9D8A7),
            isHighlighted: true,
            isYearly: widget.billingPeriod == _BillingPeriod.yearly,
            isSelected: _selectedPlanIndex == 2,
            onTap: () => setState(() => _selectedPlanIndex = 2),
          ),
          const SizedBox(width: 12),
          UpgradePlanCard(
            planName: '高级版',
            priceMonthly: '¥29',
            priceAnnual: '¥298',
            storage: '150GB',
            workspaces: '18个工作区',
            aiQuota: '3000次/月',
            priceColor: const Color(0xFFADD8E6),
            priceBgColor: const Color(0xFF1E3A5F),
            priceColor2: const Color(0xFFF9D8A7),
            isYearly: widget.billingPeriod == _BillingPeriod.yearly,
            isSelected: _selectedPlanIndex == 3,
            onTap: () => setState(() => _selectedPlanIndex = 3),
          ),
        ],
      ),
    );
  }

  Widget _buildBillingToggle(AppFlowyThemeData theme) {
    final isYearly = widget.billingPeriod == _BillingPeriod.yearly;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF2A2A2A)
            : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => widget.onBillingPeriodChanged(_BillingPeriod.monthly),
              child: Container(
                decoration: BoxDecoration(
                  color: !isYearly
                      ? (isDarkMode
                          ? const Color(0xFF3A3A3A)
                          : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: !isYearly
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  '月付',
                  style: theme.textStyle.body.standard(
                    color: !isYearly
                        ? theme.textColorScheme.primary
                        : theme.textColorScheme.secondary,
                  ).copyWith(fontWeight: !isYearly ? FontWeight.w600 : FontWeight.normal),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => widget.onBillingPeriodChanged(_BillingPeriod.yearly),
              child: Container(
                decoration: BoxDecoration(
                  color: isYearly
                      ? (isDarkMode
                          ? const Color(0xFF3A3A3A)
                          : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: isYearly
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '年付',
                      style: theme.textStyle.body.standard(
                        color: isYearly
                            ? theme.textColorScheme.primary
                            : theme.textColorScheme.secondary,
                      ).copyWith(fontWeight: isYearly ? FontWeight.w600 : FontWeight.normal),
                    ),
                    if (isYearly) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6B6B),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '省15%',
                          style: theme.textStyle.body.standard(color: Colors.white).copyWith(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBenefitIcons() {
    final theme = AppFlowyTheme.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final benefits = [
      {'label': '小马AI', 'iconLight': FlowySvgs.m_rights_ai_xl, 'iconDark': FlowySvgs.md_rights_ai_xl},
      {'label': '小马日历', 'iconLight': FlowySvgs.m_rights_calender_xl, 'iconDark': FlowySvgs.md_rights_calender_xl},
      {'label': '云端同步', 'iconLight': FlowySvgs.m_rights_cloud_xl, 'iconDark': FlowySvgs.md_rights_cloud_xl},
      {'label': '小马收藏夹', 'iconLight': FlowySvgs.m_rights_collect_xl, 'iconDark': FlowySvgs.md_rights_collect_xl},
      {'label': '云端空间', 'iconLight': FlowySvgs.m_rights_storage_xl, 'iconDark': FlowySvgs.md_rights_storage_xl},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '获赠权益',
          style: theme.textStyle.body
              .standard(color: theme.textColorScheme.primary)
              .copyWith(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _BenefitCard(label: benefits[0]['label'] as String, icon: isDarkMode ? benefits[0]['iconDark'] as FlowySvgData : benefits[0]['iconLight'] as FlowySvgData, isDarkMode: isDarkMode, theme: theme)),
            const SizedBox(width: 8),
            Expanded(child: _BenefitCard(label: benefits[1]['label'] as String, icon: isDarkMode ? benefits[1]['iconDark'] as FlowySvgData : benefits[1]['iconLight'] as FlowySvgData, isDarkMode: isDarkMode, theme: theme)),
            const SizedBox(width: 8),
            Expanded(child: _BenefitCard(label: benefits[2]['label'] as String, icon: isDarkMode ? benefits[2]['iconDark'] as FlowySvgData : benefits[2]['iconLight'] as FlowySvgData, isDarkMode: isDarkMode, theme: theme)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _BenefitCard(label: benefits[3]['label'] as String, icon: isDarkMode ? benefits[3]['iconDark'] as FlowySvgData : benefits[3]['iconLight'] as FlowySvgData, isDarkMode: isDarkMode, theme: theme)),
            const SizedBox(width: 8),
            Expanded(child: _BenefitCard(label: benefits[4]['label'] as String, icon: isDarkMode ? benefits[4]['iconDark'] as FlowySvgData : benefits[4]['iconLight'] as FlowySvgData, isDarkMode: isDarkMode, theme: theme)),
          ],
        ),
      ],
    );
  }
}

class _BenefitCard extends StatelessWidget {
  const _BenefitCard({
    required this.label,
    required this.icon,
    required this.isDarkMode,
    required this.theme,
  });

  final String label;
  final FlowySvgData icon;
  final bool isDarkMode;
  final AppFlowyThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: theme.surfaceColorScheme.layer01,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.borderColorScheme.primary, width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FlowySvg(icon, size: const Size(32, 32), blendMode: null),
          Expanded(
            child: Text(
              label,
              style: theme.textStyle.body.standard(color: theme.textColorScheme.secondary).copyWith(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
