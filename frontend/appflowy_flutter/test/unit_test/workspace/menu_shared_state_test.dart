import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('移动后可刷新同一视图的父级元数据', () {
    final state = MenuSharedState(
      view: ViewPB(
        id: 'view-id',
        parentViewId: 'source-space-id',
      ),
    );
    var notificationCount = 0;
    state.addLatestViewListener(() => notificationCount++);

    state.refreshLatestOpenView(
      ViewPB(
        id: 'view-id',
        parentViewId: 'target-space-id',
      ),
    );

    expect(state.latestOpenView?.parentViewId, 'target-space-id');
    expect(notificationCount, 1);
  });

  test('不会用其他视图覆盖当前打开视图', () {
    final state = MenuSharedState(
      view: ViewPB(
        id: 'current-view-id',
        parentViewId: 'source-space-id',
      ),
    );

    state.refreshLatestOpenView(
      ViewPB(
        id: 'other-view-id',
        parentViewId: 'target-space-id',
      ),
    );

    expect(state.latestOpenView?.id, 'current-view-id');
    expect(state.latestOpenView?.parentViewId, 'source-space-id');
  });
}
