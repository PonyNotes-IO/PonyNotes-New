import 'dart:async';
import 'dart:convert';

import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/features/share_tab/data/collab_workspace_resolver.dart';
import 'package:appflowy/features/share_tab/data/repositories/local_share_with_user_repository_impl.dart';
import 'package:appflowy/features/share_tab/logic/share_tab_bloc.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _SearchRepository extends LocalShareWithUserRepositoryImpl {
  final firstStarted = Completer<void>();
  final firstResult = Completer<FlowyResult<SharedUsers, FlowyError>>();

  @override
  Future<FlowyResult<SharedUsers, FlowyError>> searchUsers({
    required String query,
    int pageNo = 1,
  }) async {
    if (query == 'first') {
      firstStarted.complete();
      return firstResult.future;
    }
    return FlowySuccess([
      SharedUser(
        email: 'latest@example.test',
        name: 'Latest',
        role: ShareRole.guest,
        accessLevel: ShareAccessLevel.readOnly,
      ),
    ]);
  }
}

void main() {
  const pageId = 'test_page_id';
  const workspaceId = 'test_workspace_id';
  late LocalShareWithUserRepositoryImpl repository;
  late ShareTabBloc bloc;

  setUp(() {
    repository = LocalShareWithUserRepositoryImpl();
    bloc = ShareTabBloc(
      repository: repository,
      pageId: pageId,
      workspaceId: workspaceId,
    );
  });

  tearDown(() async {
    await bloc.close();
  });

  const email = 'lucas.xu@appflowy.io';

  group('ShareTabBloc', () {
    test('ignores a search response after the query changes', () async {
      final searchRepository = _SearchRepository();
      final searchBloc = ShareTabBloc(
        repository: searchRepository,
        pageId: pageId,
        workspaceId: workspaceId,
      );
      addTearDown(searchBloc.close);
      searchBloc.add(ShareTabEvent.searchAvailableUsers(query: 'first'));
      await searchRepository.firstStarted.future;

      final latest = searchBloc.stream
          .firstWhere((state) => state.availableUsers.isNotEmpty);
      searchBloc.add(ShareTabEvent.searchAvailableUsers(query: 'latest'));
      final state = await latest;
      searchRepository.firstResult.complete(FlowySuccess([]));
      await Future<void>.delayed(Duration.zero);
      expect(searchBloc.state.availableUsers, state.availableUsers);
      expect(searchBloc.state.availableUsers.single.name, 'Latest');
    });

    blocTest<ShareTabBloc, ShareTabState>(
      'shares page with user',
      build: () => bloc,
      act: (bloc) => bloc.add(
        ShareTabEvent.inviteUsers(
          emails: [email],
          accessLevel: ShareAccessLevel.readOnly,
        ),
      ),
      wait: const Duration(milliseconds: 100),
      expect: () => [
        // First state: shareResult is null
        isA<ShareTabState>().having(
          (s) => s.shareResult,
          'shareResult',
          isNull,
        ),
        // Second state: shareResult is Success and users updated
        isA<ShareTabState>()
            .having((s) => s.shareResult, 'shareResult', isNotNull)
            .having(
              (s) => s.users.any((u) => u.email == email),
              'users contains new user',
              isTrue,
            ),
      ],
    );

    blocTest<ShareTabBloc, ShareTabState>(
      'removes user from page',
      build: () => bloc,
      act: (bloc) => bloc.add(
        ShareTabEvent.removeUsers(
          emails: [email],
        ),
      ),
      wait: const Duration(milliseconds: 100),
      expect: () => [
        // First state: removeResult is null
        isA<ShareTabState>()
            .having((s) => s.removeResult, 'removeResult', isNull),
        // Second state: removeResult is Success and users updated
        isA<ShareTabState>()
            .having((s) => s.removeResult, 'removeResult', isNotNull)
            .having(
              (s) => s.users.any((u) => u.email == email),
              'users contains removed user',
              isFalse,
            ),
      ],
    );

    final guestEmail = 'guest@appflowy.io';
    blocTest<ShareTabBloc, ShareTabState>(
      'turns user into member',
      build: () => bloc,
      act: (bloc) => bloc
        ..add(
          ShareTabEvent.inviteUsers(
            emails: [guestEmail],
            accessLevel: ShareAccessLevel.readOnly,
          ),
        )
        ..add(
          ShareTabEvent.convertToMember(
            email: guestEmail,
          ),
        ),
      wait: const Duration(milliseconds: 100),
      expect: () => [
        // First state: shareResult is null
        isA<ShareTabState>().having(
          (s) => s.shareResult,
          'shareResult',
          isNull,
        ),
        // Second state: shareResult is Success and users updated
        isA<ShareTabState>()
            .having(
              (s) => s.shareResult,
              'shareResult',
              isNotNull,
            )
            .having(
              (s) => s.users.any((u) => u.email == guestEmail),
              'users contains guest@appflowy.io',
              isTrue,
            ),
        // Third state: turnIntoMemberResult is Success and users updated
        isA<ShareTabState>()
            .having(
              (s) => s.turnIntoMemberResult,
              'turnIntoMemberResult',
              isNotNull,
            )
            .having(
              (s) => s.users.firstWhere((u) => u.email == guestEmail).role,
              'guest@appflowy.io role',
              ShareRole.member,
            ),
      ],
    );

    test(
      'permission PATCH uses owner W1 after active workspace changed to W2',
      () async {
        final requestedUris = <Uri>[];
        final resolver = _StubCollabWorkspaceResolver(
          const CollabWorkspaceResolution(
            status: CollabWorkspaceResolutionStatus.resolved,
            workspaceId: 'workspace-w1',
          ),
        );
        final client = MockClient((request) async {
          requestedUris.add(request.url);
          if (request.method == 'PATCH') {
            return http.Response('', 204);
          }
          return http.Response(
            jsonEncode({
              'code': 0,
              'data': [
                {
                  'uuid': 'user-b',
                  'email': 'b@example.com',
                  'name': 'B',
                  'permission_id': 3,
                },
              ],
            }),
            200,
          );
        });
        final crossWorkspaceBloc = ShareTabBloc(
          repository: LocalShareWithUserRepositoryImpl(),
          pageId: 'view-1',
          workspaceId: '',
          workspaceResolver: resolver,
          httpClient: client,
          baseUrlProvider: () => 'https://cloud.example.com',
          accessTokenProvider: () async => 'token',
        );
        addTearDown(crossWorkspaceBloc.close);
        final completed = crossWorkspaceBloc.stream.firstWhere(
          (state) => state.updateAccessLevelResult != null,
        );

        crossWorkspaceBloc.add(
          ShareTabEvent.updateMemberPermission(
            user: SharedUser(
              email: 'b@example.com',
              name: 'B',
              role: ShareRole.member,
              accessLevel: ShareAccessLevel.readOnly,
              userId: 'user-b',
            ),
            accessLevel: ShareAccessLevel.readAndWrite,
          ),
        );
        await completed;

        final patchUri = requestedUris.singleWhere(
          (uri) => uri.path.contains('/members/user-b'),
        );
        expect(
          patchUri.path,
          '/api/workspace/workspace-w1/collab/view-1/members/user-b',
        );
        expect(
          requestedUris.map((uri) => uri.path),
          contains('/api/workspace/workspace-w1/collab/view-1/members'),
        );
        expect(crossWorkspaceBloc.workspaceId, 'workspace-w1');
        expect(resolver.preferredWorkspaceIds, ['']);
      },
    );

    test('unavailable owner workspace sends no permission request', () async {
      var requestCount = 0;
      final resolver = _StubCollabWorkspaceResolver(
        const CollabWorkspaceResolution(
          status: CollabWorkspaceResolutionStatus.unavailable,
          message: '无法确认文档所属工作区，请刷新后重试',
        ),
      );
      final failClosedBloc = ShareTabBloc(
        repository: LocalShareWithUserRepositoryImpl(),
        pageId: 'view-1',
        workspaceId: '',
        workspaceResolver: resolver,
        httpClient: MockClient((_) async {
          requestCount++;
          return http.Response('', 204);
        }),
        baseUrlProvider: () => 'https://cloud.example.com',
        accessTokenProvider: () async => 'token',
      );
      addTearDown(failClosedBloc.close);
      final failed = failClosedBloc.stream.firstWhere(
        (state) => state.updateAccessLevelResult != null,
      );

      failClosedBloc.add(
        ShareTabEvent.updateMemberPermission(
          user: SharedUser(
            email: 'b@example.com',
            name: 'B',
            role: ShareRole.member,
            accessLevel: ShareAccessLevel.readOnly,
            userId: 'user-b',
          ),
          accessLevel: ShareAccessLevel.readAndWrite,
        ),
      );
      final state = await failed;

      expect(requestCount, 0);
      expect(state.errorMessage, '无法确认文档所属工作区，请刷新后重试');
    });
  });
}

class _StubCollabWorkspaceResolver implements CollabWorkspaceResolver {
  _StubCollabWorkspaceResolver(this.result);

  final CollabWorkspaceResolution result;
  final List<String> preferredWorkspaceIds = [];

  @override
  Future<CollabWorkspaceResolution> resolve({
    required String viewId,
    String? preferredWorkspaceId,
  }) async {
    preferredWorkspaceIds.add(preferredWorkspaceId ?? '');
    return result;
  }
}
