import 'package:appflowy/plugins/shared/share/share_menu.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:flutter/material.dart';

class ShareSettingsDialog extends StatelessWidget {
  const ShareSettingsDialog({
    super.key,
    required this.tabs,
    required this.viewName,
  });

  final List<ShareMenuTab> tabs;
  final String viewName;

  @override
  Widget build(BuildContext context) {
    final effectiveTabs = tabs.isEmpty ? [ShareMenuTab.share] : tabs;
    final maxHeight = MediaQuery.of(context).size.height * 0.65;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark
        ? const Color(0xFF1F1F1F)
        : Theme.of(context).dialogBackgroundColor;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Theme.of(context).dividerColor.withValues(alpha: 0.12);

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: dialogBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HomeRadii.dialog),
        side: BorderSide(color: borderColor),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: HomeSizes.okCancelDialogMaxWidth,
          maxHeight: maxHeight,
        ),
        child: SizedBox(
          width: 560,
          child: Column(
            children: [
              _DialogHeader(
                onClose: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 24,
                  ),
                  child: ShareMenu(
                    tabs: effectiveTabs,
                    viewName: viewName,
                    onClose: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({
    required this.onClose,
  });

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconBg = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      child: Row(
        children: [
          const SizedBox(width: 36),
          Expanded(
            child: Center(
              child: Text(
                '分享设置',
                style: titleStyle ??
                    const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
          IconButton(
            style: IconButton.styleFrom(
              backgroundColor: iconBg,
              hoverColor: iconBg,
              minimumSize: const Size.square(36),
            ),
            icon: const Icon(Icons.close, size: 18),
            splashRadius: 18,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}
