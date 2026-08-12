import 'package:appflowy/plugins/space_hub/space_hub_selection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clicking the selected nested document does not clear selection', () {
    expect(
      spaceHubShouldUpdateSelection('nested-document', 'nested-document'),
      isFalse,
    );
  });

  test('compares child ids by value instead of Set identity', () {
    expect(
      spaceHubChildViewIdsChanged(
        const ['first', 'nested-parent'],
        const ['first', 'nested-parent'],
      ),
      isFalse,
    );
    expect(
      spaceHubChildViewIdsChanged(
        const ['first', 'nested-parent'],
        const ['first', 'new-parent'],
      ),
      isTrue,
    );
  });

  test('document list only reloads when its space changes', () {
    var loadCount = 0;
    final loader = SpaceHubDocumentListLoader<int>(
      spaceId: 'space-a',
      load: (_) async => ++loadCount,
    );

    final initialFuture = loader.future;
    loader.updateSpace('space-a');

    expect(loader.future, same(initialFuture));
    expect(loadCount, 1);

    loader.updateSpace('space-b');

    expect(loader.future, isNot(same(initialFuture)));
    expect(loadCount, 2);
  });

  test('document list can explicitly reload after its data changes', () {
    var loadCount = 0;
    final loader = SpaceHubDocumentListLoader<int>(
      spaceId: 'space-a',
      load: (_) async => ++loadCount,
    );

    loader.reload();

    expect(loadCount, 2);
  });

  test('finds the previous document state after inserting at the top', () {
    expect(
      spaceHubDocumentListChildIndex(
        const ValueKey<String>('space_hub_existing'),
        const ['new', 'existing'],
      ),
      1,
    );
    expect(
      spaceHubDocumentListChildIndex(
        const ValueKey<String>('space_hub_missing'),
        const ['new', 'existing'],
      ),
      isNull,
    );
  });
}
