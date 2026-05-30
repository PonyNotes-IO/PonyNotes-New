import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

class UpgradePlanCard extends StatelessWidget {
  const UpgradePlanCard({
    super.key,
    required this.planName,
    required this.priceMonthly,
    required this.priceAnnual,
    required this.storage,
    required this.workspaces,
    required this.aiQuota,
    required this.priceColor,
    required this.priceBgColor,
    this.priceColor2,
    this.isHighlighted = false,
    this.isYearly = true,
    this.isSelected = false,
    required this.onTap,
  });

  final String planName;
  final String priceMonthly;
  final String priceAnnual;
  final String storage;
  final String workspaces;
  final String aiQuota;
  final Color priceColor;
  final Color priceBgColor;
  final Color? priceColor2;
  final bool isHighlighted;
  final bool isYearly;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 160,
        child: Container(
          decoration: BoxDecoration(
            color: isSelected
                ? (Theme.of(context).brightness == Brightness.light
                    ? const Color(0xFFFFF7F2)
                    : theme.surfaceColorScheme.layer02)
                : theme.surfaceColorScheme.layer01,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : theme.borderColorScheme.primary,
              width: isSelected ? 1.6 : 1.0,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                planName,
                style: theme.textStyle.heading4.standard(
                  color: theme.textColorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              _buildPriceBox(theme),
              const SizedBox(height: 8),
              _buildFeatureRow(theme, isYearly ? '每年存储空间' : '每月存储空间', storage),
              const SizedBox(height: 4),
              _buildFeatureRow(theme, '工作区限制', workspaces),
              const SizedBox(height: 4),
              _buildFeatureRow(theme, isYearly ? '每年AI对话额度' : '每月AI对话额度', aiQuota),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPriceBox(AppFlowyThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: priceBgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: isYearly ? priceAnnual : priceMonthly,
                  style: theme.textStyle.heading2.standard(
                    color: priceColor,
                  ),
                ),
                TextSpan(
                  text: isYearly ? '/年' : '/月',
                  style: theme.textStyle.body.standard(
                    color: priceColor.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            isYearly ? '按年支付' : '按月支付',
            style: theme.textStyle.body
                .standard(color: priceColor.withValues(alpha: 0.7))
                .copyWith(fontSize: 12.0),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(AppFlowyThemeData theme, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: theme.textColorScheme.secondary,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '$label $value',
            style: theme.textStyle.body
                .standard(color: theme.textColorScheme.secondary)
                .copyWith(fontSize: 12.0),
          ),
        ),
      ],
    );
  }
}
