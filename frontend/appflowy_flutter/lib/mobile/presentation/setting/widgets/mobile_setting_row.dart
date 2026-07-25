import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

class MobileSettingRow extends StatelessWidget {
  const MobileSettingRow({
    super.key,
    required this.name,
    this.trailing,
    this.leadingIcon,
    this.onTap,
  });

  final String name;
  final Widget? trailing;
  final Widget? leadingIcon;
  final VoidCallback? onTap;

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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: splashColor,
        highlightColor: highlightColor,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              if (leadingIcon != null) ...[
                leadingIcon!,
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  name,
                  style: theme.textStyle.heading4.standard(
                    color: theme.textColorScheme.primary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}
