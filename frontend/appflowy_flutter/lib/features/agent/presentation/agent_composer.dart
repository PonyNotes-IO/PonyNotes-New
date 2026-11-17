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
    this.compact = false,
  });

  final Widget input;
  final List<Widget> leading;
  final Widget modelSelector;
  final List<Widget> actions;
  final Widget? footer;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: theme.surfaceColorScheme.layer01,
        border: Border.all(
          color: compact
              ? theme.textColorScheme.primary.withValues(alpha: .07)
              : theme.borderColorScheme.primary,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: compact
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .06),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: compact ? 40 : 72),
            child: input,
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) =>
                compact && constraints.maxWidth < 520
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: modelSelector,
                          ),
                          Row(
                            children: [...leading, const Spacer(), ...actions],
                          ),
                        ],
                      )
                    : Row(
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
