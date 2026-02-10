import 'dart:async';

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/shared/af_role_pb_extension.dart';
import 'package:appflowy/shared/af_user_profile_extension.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/members/invitation/member_http_service.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:collection/collection.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:protobuf/protobuf.dart';

part 'workspace_member_bloc.freezed.dart';

// 1. get the workspace members
// 2. display the content based on the user role
//  Owner:
//   - invite member button
//   - delete member button
//   - member list
//  Member:
//  Guest:
//   - member list
class WorkspaceMemberBloc
    extends Bloc<WorkspaceMemberEvent, WorkspaceMemberState> {
  WorkspaceMemberBloc({
    required this.userProfile,
    String? workspaceId,
    this.workspace,
  })  : _userBackendService = UserBackendService(userId: userProfile.id),
        super(WorkspaceMemberState.initial()) {
    on<WorkspaceMemberEvent>((event, emit) async {
      await event.when(
        initial: () async => _onInitial(emit, workspaceId),
        getWorkspaceMembers: () async => _onGetWorkspaceMembers(emit),
        addWorkspaceMember: (email) async => _onAddWorkspaceMember(emit, email),
        inviteWorkspaceMemberByEmail: (email, role) async =>
            _onInviteWorkspaceMemberByEmail(emit, email, role),
        removeWorkspaceMemberByEmail: (email) async =>
            _onRemoveWorkspaceMemberByEmail(emit, email),
        inviteWorkspaceMemberByLink: (link) async =>
            _onInviteWorkspaceMemberByLink(emit, link),
        generateInviteLink: () async => _onGenerateInviteLink(emit),
        updateWorkspaceMember: (email, role) async =>
            _onUpdateWorkspaceMember(emit, email, role),
        updateSubscriptionInfo: (info) async =>
            _onUpdateSubscriptionInfo(emit, info),
        upgradePlan: () async => _onUpgradePlan(),
        getInviteCode: () async => _onGetInviteCode(emit),
        updateInviteLink: (inviteLink) async => emit(
          state.copyWith(
            inviteLink: inviteLink,
          ),
        ),
      );
    });
  }

  @override
  Future<void> close() async {
    _workspaceId.dispose();

    await super.close();
  }

  final UserProfilePB userProfile;
  final UserWorkspacePB? workspace;
  final UserBackendService _userBackendService;

  final ValueNotifier<String?> _workspaceId = ValueNotifier<String?>(null);
  MemberHttpService? _memberHttpService;

  Future<void> _onInitial(
    Emitter<WorkspaceMemberState> emit,
    String? workspaceId,
  ) async {
    _workspaceId.addListener(() {
      if (!isClosed) {
        add(const WorkspaceMemberEvent.getInviteCode());
      }
    });

    await _setCurrentWorkspaceId(workspaceId);

    final currentWorkspaceId = _workspaceId.value;
    if (currentWorkspaceId == null) {
      Log.error('Failed to get workspace members: workspaceId is null');
      return;
    }

    final result =
        await _userBackendService.getWorkspaceMembers(currentWorkspaceId);
    List<WorkspaceMemberPB> members = [];
    AFRolePB myRole = AFRolePB.Guest;

    await result.fold(
      (s) async {
        members = s.items;
        myRole = _getMyRole(members);
      },
      (e) async {
        // Log and surface error via actionResult
        Log.warn('Failed to get workspace members: ${e.msg}');

        final errMsg = e.msg.toLowerCase();
        // If backend indicates Data Sync is disabled, surface a dedicated state for UI guidance.
        if (errMsg.contains('data sync') || errMsg.contains('enable data sync')) {
          Log.info('[WorkspaceMemberBloc] Data sync is disabled; emitting state to prompt user to enable it');

          // 当云同步关闭时，后端无法返回成员列表，此时无法精确判断角色。
          // 这里尽量根据已知信息推断当前用户是否为工作区创建人：
          // 1. 如果构造时传入了 workspace 且其 role 为 Owner，则认为当前用户是创建人。
          // 2. 否则保持为 Guest，仅显示「退出工作区」等受限操作。
          final fallbackRole =
              workspace?.role == AFRolePB.Owner ? AFRolePB.Owner : AFRolePB.Guest;

          emit(
            state.copyWith(
              members: const [],
              myRole: fallbackRole,
              isLoading: false,
              actionResult: WorkspaceMemberActionResult(
                actionType: WorkspaceMemberActionType.get,
                result: FlowyResult.failure(
                  FlowyError.create()
                    ..code = ErrorCode.Internal
                    ..msg = 'Data Sync is disabled',
                ),
              ),
            ),
          );
          return;
        }

        // If token-related error, try to fetch user profile (may refresh session) then retry once.
        if (errMsg.contains('expired') ||
            errMsg.contains('token') ||
            errMsg.contains('expiredsignature') ||
            errMsg.contains('unauthorized')) {
          Log.info('[WorkspaceMemberBloc] Detected auth token issue, attempting to refresh profile and retry members fetch');
          try {
            await UserEventGetUserProfile().send();
            final retry = await _userBackendService.getWorkspaceMembers(currentWorkspaceId);
            retry.fold(
              (s2) {
                members = s2.items;
                myRole = _getMyRole(members);
              },
              (e2) {
                Log.warn('[WorkspaceMemberBloc] Retry fetching members failed: ${e2.msg}');
              },
            );
          } catch (err, st) {
            Log.error('[WorkspaceMemberBloc] Exception when retrying members fetch: $err', err, st);
          }
        }
      },
    );

    if (myRole.isOwner) {
      unawaited(_fetchWorkspaceSubscriptionInfo());
    }

    emit(
      state.copyWith(
        members: members,
        myRole: myRole,
        isLoading: false,
        actionResult: WorkspaceMemberActionResult(
          actionType: WorkspaceMemberActionType.get,
          result: result,
        ),
      ),
    );
  }

  Future<void> _onGetWorkspaceMembers(
    Emitter<WorkspaceMemberState> emit,
  ) async {
    final workspaceId = _workspaceId.value;
    if (workspaceId == null) {
      Log.error('Failed to get workspace members: workspaceId is null');
      return;
    }

    final result = await _userBackendService.getWorkspaceMembers(workspaceId);

    // Check if the error is related to token expiration
    final isTokenError = result.fold(
      (s) => false,
      (e) => _isTokenExpirationError(e),
    );

    if (isTokenError) {
      Log.info('Detected token expiration error, attempting to refresh token');
      // Try to refresh the token
      final authService = getIt<AuthService>();
      final refreshResult = await authService.refreshToken();

      if (refreshResult.isSuccess) {
        Log.info('Token refresh successful, retrying get workspace members');
        // Retry the operation with refreshed token
        final retryResult = await _userBackendService.getWorkspaceMembers(workspaceId);
        final members = retryResult.fold<List<WorkspaceMemberPB>>(
          (s) => s.items,
          (e) => [],
        );
        final myRole = _getMyRole(members);
        emit(
          state.copyWith(
            members: members,
            myRole: myRole,
            actionResult: WorkspaceMemberActionResult(
              actionType: WorkspaceMemberActionType.get,
              result: retryResult,
            ),
          ),
        );
        return;
      } else {
        Log.error('Token refresh failed: ${refreshResult.getFailure().msg}');
        // Fall through to original error handling
      }
    }

    final members = result.fold<List<WorkspaceMemberPB>>(
      (s) => s.items,
      (e) => [],
    );
    final myRole = _getMyRole(members);
    emit(
      state.copyWith(
        members: members,
        myRole: myRole,
        actionResult: WorkspaceMemberActionResult(
          actionType: WorkspaceMemberActionType.get,
          result: result,
        ),
      ),
    );
  }

  /// Check if an error is related to token expiration
  bool _isTokenExpirationError(FlowyError error) {
    final msg = error.msg.toLowerCase();
    final code = error.code;

    // Check for common token expiration indicators
    return code == ErrorCode.UserUnauthorized ||
           msg.contains('expired') ||
           msg.contains('token') ||
           msg.contains('unauthorized') ||
           msg.contains('invalid') ||
           msg.contains('signature');
  }

  Future<void> _onAddWorkspaceMember(
    Emitter<WorkspaceMemberState> emit,
    String email,
  ) async {
    final workspaceId = _workspaceId.value;
    if (workspaceId == null) {
      Log.error('Failed to add workspace member by email: workspaceId is null');
      return;
    }

    final result = await _userBackendService.addWorkspaceMember(
      workspaceId,
      email,
    );
    emit(
      state.copyWith(
        actionResult: WorkspaceMemberActionResult(
          actionType: WorkspaceMemberActionType.addByEmail,
          result: result,
        ),
      ),
    );
    // the addWorkspaceMember doesn't return the updated members,
    //  so we need to get the members again
    result.onSuccess((s) {
      add(const WorkspaceMemberEvent.getWorkspaceMembers());
    });
  }

  Future<void> _onInviteWorkspaceMemberByEmail(
    Emitter<WorkspaceMemberState> emit,
    String email,
    AFRolePB role,
  ) async {
    final workspaceId = _workspaceId.value;
    if (workspaceId == null) {
      Log.error(
        'Failed to invite workspace member by email: workspaceId is null',
      );
      return;
    }

    final result = await _userBackendService.inviteWorkspaceMember(
      workspaceId,
      email,
      role: role,
    );
    emit(
      state.copyWith(
        actionResult: WorkspaceMemberActionResult(
          actionType: WorkspaceMemberActionType.inviteByEmail,
          result: result,
        ),
      ),
    );
    // Refresh members list when invite succeeds so UI updates immediately.
    result.onSuccess((_) {
      add(const WorkspaceMemberEvent.getWorkspaceMembers());
    });
  }

  Future<void> _onRemoveWorkspaceMemberByEmail(
    Emitter<WorkspaceMemberState> emit,
    String email,
  ) async {
    final workspaceId = _workspaceId.value;
    if (workspaceId == null) {
      Log.error(
        'Failed to remove workspace member by email: workspaceId is null',
      );
      return;
    }

    final result = await _userBackendService.removeWorkspaceMember(
      workspaceId,
      email,
    );
    final members = result.fold(
      (s) => state.members.where((e) => e.email != email).toList(),
      (e) => state.members,
    );
    emit(
      state.copyWith(
        members: members,
        actionResult: WorkspaceMemberActionResult(
          actionType: WorkspaceMemberActionType.removeByEmail,
          result: result,
        ),
      ),
    );
  }

  Future<void> _onInviteWorkspaceMemberByLink(
    Emitter<WorkspaceMemberState> emit,
    String link,
  ) async {}

  Future<void> _onGenerateInviteLink(
    Emitter<WorkspaceMemberState> emit,
  ) async {
    final workspaceId = _workspaceId.value;
    if (workspaceId == null) {
      Log.error('Failed to generate invite link: workspaceId is null');
      return;
    }

    final resetInviteLink = state.inviteLink != null;

    final result = await _memberHttpService?.generateInviteCode(
      workspaceId: workspaceId,
    );

    await result?.fold(
      (s) async {
        final inviteLink = await _buildInviteLink(inviteCode: s);
        emit(
          state.copyWith(
            inviteLink: inviteLink,
            actionResult: WorkspaceMemberActionResult(
              actionType: resetInviteLink
                  ? WorkspaceMemberActionType.resetInviteLink
                  : WorkspaceMemberActionType.generateInviteLink,
              result: result,
            ),
          ),
        );
      },
      (e) async {
        Log.error('Failed to generate invite link: ${e.msg}', e);
        emit(
          state.copyWith(
            actionResult: WorkspaceMemberActionResult(
              actionType: resetInviteLink
                  ? WorkspaceMemberActionType.resetInviteLink
                  : WorkspaceMemberActionType.generateInviteLink,
              result: result,
            ),
          ),
        );
      },
    );
  }

  Future<void> _onUpdateWorkspaceMember(
    Emitter<WorkspaceMemberState> emit,
    String email,
    AFRolePB role,
  ) async {
    final workspaceId = _workspaceId.value;
    if (workspaceId == null) {
      Log.error('Failed to update workspace member: workspaceId is null');
      return;
    }

    final result = await _userBackendService.updateWorkspaceMember(
      workspaceId,
      email,
      role,
    );
    final members = result.fold(
      (s) => state.members.map((e) {
        if (e.email == email) {
          e.freeze();
          return e.rebuild((p0) => p0.role = role);
        }
        return e;
      }).toList(),
      (e) => state.members,
    );
    emit(
      state.copyWith(
        members: members,
        actionResult: WorkspaceMemberActionResult(
          actionType: WorkspaceMemberActionType.updateRole,
          result: result,
        ),
      ),
    );
  }

  Future<void> _onUpdateSubscriptionInfo(
    Emitter<WorkspaceMemberState> emit,
    WorkspaceSubscriptionInfoPB info,
  ) async {
    emit(state.copyWith(subscriptionInfo: info));
  }

  Future<void> _onUpgradePlan() async {
    final workspaceId = _workspaceId.value;
    if (workspaceId == null) {
      Log.error('Failed to upgrade plan: workspaceId is null');
      return;
    }

    final plan = state.subscriptionInfo?.plan;
    if (plan == null) {
      return Log.error('Failed to upgrade plan: plan is null');
    }

    if (plan == WorkspacePlanPB.FreePlan) {
      final checkoutLink = await _userBackendService.createSubscription(
        workspaceId,
        SubscriptionPlanPB.Stand,
      );

      checkoutLink.fold(
        (pl) => afLaunchUrlString(pl.paymentLink),
        (f) => Log.error('Failed to create subscription: ${f.msg}', f),
      );
    }
  }

  Future<void> _onGetInviteCode(Emitter<WorkspaceMemberState> emit) async {
    final baseUrl = await getAppFlowyCloudUrl();
    final authToken = userProfile.authToken;
    final workspaceId = _workspaceId.value;
    String? _extractAuthToken(String? raw) {
      if (raw == null) return null;
      final s = raw.trim();
      if (s.isEmpty) return null;
      // If accidentally a JSON blob (e.g. serialised user object), try to decode and extract common token fields.
      if (s.startsWith('{')) {
        try {
          final parsed = json.decode(s);
          if (parsed is Map) {
            if (parsed.containsKey('access_token')) return parsed['access_token']?.toString();
            if (parsed.containsKey('token')) return parsed['token']?.toString();
            if (parsed.containsKey('auth') && parsed['auth'] is Map && parsed['auth']['access_token'] != null) {
              return parsed['auth']['access_token']?.toString();
            }
          }
        } catch (_) {
          // fallthrough to return raw
        }
      }
      return s;
    }

    final extractedAuth = _extractAuthToken(authToken);
    if (extractedAuth != null && workspaceId != null) {
      _memberHttpService = MemberHttpService(
        baseUrl: baseUrl,
        authToken: extractedAuth,
      );
      unawaited(
        _memberHttpService?.getInviteCode(workspaceId: workspaceId).fold(
          (s) async {
            final inviteLink = await _buildInviteLink(inviteCode: s);
            if (!isClosed) {
              add(WorkspaceMemberEvent.updateInviteLink(inviteLink));
            }
          },
          (e) {},
        ),
      );
    } else {
      // Auth token missing — not a fatal error for UI; log as info to avoid noisy error logs.
      Log.info('Auth token not available; skipping invite-link HTTP client initialization');
    }
  }

  AFRolePB _getMyRole(List<WorkspaceMemberPB> members) {
    final role = members
        .firstWhereOrNull(
          (e) => e.name == userProfile.name,
        )
        ?.role;
    if (role == null) {
      // Don't emit an error-level log when role is missing (e.g. data sync disabled).
      // Fallback to Guest silently to avoid noisy error logs on initial load.
      Log.info('My role not found locally; defaulting to Guest');
      return AFRolePB.Guest;
    }
    return role;
  }

  Future<void> _setCurrentWorkspaceId(String? workspaceId) async {
    if (workspace != null) {
      _workspaceId.value = workspace!.workspaceId;
    } else if (workspaceId != null && workspaceId.isNotEmpty) {
      _workspaceId.value = workspaceId;
    } else {
      final currentWorkspace = await FolderEventReadCurrentWorkspace().send();
      currentWorkspace.fold((s) {
        _workspaceId.value = s.id;
      }, (e) {
        // 注意：不使用 assert，因为在某些情况下（如数据同步禁用时）这可能会失败
        // 这不应该导致程序崩溃
        Log.error('Failed to read current workspace: $e');
      });
    }
  }

  Future<void> _fetchWorkspaceSubscriptionInfo() async {
    final workspaceId = _workspaceId.value;
    if (workspaceId == null) {
      Log.error('Failed to fetch subscription info: workspaceId is null');
      return;
    }

    final result = await UserBackendService.getWorkspaceSubscriptionInfo(
      workspaceId,
    );

    result.fold(
      (info) {
        if (!isClosed) {
          add(WorkspaceMemberEvent.updateSubscriptionInfo(info));
        }
      },
      (f) => Log.error('Failed to fetch subscription info: ${f.msg}', f),
    );
  }

  Future<String> _buildInviteLink({required String inviteCode}) async {
    final baseUrl = await getAppFlowyShareDomain();
    final authToken = userProfile.authToken;
    final workspaceId = workspace?.workspaceId ?? _workspaceId.value ?? '';
    if (authToken != null) {
      // Attach workspaceId as query param so visiting the link can be resolved
      // by client-side landing page logic.
      final encodedCode = Uri.encodeComponent(inviteCode);
      final encodedWs = Uri.encodeComponent(workspaceId);
      return '$baseUrl/invited?q=$encodedCode&ws=$encodedWs';
    }
    return '';
  }
}

@freezed
class WorkspaceMemberEvent with _$WorkspaceMemberEvent {
  const factory WorkspaceMemberEvent.initial() = Initial;

  // Members related events
  const factory WorkspaceMemberEvent.getWorkspaceMembers() =
      GetWorkspaceMembers;
  const factory WorkspaceMemberEvent.addWorkspaceMember(String email) =
      AddWorkspaceMember;
  const factory WorkspaceMemberEvent.inviteWorkspaceMemberByEmail(
    String email,
    AFRolePB role,
  ) = InviteWorkspaceMemberByEmail;
  const factory WorkspaceMemberEvent.removeWorkspaceMemberByEmail(
    String email,
  ) = RemoveWorkspaceMemberByEmail;
  const factory WorkspaceMemberEvent.updateWorkspaceMember(
    String email,
    AFRolePB role,
  ) = UpdateWorkspaceMember;

  // Subscription related events
  const factory WorkspaceMemberEvent.updateSubscriptionInfo(
    WorkspaceSubscriptionInfoPB subscriptionInfo,
  ) = UpdateSubscriptionInfo;
  const factory WorkspaceMemberEvent.upgradePlan() = UpgradePlan;

  // Invite link related events
  const factory WorkspaceMemberEvent.inviteWorkspaceMemberByLink(
    String link,
  ) = InviteWorkspaceMemberByLink;
  const factory WorkspaceMemberEvent.getInviteCode() = GetInviteCode;
  const factory WorkspaceMemberEvent.generateInviteLink() = GenerateInviteLink;
  const factory WorkspaceMemberEvent.updateInviteLink(String inviteLink) =
      UpdateInviteLink;
}

enum WorkspaceMemberActionType {
  none,
  get,
  // this event will send an invitation to the member
  inviteByEmail,
  inviteByLink,
  generateInviteLink,
  resetInviteLink,
  // this event will add the member without sending an invitation
  addByEmail,
  removeByEmail,
  updateRole,
}

class WorkspaceMemberActionResult {
  const WorkspaceMemberActionResult({
    required this.actionType,
    required this.result,
  });

  final WorkspaceMemberActionType actionType;
  final FlowyResult<void, FlowyError> result;
}

@freezed
class WorkspaceMemberState with _$WorkspaceMemberState {
  const WorkspaceMemberState._();

  const factory WorkspaceMemberState({
    @Default([]) List<WorkspaceMemberPB> members,
    @Default(AFRolePB.Guest) AFRolePB myRole,
    @Default(null) WorkspaceMemberActionResult? actionResult,
    @Default(true) bool isLoading,
    // dataSyncRequired removed from factory; provide computed getter instead.
    @Default(null) WorkspaceSubscriptionInfoPB? subscriptionInfo,
    @Default(null) String? inviteLink,
  }) = _WorkspaceMemberState;

  factory WorkspaceMemberState.initial() => const WorkspaceMemberState();

  /// Whether the current state indicates Data Sync is required (backend disabled).
  bool get dataSyncRequired {
    final ar = actionResult;
    if (ar == null) return false;
    try {
      if (ar.result.isFailure) {
        final f = ar.result.getFailure();
        final msg = f.msg.toLowerCase();
        return msg.contains('data sync') || msg.contains('enable data sync') || msg.contains('datasync');
      }
    } catch (_) {
      // ignore
    }
    return false;
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is WorkspaceMemberState &&
        other.members == members &&
        other.myRole == myRole &&
        other.subscriptionInfo == subscriptionInfo &&
        other.inviteLink == inviteLink &&
        identical(other.actionResult, actionResult);
  }
}
