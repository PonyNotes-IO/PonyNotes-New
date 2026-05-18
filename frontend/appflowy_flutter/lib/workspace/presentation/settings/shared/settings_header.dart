import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

/// Renders a simple header for the settings view
///
class SettingsHeader extends StatelessWidget {
  const SettingsHeader({
    super.key,
    required this.title,
    this.description,
    this.descriptionBuilder,
    this.leadingBuilder,
    this.trailingBuilder,
  });

  final String title;
  final String? description;
  final WidgetBuilder? descriptionBuilder;
  final WidgetBuilder? leadingBuilder;
  final WidgetBuilder? trailingBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: double.infinity,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (leadingBuilder != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: leadingBuilder!(context),
                ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: theme.spacing.l),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textStyle.heading2.enhanced(
                    color: theme.textColorScheme.primary,
                  ),
                ),
              ),
              if (trailingBuilder != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: trailingBuilder!(context),
                ),
            ],
          ),
        ),
        if (descriptionBuilder != null) ...[
          VSpace(theme.spacing.xs),
          descriptionBuilder!(context),
        ] else if (description?.isNotEmpty == true) ...[
          VSpace(theme.spacing.xs),
          Text(
            description!,
            textAlign: TextAlign.center,
            maxLines: 4,
            style: theme.textStyle.caption.standard(
              color: theme.textColorScheme.secondary,
            ),
          ),
        ],
      ],
    );
  }
}
