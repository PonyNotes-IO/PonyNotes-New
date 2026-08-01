import 'dart:async';

import 'package:appflowy/mobile/presentation/selection_menu/mobile_selection_menu_item.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import 'mobile_selection_menu_item_widget.dart';
import 'mobile_selection_menu_widget.dart';

class MobileSelectionMenu extends SelectionMenuService {
  MobileSelectionMenu({
    required this.context,
    required this.editorState,
    required this.selectionMenuItems,
    this.deleteSlashByDefault = false,
    this.deleteKeywordsByDefault = false,
    this.style = MobileSelectionMenuStyle.light,
    this.itemCountFilter = 0,
    this.startOffset = 0,
    this.singleColumn = false,
  });

  final BuildContext context;
  final EditorState editorState;
  final List<SelectionMenuItem> selectionMenuItems;
  final bool deleteSlashByDefault;
  final bool deleteKeywordsByDefault;
  final bool singleColumn;

  @override
  final MobileSelectionMenuStyle style;

  OverlayEntry? _selectionMenuEntry;
  Offset _offset = Offset.zero;
  Alignment _alignment = Alignment.topLeft;
  final int itemCountFilter;
  final int startOffset;
  ValueNotifier<_Position> _positionNotifier = ValueNotifier(_Position.zero);

  @override
  void dismiss() {
    if (_selectionMenuEntry != null) {
      editorState.service.keyboardService?.enable();
      editorState.service.scrollService?.enable();
      editorState
          .removeScrollViewScrolledListener(_checkPositionAfterScrolling);
      _positionNotifier.dispose();
    }

    _selectionMenuEntry?.remove();
    _selectionMenuEntry = null;
  }

  @override
  Future<void> show() async {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      _show();
      editorState.addScrollViewScrolledListener(_checkPositionAfterScrolling);
      completer.complete();
    });
    return completer.future;
  }

  void _show() {
    final position = _getCurrentPosition();
    if (position == null) return;

    // 使用屏幕尺寸而非编辑器尺寸：
    // 在 Pad 上编辑器可能居中（不在屏幕左上角），若 SizedBox 只覆盖编辑器区域，
    // 光标的全局坐标可能超出 SizedBox 边界，导致菜单被 Stack 裁剪或位置偏移。
    final screenSize = MediaQuery.of(context).size;

    _positionNotifier = ValueNotifier(position);
    final showAtTop = position.top != null;
    _selectionMenuEntry = OverlayEntry(
      builder: (context) {
        return SizedBox(
          width: screenSize.width,
          height: screenSize.height,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: dismiss,
            child: Stack(
              children: [
                ValueListenableBuilder(
                  valueListenable: _positionNotifier,
                  builder: (context, value, _) {
                    return Positioned(
                      top: value.top,
                      bottom: value.bottom,
                      left: value.left,
                      right: value.right,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: MobileSelectionMenuWidget(
                          selectionMenuStyle: style,
                          singleColumn: singleColumn,
                          showAtTop: showAtTop,
                          items: selectionMenuItems
                            ..forEach((element) {
                              if (element is MobileSelectionMenuItem) {
                                element.deleteSlash = false;
                                element.deleteKeywords =
                                    deleteKeywordsByDefault;
                                for (final e in element.children) {
                                  e.deleteSlash = deleteSlashByDefault;
                                  e.deleteKeywords = deleteKeywordsByDefault;
                                  e.onSelected = () {
                                    dismiss();
                                  };
                                }
                              } else {
                                element.deleteSlash = deleteSlashByDefault;
                                element.deleteKeywords =
                                    deleteKeywordsByDefault;
                                element.onSelected = () {
                                  dismiss();
                                };
                              }
                            }),
                          maxItemInRow: 5,
                          editorState: editorState,
                          itemCountFilter: itemCountFilter,
                          startOffset: startOffset,
                          menuService: this,
                          onExit: () {
                            dismiss();
                          },
                          deleteSlashByDefault: deleteSlashByDefault,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );

    Overlay.of(context, rootOverlay: true).insert(_selectionMenuEntry!);

    editorState.service.keyboardService?.disable(showCursor: true);
    editorState.service.scrollService?.disable();
  }

  /// the workaround for: editor auto scrolling that will cause wrong position
  /// of slash menu
  void _checkPositionAfterScrolling() {
    final position = _getCurrentPosition();
    if (position == null) return;
    if (position == _positionNotifier.value) {
      Future.delayed(const Duration(milliseconds: 100)).then((_) {
        final position = _getCurrentPosition();
        if (position == null) return;
        if (position != _positionNotifier.value) {
          _positionNotifier.value = position;
        }
      });
    } else {
      _positionNotifier.value = position;
    }
  }

  _Position? _getCurrentPosition() {
    final selectionRects = editorState.selectionRects();
    if (selectionRects.isEmpty) {
      return null;
    }
    final screenSize = MediaQuery.of(context).size;
    calculateSelectionMenuOffset(selectionRects.first, screenSize);
    final (left, top, right, bottom) = getPosition();
    return _Position(left, top, right, bottom);
  }

  @override
  Alignment get alignment {
    return _alignment;
  }

  @override
  Offset get offset {
    return _offset;
  }

  @override
  (double? left, double? top, double? right, double? bottom) getPosition() {
    double? left, top, right, bottom;
    switch (alignment) {
      case Alignment.topLeft:
        left = offset.dx;
        top = offset.dy;
        break;
      case Alignment.bottomLeft:
        left = offset.dx;
        bottom = offset.dy;
        break;
      case Alignment.topRight:
        right = offset.dx;
        top = offset.dy;
        break;
      case Alignment.bottomRight:
        right = offset.dx;
        bottom = offset.dy;
        break;
    }
    return (left, top, right, bottom);
  }

  void calculateSelectionMenuOffset(Rect rect, Size screenSize) {
    // 使用屏幕尺寸计算菜单位置：
    // rect 是光标的全局坐标，Overlay 中的 SizedBox 也覆盖整个屏幕，
    // 因此 left/right/top/bottom 都基于屏幕坐标系，与光标坐标一致。
    const menuHeight = 192.0, menuWidth = 240.0;
    final screenHeight = screenSize.height;
    final screenWidth = screenSize.width;
    final rectHeight = rect.height;

    // 光标的全局坐标
    final cursorX = rect.left;
    final cursorY = rect.top;

    // 默认：菜单在光标下方，左边对齐光标
    // Alignment.bottomRight + right = screenWidth - cursorX - menuWidth
    // → 菜单右边 = screenWidth - right = cursorX + menuWidth
    // → 菜单左边 = cursorX（对齐光标）
    _alignment = Alignment.bottomRight;
    _offset = Offset(
      screenWidth - cursorX - menuWidth,
      screenHeight - cursorY - menuHeight - rectHeight,
    );

    // 如果下方空间不够，菜单在光标上方
    if (cursorY + menuHeight >= screenHeight) {
      if (cursorY > menuHeight) {
        _offset = Offset(
          _offset.dx,
          cursorY - menuHeight,
        );
        _alignment = Alignment.topRight;
      } else {
        _offset = Offset(
          _offset.dx,
          screenHeight - menuHeight - rectHeight,
        );
      }
    }

    // 如果右边空间不够，菜单改为右边对齐光标
    if (cursorX + menuWidth >= screenWidth) {
      if (cursorX > menuWidth) {
        _alignment = _alignment == Alignment.bottomRight
            ? Alignment.bottomLeft
            : Alignment.topLeft;
        _offset = Offset(
          cursorX - menuWidth,
          _offset.dy,
        );
      } else {
        _offset = Offset(
          screenWidth - menuWidth,
          _offset.dy,
        );
      }
    }
  }
}

class _Position {
  const _Position(this.left, this.top, this.right, this.bottom);

  final double? left;
  final double? top;
  final double? right;
  final double? bottom;

  static const _Position zero = _Position(0, 0, 0, 0);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _Position &&
          runtimeType == other.runtimeType &&
          left == other.left &&
          top == other.top &&
          right == other.right &&
          bottom == other.bottom;

  @override
  int get hashCode =>
      left.hashCode ^ top.hashCode ^ right.hashCode ^ bottom.hashCode;
}
