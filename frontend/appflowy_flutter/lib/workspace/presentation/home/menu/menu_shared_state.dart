import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';

class MenuSharedState {
  MenuSharedState({
    ViewPB? view,
  }) {
    _latestOpenView.value = view;
  }

  final ValueNotifier<ViewPB?> _latestOpenView = ValueNotifier<ViewPB?>(null);

  ViewPB? get latestOpenView => _latestOpenView.value;
  ValueNotifier<ViewPB?> get notifier => _latestOpenView;

  set latestOpenView(ViewPB? view) {
    if (_latestOpenView.value?.id != view?.id) {
      _latestOpenView.value = view;
    }
  }

  void addLatestViewListener(VoidCallback listener) {
    _latestOpenView.addListener(listener);
  }

  void removeLatestViewListener(VoidCallback listener) {
    _latestOpenView.removeListener(listener);
  }

  /// 标记当前打开的文档是否来自"最爱"或"共享"列表。
  /// 这些列表没有二级菜单，因此需要在文档页面显示侧边栏展开按钮。
  bool openedFromFavoriteOrShared = false;
}
