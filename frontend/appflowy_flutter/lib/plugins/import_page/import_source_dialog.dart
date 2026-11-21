import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';

class ImportSourceDialog extends StatelessWidget {
  const ImportSourceDialog({
    super.key,
    required this.title,
    required this.description,
    required this.picker,
    required this.instructions,
    required this.cancelLabel,
    required this.onCancel,
    this.status,
  });

  final String title;
  final String description;
  final Widget picker;
  final String instructions;
  final String cancelLabel;
  final VoidCallback? onCancel;
  final Widget? status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final outline = colors.onSurface.withValues(alpha: isDark ? 0.15 : 0.12);
    return Dialog(
      backgroundColor: isDark ? const Color(0xFF202020) : colors.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      constraints: const BoxConstraints(maxWidth: 544),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: outline),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            picker,
            if (status case final status?) ...[
              const SizedBox(height: 8),
              Semantics(liveRegion: true, child: status),
            ],
            const SizedBox(height: 12),
            Text(
              instructions,
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.6,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: OutlinedButton(
                onPressed: onCancel,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(76, 36),
                  foregroundColor: colors.onSurface,
                  side: BorderSide(color: outline),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(cancelLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ImportSourcePicker extends StatelessWidget {
  const ImportSourcePicker({
    super.key,
    required this.icon,
    required this.label,
    required this.hint,
    required this.onPressed,
    this.highlighted = false,
  });

  final IconData icon;
  final Widget label;
  final String hint;
  final VoidCallback? onPressed;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark ? const Color(0xFFFF9A7A) : const Color(0xFFB83912);
    return DottedBorder(
      borderType: BorderType.RRect,
      radius: const Radius.circular(12),
      dashPattern: const [5, 4],
      color: accent.withValues(alpha: highlighted ? 1 : 0.7),
      padding: EdgeInsets.zero,
      child: Container(
        constraints: const BoxConstraints(minHeight: 132),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: highlighted ? 0.15 : 0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: isDark ? 0.13 : 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: accent),
            ),
            TextButton(
              onPressed: onPressed,
              style: TextButton.styleFrom(foregroundColor: accent),
              child: label,
            ),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
