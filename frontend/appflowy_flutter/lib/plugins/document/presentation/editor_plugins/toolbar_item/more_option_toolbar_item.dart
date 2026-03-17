import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_page.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/desktop_toolbar/desktop_floating_toolbar.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/desktop_toolbar/link/link_create_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/desktop_toolbar/link/link_hover_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy/plugins/document/presentation/editor_style.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
// ignore: implementation_imports
import 'package:appflowy_editor/src/editor/toolbar/desktop/items/utils/tooltip_util.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'custom_text_align_toolbar_item.dart';
import 'text_suggestions_toolbar_item.dart';

const _kMoreOptionItemId = 'editor.more_option';
const kFontToolbarItemId = 'editor.font';

@visibleForTesting
const kFontFamilyToolbarItemKey = ValueKey('FontFamilyToolbarItem');

final ToolbarItem moreOptionItem = ToolbarItem(
  id: _kMoreOptionItemId,
  group: 5,
  isActive: showInAnyTextType,
  builder: (
    context,
    editorState,
    highlightColor,
    iconColor,
    tooltipBuilder,
  ) {
    return MoreOptionActionList(
      editorState: editorState,
      tooltipBuilder: tooltipBuilder,
      highlightColor: highlightColor,
    );
  },
);

class MoreOptionActionList extends StatefulWidget {
  const MoreOptionActionList({
    super.key,
    required this.editorState,
    required this.highlightColor,
    this.tooltipBuilder,
  });

  final EditorState editorState;
  final ToolbarTooltipBuilder? tooltipBuilder;
  final Color highlightColor;

  @override
  State<MoreOptionActionList> createState() => _MoreOptionActionListState();
}

class _MoreOptionActionListState extends State<MoreOptionActionList> {
  final popoverController = PopoverController();
  PopoverController fontPopoverController = PopoverController();
  PopoverController suggestionsPopoverController = PopoverController();
  PopoverController textAlignPopoverController = PopoverController();

  bool isSelected = false;

  EditorState get editorState => widget.editorState;

  Color get highlightColor => widget.highlightColor;

  MoreOptionCommand? tappedCommand;

  @override
  void dispose() {
    super.dispose();
    popoverController.close();
    fontPopoverController.close();
    suggestionsPopoverController.close();
    textAlignPopoverController.close();
  }

  @override
  Widget build(BuildContext context) {
    return AppFlowyPopover(
      controller: popoverController,
      direction: PopoverDirection.bottomWithLeftAligned,
      offset: const Offset(0, 2.0),
      onOpen: () => keepEditorFocusNotifier.increase(),
      onClose: () {
        setState(() {
          isSelected = false;
        });
        keepEditorFocusNotifier.decrease();
      },
      popupBuilder: (context) => buildPopoverContent(),
      child: buildChild(context),
    );
  }

  void showPopover() {
    keepEditorFocusNotifier.increase();
    popoverController.show();
  }

  Widget buildChild(BuildContext context) {
    final iconColor = Theme.of(context).iconTheme.color;
    final child = FlowyIconButton(
      width: 36,
      height: 32,
      isSelected: isSelected,
      hoverColor: EditorStyleCustomizer.toolbarHoverColor(context),
      icon: FlowySvg(
        FlowySvgs.toolbar_more_m,
        size: Size.square(20),
        color: iconColor,
      ),
      onPressed: () {
        setState(() {
          isSelected = true;
        });
        showPopover();
      },
    );

    return widget.tooltipBuilder?.call(
          context,
          _kMoreOptionItemId,
          LocaleKeys.document_toolbar_moreOptions.tr(),
          child,
        ) ??
        child;
  }

  Color? getFormulaColor() {
    if (isFormulaHighlight(editorState)) {
      return widget.highlightColor;
    }
    return null;
  }

  Color? getStrikethroughColor() {
    final selection = editorState.selection;
    if (selection == null || selection.isCollapsed) {
      return null;
    }
    final node = editorState.getNodeAtPath(selection.start.path);
    final delta = node?.delta;
    if (node == null || delta == null) {
      return null;
    }

    final nodes = editorState.getNodesInSelection(selection);
    final isHighlight = nodes.allSatisfyInSelection(
      selection,
      (delta) =>
          delta.isNotEmpty &&
          delta.everyAttributes(
            (attr) => attr[MoreOptionCommand.strikethrough.name] == true,
          ),
    );
    return isHighlight ? widget.highlightColor : null;
  }

  Widget buildPopoverContent() {
    final showFormula = onlyShowInSingleSelectionAndTextType(editorState);
    const fontColor = Color(0xff99A1A8);
    final isNarrow = isNarrowWindow(editorState);
    return MouseRegion(
      child: SeparatedColumn(
        mainAxisSize: MainAxisSize.min,
        separatorBuilder: () => const VSpace(4.0),
        children: [
          if (isNarrow) ...[
            buildTurnIntoSelector(),
            buildCommandItem(MoreOptionCommand.link),
            buildTextAlignSelector(),
          ],
          buildFontSelector(),
          buildCommandItem(
            MoreOptionCommand.strikethrough,
            rightIcon: FlowyText(
              shortcutTooltips(
                '⌘⇧S',
                'Ctrl⇧S',
                'Ctrl⇧S',
              ).trim(),
              color: fontColor,
              fontSize: 12,
              figmaLineHeight: 16,
              fontWeight: FontWeight.w400,
            ),
          ),
          if (showFormula)
            buildCommandItem(
              MoreOptionCommand.formula,
              rightIcon: FlowyText(
                shortcutTooltips(
                  '⌘⇧E',
                  'Ctrl⇧E',
                  'Ctrl⇧E',
                ).trim(),
                color: fontColor,
                fontSize: 12,
                figmaLineHeight: 16,
                fontWeight: FontWeight.w400,
              ),
            ),
        ],
      ),
    );
  }

  Widget buildCommandItem(
    MoreOptionCommand command, {
    Widget? rightIcon,
    VoidCallback? onTap,
  }) {
    final isFontCommand = command == MoreOptionCommand.font;
    return SizedBox(
      height: 36,
      child: FlowyButton(
        key: isFontCommand ? kFontFamilyToolbarItemKey : null,
        leftIconSize: const Size.square(20),
        leftIcon: FlowySvg(command.svg),
        rightIcon: rightIcon,
        iconPadding: 12,
        text: FlowyText(
          command.title,
          figmaLineHeight: 20,
          fontWeight: FontWeight.w400,
        ),
        onTap: onTap ??
            () {
              command.onExecute(editorState, context);
              hideOtherPopovers(command);
              if (command != MoreOptionCommand.font) {
                popoverController.close();
              }
            },
      ),
    );
  }

  Widget buildFontSelector() {
    final selection = editorState.selection!;
    final String? currentFontFamily = editorState
        .getDeltaAttributeValueInSelection(AppFlowyRichTextKeys.fontFamily);
    return FontFamilyDropDown(
      currentFontFamily: currentFontFamily ?? '',
      offset: const Offset(-240, 0),
      popoverController: fontPopoverController,
      onOpen: () => keepEditorFocusNotifier.increase(),
      onClose: () => keepEditorFocusNotifier.decrease(),
      onFontFamilyChanged: (fontFamily) async {
        fontPopoverController.close();
        popoverController.close();
        try {
          await editorState.formatDelta(selection, {
            AppFlowyRichTextKeys.fontFamily: fontFamily,
          });
        } catch (e) {
          Log.error('Failed to set font family: $e');
        }
      },
      onResetFont: () async {
        fontPopoverController.close();
        popoverController.close();
        await editorState
            .formatDelta(selection, {AppFlowyRichTextKeys.fontFamily: null});
      },
      child: buildCommandItem(
        MoreOptionCommand.font,
        rightIcon: FlowySvg(FlowySvgs.toolbar_arrow_right_m),
      ),
    );
  }

  Widget buildTurnIntoSelector() {
    final selectionRects = editorState.selectionRects();
    double height = -6;
    if (selectionRects.isNotEmpty) height = selectionRects.first.height;
    return SuggestionsActionList(
      editorState: editorState,
      popoverController: suggestionsPopoverController,
      popoverDirection: PopoverDirection.leftWithTopAligned,
      showOffset: Offset(-8, height),
      onSelect: () => getIt<FloatingToolbarController>().hideToolbar(),
      child: buildCommandItem(
        MoreOptionCommand.suggestions,
        rightIcon: FlowySvg(FlowySvgs.toolbar_arrow_right_m),
        onTap: () {
          if (tappedCommand == MoreOptionCommand.suggestions) return;
          hideOtherPopovers(MoreOptionCommand.suggestions);
          keepEditorFocusNotifier.increase();
          suggestionsPopoverController.show();
        },
      ),
    );
  }

  Widget buildTextAlignSelector() {
    return TextAlignActionList(
      editorState: editorState,
      popoverController: textAlignPopoverController,
      popoverDirection: PopoverDirection.leftWithTopAligned,
      showOffset: Offset(-8, 0),
      onSelect: () => getIt<FloatingToolbarController>().hideToolbar(),
      highlightColor: highlightColor,
      child: buildCommandItem(
        MoreOptionCommand.textAlign,
        rightIcon: FlowySvg(FlowySvgs.toolbar_arrow_right_m),
        onTap: () {
          if (tappedCommand == MoreOptionCommand.textAlign) return;
          hideOtherPopovers(MoreOptionCommand.textAlign);
          keepEditorFocusNotifier.increase();
          textAlignPopoverController.show();
        },
      ),
    );
  }

  void hideOtherPopovers(MoreOptionCommand currentCommand) {
    if (tappedCommand == currentCommand) return;
    if (tappedCommand == MoreOptionCommand.font) {
      fontPopoverController.close();
      fontPopoverController = PopoverController();
    } else if (tappedCommand == MoreOptionCommand.suggestions) {
      suggestionsPopoverController.close();
      suggestionsPopoverController = PopoverController();
    } else if (tappedCommand == MoreOptionCommand.textAlign) {
      textAlignPopoverController.close();
      textAlignPopoverController = PopoverController();
    }
    tappedCommand = currentCommand;
  }
}

enum MoreOptionCommand {
  suggestions(FlowySvgs.turninto_s),
  link(FlowySvgs.toolbar_link_m),
  textAlign(
    FlowySvgs.toolbar_alignment_m,
  ),
  font(FlowySvgs.type_font_m),
  strikethrough(FlowySvgs.type_strikethrough_m),
  formula(FlowySvgs.type_formula_m);

  const MoreOptionCommand(this.svg);

  final FlowySvgData svg;

  String get title {
    switch (this) {
      case suggestions:
        return LocaleKeys.document_toolbar_turnInto.tr();
      case link:
        return LocaleKeys.document_toolbar_link.tr();
      case textAlign:
        return LocaleKeys.button_align.tr();
      case font:
        return LocaleKeys.document_toolbar_font.tr();
      case strikethrough:
        return LocaleKeys.editor_strikethrough.tr();
      case formula:
        return LocaleKeys.document_toolbar_equation.tr();
    }
  }

  Future<void> onExecute(EditorState editorState, BuildContext context) async {
    final selection = editorState.selection!;
    if (this == link) {
      final nodes = editorState.getNodesInSelection(selection);
      final isHref = nodes.allSatisfyInSelection(selection, (delta) {
        return delta.everyAttributes(
          (attributes) => attributes[AppFlowyRichTextKeys.href] != null,
        );
      });
      getIt<FloatingToolbarController>().hideToolbar();
      if (isHref) {
        getIt<LinkHoverTriggers>().call(
          HoverTriggerKey(nodes.first.id, selection),
        );
      } else {
        final viewId = context.read<DocumentBloc?>()?.documentId ?? '';
        showLinkCreateMenu(context, editorState, selection, viewId);
      }
    } else if (this == strikethrough) {
      await editorState.toggleAttribute(name);
    } else if (this == formula) {
      final node = editorState.getNodeAtPath(selection.start.path);
      final delta = node?.delta;
      if (node == null || delta == null) {
        return;
      }

      getIt<FloatingToolbarController>().hideToolbar();

      final isHighlight = isFormulaHighlight(editorState);
      if (isHighlight) {
        final formula = delta
            .slice(selection.startIndex, selection.endIndex)
            .whereType<TextInsert>()
            .firstOrNull
            ?.attributes?[InlineMathEquationKeys.formula];
        assert(formula != null);
        if (formula == null) {
          return;
        }
        // 显示公式编辑弹窗
        if (context.mounted) {
          await _showFormulaEditDialog(
            context: context,
            editorState: editorState,
            node: node,
            index: selection.startIndex,
            initialFormula: formula,
            isNewFormula: false,
          );
        }
      } else {
        final text = editorState.getTextInSelection(selection).join();
        final transaction = editorState.transaction;
        transaction.replaceText(
          node,
          selection.startIndex,
          selection.length,
          MentionBlockKeys.mentionChar,
          attributes: {
            InlineMathEquationKeys.formula: text,
          },
        );
        await editorState.apply(transaction);
        // 显示公式编辑弹窗
        if (context.mounted) {
          await _showFormulaEditDialog(
            context: context,
            editorState: editorState,
            node: node,
            index: selection.startIndex,
            initialFormula: text,
            isNewFormula: true,
          );
        }
      }
    }
  }

  Future<void> _showFormulaEditDialog({
    required BuildContext context,
    required EditorState editorState,
    required Node node,
    required int index,
    required String initialFormula,
    required bool isNewFormula,
  }) async {
    final controller = TextEditingController(text: initialFormula);
    OverlayEntry? formulaOverlay;
    formulaOverlay = OverlayEntry(
      builder: (ctx) {
        return _FormulaEditOverlay(
          controller: controller,
          onSubmit: (value) async {
            if (isNewFormula) {
              // 对于新公式，需要更新已插入的公式
              final transaction = editorState.transaction
                ..formatText(node, index, 1, {
                  InlineMathEquationKeys.formula: value,
                });
              await editorState.apply(transaction);
            }
            formulaOverlay?.remove();
          },
          onCancel: () {
            if (isNewFormula) {
              // 取消时删除刚插入的占位符
              final transaction = editorState.transaction
                ..deleteText(node, index, 1);
              editorState.apply(transaction);
            }
            formulaOverlay?.remove();
          },
        );
      },
    );
    Overlay.of(context, rootOverlay: true).insert(formulaOverlay);
  }
}

/// 公式编辑浮层
class _FormulaEditOverlay extends StatelessWidget {
  const _FormulaEditOverlay({
    required this.controller,
    required this.onSubmit,
    required this.onCancel,
  });

  final TextEditingController controller;
  final void Function(String) onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 点击外部关闭
        Positioned.fill(
          child: GestureDetector(
            onTap: onCancel,
            child: Container(color: Colors.transparent),
          ),
        ),
        // 编辑框
        Center(
          child: Material(
            color: Theme.of(context).canvasColor,
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 320,
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    LocaleKeys.document_plugins_mathEquation_editMathEquation
                        .tr(),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'E = MC^2',
                    ),
                    onSubmitted: (value) => onSubmit(value),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: onCancel,
                        child: Text(LocaleKeys.button_cancel.tr()),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => onSubmit(controller.text),
                        child: Text(LocaleKeys.button_done.tr()),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

bool isFormulaHighlight(EditorState editorState) {
  final selection = editorState.selection;
  if (selection == null || selection.isCollapsed) {
    return false;
  }
  final node = editorState.getNodeAtPath(selection.start.path);
  final delta = node?.delta;
  if (node == null || delta == null) {
    return false;
  }

  final nodes = editorState.getNodesInSelection(selection);
  return nodes.allSatisfyInSelection(selection, (delta) {
    return delta.everyAttributes(
      (attributes) => attributes[InlineMathEquationKeys.formula] != null,
    );
  });
}
