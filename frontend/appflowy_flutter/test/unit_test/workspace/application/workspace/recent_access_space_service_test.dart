import 'dart:async';
import 'dart:convert';

import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/workspace/recent_access_space_service.dart';
import 'package:appflowy/workspace/application/workspace/workspace_service.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('复用已经存在的“最近访问”私有空间', () async {
    final existingSpace = _space(
      id: 'recent-space',
      name: RecentAccessSpaceService.spaceName,
    );
    final workspaceService = _FakeWorkspaceService(
      workspaceId: 'existing-workspace',
      privateViews: [
        ViewPB(
          id: 'same-name-document',
          name: RecentAccessSpaceService.spaceName,
          layout: ViewLayoutPB.Document,
        ),
        existingSpace,
      ],
    );

    final result = await RecentAccessSpaceService(
      workspaceId: 'existing-workspace',
      userId: fixnum.Int64.ONE,
      workspaceService: workspaceService,
      logInfo: (_) {},
    ).getOrCreate();

    expect(result.space.id, existingSpace.id);
    expect(result.wasCreated, isFalse);
    expect(workspaceService.createCalls, 0);
  });

  test('不存在时自动创建“最近访问”私有空间', () async {
    final createdSpace = _space(
      id: 'created-recent-space',
      name: RecentAccessSpaceService.spaceName,
    );
    final workspaceService = _FakeWorkspaceService(
      workspaceId: 'missing-workspace',
      privateViews: const [],
      createdSpace: createdSpace,
    );

    final result = await RecentAccessSpaceService(
      workspaceId: 'missing-workspace',
      userId: fixnum.Int64.ONE,
      workspaceService: workspaceService,
      logInfo: (_) {},
    ).getOrCreate();

    expect(result.space.id, createdSpace.id);
    expect(result.wasCreated, isTrue);
    expect(workspaceService.createCalls, 1);
    expect(
      workspaceService.createdName,
      RecentAccessSpaceService.spaceName,
    );
    expect(workspaceService.createdSection, ViewSectionPB.Private);
    expect(workspaceService.createdLayout, ViewLayoutPB.Document);
    expect(workspaceService.createdSetAsCurrent, isFalse);
    expect(
      jsonDecode(workspaceService.createdExtra!),
      containsPair(ViewExtKeys.isSpaceKey, true),
    );
    expect(
      jsonDecode(workspaceService.createdExtra!),
      containsPair(ViewExtKeys.spacePermissionKey, 1),
    );
  });

  test('同一工作区并发请求只创建一个“最近访问”空间', () async {
    final createCompleter = Completer<ViewPB>();
    final workspaceService = _FakeWorkspaceService(
      workspaceId: 'concurrent-workspace',
      privateViews: const [],
      createCompleter: createCompleter,
    );
    final firstService = RecentAccessSpaceService(
      workspaceId: 'concurrent-workspace',
      userId: fixnum.Int64.ONE,
      workspaceService: workspaceService,
      logInfo: (_) {},
    );
    final secondService = RecentAccessSpaceService(
      workspaceId: 'concurrent-workspace',
      userId: fixnum.Int64.ONE,
      workspaceService: workspaceService,
      logInfo: (_) {},
    );

    final first = firstService.getOrCreate();
    final second = secondService.getOrCreate();
    await Future<void>.delayed(Duration.zero);

    expect(workspaceService.createCalls, 1);
    createCompleter.complete(
      _space(
        id: 'single-recent-space',
        name: RecentAccessSpaceService.spaceName,
      ),
    );

    final results = await Future.wait([first, second]);
    expect(results.map((result) => result.space.id).toSet(), {
      'single-recent-space',
    });
    expect(workspaceService.createCalls, 1);
  });
}

ViewPB _space({required String id, required String name}) {
  return ViewPB(
    id: id,
    name: name,
    layout: ViewLayoutPB.Document,
    extra: jsonEncode({
      ViewExtKeys.isSpaceKey: true,
      ViewExtKeys.spacePermissionKey: 1,
    }),
  );
}

class _FakeWorkspaceService extends WorkspaceService {
  _FakeWorkspaceService({
    required super.workspaceId,
    required this.privateViews,
    this.createdSpace,
    this.createCompleter,
  }) : super(userId: fixnum.Int64.ONE);

  final List<ViewPB> privateViews;
  final ViewPB? createdSpace;
  final Completer<ViewPB>? createCompleter;

  int createCalls = 0;
  String? createdName;
  ViewSectionPB? createdSection;
  ViewLayoutPB? createdLayout;
  bool? createdSetAsCurrent;
  String? createdExtra;

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getPrivateViews() async {
    return FlowyResult.success(privateViews);
  }

  @override
  Future<FlowyResult<ViewPB, FlowyError>> createView({
    required String name,
    required ViewSectionPB viewSection,
    int? index,
    ViewLayoutPB? layout,
    bool? setAsCurrent,
    String? viewId,
    String? extra,
  }) async {
    createCalls++;
    createdName = name;
    createdSection = viewSection;
    createdLayout = layout;
    createdSetAsCurrent = setAsCurrent;
    createdExtra = extra;

    final view =
        createCompleter != null ? await createCompleter!.future : createdSpace!;
    return FlowyResult.success(view);
  }
}
