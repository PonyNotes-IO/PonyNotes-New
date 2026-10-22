import 'dart:collection';

import 'package:appflowy_popover/appflowy_popover.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'layout.dart';

typedef _EntryMap = LinkedHashMap<PopoverState, OverlayEntryContext>;

class RootOverlayEntry {
  final _EntryMap _entries = _EntryMap();

  bool contains(PopoverState state) => _entries.containsKey(state);

  bool get isEmpty => _entries.isEmpty;
  bool get isNotEmpty => _entries.isNotEmpty;

  void addEntry(
    BuildContext context,
    String id,
    PopoverState newState,
    OverlayEntry entry,
    bool asBarrier,
    AnimationController animationController,
  ) {
    _entries[newState] = OverlayEntryContext(
      id,
      entry,
      newState,
      asBarrier,
      animationController,
    );
    Overlay.of(context).insert(entry);
  }

  void removeEntry(PopoverState state) {
    final removedEntry = _entries.remove(state);
    removedEntry?.overlayEntry.remove();
  }

  OverlayEntryContext? popEntry() {
    if (isEmpty) {
      return null;
    }

    final lastEntry = _entries.values.last;
    _entries.remove(lastEntry.popoverState);
    final animation = lastEntry.animationController.reverse();
    // 重新打开会取消关闭动画，旧弹层仍须清理；关闭通知只在动画完成时发送。
    animation.whenCompleteOrCancel(lastEntry.overlayEntry.remove);
    animation.then((_) {
      lastEntry.popoverState.widget.onClose?.call();
    });

    return lastEntry.asBarrier ? lastEntry : popEntry();
  }

  bool isLastEntryAsBarrier() {
    if (isEmpty) {
      return false;
    }

    return _entries.values.last.asBarrier;
  }
}

class OverlayEntryContext {
  OverlayEntryContext(
    this.id,
    this.overlayEntry,
    this.popoverState,
    this.asBarrier,
    this.animationController,
  );

  final String id;
  final OverlayEntry overlayEntry;
  final PopoverState popoverState;
  final bool asBarrier;
  final AnimationController animationController;

  @override
  String toString() {
    return 'OverlayEntryContext(id: $id, asBarrier: $asBarrier, popoverState: ${popoverState.widget.debugId})';
  }
}

class PopoverMask extends StatelessWidget {
  const PopoverMask({
    super.key,
    required this.onTap,
    this.decoration,
    this.interactiveTarget,
  });

  final VoidCallback onTap;
  final Decoration? decoration;
  final PopoverLink? interactiveTarget;

  @override
  Widget build(BuildContext context) {
    final mask = GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: decoration,
      ),
    );
    final target = interactiveTarget;
    return target == null
        ? mask
        : _InteractivePopoverTarget(link: target, child: mask);
  }
}

class _InteractivePopoverTarget extends SingleChildRenderObjectWidget {
  const _InteractivePopoverTarget({required this.link, required super.child});

  final PopoverLink link;

  @override
  _InteractivePopoverTargetRenderBox createRenderObject(BuildContext context) =>
      _InteractivePopoverTargetRenderBox(link);

  @override
  void updateRenderObject(
    BuildContext context,
    _InteractivePopoverTargetRenderBox renderObject,
  ) =>
      renderObject.link = link;
}

class _InteractivePopoverTargetRenderBox extends RenderProxyBox {
  _InteractivePopoverTargetRenderBox(this.link);

  PopoverLink link;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final offset = link.leaderOffset;
    final size = link.leaderSize;
    if (offset != null &&
        size != null &&
        (offset & size).contains(localToGlobal(position))) {
      return false;
    }
    return super.hitTest(result, position: position);
  }
}
