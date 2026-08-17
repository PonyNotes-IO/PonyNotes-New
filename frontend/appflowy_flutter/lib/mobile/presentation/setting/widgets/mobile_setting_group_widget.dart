import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

class MobileSettingGroup extends StatelessWidget {
  const MobileSettingGroup({
    required this.groupTitle,
    required this.settingItemList,
    this.showDivider = true,
    this.showItemDivider = true,
    this.wrapInCard = false,
    super.key,
  });

  final String groupTitle;
  final List<Widget> settingItemList;
  final bool showDivider;

  /// Whether to render a thin divider between items when [wrapInCard] is true.
  final bool showItemDivider;
  final bool wrapInCard;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final isLightMode = Theme.of(context).brightness == Brightness.light;

    if (wrapInCard) {
      // Match the card style used on the mobile home page (e.g. MobileRecentView
      // and UpgradePlanCard): use theme.surfaceColorScheme.layer01, which gives a
      // visible contrast against the page background (#121212) in dark mode.
      //
      // The title is rendered inside the card at the top, matching the visual
      // style of the home page setting cards (e.g. _ThemeModeSettingItem).
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VSpace(theme.spacing.s),
          Container(
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
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (groupTitle.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Text(
                      groupTitle,
                      style: theme.textStyle.heading4.standard(
                        color: theme.textColorScheme.primary,
                      ),
                    ),
                  ),
                ...settingItemList.asMap().entries.map((entry) {
                  final i = entry.key;
                  final item = entry.value;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      item,
                      if (showItemDivider && i < settingItemList.length - 1)
                        Divider(
                          color: theme.borderColorScheme.primary
                              .withValues(alpha: 0.5),
                          height: 0.5,
                          indent: 16,
                          endIndent: 16,
                        ),
                    ],
                  );
                }),
              ],
            ),
          ),
          showDivider
              ? AFDivider(spacing: theme.spacing.m)
              : const SizedBox.shrink(),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        VSpace(theme.spacing.s),
        Text(
          groupTitle,
          style: theme.textStyle.heading4.enhanced(
            color: theme.textColorScheme.primary,
          ),
        ),
        VSpace(theme.spacing.s),
        ...settingItemList,
        showDivider
            ? AFDivider(spacing: theme.spacing.m)
            : const SizedBox.shrink(),
      ],
    );
  }
}
