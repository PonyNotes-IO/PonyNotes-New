import 'package:appflowy/plugins/inline_actions/handlers/inline_page_reference.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/recent/cached_recent_service.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecentViews extends CachedRecentService {
  _RecentViews(this.views);
  final List<ViewPB> views;
  @override
  Future<List<SectionViewPB>> recentViews() async => [
        for (final view in views) SectionViewPB(item: view),
      ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'recent references hide the workspace root even when cached metadata has no workspace ID',
      () async {
    getIt.pushNewScope();
    addTearDown(getIt.popScope);
    getIt.registerSingleton<CachedRecentService>(
      _RecentViews([
        ViewPB(id: 'workspace-id', name: 'Workspace'),
        ViewPB(
          id: 'normal-note',
          name: 'Workspace',
          workspaceId: 'workspace-id',
        ),
        ViewPB(
          id: 'another-note',
          name: 'Readable note',
          workspaceId: 'workspace-id',
        ),
      ]),
    );
    final service = InlinePageReferenceService(
      currentViewId: 'current',
      workspaceId: 'workspace-id',
    );
    addTearDown(service.dispose);
    final results = await service.search();
    expect(
      results.results.map((item) => item.label),
      ['Workspace', 'Readable note'],
    );
    final repeated = await service.search();
    expect(repeated.results, hasLength(2));
  });

  test(
      'root filtering uses IDs, including renamed roots and callers without workspace context',
      () async {
    getIt.pushNewScope();
    addTearDown(getIt.popScope);
    getIt.registerSingleton<CachedRecentService>(
      _RecentViews([
        ViewPB(
          id: 'workspace-id',
          name: 'Renamed workspace',
          workspaceId: 'workspace-id',
        ),
        ViewPB(
          id: 'normal-note',
          name: 'Workspace',
          workspaceId: 'workspace-id',
        ),
      ]),
    );
    final service = InlinePageReferenceService(currentViewId: 'current');
    addTearDown(service.dispose);
    final results = await service.search();
    expect(results.results.map((item) => item.label), ['Workspace']);
  });
  test(
      'brackets start with all current-space notes even when recent history is entirely external',
      () async {
    getIt.pushNewScope();
    addTearDown(getIt.popScope);
    getIt.registerSingleton<CachedRecentService>(
      _RecentViews([
        ViewPB(id: 'external', name: 'A external', parentViewId: 'two'),
      ]),
    );
    final service = InlinePageReferenceService(
      currentViewId: 'current',
      workspaceId: 'ws',
      selectBlock: true,
      loadViews: () async => [
        ViewPB(
          id: 'one',
          name: 'Local space',
          extra: '{"is_space":true}',
        ),
        ViewPB(
          id: 'two',
          name: 'Other space',
          extra: '{"is_space":true}',
        ),
        ViewPB(id: 'ws', name: 'Workspace'),
        ViewPB(id: 'current', parentViewId: 'one'),
        ViewPB(
          id: 'local',
          name: 'Z local never visited',
          parentViewId: 'one',
        ),
        ViewPB(id: 'external', name: 'A external', parentViewId: 'two'),
        ViewPB(
          id: 'child',
          name: 'Nested child',
          parentViewId: 'external',
        ),
        ViewPB(
          id: 'deep',
          name: 'Deep descendant',
          parentViewId: 'child',
        ),
      ],
    );
    addTearDown(service.dispose);
    final initial = await service.search();
    expect(initial.results.first.label, startsWith('Z local never visited'));
    expect(
      initial.results.map((item) => item.label),
      contains(startsWith('Nested child')),
    );
    expect(
      initial.results
          .map((item) => item.label)
          .any((label) => label == 'Workspace'),
      isFalse,
    );
    final child = await service.search('Nested child');
    expect(
      child.results
          .firstWhere((item) => item.label.startsWith('Nested child'))
          .label,
      contains('Other space / A external'),
    );
    final deep = await service.search('Deep descendant');
    expect(deep.results.single.label, startsWith('Deep descendant'));
    final path = await service.search('A external');
    expect(
      path.results.map((item) => item.label),
      contains(startsWith('Deep descendant')),
    );
  });

  test(
      'brackets have a full-picker entry when local or nested matches exceed the inline limit',
      () async {
    getIt.pushNewScope();
    addTearDown(getIt.popScope);
    getIt.registerSingleton<CachedRecentService>(_RecentViews([]));
    final service = InlinePageReferenceService(
      currentViewId: 'current',
      workspaceId: 'ws',
      selectBlock: true,
      limitResults: 2,
      loadViews: () async => [
        ViewPB(
          id: 'one',
          name: 'Local space',
          extra: '{"is_space":true}',
        ),
        ViewPB(id: 'current', parentViewId: 'one'),
        for (var i = 0; i < 5; i++)
          ViewPB(id: 'note-$i', name: 'Note $i', parentViewId: 'one'),
      ],
    );
    addTearDown(service.dispose);
    final initial = await service.search();
    expect(initial.results, hasLength(3));
    expect(initial.results.last.onSelected, isNotNull);
    final last = await service.search('Note 4');
    expect(last.results.single.label, startsWith('Note 4'));
  });
}
