import 'package:appflowy/workspace/presentation/settings/shared/settings_category_spacer.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_header.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

class SettingsBody extends StatelessWidget {
  const SettingsBody(
      {super.key,
      required this.title,
      this.description,
      this.descriptionBuilder,
      this.headerLeadingBuilder,
      this.headerTrailingBuilder,
      this.autoSeparate = true,
      required this.children,
      this.bottomWidget});

  final String title;
  final String? description;
  final WidgetBuilder? descriptionBuilder;
  final WidgetBuilder? headerLeadingBuilder;
  final WidgetBuilder? headerTrailingBuilder;
  final bool autoSeparate;
  final List<Widget> children;
  final Widget? bottomWidget;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      VSpace(20),
      SettingsHeader(
        title: title,
        description: description,
        descriptionBuilder: descriptionBuilder,
        leadingBuilder: headerLeadingBuilder,
        trailingBuilder: headerTrailingBuilder,
      ),
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth < 460 ? 16.0 : 24.0;
            final verticalPadding = constraints.maxWidth < 460 ? 18.0 : 24.0;
            return SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: verticalPadding,
                ),
                child: Column(children: [
                  if (children.isNotEmpty) ...[
                    SizedBox(height: verticalPadding),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: children,
                    ),
                  ],
                ]));
          },
        ),
      ),
      bottomWidget != null ? bottomWidget! : SizedBox.shrink()
    ]);
  }
}
