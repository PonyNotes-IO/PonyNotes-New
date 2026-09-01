import 'package:flutter/foundation.dart';

/// Whether the mobile space document list should keep its existing sequence.
///
/// Android keeps the `ViewBloc` list alive and lets its own view listener apply
/// structural changes. Other clients retain the pre-existing SpaceBloc refresh
/// behavior until they are intentionally migrated.
bool mobileSpaceKeepsDocumentListCached({required bool isAndroid}) => isAndroid;

/// 文档删除或跨空间移动完成后，按空间 ID 驱动移动端文档列表重新加载。
///
/// 这里只保存每个空间的递增版本，不保存一次性事件。这样目标 `MobileSpaceItem`
/// 即使在变更期间被卸载，重新挂载后仍能补消费尚未处理的刷新版本。
class MobileSpaceListRefreshNotifier extends ChangeNotifier {
  MobileSpaceListRefreshNotifier._();

  static final MobileSpaceListRefreshNotifier instance =
      MobileSpaceListRefreshNotifier._();

  final Map<String, int> _revisions = <String, int>{};

  int revisionFor(String spaceId) => _revisions[spaceId] ?? 0;

  void requestRefresh(String spaceId) {
    if (spaceId.isEmpty) {
      return;
    }
    _revisions[spaceId] = revisionFor(spaceId) + 1;
    notifyListeners();
  }

  @visibleForTesting
  void reset() {
    _revisions.clear();
  }
}
