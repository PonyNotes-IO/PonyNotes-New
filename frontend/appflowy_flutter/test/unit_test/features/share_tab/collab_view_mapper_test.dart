import 'package:appflowy/features/share_tab/data/collab_view_mapper.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('carries owner workspace into the navigation ViewPB', () {
    final item = sharedCollabViewFromJson({
      'oid': 'view-1',
      'name': 'Shared note',
      'owner_workspace_id': 'workspace-w1',
      'view_layout': 0,
      'created_at': '2026-07-30T00:00:00Z',
    });

    expect(item, isNotNull);
    expect(item!.ownerWorkspaceId, 'workspace-w1');
    expect(item.view.workspaceId, 'workspace-w1');
    expect(item.view.layout, ViewLayoutPB.Document);
    expect(
      item.view.createTime.toInt(),
      DateTime.parse('2026-07-30T00:00:00Z').millisecondsSinceEpoch ~/ 1000,
    );
  });

  test('supports camelCase aliases and numeric timestamps', () {
    final item = sharedCollabViewFromJson({
      'objectId': 'view-2',
      'ownerWorkspaceId': 'workspace-w2',
      'viewLayout': '2',
      'create_time': 1775000000000,
    });

    expect(item, isNotNull);
    expect(item!.view.id, 'view-2');
    expect(item.ownerWorkspaceId, 'workspace-w2');
    expect(item.view.workspaceId, 'workspace-w2');
    expect(item.view.layout, ViewLayoutPB.Board);
    expect(item.view.createTime.toInt(), 1775000000);
  });

  test('returns null when the shared entry has no view id', () {
    expect(sharedCollabViewFromJson({'name': 'Invalid'}), isNull);
  });

  test('preserves owner workspace when replacing view details', () {
    final item = SharedCollabView(
      view: ViewPB()..id = 'view-1',
      ownerWorkspaceId: 'workspace-w1',
    );
    final detailed = ViewPB()
      ..id = 'view-1'
      ..name = 'Resolved title';

    final result = item.copyWith(view: detailed);

    expect(result.ownerWorkspaceId, 'workspace-w1');
    expect(result.view.name, 'Resolved title');
    expect(result.view.workspaceId, 'workspace-w1');
  });
}
