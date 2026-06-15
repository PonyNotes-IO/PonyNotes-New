import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';

class MenuSharedState {
  MenuSharedState({
    ViewPB? view,
  }) {
    _latestOpenView.value = view;
  }

  final ValueNotifier<ViewPB?> _latestOpenView = ValueNotifier<ViewPB?>(null);
  final ValueNotifier<ViewPB?> _previousOpenViewNotifier =
      ValueNotifier<ViewPB?>(null);

  /// 在最新打开的视图被覆盖之前，先把上一个视图快照到这里。
  /// 用于"返回上一文档"功能：例如在 doc A 内通过 sub_page 块自动跳转到
  /// 新建的 doc B 时，B 的左上角会出现返回按钮，点击后回到 A。
  ViewPB? get previousOpenView => _previousOpenViewNotifier.value;
  ValueNotifier<ViewPB?> get previousOpenViewNotifier =>
      _previousOpenViewNotifier;

  void setPreviousOpenView(ViewPB? view) {
    if (_previousOpenViewNotifier.value?.id != view?.id) {
      _previousOpenViewNotifier.value = view;
    }
  }

  void clearPreviousOpenView() {
    if (_previousOpenViewNotifier.value != null) {
      _previousOpenViewNotifier.value = null;
    }
  }

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
