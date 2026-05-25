import 'dart:async';

import 'package:appflowy_backend/log.dart';

/// 用于在恢复垃圾箱项目时通知 FavoriteBloc 刷新最爱列表
class FavoriteRefreshNotifier {
  static final _controller = StreamController<void>.broadcast();

  static Stream<void> get stream => _controller.stream;

  /// 通知 FavoriteBloc 刷新
  static void notify() {
    Log.debug('[FavoriteRefreshNotifier] notify() called');
    _controller.add(null);
  }
}
