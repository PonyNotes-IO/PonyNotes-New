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
  String? _openedFromFavoriteOrSharedViewId;
  String? _sidebarExpandButtonViewId;

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

  void markOpenedFromFavoriteOrShared(ViewPB view) {
    _openedFromFavoriteOrSharedViewId = view.id;
    _sidebarExpandButtonViewId = view.id;
  }

  bool isOpenedFromFavoriteOrShared(ViewPB? view) {
    return view != null && _openedFromFavoriteOrSharedViewId == view.id;
  }

  void clearOpenedFromFavoriteOrShared([ViewPB? view]) {
    if (view == null || _openedFromFavoriteOrSharedViewId == view.id) {
      _openedFromFavoriteOrSharedViewId = null;
    }
  }

  bool shouldShowSidebarExpandButton(ViewPB? view) {
    return view != null && _sidebarExpandButtonViewId == view.id;
  }

  void clearSidebarExpandButton([ViewPB? view]) {
    if (view == null || _sidebarExpandButtonViewId != null) {
      _sidebarExpandButtonViewId = null;
    }
  }
}
