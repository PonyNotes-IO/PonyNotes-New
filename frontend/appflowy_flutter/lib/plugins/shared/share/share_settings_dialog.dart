import 'package:appflowy/plugins/shared/share/share_menu.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

class ShareSettingsDialog extends StatelessWidget {
  const ShareSettingsDialog({
    super.key,
    required this.tabs,
    required this.viewName,
    this.anchor,
  });

  final List<ShareMenuTab> tabs;
  final String viewName;
  final Offset? anchor;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final size = MediaQuery.sizeOf(context);
    final position = anchor;
    final anchored = position != null && size.width >= 600;
    return Dialog(
      alignment: anchored ? Alignment.topRight : Alignment.center,
      insetPadding: anchored
          ? EdgeInsets.fromLTRB(
              16,
              (position.dy + 8).clamp(12, size.height * .25).toDouble(),
              (size.width - position.dx - 12)
                  .clamp(16, size.width - 514)
                  .toDouble(),
              16,
            )
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF262626)
          : theme.surfaceContainerColorScheme.layer01,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black.withValues(alpha: .16),
      elevation: 12,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: theme.borderColorScheme.primary.withValues(alpha: .22),
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 217, maxHeight: 560),
        child: SizedBox(
          key: const ValueKey('document-share-dialog'),
          width: 498,
          child: ShareMenu(
            tabs: tabs.isEmpty ? const [ShareMenuTab.share] : tabs,
            viewName: viewName,
            onClose: () => Navigator.of(context).maybePop(),
          ),
        ),
      ),
    );
  }
}
