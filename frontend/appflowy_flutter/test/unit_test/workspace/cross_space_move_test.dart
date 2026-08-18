import 'dart:convert';

import 'package:appflowy/features/workspace/logic/workspace_state.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/cross_space_move.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_room_service.dart';
import 'package:appflowy/workspace/application/menu/sidebar_sections_bloc.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart'
    hide AFRolePB;
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:fixnum/fixnum.dart';
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
}
