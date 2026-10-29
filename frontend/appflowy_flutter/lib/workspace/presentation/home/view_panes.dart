import 'dart:math' as math;

import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Captured by page menus before their popover moves into the root overlay.
class ViewPaneScope extends InheritedWidget {
  const ViewPaneScope({
    super.key,
    required this.split,
    required super.child,
  });

  final void Function(Axis axis) split;

  static ViewPaneScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ViewPaneScope>();

  @override
  bool updateShouldNotify(ViewPaneScope oldWidget) => split != oldWidget.split;
}

class ViewPanes extends StatefulWidget {
  const ViewPanes({
    super.key,
    required this.view,
    required this.builder,
    this.onActiveViewChanged,
  });

  final ViewPB view;
  final Widget Function(BuildContext context, ViewPB view) builder;
  final ValueChanged<ViewPB>? onActiveViewChanged;

  @override
  State<ViewPanes> createState() => ViewPanesState();
}

class _Pane {
  _Pane(this.view);

  final key = UniqueKey();
  ViewPB? view;
  Axis axis = Axis.horizontal;
  double ratio = 0.5;
  _Pane? first;
  _Pane? second;
}

class ViewPanesState extends State<ViewPanes> {
  late _Pane _root = _Pane(widget.view);
  late _Pane _active = _root;

  void split(Axis axis) => _split(_active, axis);

  @override
  void didUpdateWidget(ViewPanes oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view != widget.view) {
      _active.view = widget.view;
    }
  }

  void _activate(_Pane pane) {
    if (_active == pane) return;
    setState(() => _active = pane);
    widget.onActiveViewChanged?.call(pane.view!);
  }

  void _split(_Pane pane, Axis axis) {
    final copy = _Pane(pane.view);
    final branch = _Pane(null)
      ..axis = axis
      ..first = pane
      ..second = copy;
    setState(() {
      _root = _replace(_root, pane, branch);
      _active = copy;
    });
    widget.onActiveViewChanged?.call(copy.view!);
  }

  _Pane _replace(_Pane node, _Pane target, _Pane replacement) {
    if (node == target) return replacement;
    if (node.first != null) {
      node.first = _replace(node.first!, target, replacement);
      node.second = _replace(node.second!, target, replacement);
    }
    return node;
  }

  _Pane _remove(_Pane node, _Pane target) {
    if (node.first == target) return node.second!;
    if (node.second == target) return node.first!;
    if (node.first != null) {
      node.first = _remove(node.first!, target);
      node.second = _remove(node.second!, target);
    }
    return node;
  }

  void _close(_Pane pane) {
    if (_root == pane) return;
    setState(() {
      _root = _remove(_root, pane);
      if (_active == pane) {
        _active = _root;
        while (_active.first != null) {
          _active = _active.first!;
        }
      }
    });
    widget.onActiveViewChanged?.call(_active.view!);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final panes = <Widget>[];
        final dividers = <Widget>[];
        final isSplit = _root.first != null;

        void layout(_Pane node, Rect bounds) {
          if (node.first == null) {
            panes.add(
              Positioned.fromRect(
                key: node.key,
                rect: bounds,
                child: ViewPaneScope(
                  split: (axis) => _split(node, axis),
                  child: Listener(
                    onPointerDown: (_) => _activate(node),
                    child: Focus(
                      canRequestFocus: false,
                      onFocusChange: (focused) {
                        if (focused) _activate(node);
                      },
                      child: ClipRect(
                        child: Column(
                          children: [
                            if (isSplit)
                              Container(
                                height: 32,
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: _active == node
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primary
                                          : Theme.of(context).dividerColor,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        node.view!.nameOrDefault,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ),
                                    IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints:
                                          const BoxConstraints.tightFor(
                                        width: 30,
                                        height: 30,
                                      ),
                                      iconSize: 16,
                                      tooltip: 'viewPanes.closePane'.tr(),
                                      icon: const Icon(Icons.close),
                                      onPressed: () => _close(node),
                                    ),
                                  ],
                                ),
                              )
                            else
                              const SizedBox.shrink(),
                            Expanded(
                              child: Builder(
                                builder: (context) =>
                                    widget.builder(context, node.view!),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            return;
          }

          final horizontal = node.axis == Axis.horizontal;
          final extent =
              math.max(0.0, (horizontal ? bounds.width : bounds.height) - 5);
          final firstExtent = extent * node.ratio;
          final firstBounds = Rect.fromLTWH(
            bounds.left,
            bounds.top,
            horizontal ? firstExtent : bounds.width,
            horizontal ? bounds.height : firstExtent,
          );
          final secondBounds = Rect.fromLTWH(
            horizontal ? bounds.left + firstExtent + 5 : bounds.left,
            horizontal ? bounds.top : bounds.top + firstExtent + 5,
            horizontal ? extent - firstExtent : bounds.width,
            horizontal ? bounds.height : extent - firstExtent,
          );
          layout(node.first!, firstBounds);
          layout(node.second!, secondBounds);

          void resize(double delta) {
            if (extent <= 0) return;
            final minimum = math.min(160.0, extent / 2) / extent;
            setState(() {
              node.ratio =
                  (node.ratio + delta / extent).clamp(minimum, 1 - minimum);
            });
          }

          dividers.add(
            Positioned(
              key: node.key,
              left: horizontal ? firstBounds.right : bounds.left,
              top: horizontal ? bounds.top : firstBounds.bottom,
              width: horizontal ? 5 : bounds.width,
              height: horizontal ? bounds.height : 5,
              child: Semantics(
                label: 'viewPanes.resizePanes'.tr(),
                child: MouseRegion(
                  cursor: horizontal
                      ? SystemMouseCursors.resizeLeftRight
                      : SystemMouseCursors.resizeUpDown,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: horizontal
                        ? (details) => resize(details.delta.dx)
                        : null,
                    onVerticalDragUpdate: horizontal
                        ? null
                        : (details) => resize(details.delta.dy),
                    child: ColoredBox(color: Theme.of(context).dividerColor),
                  ),
                ),
              ),
            ),
          );
        }

        layout(_root, Offset.zero & constraints.biggest);
        // Keep every editor under the same Stack when the split tree changes.
        return Stack(children: [...panes, ...dividers]);
      },
    );
  }
}
