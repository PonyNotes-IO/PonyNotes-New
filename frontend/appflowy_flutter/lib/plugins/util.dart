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

  @override
  final ValueNotifier<DeletedViewPB?> isDeleted = ValueNotifier(null);

  @override
  void dispose() {
    isDeleted.dispose();
    viewNotifier.dispose();
    _viewListener?.stop();
  }
}
