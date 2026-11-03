import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/selectable_svg_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/slash_menu/slash_menu_items/slash_menu_item_builder.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';

import 'note_reference_picker.dart';

final noteReferenceSlashItem = SelectionMenuItem(
  getName: () => 'document.slashMenu.name.referenceParagraph'.tr(),
  keywords: ['引用段落', '段落引用', '片段', 'reference', 'passage', 'block reference'],
  handler: (editor, menu, context) async {
    final editorContext = editor.document.root.context;
    menu.dismiss();
    if (editorContext != null && editorContext.mounted) {
      await insertNoteReference(editorContext, editor);
    }
  },
  nameBuilder: slashMenuItemNameBuilder,
  icon: (_, selected, style) => SelectableSvgWidget(
    data: FlowySvgs.slash_menu_icon_quote_s,
    isSelected: selected,
    style: style,
  ),
);
