import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

class AgentComposer extends StatelessWidget {
  const AgentComposer({
    super.key,
    required this.input,
    required this.leading,
    required this.modelSelector,
    required this.actions,
    this.footer,
  });

  final Widget input;
  final List<Widget> leading;
  final Widget modelSelector;
  final List<Widget> actions;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surfaceColorScheme.layer01,
        border: Border.all(color: theme.borderColorScheme.primary),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: input,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ...leading,
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: modelSelector,
                ),
              ),
              const SizedBox(width: 8),
              ...actions,
            ],
          ),
          if (footer != null) ...[
            const SizedBox(height: 8),
            footer!,
          ],
        ],
      ),
    );
  }
}
