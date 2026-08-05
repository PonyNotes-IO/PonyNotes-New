import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

class ContinueWithButton extends StatelessWidget {
  const ContinueWithButton({
    super.key,
    required this.onTap,
    required this.text,
    this.borderRadius,
  });

  final VoidCallback onTap;
  final String text;
  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return AFFilledTextButton.primary(
      size: AFButtonSize.xl,
      alignment: Alignment.center,
      text: text,
      onTap: onTap,
      borderRadius: borderRadius,
      textStyle: theme.textStyle.body.enhanced(
        color: theme.textColorScheme.onFill,
      ),
    );
  }
}
