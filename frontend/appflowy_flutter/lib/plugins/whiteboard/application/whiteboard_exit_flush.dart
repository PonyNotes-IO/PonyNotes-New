import 'dart:async';

import 'package:appflowy_backend/log.dart';

/// 协作白板"切走前冲刷保存"协调器。
///
/// 背景（2026-07-17 慢机器多人协作丢最后编辑根因修复）：
/// A 套在线协作白板（RemoteWhiteboardPage + InAppWebView 加载 xm-arts）在切换视图 /
/// 关闭标签时会被同步 dispose，底层 WebView 随之销毁并中断仍在飞行中的保存请求。
/// 慢机器上"最后一小段编辑"来不及推到服务器 → 别人重载看不到。
///
/// Flutter 的 State.dispose() 是同步的、无法 await。真正能"等保存完成再销毁"的时机
/// 在上游：切换/关闭标签由 TabsBloc 的异步事件处理器触发（emit → 同步 dispose 当前
/// plugin）。因此在 emit 之前 await 一次当前已挂载白板的保存冲刷（各自带超时兜底），
/// 即可保证最后一次保存在 WebView 销毁前完成或超时。
///
/// 每个 RemoteWhiteboardPage 在 initState 时用自身实例作为 key 注册一个冲刷回调，
/// dispose 时注销；这里按实例 key 存储，避免同一 viewId 新旧页面重建时互相误删。
class WhiteboardExitFlush {
  WhiteboardExitFlush._();

  static final WhiteboardExitFlush instance = WhiteboardExitFlush._();

  /// key 为注册方的实例对象（保证唯一），value 为其冲刷回调（自身应带超时兜底）。
  final Map<Object, Future<void> Function()> _callbacks =
      <Object, Future<void> Function()>{};

  /// 是否存在已挂载的协作白板（用于上游快速判断是否需要 await 冲刷）。
  bool get hasActive => _callbacks.isNotEmpty;

  void register(Object key, Future<void> Function() flush) {
    _callbacks[key] = flush;
  }

  void unregister(Object key) {
    _callbacks.remove(key);
  }

  /// 冲刷所有已挂载协作白板：触发退出保存并等待完成。
  ///
  /// 每个回调自身带 2s 超时兜底；这里再包一层总超时（3s），绝不阻塞 UI 过久。
  /// 未改动的白板会因"版本未变"守卫在 JS 侧快速返回，几乎零开销。
  Future<void> flushAll() async {
    if (_callbacks.isEmpty) return;
    final callbacks = List<Future<void> Function()>.from(_callbacks.values);
    try {
      await Future.wait(
        callbacks.map((cb) {
          try {
            return cb();
          } catch (e) {
            Log.warn('[WhiteboardExitFlush] 冲刷回调异常: $e');
            return Future<void>.value();
          }
        }),
      ).timeout(const Duration(seconds: 3));
    } catch (e) {
      Log.warn('[WhiteboardExitFlush] 冲刷保存超时或异常，继续销毁: $e');
    }
  }
}
