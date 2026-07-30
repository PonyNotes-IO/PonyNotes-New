import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';

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
