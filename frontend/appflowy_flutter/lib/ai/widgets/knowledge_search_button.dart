import 'package:flutter/material.dart';

/// Shared toggle for the welcome screen and the conversation toolbar.
class KnowledgeSearchButton extends StatelessWidget {
  const KnowledgeSearchButton({
    super.key,
    required this.enabled,
    required this.onChanged,
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = enabled
        ? const Color(0xFFE94618)
        : dark
            ? const Color(0xFFB0B0B0)
            : const Color(0xFF636363);
    return Tooltip(
      message: enabled ? '关闭知识库检索' : '优先检索当前工作区中你有权访问的笔记',
      child: Semantics(
        toggled: enabled,
        child: SizedBox(
          height: 30,
          child: OutlinedButton(
            onPressed: () => onChanged(!enabled),
            style: OutlinedButton.styleFrom(
              foregroundColor: color,
              backgroundColor: enabled
                  ? color.withValues(alpha: 0.08)
                  : dark
                      ? const Color(0xFF2A2A2A)
                      : Colors.white,
              side: BorderSide(
                color: enabled
                    ? color
                    : dark
                        ? const Color(0xFF4A4A4A)
                        : const Color(0xFFCDCDCD),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              textStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
            child: const Text('知识库检索'),
          ),
        ),
      ),
    );
  }
}
