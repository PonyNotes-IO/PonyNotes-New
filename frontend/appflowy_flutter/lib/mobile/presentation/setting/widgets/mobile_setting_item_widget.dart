import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

class MobileSettingItem extends StatelessWidget {
  const MobileSettingItem({
    super.key,
    this.name,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    this.trailing,
    this.leadingIcon,
    this.title,
    this.subtitle,
    this.onTap,
  });

  final String? name;
  final EdgeInsets padding;
  final Widget? trailing;
  final Widget? leadingIcon;
  final Widget? subtitle;
  final VoidCallback? onTap;
  final Widget? title;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    final splashColor = isLightMode
        ? Colors.black.withValues(alpha: 0.04)
        : Colors.white.withValues(alpha: 0.08);
    final highlightColor = isLightMode
        ? Colors.black.withValues(alpha: 0.02)
        : Colors.white.withValues(alpha: 0.04);

    return Padding(
      padding: padding,
      child: Material(
        color: theme.surfaceColorScheme.layer01,
        child: InkWell(
          onTap: onTap,
          splashColor: splashColor,
          highlightColor: highlightColor,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.zero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (leadingIcon != null) ...[
                      leadingIcon!,
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: title ?? _buildDefaultTitle(context, name),
                    ),
                    if (trailing != null) trailing!,
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  DefaultTextStyle(
                    style: theme.textStyle.body.standard(
                      color: theme.textColorScheme.secondary,
                    ),
                    child: subtitle!,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultTitle(BuildContext context, String? name) {
    final theme = AppFlowyTheme.of(context);
    return Text(
      name ?? '',
      style: theme.textStyle.heading4.standard(
        color: theme.textColorScheme.primary,
      ),
      overflow: TextOverflow.ellipsis,
    );
  }
}
