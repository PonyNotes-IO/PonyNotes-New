import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/mobile_block_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/selectable_svg_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/block_menu/block_menu_button.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/hover.dart';
import 'package:flowy_infra_ui/style_widget/text_input.dart';
import 'package:flowy_infra_ui/widget/buttons/primary_button.dart';
import 'package:flowy_infra_ui/widget/buttons/secondary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:provider/provider.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:flowy_infra/platform_extension.dart';

class MathEquationBlockKeys {
  const MathEquationBlockKeys._();

  static const String type = 'math_equation';

  /// The content of a math equation block.
  ///
  /// The value is a String.
  static const String formula = 'formula';
}

Node mathEquationNode({
  String formula = '',
}) {
  final attributes = {
    MathEquationBlockKeys.formula: formula,
  };
  return Node(
    type: MathEquationBlockKeys.type,
    attributes: attributes,
  );
}

// defining the callout block menu item for selection
SelectionMenuItem mathEquationItem = SelectionMenuItem.node(
  getName: LocaleKeys.document_plugins_mathEquation_name.tr,
  iconBuilder: (editorState, onSelected, style) => SelectableSvgWidget(
    data: FlowySvgs.icon_math_eq_s,
    isSelected: onSelected,
    style: style,
  ),
  keywords: ['tex, latex, katex', 'math equation', 'formula'],
  nodeBuilder: (editorState, _) => mathEquationNode(),
  replace: (_, node) => node.delta?.isEmpty ?? false,
  updateSelection: (editorState, path, __, ___) {
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      final mathEquationState =
          editorState.getNodeAtPath(path)?.key.currentState;
      if (mathEquationState != null &&
          mathEquationState is MathEquationBlockComponentWidgetState) {
        mathEquationState.showEditingOverlay();
      }
    });
    return null;
  },
);

class MathEquationBlockComponentBuilder extends BlockComponentBuilder {
  MathEquationBlockComponentBuilder({
    super.configuration,
  });

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return MathEquationBlockComponentWidget(
      key: node.key,
      node: node,
      configuration: configuration,
      showActions: showActions(node),
      actionBuilder: (context, state) => actionBuilder(
        blockComponentContext,
        state,
      ),
      actionTrailingBuilder: (context, state) => actionTrailingBuilder(
        blockComponentContext,
        state,
      ),
    );
  }

  @override
  BlockComponentValidate get validate => (node) =>
      node.children.isEmpty &&
      node.attributes[MathEquationBlockKeys.formula] is String;
}

class MathEquationBlockComponentWidget extends BlockComponentStatefulWidget {
  const MathEquationBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<MathEquationBlockComponentWidget> createState() =>
      MathEquationBlockComponentWidgetState();
}

class MathEquationBlockComponentWidgetState
    extends State<MathEquationBlockComponentWidget>
    with BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  String get formula =>
      widget.node.attributes[MathEquationBlockKeys.formula] as String;

  late final editorState = context.read<EditorState>();
  final ValueNotifier<bool> isHover = ValueNotifier(false);

  late final controller = TextEditingController(text: formula);

  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _overlayEntry?.remove();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onHover: (value) => isHover.value = value,
      onTap: showEditingOverlay,
      child: _build(context),
    );
  }

  Widget _build(BuildContext context) {
    Widget child = Container(
      constraints: const BoxConstraints(minHeight: 52),
      decoration: BoxDecoration(
        color: formula.isNotEmpty
            ? Colors.transparent
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: FlowyHover(
        style: HoverStyle(
          borderRadius: BorderRadius.circular(4),
        ),
        child: formula.isEmpty
            ? _buildPlaceholderWidget(context)
            : _buildMathEquation(context),
      ),
    );

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        actionTrailingBuilder: widget.actionTrailingBuilder,
        child: child,
      );
    }

    if (PlatformInfo.isMobile) {
      child = MobileBlockActionButtons(
        node: node,
        editorState: editorState,
        child: child,
      );
    }

    child = Padding(
      padding: padding,
      child: child,
    );

    if (PlatformInfo.isDesktopOrTabletOrWeb) {
      child = Stack(
        children: [
          child,
          Positioned(
            right: 6,
            top: 12,
            child: ValueListenableBuilder<bool>(
              valueListenable: isHover,
              builder: (_, value, __) =>
                  value ? _buildDeleteButton(context) : const SizedBox.shrink(),
            ),
          ),
        ],
      );
    }

    return child;
  }

  Widget _buildPlaceholderWidget(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          const HSpace(10),
          FlowySvg(
            FlowySvgs.slash_menu_icon_math_equation_s,
            color: Theme.of(context).hintColor,
            size: const Size.square(24),
          ),
          const HSpace(10),
          FlowyText(
            LocaleKeys.document_plugins_mathEquation_addMathEquation.tr(),
            color: Theme.of(context).hintColor,
          ),
        ],
      ),
    );
  }

  Widget _buildMathEquation(BuildContext context) {
    return Center(
      child: Math.tex(
        formula,
        textStyle: const TextStyle(fontSize: 20),
      ),
    );
  }

  Widget _buildDeleteButton(BuildContext context) {
    return MenuBlockButton(
      tooltip: LocaleKeys.button_delete.tr(),
      iconData: FlowySvgs.trash_s,
      onTap: () {
        final transaction = editorState.transaction..deleteNode(widget.node);
        editorState.apply(transaction);
      },
    );
  }

  void showEditingOverlay() {
    dismissOverlay();

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    final editorOffset = editorState.renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final editorSize = editorState.renderBox?.size ?? Size.zero;

    const editorWidth = 400.0;
    const editorHeight = 120.0;

    double offsetX = position.dx + (size.width - editorWidth) / 2;
    double offsetY = position.dy + size.height + 8;

    if (offsetX < editorOffset.dx) {
      offsetX = editorOffset.dx + 8;
    }
    if (offsetX + editorWidth > editorOffset.dx + editorSize.width) {
      offsetX = editorOffset.dx + editorSize.width - editorWidth - 8;
    }
    if (offsetY + editorHeight > editorOffset.dy + editorSize.height) {
      offsetY = position.dy - editorHeight - 8;
    }

    _overlayEntry = OverlayEntry(
      builder: (_) => Material(
        type: MaterialType.transparency,
        child: SizedBox(
          height: editorSize.height,
          width: editorSize.width,
          child: KeyboardListener(
            focusNode: FocusNode()..requestFocus(),
            onKeyEvent: (key) {
              if (key.logicalKey == LogicalKeyboardKey.escape) {
                dismissOverlay();
              }
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: dismissOverlay,
              child: Stack(
                children: [
                  _MathEquationEditorOverlay(
                    initialFormula: formula,
                    controller: controller,
                    offset: Offset(offsetX, offsetY),
                    editorState: editorState,
                    node: widget.node,
                    onDismiss: dismissOverlay,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void dismissOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void showEditingDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).canvasColor,
          title: Text(
            LocaleKeys.document_plugins_mathEquation_editMathEquation.tr(),
          ),
          content: KeyboardListener(
            focusNode: FocusNode(),
            onKeyEvent: (key) {
              if (key.logicalKey == LogicalKeyboardKey.enter &&
                  !HardwareKeyboard.instance.isShiftPressed) {
                updateMathEquation(controller.text, context);
              } else if (key.logicalKey == LogicalKeyboardKey.escape) {
                dismiss(context);
              }
            },
            child: SizedBox(
              width: MediaQuery.of(context).size.width * 0.3,
              child: TextField(
                autofocus: true,
                controller: controller,
                maxLines: null,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'E = MC^2',
                ),
              ),
            ),
          ),
          actions: [
            SecondaryTextButton(
              LocaleKeys.button_cancel.tr(),
              mode: TextButtonMode.big,
              onPressed: () => dismiss(context),
            ),
            PrimaryTextButton(
              LocaleKeys.button_done.tr(),
              onPressed: () => updateMathEquation(controller.text, context),
            ),
          ],
          actionsPadding: const EdgeInsets.only(bottom: 20),
          actionsAlignment: MainAxisAlignment.spaceAround,
        );
      },
    );
  }

  void updateMathEquation(String mathEquation, BuildContext context) {
    if (mathEquation == formula) {
      dismiss(context);
      return;
    }
    final transaction = editorState.transaction
      ..updateNode(
        widget.node,
        {
          MathEquationBlockKeys.formula: mathEquation,
        },
      );
    editorState.apply(transaction);
    dismiss(context);
  }

  void dismiss(BuildContext context) {
    Navigator.of(context).pop();
  }
}

class _MathEquationEditorOverlay extends StatefulWidget {
  const _MathEquationEditorOverlay({
    required this.initialFormula,
    required this.controller,
    required this.offset,
    required this.editorState,
    required this.node,
    required this.onDismiss,
  });

  final String initialFormula;
  final TextEditingController controller;
  final Offset offset;
  final EditorState editorState;
  final Node node;
  final VoidCallback onDismiss;

  @override
  State<_MathEquationEditorOverlay> createState() =>
      _MathEquationEditorOverlayState();
}

class _MathEquationEditorOverlayState extends State<_MathEquationEditorOverlay> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialFormula);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = controller.text;
    widget.onDismiss();
    if (value == widget.initialFormula) {
      return;
    }
    final transaction = widget.editorState.transaction
      ..updateNode(
        widget.node,
        {
          MathEquationBlockKeys.formula: value,
        },
      );
    widget.editorState.apply(transaction);
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.offset.dx,
      top: widget.offset.dy,
      child: GestureDetector(
        onTap: () {},
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                LocaleKeys.document_plugins_mathEquation_editMathEquation
                    .tr(),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              FlowyFormTextInput(
                autoFocus: true,
                textAlign: TextAlign.left,
                controller: controller,
                hintText: 'E = MC^2',
                onEditingComplete: _submit,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SecondaryTextButton(
                    LocaleKeys.button_cancel.tr(),
                    mode: TextButtonMode.big,
                    onPressed: widget.onDismiss,
                  ),
                  const SizedBox(width: 8),
                  PrimaryTextButton(
                    LocaleKeys.button_done.tr(),
                    onPressed: _submit,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
