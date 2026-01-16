import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/cell/bloc/url_cell_bloc.dart';
import 'package:appflowy/plugins/database/widgets/cell/desktop_grid/desktop_grid_url_cell.dart';
import 'package:appflowy/plugins/database/widgets/row/accessory/cell_accessory.dart';
import 'package:appflowy/plugins/database/widgets/row/cells/cell_container.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../editable_cell_skeleton/url.dart';

class DesktopRowDetailURLSkin extends IEditableURLCellSkin {
  @override
  Widget build(
    BuildContext context,
    CellContainerNotifier cellContainerNotifier,
    ValueNotifier<bool> compactModeNotifier,
    URLCellBloc bloc,
    FocusNode focusNode,
    TextEditingController textEditingController,
    URLCellDataNotifier cellDataNotifier,
  ) {
    return LinkTextField(
      controller: textEditingController,
      focusNode: focusNode,
    );
  }

  @override
  List<GridCellAccessoryBuilder> accessoryBuilder(
    GridCellAccessoryBuildContext context,
    URLCellDataNotifier cellDataNotifier,
  ) {
    return [
      accessoryFromType(
        GridURLCellAccessoryType.visitURL,
        cellDataNotifier,
      ),
    ];
  }
}

class LinkTextField extends StatefulWidget {
  const LinkTextField({
    super.key,
    required this.controller,
    required this.focusNode,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  State<LinkTextField> createState() => _LinkTextFieldState();
}

class _LinkTextFieldState extends State<LinkTextField> {
  bool isLinkClickable = false;

  @override
  void initState() {
    super.initState();
    _updateLinkClickableState();
    // 使用 Focus 的 onKeyEvent 而不是全局键盘处理器，避免键盘状态不同步
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (widget.focusNode.hasFocus) {
      _updateLinkClickableState();
    } else {
      if (isLinkClickable) {
        setState(() => isLinkClickable = false);
      }
    }
  }

  void _updateLinkClickableState() {
    final keyboard = HardwareKeyboard.instance;
    final canOpenLink = keyboard.isControlPressed || keyboard.isMetaPressed;
    if (canOpenLink != isLinkClickable) {
      setState(() => isLinkClickable = canOpenLink);
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    // 只在有焦点时更新状态
    if (widget.focusNode.hasFocus && event is KeyDownEvent) {
      _updateLinkClickableState();
    }
    // 返回 ignored 让事件继续传播，不拦截输入
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _handleKeyEvent,
      child: TextField(
      mouseCursor:
          isLinkClickable ? SystemMouseCursors.click : SystemMouseCursors.text,
      controller: widget.controller,
      focusNode: widget.focusNode,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
      onTap: () {
        if (isLinkClickable) {
          openUrlCellLink(widget.controller.text);
        }
      },
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        border: InputBorder.none,
        focusedBorder: InputBorder.none,
        enabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        hintText: LocaleKeys.grid_row_textPlaceholder.tr(),
        hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).hintColor,
            ),
        isDense: true,
      ),
    ));
  }
}
