import 'dart:async';
import 'dart:convert';

import 'package:appflowy/features/workspace/logic/workspace_state.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/cross_space_move.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/draggable_view_item.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_room_service.dart';
import 'package:appflowy/workspace/application/menu/sidebar_sections_bloc.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart'
    hide AFRolePB;
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cross-space move permissions', () {
    test('fails closed when role is missing', () {
      expect(
        crossSpaceMoveDenyReasonForRole(null, ViewSectionPB.Public),
        isNotNull,
      );
      expect(
        crossSpaceMoveDenyReasonForRole(null, ViewSectionPB.Private),
        isNotNull,
      );
    });

    test('allows members into shared space but only owners out', () {
      expect(
        crossSpaceMoveDenyReasonForRole(AFRolePB.Guest, ViewSectionPB.Public),
        isNotNull,
      );
      expect(
        crossSpaceMoveDenyReasonForRole(AFRolePB.Member, ViewSectionPB.Public),
        isNull,
      );
      expect(
        crossSpaceMoveDenyReasonForRole(AFRolePB.Member, ViewSectionPB.Private),
        isNotNull,
      );
      expect(
        crossSpaceMoveDenyReasonForRole(AFRolePB.Owner, ViewSectionPB.Private),
        isNull,
      );
    });
  });

  test('only the whiteboard creator can move a whiteboard', () {
    final whiteboardWithoutCreator = ViewPB()..layout = ViewLayoutPB.Whiteboard;
    final whiteboard = ViewPB()
      ..layout = ViewLayoutPB.Whiteboard
      ..createdBy = Int64(42);
    final document = ViewPB()..layout = ViewLayoutPB.Document;

    expect(canCurrentUserMoveWhiteboard(whiteboardWithoutCreator, 42), isFalse);
    expect(canCurrentUserMoveWhiteboard(whiteboard, 7), isFalse);
    expect(canCurrentUserMoveWhiteboard(whiteboard, 42), isTrue);
    expect(canCurrentUserMoveWhiteboard(document, 7), isTrue);
  });

  test('encodes room credentials as initial whiteboard data', () {
    final encoded = WhiteboardRoomService.encodeInitialData('room-1', 'key-1');
    final decoded = jsonDecode(utf8.decode(encoded)) as Map<String, dynamic>;

    expect(decoded, {'roomId': 'room-1', 'roomKey': 'key-1'});
  });

  test('同一白板的跨区移动互斥且释放后允许重试', () {
    final guard = CrossSpaceWhiteboardMoveGuard();

    expect(guard.tryAcquire('whiteboard-1'), isTrue);
    expect(guard.tryAcquire('whiteboard-1'), isFalse);
    expect(guard.tryAcquire('whiteboard-2'), isTrue);

    guard.release('whiteboard-1');
    expect(guard.tryAcquire('whiteboard-1'), isTrue);
  });

  test('普通文档移动期间拒绝同一文档重复提交', () {
    final guard = CrossSpaceMoveGuard();

    expect(guard.tryAcquire('document-1'), isTrue);
    expect(guard.tryAcquire('document-1'), isFalse);
    expect(guard.tryAcquire('document-2'), isTrue);

    guard.release('document-1');
    expect(guard.tryAcquire('document-1'), isTrue);
  });

  test('移动完成刷新器不依赖原菜单 context 仍可执行', () {
    var spacesRefreshCount = 0;
    var favoritesRefreshCount = 0;
    final refresher = SidebarMoveStateRefresher(
      refreshSpaces: () => spacesRefreshCount++,
      refreshFavorites: () => favoritesRefreshCount++,
    );

    refresher.refresh();

    expect(spacesRefreshCount, 1);
    expect(favoritesRefreshCount, 1);
  });

  test('桌面端仅在源白板仍是当前视图时登记迁移交接', () {
    expect(
      shouldPrepareDesktopWhiteboardReplacement(
        oldViewId: 'old',
        latestOpenViewId: 'old',
        currentPluginId: 'home',
      ),
      isTrue,
    );
    expect(
      shouldPrepareDesktopWhiteboardReplacement(
        oldViewId: 'old',
        latestOpenViewId: 'other',
        currentPluginId: 'old',
      ),
      isTrue,
    );
    expect(
      shouldPrepareDesktopWhiteboardReplacement(
        oldViewId: 'old',
        latestOpenViewId: 'other',
        currentPluginId: 'home',
      ),
      isFalse,
    );
  });

  group('跨父节点移动的子列表更新', () {
    test('目标列表缺少通知中的文档时识别为结构移动', () {
      final existing = ViewPB()
        ..id = 'existing'
        ..parentViewId = 'target';
      final moved = ViewPB()
        ..id = 'moved'
        ..parentViewId = 'target';
      final update = ChildViewUpdatePB()
        ..parentViewId = 'target'
        ..updateChildViews.add(moved);

      expect(
        childViewUpdateContainsStructuralMove(
          parentViewId: 'target',
          currentChildren: [existing],
          update: update,
        ),
        isTrue,
      );
    });

    test('现有文档的父节点已改变时识别为结构移动', () {
      final moved = ViewPB()
        ..id = 'moved'
        ..parentViewId = 'source';
      final movedUpdate = ViewPB()
        ..id = 'moved'
        ..parentViewId = 'target';
      final update = ChildViewUpdatePB()
        ..parentViewId = 'source'
        ..updateChildViews.add(movedUpdate);

      expect(
        childViewUpdateContainsStructuralMove(
          parentViewId: 'source',
          currentChildren: [moved],
          update: update,
        ),
        isTrue,
      );
    });

    test('同一父节点内已有文档的元数据更新无需结构合并', () {
      final existing = ViewPB()
        ..id = 'existing'
        ..parentViewId = 'target';
      final updated = ViewPB()
        ..id = 'existing'
        ..parentViewId = 'target'
        ..name = 'updated';
      final update = ChildViewUpdatePB()
        ..parentViewId = 'target'
        ..updateChildViews.add(updated);

      expect(
        childViewUpdateContainsStructuralMove(
          parentViewId: 'target',
          currentChildren: [existing],
          update: update,
        ),
        isFalse,
      );
    });

    test('目标列表直接插入通知中的移动文档', () {
      final existing = ViewPB()
        ..id = 'existing'
        ..parentViewId = 'target';
      final moved = ViewPB()
        ..id = 'moved'
        ..parentViewId = 'target';

      final merged = mergeUpdatedChildViews(
        parentViewId: 'target',
        currentChildren: [existing],
        updatedChildren: [moved],
      );

      expect(merged.map((view) => view.id), ['moved', 'existing']);
    });

    test('源列表直接移除父节点已经改变的文档', () {
      final moved = ViewPB()
        ..id = 'moved'
        ..parentViewId = 'source';
      final movedUpdate = ViewPB()
        ..id = 'moved'
        ..parentViewId = 'target';

      final merged = mergeUpdatedChildViews(
        parentViewId: 'source',
        currentChildren: [moved],
        updatedChildren: [movedUpdate],
      );

      expect(merged, isEmpty);
    });
  });

  test('clears a stale workspace role explicitly', () {
    final state = UserWorkspaceState.initial(UserProfilePB()).copyWith(
      currentUserRole: AFRolePB.Owner,
    );

    expect(state.copyWith(clearCurrentUserRole: true).currentUserRole, isNull);
  });

  test('resolves the section of a nested view', () async {
    final child = ViewPB()..id = 'child';
    final root = ViewPB()
      ..id = 'root'
      ..childViews.add(child);
    final bloc = SidebarSectionsBloc();
    final updated = bloc.stream.firstWhere(
      (state) => state.section.publicViews.isNotEmpty,
    );

    bloc.add(
      SidebarSectionsEvent.receiveSectionViewsUpdate(
        SectionViewsPB()
          ..section = ViewSectionPB.Public
          ..views.add(root),
      ),
    );
    await updated;

    expect(bloc.getViewSection(child), ViewSectionPB.Public);
    await bloc.close();
  });

  test('a section update removes the same view from the stale section',
      () async {
    final moved = ViewPB()..id = 'moved';
    final privateRoot = ViewPB()
      ..id = 'private-root'
      ..childViews.add(moved);
    final publicRoot = ViewPB()
      ..id = 'public-root'
      ..childViews.add(moved);
    final bloc = SidebarSectionsBloc();

    bloc.add(
      SidebarSectionsEvent.receiveSectionViewsUpdate(
        SectionViewsPB()
          ..section = ViewSectionPB.Private
          ..views.add(privateRoot),
      ),
    );
    await bloc.stream.firstWhere(
      (state) => state.section.privateViews.isNotEmpty,
    );

    bloc.add(
      SidebarSectionsEvent.receiveSectionViewsUpdate(
        SectionViewsPB()
          ..section = ViewSectionPB.Public
          ..views.add(publicRoot),
      ),
    );
    final state = await bloc.stream.firstWhere(
      (state) => state.section.publicViews.isNotEmpty,
    );

    expect(state.section.publicViews.single.childViews.single.id, 'moved');
    expect(state.section.privateViews.single.childViews, isEmpty);
    expect(bloc.getViewSection(moved), ViewSectionPB.Public);
    await bloc.close();
  });

  test('private-to-private moves use the offline folder path', () {
    expect(
      isOfflinePrivateMove(ViewSectionPB.Private, ViewSectionPB.Private),
      isTrue,
    );
    expect(
      isOfflinePrivateMove(ViewSectionPB.Private, ViewSectionPB.Public),
      isFalse,
    );
  });

  test('drop positions preserve sibling, nesting, and parent-lift semantics',
      () {
    final target = ViewPB()
      ..id = 'target'
      ..parentViewId = 'target-parent';

    expect(
      draggableViewMoveTarget(
        position: DraggableHoverPosition.top,
        target: target,
        previousViewId: 'previous-sibling',
      ),
      (targetParentId: 'target-parent', prevViewId: 'previous-sibling'),
    );
    expect(
      draggableViewMoveTarget(
        position: DraggableHoverPosition.center,
        target: target,
        previousViewId: 'previous-sibling',
      ),
      (targetParentId: 'target', prevViewId: null),
    );
    expect(
      draggableViewMoveTarget(
        position: DraggableHoverPosition.bottom,
        target: target,
        previousViewId: 'previous-sibling',
      ),
      (targetParentId: 'target-parent', prevViewId: 'target'),
    );
  });

  testWidgets('same-section moves wait for the folder result', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (builderContext) {
            context = builderContext;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final view = ViewPB()
      ..id = 'child'
      ..parentViewId = 'old-parent';
    final viewBloc = _RecordingViewBloc();
    var completed = false;
    final move = coordinateViewMove(
      context,
      viewBloc: viewBloc,
      view: view,
      targetParentId: 'new-parent',
      prevViewId: 'previous-sibling',
      fromSection: ViewSectionPB.Public,
      toSection: ViewSectionPB.Public,
    ).then((outcome) {
      completed = true;
      return outcome;
    });

    await tester.pump();
    expect(completed, isFalse);
    expect(viewBloc.newParentId, 'new-parent');
    expect(viewBloc.prevId, 'previous-sibling');
    expect(viewBloc.fromSection, ViewSectionPB.Public);
    expect(viewBloc.toSection, ViewSectionPB.Public);

    viewBloc.moveCompleter.complete(FlowyResult.success(null));
    await tester.pump();

    expect(await move, CrossSpaceMoveOutcome.moved);
    await viewBloc.close();
  });

  testWidgets('private space section resolves from local metadata',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (builderContext) {
            context = builderContext;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    final privateSpace = ViewPB()
      ..id = 'private-space'
      ..extra = jsonEncode({'is_space': true, 'space_permission': 1});

    expect(
      await resolveViewSection(context, privateSpace),
      ViewSectionPB.Private,
    );
  });
}

class _RecordingViewBloc extends ViewBloc {
  _RecordingViewBloc() : super(view: ViewPB()..id = 'recording-view');

  final moveCompleter = Completer<FlowyResult<void, FlowyError>?>();
  String? newParentId;
  String? prevId;
  ViewSectionPB? fromSection;
  ViewSectionPB? toSection;

  @override
  Future<FlowyResult<void, FlowyError>?> moveView({
    required ViewPB from,
    required String newParentId,
    required String? prevId,
    required ViewSectionPB? fromSection,
    required ViewSectionPB? toSection,
  }) {
    this.newParentId = newParentId;
    this.prevId = prevId;
    this.fromSection = fromSection;
    this.toSection = toSection;
    return moveCompleter.future;
  }

  @override
  // ignore: must_call_super
  Future<void> close() async {}
}
