import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';
import 'package:protobuf/protobuf.dart';

/// Forwards view deletion notifications to the page host.
///
/// Some plugins render their own page instead of using [DocumentPage], so
/// they need the same deletion-to-host bridge that document plugins provide.
class PluginDeletionListener extends StatefulWidget {
  const PluginDeletionListener({
    super.key,
    required this.notifier,
    required this.onDeleted,
    required this.child,
  });

  final ViewPluginNotifier notifier;
  final Function(ViewPB, int?)? onDeleted;
  final Widget child;

  @override
  State<PluginDeletionListener> createState() => _PluginDeletionListenerState();
}

class _PluginDeletionListenerState extends State<PluginDeletionListener> {
  @override
  void initState() {
    super.initState();
    widget.notifier.isDeleted.addListener(_handleDeleted);
  }

  @override
  void didUpdateWidget(covariant PluginDeletionListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notifier != widget.notifier) {
      oldWidget.notifier.isDeleted.removeListener(_handleDeleted);
      widget.notifier.isDeleted.addListener(_handleDeleted);
    }
  }

  void _handleDeleted() {
    final deletedView = widget.notifier.isDeleted.value;
    if (deletedView == null) {
      return;
    }

    final index = deletedView.hasIndex() ? deletedView.index : null;
    widget.onDeleted?.call(widget.notifier.view, index);
  }

  @override
  void dispose() {
    widget.notifier.isDeleted.removeListener(_handleDeleted);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class ViewPluginNotifier extends PluginNotifier<DeletedViewPB?> {
  ViewPluginNotifier({
    required ViewPB view,
  })  : _view = view,
        viewNotifier = ValueNotifier(view),
        _viewListener = ViewListener(viewId: view.id) {
    _viewListener?.start(
      onViewUpdated: (updatedView) {
        _view = updatedView;
        viewNotifier.value = updatedView;
      },
      onViewMoveToTrash: (result) => result.fold(
        (deletedView) => isDeleted.value = deletedView,
        (err) => Log.error(err),
      ),
    );
  }

  ViewPB _view;
  ViewPB get view => _view;
  set view(ViewPB value) {
    _view = value;
    viewNotifier.value = value;
  }

  final ValueNotifier<ViewPB> viewNotifier;
  final ViewListener? _viewListener;

  /// 乐观更新视图名称，立即通知 [viewNotifier] 监听者，
  /// 无需等待后端 DidUpdateView 通知回传。
  void updateViewName(String newName) {
    _view.freeze();
    _view = _view.rebuild((b) => b.name = newName);
    viewNotifier.value = _view;
  }

  @override
  final ValueNotifier<DeletedViewPB?> isDeleted = ValueNotifier(null);

  @override
  void dispose() {
    isDeleted.dispose();
    viewNotifier.dispose();
    _viewListener?.stop();
  }
}
