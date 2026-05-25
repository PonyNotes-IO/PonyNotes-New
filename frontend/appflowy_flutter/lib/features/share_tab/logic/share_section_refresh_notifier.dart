import 'dart:async';

/// 共享区域刷新通知器
/// 用于在生成分享链接后，通知侧边栏"共享"菜单立即刷新数据
class ShareSectionRefreshNotifier {
  ShareSectionRefreshNotifier._();

  static final _controller = StreamController<void>.broadcast();

  static Stream<void> get stream => _controller.stream;

  static void notify() {
    _controller.add(null);
  }
}
