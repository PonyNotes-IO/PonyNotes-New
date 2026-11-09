import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_page.dart';
import 'package:appflowy/plugins/document/presentation/editor_style.dart';
import 'package:appflowy/util/theme_extension.dart';
import 'package:appflowy/workspace/application/settings/shortcuts/shortcut_registry.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/style_widget/icon_button.dart';
import 'package:flutter/material.dart';

import 'custom_placeholder_toolbar_item.dart';
import 'toolbar_id_enum.dart';

final List<ToolbarItem> customMarkdownFormatItems = [
  _FormatToolbarItem(
    id: ToolbarId.bold,
    name: 'bold',
    svg: FlowySvgs.toolbar_bold_m,
  ),
  group1PaddingItem,
  _FormatToolbarItem(
    id: ToolbarId.underline,
    name: 'underline',
    svg: FlowySvgs.toolbar_underline_m,
  ),
  group1PaddingItem,
  _FormatToolbarItem(
    id: ToolbarId.italic,
    name: 'italic',
    svg: FlowySvgs.toolbar_inline_italic_m,
  ),
];

final ToolbarItem customInlineCodeItem = _FormatToolbarItem(
  id: ToolbarId.code,
  name: 'code',
  svg: FlowySvgs.toolbar_inline_code_m,
  group: 2,
);

class _FormatToolbarItem extends ToolbarItem {
  _FormatToolbarItem({
    required ToolbarId id,
    required String name,
    required FlowySvgData svg,
    super.group = 1,
  }) : super(
          id: id.id,
          isActive: showInAnyTextType,
          builder: (
            context,
            editorState,
            highlightColor,
            iconColor,
            tooltipBuilder,
          ) {
            final selection = editorState.selection!;
            final nodes = editorState.getNodesInSelection(selection);
            final isHighlight = nodes.allSatisfyInSelection(
              selection,
              (delta) =>
                  delta.isNotEmpty &&
                  delta.everyAttributes((attr) => attr[name] == true),
            );

            final hoverColor = isHighlight
                ? highlightColor
                : EditorStyleCustomizer.toolbarHoverColor(context);
            final isDark = !Theme.of(context).isLightMode;
            final theme = AppFlowyTheme.of(context);

            final child = FlowyIconButton(
              width: 36,
              height: 32,
              hoverColor: hoverColor,
              isSelected: isHighlight,
              icon: FlowySvg(
                svg,
                size: Size.square(20.0),
                color: (isDark && isHighlight)
                    ? Color(0xFF282E3A)
                    : theme.iconColorScheme.primary,
              ),
              onPressed: () => editorState.toggleAttribute(
                name,
                selection: selection,
              ),
            );

            if (tooltipBuilder != null) {
              return tooltipBuilder(
                context,
                id.id,
                _getTooltipText(context, id),
                child,
              );
            }
            return child;
          },
        );
}

String _getTooltipText(BuildContext context, ToolbarId id) {
  final (label, key) = switch (id) {
    ToolbarId.underline => (
        LocaleKeys.toolbar_underline.tr(),
        toggleUnderlineCommand.key
      ),
    ToolbarId.bold => (LocaleKeys.toolbar_bold.tr(), toggleBoldCommand.key),
    ToolbarId.italic => (LocaleKeys.toolbar_italic.tr(), toggleItalicCommand.key),
    ToolbarId.code => (
        LocaleKeys.document_toolbar_inlineCode.tr(),
        toggleCodeCommand.key
      ),
    _ => ('', ''),
  };
  if (key.isEmpty) return label;
  final binding = shortcutLabel(context, key);
  return binding.isEmpty ? label : '$label ($binding)';
}
