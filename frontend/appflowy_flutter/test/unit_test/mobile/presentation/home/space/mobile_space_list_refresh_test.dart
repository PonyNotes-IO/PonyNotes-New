import 'package:appflowy/mobile/presentation/home/space/mobile_space_list_refresh.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(MobileSpaceListRefreshNotifier.instance.reset);

  test('Android keeps the loaded document sequence while switching documents',
      () {
    expect(
      mobileSpaceKeepsDocumentListCached(isAndroid: true),
      isTrue,
    );
  });

  test('non-Android clients keep the existing refresh behavior', () {
    expect(
      mobileSpaceKeepsDocumentListCached(isAndroid: false),
      isFalse,
    );
  });

  test('跨空间移动只递增目标空间的刷新版本', () {
    final notifier = MobileSpaceListRefreshNotifier.instance;

    notifier.requestRefresh('private-a');

    expect(notifier.revisionFor('private-a'), 1);
    expect(notifier.revisionFor('private-b'), 0);
  });

  test('同一目标空间的重复移动均产生新刷新版本', () {
    final notifier = MobileSpaceListRefreshNotifier.instance;

    notifier
      ..requestRefresh('private-a')
      ..requestRefresh('private-a');

    expect(notifier.revisionFor('private-a'), 2);
  });

  test('删除文档后可显式请求所属空间列表刷新', () {
    final notifier = MobileSpaceListRefreshNotifier.instance;

    notifier.requestRefresh('space-containing-deleted-view');

    expect(notifier.revisionFor('space-containing-deleted-view'), 1);
  });
}
