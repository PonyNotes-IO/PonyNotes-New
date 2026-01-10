import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';

enum WorkspaceActionType {
  none,
  create,
  delete,
  open,
  rename,
  updateIcon,
  fetchWorkspaces,
  leave,
  fetchSubscriptionInfo,
}

class WorkspaceActionResult {
  const WorkspaceActionResult({
    required this.actionType,
    required this.isLoading,
    required this.result,
  });

  final WorkspaceActionType actionType;
  final bool isLoading;
  final FlowyResult<void, FlowyError>? result;

  @override
  String toString() {
    return 'WorkspaceActionResult(actionType: $actionType, isLoading: $isLoading, result: $result)';
  }
}

class UserWorkspaceState {
  factory UserWorkspaceState.initial(UserProfilePB userProfile) =>
      UserWorkspaceState(
        userProfile: userProfile,
      );

  const UserWorkspaceState({
    this.currentWorkspace,
    this.workspaces = const [],
    this.actionResult,
    this.isCollabWorkspaceOn = false,
    required this.userProfile,
    this.workspaceSubscriptionInfo,
    this.currentSubscription,
    this.isCloudSyncEnabled = false, // 云同步开关状态，默认关闭
    this.folderSyncState, // 文件夹同步状态
  });

  final UserWorkspacePB? currentWorkspace;
  final List<UserWorkspacePB> workspaces;
  final WorkspaceActionResult? actionResult;
  final bool isCollabWorkspaceOn;
  final UserProfilePB userProfile;
  final WorkspaceSubscriptionInfoPB? workspaceSubscriptionInfo;
  final CurrentSubscription? currentSubscription;
  final bool isCloudSyncEnabled; // 云同步开关状态
  final FolderSyncStatePB? folderSyncState; // 文件夹同步状态

  UserWorkspaceState copyWith({
    UserWorkspacePB? currentWorkspace,
    List<UserWorkspacePB>? workspaces,
    WorkspaceActionResult? actionResult,
    bool? isCollabWorkspaceOn,
    UserProfilePB? userProfile,
    WorkspaceSubscriptionInfoPB? workspaceSubscriptionInfo,
    CurrentSubscription? currentSubscription,
    bool? isCloudSyncEnabled,
    FolderSyncStatePB? folderSyncState,
  }) {
    return UserWorkspaceState(
      currentWorkspace: currentWorkspace ?? this.currentWorkspace,
      workspaces: workspaces ?? this.workspaces,
      actionResult: actionResult ?? this.actionResult,
      isCollabWorkspaceOn: isCollabWorkspaceOn ?? this.isCollabWorkspaceOn,
      userProfile: userProfile ?? this.userProfile,
      workspaceSubscriptionInfo:
          workspaceSubscriptionInfo ?? this.workspaceSubscriptionInfo,
      currentSubscription: currentSubscription ?? this.currentSubscription,
      isCloudSyncEnabled: isCloudSyncEnabled ?? this.isCloudSyncEnabled,
      folderSyncState: folderSyncState ?? this.folderSyncState,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserWorkspaceState &&
        other.currentWorkspace == currentWorkspace &&
        other.workspaces == workspaces &&
        other.actionResult == actionResult &&
        other.isCollabWorkspaceOn == isCollabWorkspaceOn &&
        other.userProfile == userProfile &&
        other.workspaceSubscriptionInfo == workspaceSubscriptionInfo &&
        other.currentSubscription == currentSubscription &&
        other.isCloudSyncEnabled == isCloudSyncEnabled &&
        other.folderSyncState == folderSyncState;
  }

  @override
  int get hashCode {
    return Object.hash(
      currentWorkspace,
      workspaces,
      actionResult,
      isCollabWorkspaceOn,
      userProfile,
      workspaceSubscriptionInfo,
      currentSubscription,
      isCloudSyncEnabled,
      folderSyncState,
    );
  }

  @override
  String toString() {
    return 'WorkspaceState(currentWorkspace: $currentWorkspace, workspaces: $workspaces, actionResult: $actionResult, isCollabWorkspaceOn: $isCollabWorkspaceOn, userProfile: $userProfile, workspaceSubscriptionInfo: $workspaceSubscriptionInfo, currentSubscription: $currentSubscription, isCloudSyncEnabled: $isCloudSyncEnabled, folderSyncState: $folderSyncState)';
  }
}
