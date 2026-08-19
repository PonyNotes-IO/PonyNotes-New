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
