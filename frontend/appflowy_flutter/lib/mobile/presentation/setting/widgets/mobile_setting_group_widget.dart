import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

class MobileSettingGroup extends StatelessWidget {
  const MobileSettingGroup({
    required this.groupTitle,
    required this.settingItemList,
    this.showDivider = true,
    this.wrapInCard = false,
    super.key,
  });

  final String groupTitle;
  final List<Widget> settingItemList;
  final bool showDivider;
  final bool wrapInCard;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final isLightMode = Theme.of(context).brightness == Brightness.light;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!wrapInCard) ...[
          VSpace(theme.spacing.s),
          Text(
            groupTitle,
            style: theme.textStyle.heading4.enhanced(
              color: theme.textColorScheme.primary,
            ),
          ),
          VSpace(theme.spacing.s),
        ],
        if (wrapInCard)
          ...settingItemList.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                item,
                if (i < settingItemList.length - 1)
                  Divider(
                    color: theme.borderColorScheme.primary
                        .withValues(alpha: 0.5),
                    height: 0.5,
                    indent: 16,
                    endIndent: 16,
                  ),
              ],
            );
          })
        else
          ...settingItemList,
        showDivider
            ? AFDivider(spacing: theme.spacing.m)
            : const SizedBox.shrink(),
      ],
    );

    if (wrapInCard) {
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
          Container(
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
            child: content,
          ),
        ],
      );
    }

    return content;
  }
}
