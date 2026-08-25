import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';

bool didMobileCurrentWorkspaceChange(
  UserWorkspaceState previous,
  UserWorkspaceState current,
) =>
    previous.currentWorkspace?.workspaceId !=
    current.currentWorkspace?.workspaceId;

bool didMobileCurrentWorkspaceMetadataChange(
  UserWorkspaceState previous,
  UserWorkspaceState current,
) =>
    previous.currentWorkspace != current.currentWorkspace;

bool didMobileWorkspaceActionResultChange(
  UserWorkspaceState previous,
  UserWorkspaceState current,
) =>
    previous.actionResult != current.actionResult;
