import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

enum MobileAppBarLeadingType {
  back,
  cancel,
  close,
}

class MobileAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool showBackButton;
  final VoidCallback? onBackPressed;
  final bool showDivider;
  final MobileAppBarLeadingType leadingType;
  final bool centerTitle;

  const MobileAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.showBackButton = true,
    this.onBackPressed,
    this.showDivider = true,
    this.leadingType = MobileAppBarLeadingType.back,
    this.centerTitle = false,
  });

  @override
  Size get preferredSize => const Size.fromHeight(44);

  @override
  Widget build(BuildContext context) {
    final afTheme = AppFlowyTheme.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      bottom: false,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          border: showDivider
              ? Border(
                  bottom: BorderSide(
                    color: theme.dividerColor.withValues(alpha: 0.5),
                    width: 0.5,
                  ),
                )
              : null,
        ),
        child: Row(
          children: [
            if (leading != null)
              leading!
            else if (showBackButton)
              _buildLeading(context),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                title,
                style: afTheme.textStyle.heading4.standard(
                  color: afTheme.textColorScheme.primary,
                ),
                textAlign: centerTitle ? TextAlign.center : TextAlign.center,
              ),
            ),
            if (actions != null) ...actions! else const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildLeading(BuildContext context) {
    switch (leadingType) {
      case MobileAppBarLeadingType.back:
        return IconButton(
          onPressed: onBackPressed ?? () => Navigator.pop(context),
          icon: FlowySvg(
            FlowySvgs.m_app_bar_back_s,
            size: const Size(7, 12),
            color: AppFlowyTheme.of(context).iconColorScheme.primary,
          ),
        );
      case MobileAppBarLeadingType.cancel:
        return GestureDetector(
          onTap: onBackPressed ?? () => Navigator.pop(context),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: FlowyText(
              LocaleKeys.button_cancel.tr(),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      case MobileAppBarLeadingType.close:
        return IconButton(
          onPressed: onBackPressed ?? () => Navigator.pop(context),
          icon: FlowySvg(
            FlowySvgs.m_app_bar_close_s,
            color: AppFlowyTheme.of(context).iconColorScheme.primary,
          ),
        );
    }
  }
}
