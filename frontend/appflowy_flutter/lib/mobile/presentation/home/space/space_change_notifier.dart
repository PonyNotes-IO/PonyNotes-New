import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';

/// Notifier for global space changes (e.g. create / delete / update).
///
/// Although it lives in the `mobile/` folder, it's used by **both** mobile
/// and desktop `SpaceBloc` instances — name kept as-is to avoid touching
/// dozens of call sites, but the class itself is platform-agnostic.
///
/// `MobileSpaceManagementPage` (and any other component that mutates spaces
/// via a private `SpaceBloc` instance) should call
/// [SpaceChangeNotifier.notifySpacesChanged] after the mutation is
/// persisted to the backend, so the home screen's `SpaceBloc` (which is a
/// different instance) can re-dispatch `SpaceEvent.initial` to refresh its
/// `spaces` list.
///
/// For freshly created spaces, prefer [notifySpaceCreated] which also
/// passes the new [ViewPB] along, so listeners can immediately merge it
/// into their `SpaceBloc.state.spaces` without waiting for backend
/// `getPublicViews` cache (which can lag several seconds).
///
/// Listeners are responsible for any UX workarounds (e.g. backend
/// `getPublicViews` cache lag that briefly omits the just-created space);
/// the notifier itself is intentionally a thin pub-sub.
class SpaceChangeNotifier extends ChangeNotifier {
  SpaceChangeNotifier._();
  static final SpaceChangeNotifier instance =
      SpaceChangeNotifier._();

  /// Bumps a counter and notifies listeners. Listeners should trigger a
  /// refresh on their `SpaceBloc` (e.g. re-add `SpaceEvent.initial`).
  void notifySpacesChanged() {
    notifyListeners();
  }

  /// Push a freshly-created [ViewPB] (already persisted on the backend) to
  /// all listeners. Listeners should:
  ///   1) Merge [newSpace] into their `SpaceBloc.state.spaces` right away
  ///      (do not wait for backend `getPublicViews` cache to sync).
  ///   2) Still re-dispatch `SpaceEvent.initial` to pick up backend state.
  void notifySpaceCreated(ViewPB newSpace) {
    // 全局跟踪这个 space 为"待 backend cache 同步"，任何客户端
    // `SpaceBloc` 在拉 backend 时都会保留它，避免被覆盖。
    _markPendingInternal(newSpace.id);
    _lastCreatedSpace = newSpace;
    notifyListeners();
    // 5s 后清空 _lastCreatedSpace，避免下次普通 notifySpacesChanged 又
    // 把同一个 space 重复 push 进去。
    // 注意：_pendingNewSpaceIds 不能在这里清，它要等任何拉取 backend
    // 拉到该 id 时再清（可能跨多个客户端实例）。
    Future<void>.delayed(const Duration(seconds: 5), () {
      if (identical(_lastCreatedSpace, newSpace)) {
        _lastCreatedSpace = null;
      }
    });
  }

  /// 把一个 space id 标记为"全局 pending"，但不触发 `notifyListeners`。
  /// 适用于 `SpaceBloc._createSpace` 这种"本地 bloc 已经 emit，UI 已经
  /// 刷新，但还要防止其它 bloc 实例的 `initial` 覆盖它"的场景。
  void markPendingNewSpace(String spaceId) {
    _markPendingInternal(spaceId);
  }

  void _markPendingInternal(String spaceId) {
    _pendingNewSpaceIds.add(spaceId);
  }

  ViewPB? _lastCreatedSpace;

  /// Most recently notified freshly-created space, or null.
  ViewPB? get lastCreatedSpace => _lastCreatedSpace;

  /// 全局待同步集合：所有客户端创建的、backend cache 还没拉到的 space id。
  /// 任何 `SpaceBloc` 在执行 `initial` / `didReceiveSpaceUpdate` 拉取
  /// backend 时都应该：
  ///   1) 从这里读 pending ids；
  ///   2) 把仍然 pending 的 space 从自己 `state.spaces` 里 merge 出来；
  ///   3) 把这次 backend 拉到（即 backend cache 已同步）的 id 从这里
  ///      清掉。
  final Set<String> _pendingNewSpaceIds = <String>{};

  Set<String> get pendingNewSpaceIds => Set.unmodifiable(_pendingNewSpaceIds);

  /// 检查某个 id 是否仍 pending（backend cache 还没同步）。
  bool isPending(String id) => _pendingNewSpaceIds.contains(id);

  /// 当 backend 拉取到某个 pending id 时调用，从 pending set 里清除。
  /// 返回这次被 resolved 的 id 数量。
  int resolvePending(Iterable<String> fetchedIds) {
    final resolved = _pendingNewSpaceIds.where(fetchedIds.contains).toList();
    for (final id in resolved) {
      _pendingNewSpaceIds.remove(id);
    }
    return resolved.length;
  }
}
