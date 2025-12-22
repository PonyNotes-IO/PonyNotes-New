import 'package:appflowy/plugins/shared/share/share_menu.dart';
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

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: maxHeight,
        ),
        child: SizedBox(
          width: 540,
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              _DialogHeader(
                onClose: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      child: Row(
        children: [
          // 左侧占位，保证标题整体居中
          const SizedBox(width: 24),
          Expanded(
            child: Center(
              child: Text(
                '共享设置',
                style: titleStyle ??
                    const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
          // 右上角关闭按钮
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            splashRadius: 18,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

