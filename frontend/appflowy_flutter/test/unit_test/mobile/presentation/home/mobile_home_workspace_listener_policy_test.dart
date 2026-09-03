import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/mobile/presentation/home/mobile_home_workspace_listener_policy.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final userProfile = UserProfilePB();

  UserWorkspaceState state({
    String? workspaceId,
    WorkspaceActionResult? actionResult,
  }) =>
      UserWorkspaceState(
        userProfile: userProfile,
        currentWorkspace: workspaceId == null
            ? null
            : UserWorkspacePB(workspaceId: workspaceId),
        actionResult: actionResult,
      );

  group('移动端首页工作区监听策略', () {
    test('只有工作区标识变化时才重置最近访问和搜索状态', () {
      expect(
        didMobileCurrentWorkspaceChange(
          state(workspaceId: 'workspace-a'),
          state(workspaceId: 'workspace-a'),
        ),
        isFalse,
      );
      expect(
        didMobileCurrentWorkspaceChange(
          state(workspaceId: 'workspace-a'),
          state(workspaceId: 'workspace-b'),
        ),
        isTrue,
      );
      expect(
        didMobileCurrentWorkspaceChange(
          state(),
          state(workspaceId: 'workspace-a'),
        ),
        isTrue,
      );
    });

    test('非工作区状态变化不会触发工作区重置', () {
      final previous = state(workspaceId: 'workspace-a');
      final current = previous.copyWith(isCloudSyncEnabled: false);

      expect(didMobileCurrentWorkspaceChange(previous, current), isFalse);
      expect(
        didMobileCurrentWorkspaceMetadataChange(previous, current),
        isFalse,
      );
    });

    test('工作区列表变化会触发邀请目标的重新匹配', () {
      final previous = state(workspaceId: 'workspace-a');
      final current = previous.copyWith(
        workspaces: [UserWorkspacePB(workspaceId: 'workspace-b')],
      );

      expect(didMobileWorkspaceListChange(previous, current), isTrue);
      expect(
        didMobileWorkspaceListChange(previous, previous.copyWith()),
        isFalse,
      );
    });

    test('工作区显示信息变化只刷新当前工作区展示', () {
      final previous = state(workspaceId: 'workspace-a');
      final current = previous.copyWith(
        currentWorkspace: UserWorkspacePB(
          workspaceId: 'workspace-a',
          name: '新的工作区名称',
        ),
      );

      expect(didMobileCurrentWorkspaceChange(previous, current), isFalse);
      expect(
        didMobileCurrentWorkspaceMetadataChange(previous, current),
        isTrue,
      );
    });

    test('操作结果变化仍会独立触发结果提示', () {
      final previous = state(workspaceId: 'workspace-a');
      final current = state(
        workspaceId: 'workspace-a',
        actionResult: WorkspaceActionResult(
          actionType: WorkspaceActionType.rename,
          isLoading: false,
          result: null,
        ),
      );

      expect(didMobileWorkspaceActionResultChange(previous, current), isTrue);
      expect(didMobileCurrentWorkspaceChange(previous, current), isFalse);
    });
  });
}
