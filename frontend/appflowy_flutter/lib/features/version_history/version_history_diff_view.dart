import 'package:appflowy/features/version_history/version_history_diff.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class HistoryDiffView extends StatelessWidget {
  const HistoryDiffView({super.key, required this.difference});
  final HistoryDiff difference;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final removed = dark ? const Color(0xFFFFB4AB) : const Color(0xFF9C2020);
    final added = dark ? const Color(0xFF8DD9A1) : const Color(0xFF196B35);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 20,
            runSpacing: 8,
            children: [
              Text(
                '− ${'versionHistory.currentContent'.tr()} (${difference.removed})',
                style: TextStyle(color: removed),
              ),
              Text(
                '+ ${'versionHistory.restoredContent'.tr()} (${difference.added})',
                style: TextStyle(color: added),
              ),
            ],
          ),
        ),
        if (!difference.hasChanges)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text('versionHistory.noChanges'.tr()),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: difference.lines.length,
            itemBuilder: (context, index) {
              final line = difference.lines[index];
              final color = switch (line.change) {
                HistoryChange.added => added,
                HistoryChange.removed => removed,
                HistoryChange.unchanged => theme.colorScheme.onSurface,
              };
              final mark = switch (line.change) {
                HistoryChange.added => '+',
                HistoryChange.removed => '−',
                HistoryChange.unchanged => ' ',
              };
              return ColoredBox(
                color: line.change == HistoryChange.unchanged
                    ? Colors.transparent
                    : color.withValues(alpha: dark ? 0.12 : 0.07),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 36,
                        child: Text(
                          '${line.currentLine ?? ''}',
                          style: theme.textTheme.labelMedium,
                        ),
                      ),
                      SizedBox(
                        width: 36,
                        child: Text(
                          '${line.versionLine ?? ''}',
                          style: theme.textTheme.labelMedium,
                        ),
                      ),
                      SizedBox(
                        width: 20,
                        child: Text(
                          mark,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SelectableText(
                              line.text.isEmpty ? ' ' : line.text,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: color, height: 1.6),
                            ),
                            if (line.attributesChanged)
                              Text(
                                'versionHistory.attributesChanged'.tr(),
                                style: theme.textTheme.labelMedium
                                    ?.copyWith(color: color),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
