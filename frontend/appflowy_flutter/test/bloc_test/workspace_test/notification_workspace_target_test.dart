import 'package:appflowy/features/workspace/data/repositories/workspace_repository.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/subscription_success_listenable/subscription_success_listenable.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/workspace.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockWorkspaceRepository extends Mock implements WorkspaceRepository {}

class _RecordingWorkspaceBloc extends UserWorkspaceBloc {
  _RecordingWorkspaceBloc({
    required super.repository,
    required super.userProfile,
  });

  final openRequests = <WorkspaceEventOpenWorkspace>[];

  @override
  void add(UserWorkspaceEvent event) {
    if (event is WorkspaceEventOpenWorkspace) {
      openRequests.add(event);
      return;
    }
    super.add(event);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _MockWorkspaceRepository repository;
  final profile = UserProfilePB();
  final currentWorkspace = UserWorkspacePB(workspaceId: 'current-workspace');
  final otherWorkspace = UserWorkspacePB(
    workspaceId: 'other-workspace',
    workspaceType: WorkspaceTypePB.ServerW,
  );

  setUp(() {
    getIt.registerSingleton<SubscriptionSuccessListenable>(
      SubscriptionSuccessListenable(),
    );
    repository = _MockWorkspaceRepository();
    when(() => repository.getCurrentWorkspace()).thenAnswer(
      (_) async => FlowyResult.success(WorkspacePB(id: 'current-workspace')),
    );
    when(() => repository.getWorkspaces()).thenAnswer(
      (_) async => FlowyResult.success([otherWorkspace, currentWorkspace]),
    );
  });

  tearDown(() async {
    await getIt.unregister<SubscriptionSuccessListenable>();
  });

  blocTest<UserWorkspaceBloc, UserWorkspaceState>(
    '通知目标工作区不存在时保留当前工作区，不能跳到列表第一项',
    build: () =>
        UserWorkspaceBloc(repository: repository, userProfile: profile),
    seed: () => UserWorkspaceState(
      userProfile: profile,
      currentWorkspace: currentWorkspace,
    ),
    act: (bloc) => bloc.add(
      UserWorkspaceEvent.fetchWorkspaces(
        initialWorkspaceId: 'deleted-workspace',
      ),
    ),
    expect: () => [
      isA<UserWorkspaceState>()
          .having((s) => s.currentWorkspace, '当前工作区', currentWorkspace)
          .having((s) => s.workspaces.length, '刷新后的工作区数', 2),
    ],
    verify: (_) => verifyNever(
      () => repository.openWorkspace(
        workspaceId: 'other-workspace',
        workspaceType: otherWorkspace.workspaceType,
      ),
    ),
  );

  blocTest<_RecordingWorkspaceBloc, UserWorkspaceState>(
    '通知重试只刷新列表，不能自行打开新加载的工作区',
    setUp: () {
      when(() => repository.getCurrentWorkspace()).thenAnswer(
        (_) async => FlowyResult.success(WorkspacePB(id: 'other-workspace')),
      );
    },
    build: () => _RecordingWorkspaceBloc(
      repository: repository,
      userProfile: profile,
    ),
    seed: () => UserWorkspaceState(
      userProfile: profile,
      currentWorkspace: currentWorkspace,
    ),
    act: (bloc) => bloc.add(UserWorkspaceEvent.fetchWorkspaces()),
    expect: () => [
      isA<UserWorkspaceState>()
          .having((s) => s.currentWorkspace, '当前工作区', currentWorkspace)
          .having((s) => s.workspaces.length, '刷新后的工作区数', 2),
    ],
    verify: (bloc) => expect(bloc.openRequests, isEmpty),
  );

  blocTest<_RecordingWorkspaceBloc, UserWorkspaceState>(
    '显式请求存在的目标时仍按真实工作区类型打开，兼容原有邀请流程',
    build: () => _RecordingWorkspaceBloc(
      repository: repository,
      userProfile: profile,
    ),
    seed: () => UserWorkspaceState(
      userProfile: profile,
      currentWorkspace: currentWorkspace,
    ),
    act: (bloc) => bloc.add(
      UserWorkspaceEvent.fetchWorkspaces(
        initialWorkspaceId: otherWorkspace.workspaceId,
      ),
    ),
    expect: () => [isA<UserWorkspaceState>()],
    verify: (bloc) {
      expect(bloc.openRequests, hasLength(1));
      expect(bloc.openRequests.single.workspaceId, otherWorkspace.workspaceId);
      expect(
        bloc.openRequests.single.workspaceType,
        otherWorkspace.workspaceType,
      );
    },
  );
}
