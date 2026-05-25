import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../third_party/saber_core/data/editor/text_box.dart';

/// ✅ 文字格式化工具栏
class TextFormattingToolbar extends StatelessWidget {
  const TextFormattingToolbar({
    super.key,
    required this.formatting,
    required this.onFormattingChanged,
  });

  final TextFormatting formatting;
  final ValueChanged<TextFormatting> onFormattingChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ✅ 加粗
          _buildFormatButton(
            context: context,
            icon: FontAwesomeIcons.bold,
            tooltip: '加粗',
            isActive: formatting.bold,
            onTap: () {
              onFormattingChanged(formatting.copyWith(bold: !formatting.bold));
            },
          ),
          const SizedBox(width: 4),
          // ✅ 斜体
          _buildFormatButton(
            context: context,
            icon: FontAwesomeIcons.italic,
            tooltip: '斜体',
            isActive: formatting.italic,
            onTap: () {
              onFormattingChanged(formatting.copyWith(italic: !formatting.italic));
            },
          ),
          const SizedBox(width: 4),
          // ✅ 下划线
          _buildFormatButton(
            context: context,
            icon: FontAwesomeIcons.underline,
            tooltip: '下划线',
            isActive: formatting.underline,
            onTap: () {
              onFormattingChanged(formatting.copyWith(underline: !formatting.underline));
            },
          ),
          const SizedBox(width: 4),
          // ✅ 删除线
          _buildFormatButton(
            context: context,
            icon: FontAwesomeIcons.strikethrough,
            tooltip: '删除线',
            isActive: formatting.strikethrough,
            onTap: () {
              onFormattingChanged(formatting.copyWith(strikethrough: !formatting.strikethrough));
            },
          ),
          const SizedBox(width: 8),
          // ✅ 上标
          _buildFormatButton(
            context: context,
            icon: FontAwesomeIcons.superscript,
            tooltip: '上标',
            isActive: formatting.superscript,
            onTap: () {
              onFormattingChanged(formatting.copyWith(
                superscript: !formatting.superscript,
                subscript: formatting.superscript ? false : formatting.subscript, // 互斥
              ));
            },
          ),
          const SizedBox(width: 4),
          // ✅ 下标
          _buildFormatButton(
            context: context,
            icon: FontAwesomeIcons.subscript,
            tooltip: '下标',
            isActive: formatting.subscript,
            onTap: () {
              onFormattingChanged(formatting.copyWith(
                subscript: !formatting.subscript,
                superscript: formatting.subscript ? false : formatting.superscript, // 互斥
              ));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFormatButton({
    required BuildContext context,
    required IconData icon,
    required String tooltip,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: isActive
            ? Theme.of(context).colorScheme.primaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(6),
            child: FaIcon(
              icon,
              size: 14,
              color: isActive
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

