import 'dart:async';
import 'dart:convert';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/features/workspace/data/repositories/workspace_repository.dart';
import 'package:appflowy/features/workspace/logic/workspace_event.dart';
import 'package:appflowy/features/workspace/logic/workspace_state.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/reminder/reminder_bloc.dart';
import 'package:appflowy/user/application/user_listener.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:bloc/bloc.dart';
import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart' as http;
import 'package:protobuf/protobuf.dart';

export 'workspace_event.dart';
export 'workspace_state.dart';

class _WorkspaceFetchResult {
  const _WorkspaceFetchResult({
    this.currentWorkspace,
    required this.workspaces,
    required this.shouldOpenWorkspace,
  });

  final UserWorkspacePB? currentWorkspace;
  final List<UserWorkspacePB> workspaces;
  final bool shouldOpenWorkspace;
}

class UserWorkspaceBloc extends Bloc<UserWorkspaceEvent, UserWorkspaceState> {
  UserWorkspaceBloc({
    required this.repository,
    required this.userProfile,
    this.initialWorkspaceId,
  })  : _listener = UserListener(userProfile: userProfile),
        super(UserWorkspaceState.initial(userProfile)) {
    on<WorkspaceEventInitialize>(_onInitialize);
    on<WorkspaceEventFetchWorkspaces>(_onFetchWorkspaces);
    on<WorkspaceEventCreateWorkspace>(_onCreateWorkspace);
    on<WorkspaceEventDeleteWorkspace>(_onDeleteWorkspace);
    on<WorkspaceEventOpenWorkspace>(_onOpenWorkspace);
    on<WorkspaceEventRenameWorkspace>(_onRenameWorkspace);
    on<WorkspaceEventUpdateWorkspaceIcon>(_onUpdateWorkspaceIcon);
    on<WorkspaceEventLeaveWorkspace>(_onLeaveWorkspace);
    on<WorkspaceEventFetchWorkspaceSubscriptionInfo>(
      _onFetchWorkspaceSubscriptionInfo,
    );
    on<WorkspaceEventUpdateWorkspaceSubscriptionInfo>(
      _onUpdateWorkspaceSubscriptionInfo,
    );
    on<WorkspaceEventEmitWorkspaces>(_onEmitWorkspaces);
    on<WorkspaceEventEmitUserProfile>(_onEmitUserProfile);
    on<WorkspaceEventEmitCurrentWorkspace>(_onEmitCurrentWorkspace);
    on<WorkspaceEventFetchCurrentSubscription>(_onFetchCurrentSubscription);
    on<WorkspaceEventUpdateCurrentSubscription>(_onUpdateCurrentSubscription);
  }

  final String? initialWorkspaceId;
  final WorkspaceRepository repository;
  final UserProfilePB userProfile;
  final UserListener _listener;

  @override
  Future<void> close() {
    _listener.stop();
    return super.close();
  }

  Future<void> _onInitialize(
    WorkspaceEventInitialize event,
    Emitter<UserWorkspaceState> emit,
  ) async {
    await _setupListeners();
    await _initializeWorkspaces(emit);
  }

  Future<void> _onFetchWorkspaces(
    WorkspaceEventFetchWorkspaces event,
    Emitter<UserWorkspaceState> emit,
  ) async {
    final result = await _fetchWorkspaces(
      initialWorkspaceId: event.initialWorkspaceId,
    );

    final currentWorkspace = result.currentWorkspace;
    final workspaces = result.workspaces;
    Log.info(
      'fetch workspaces: current workspace: ${currentWorkspace?.workspaceId}, workspaces: ${workspaces.map((e) => e.workspaceId)}',
    );

    emit(
      state.copyWith(
        workspaces: workspaces,
      ),
    );

    if (currentWorkspace != null &&
        currentWorkspace.workspaceId != state.currentWorkspace?.workspaceId) {
      Log.info(
        'fetch workspaces: try to open workspace: ${currentWorkspace.workspaceId}',
      );
      add(
        UserWorkspaceEvent.openWorkspace(
          workspaceId: currentWorkspace.workspaceId,
          workspaceType: currentWorkspace.workspaceType,
        ),
      );
    }
  }

  Future<void> _onCreateWorkspace(
    WorkspaceEventCreateWorkspace event,
    Emitter<UserWorkspaceState> emit,
  ) async {
    emit(
      state.copyWith(
        actionResult: const WorkspaceActionResult(
          actionType: WorkspaceActionType.create,
          isLoading: true,
          result: null,
        ),
      ),
    );

    final result = await repository.createWorkspace(
      name: event.name,
      workspaceType: event.workspaceType,
    );

    final workspaces = result.fold(
      (s) => [...state.workspaces, s],
      (e) => state.workspaces,
    );

    emit(
      state.copyWith(
        workspaces: _sortWorkspaces(workspaces),
        actionResult: WorkspaceActionResult(
          actionType: WorkspaceActionType.create,
          isLoading: false,
          result: result.map((_) {}),
        ),
      ),
    );

    result
      ..onSuccess((s) {
        Log.info('create workspace success: $s');
        add(
          UserWorkspaceEvent.openWorkspace(
            workspaceId: s.workspaceId,
            workspaceType: s.workspaceType,
          ),
        );
      })
      ..onFailure((f) {
        Log.error('create workspace error: $f');
      });
  }

  Future<void> _onDeleteWorkspace(
    WorkspaceEventDeleteWorkspace event,
    Emitter<UserWorkspaceState> emit,
  ) async {
    Log.info('try to delete workspace: ${event.workspaceId}');
    emit(
      state.copyWith(
        actionResult: const WorkspaceActionResult(
          actionType: WorkspaceActionType.delete,
          isLoading: true,
          result: null,
        ),
      ),
    );

    final remoteWorkspaces = await _fetchWorkspaces().then(
      (value) => value.workspaces,
    );

    if (state.workspaces.length <= 1 || remoteWorkspaces.length <= 1) {
      final result = FlowyResult.failure(
        FlowyError(
          code: ErrorCode.Internal,
          msg: LocaleKeys.workspace_cannotDeleteTheOnlyWorkspace.tr(),
        ),
      );
      return emit(
        state.copyWith(
          actionResult: WorkspaceActionResult(
            actionType: WorkspaceActionType.delete,
            result: result,
            isLoading: false,
          ),
        ),
      );
    }

    final result = await repository.deleteWorkspace(
      workspaceId: event.workspaceId,
    );
    final workspacesResult = await _fetchWorkspaces();
    final workspaces = workspacesResult.workspaces;
    final containsDeletedWorkspace =
        _findWorkspaceById(event.workspaceId, workspaces) != null;

    result
      ..onSuccess((_) {
        Log.info('delete workspace success: ${event.workspaceId}');
        final firstWorkspace = workspaces.firstOrNull;
        assert(
          firstWorkspace != null,
          'the first workspace must not be null',
        );
        if (state.currentWorkspace?.workspaceId == event.workspaceId &&
            firstWorkspace != null) {
          Log.info(
            'delete workspace: open the first workspace: ${firstWorkspace.workspaceId}',
          );
          add(
            UserWorkspaceEvent.openWorkspace(
              workspaceId: firstWorkspace.workspaceId,
              workspaceType: firstWorkspace.workspaceType,
            ),
          );
        }
      })
      ..onFailure((f) {
        Log.error('delete workspace error: $f');
        if (!containsDeletedWorkspace && workspaces.isNotEmpty) {
          add(
            UserWorkspaceEvent.openWorkspace(
              workspaceId: workspaces.first.workspaceId,
              workspaceType: workspaces.first.workspaceType,
            ),
          );
        }
      });

    emit(
      state.copyWith(
        workspaces: workspaces,
        actionResult: WorkspaceActionResult(
          actionType: WorkspaceActionType.delete,
          result: result,
          isLoading: false,
        ),
      ),
    );
  }

  Future<void> _onOpenWorkspace(
    WorkspaceEventOpenWorkspace event,
    Emitter<UserWorkspaceState> emit,
  ) async {
    emit(
      state.copyWith(
        actionResult: const WorkspaceActionResult(
          actionType: WorkspaceActionType.open,
          isLoading: true,
          result: null,
        ),
      ),
    );

    final result = await repository.openWorkspace(
      workspaceId: event.workspaceId,
      workspaceType: event.workspaceType,
    );

    final currentWorkspace = result.fold(
      (s) => _findWorkspaceById(event.workspaceId),
      (e) => state.currentWorkspace,
    );

    result
      ..onSuccess((s) {
        Log.info(
          'open workspace success: ${event.workspaceId}, current workspace: ${currentWorkspace?.toProto3Json()}',
        );
        
        // 工作空间打开成功后，延迟 2 秒再请求会员信息，确保页面已完全加载
        Log.info('[UserWorkspaceBloc] 工作空间打开成功，延迟 2 秒后请求会员信息');
        Future.delayed(const Duration(seconds: 2), () {
          if (!isClosed && state.currentWorkspace?.workspaceId == event.workspaceId) {
            Log.info('[UserWorkspaceBloc] 开始请求会员信息（工作空间打开完成后）');
            // 同时请求 subscriptionInfo 和 currentSubscription
            add(
              UserWorkspaceEvent.fetchWorkspaceSubscriptionInfo(
                workspaceId: event.workspaceId,
              ),
            );
            add(UserWorkspaceEvent.fetchCurrentSubscription());
          }
        });
      })
      ..onFailure((f) {
        Log.error('open workspace error: $f');
      });

    emit(
      state.copyWith(
        currentWorkspace: currentWorkspace,
        actionResult: WorkspaceActionResult(
          actionType: WorkspaceActionType.open,
          isLoading: false,
          result: result,
        ),
      ),
    );

    getIt<ReminderBloc>().add(
      ReminderEvent.started(),
    );
  }

  Future<void> _onRenameWorkspace(
    WorkspaceEventRenameWorkspace event,
    Emitter<UserWorkspaceState> emit,
  ) async {
    final result = await repository.renameWorkspace(
      workspaceId: event.workspaceId,
      name: event.name,
    );

    final workspaces = result.fold(
      (s) => _updateWorkspaceInList(event.workspaceId, (workspace) {
        workspace.freeze();
        return workspace.rebuild((p0) {
          p0.name = event.name;
        });
      }),
      (f) => state.workspaces,
    );

    final currentWorkspace = _findWorkspaceById(
      state.currentWorkspace?.workspaceId ?? '',
      workspaces,
    );

    Log.info('rename workspace: ${event.workspaceId}, name: ${event.name}');

    result.onFailure((f) {
      Log.error('rename workspace error: $f');
    });

    emit(
      state.copyWith(
        workspaces: workspaces,
        currentWorkspace: currentWorkspace,
        actionResult: WorkspaceActionResult(
          actionType: WorkspaceActionType.rename,
          isLoading: false,
          result: result,
        ),
      ),
    );
  }

  Future<void> _onUpdateWorkspaceIcon(
    WorkspaceEventUpdateWorkspaceIcon event,
    Emitter<UserWorkspaceState> emit,
  ) async {
    final workspace = _findWorkspaceById(event.workspaceId);
    if (workspace == null) {
      Log.error('workspace not found: ${event.workspaceId}');
      return;
    }

    if (event.icon == workspace.icon) {
      Log.info('ignore same icon update');
      return;
    }

    final result = await repository.updateWorkspaceIcon(
      workspaceId: event.workspaceId,
      icon: event.icon,
    );

    final workspaces = result.fold(
      (s) => _updateWorkspaceInList(event.workspaceId, (workspace) {
        workspace.freeze();
        return workspace.rebuild((p0) {
          p0.icon = event.icon;
        });
      }),
      (f) => state.workspaces,
    );

    final currentWorkspace = _findWorkspaceById(
      state.currentWorkspace?.workspaceId ?? '',
      workspaces,
    );

    Log.info(
      'update workspace icon: ${event.workspaceId}, icon: ${event.icon}',
    );

    result.onFailure((f) {
      Log.error('update workspace icon error: $f');
    });

    emit(
      state.copyWith(
        workspaces: workspaces,
        currentWorkspace: currentWorkspace,
        actionResult: WorkspaceActionResult(
          actionType: WorkspaceActionType.updateIcon,
          isLoading: false,
          result: result,
        ),
      ),
    );
  }

  Future<void> _onLeaveWorkspace(
    WorkspaceEventLeaveWorkspace event,
    Emitter<UserWorkspaceState> emit,
  ) async {
    final result = await repository.leaveWorkspace(
      workspaceId: event.workspaceId,
    );

    final workspaces = result.fold(
      (s) => state.workspaces
          .where((e) => e.workspaceId != event.workspaceId)
          .toList(),
      (e) => state.workspaces,
    );

    result
      ..onSuccess((_) {
        Log.info('leave workspace success: ${event.workspaceId}');
        if (state.currentWorkspace?.workspaceId == event.workspaceId &&
            workspaces.isNotEmpty) {
          add(
            UserWorkspaceEvent.openWorkspace(
              workspaceId: workspaces.first.workspaceId,
              workspaceType: workspaces.first.workspaceType,
            ),
          );
        }
      })
      ..onFailure((f) {
        Log.error('leave workspace error: $f');
      });

    emit(
      state.copyWith(
        workspaces: _sortWorkspaces(workspaces),
        actionResult: WorkspaceActionResult(
          actionType: WorkspaceActionType.leave,
          isLoading: false,
          result: result,
        ),
      ),
    );
  }

  Future<void> _onFetchWorkspaceSubscriptionInfo(
    WorkspaceEventFetchWorkspaceSubscriptionInfo event,
    Emitter<UserWorkspaceState> emit,
  ) async {
    Log.info('[UserWorkspaceBloc] 开始获取工作空间订阅信息: workspaceId=${event.workspaceId}');
    
    final enabled = await repository.isBillingEnabled();
    Log.info('[UserWorkspaceBloc] isBillingEnabled: $enabled');
    
    // If billing is not enabled, we don't need to fetch the workspace subscription info
    if (!enabled) {
      Log.warn('[UserWorkspaceBloc] 计费功能未启用，跳过获取工作空间订阅信息');
      return;
    }

    Log.info('[UserWorkspaceBloc] 开始调用 getWorkspaceSubscriptionInfo API');
    unawaited(
      repository
          .getWorkspaceSubscriptionInfo(
        workspaceId: event.workspaceId,
      )
          .fold(
        (workspaceSubscriptionInfo) {
          Log.info('[UserWorkspaceBloc] getWorkspaceSubscriptionInfo 成功: workspaceId=${event.workspaceId}, plan=${workspaceSubscriptionInfo.plan}');
          
          if (isClosed) {
            Log.warn('[UserWorkspaceBloc] Bloc 已关闭，跳过更新工作空间订阅信息');
            return;
          }

          final currentWorkspaceId = state.currentWorkspace?.workspaceId;
          if (currentWorkspaceId != event.workspaceId) {
            Log.warn('[UserWorkspaceBloc] 工作空间 ID 不匹配: current=$currentWorkspaceId, event=${event.workspaceId}，跳过更新');
            return;
          }

          Log.info(
            '[UserWorkspaceBloc] 更新工作空间订阅信息: workspaceId=${event.workspaceId}, plan=${workspaceSubscriptionInfo.plan}',
          );

          add(
            UserWorkspaceEvent.updateWorkspaceSubscriptionInfo(
              workspaceId: event.workspaceId,
              subscriptionInfo: workspaceSubscriptionInfo,
            ),
          );
        },
        (e) {
          Log.error('[UserWorkspaceBloc] 获取工作空间订阅信息失败: workspaceId=${event.workspaceId}, error=$e', e);
          // 即使失败，也尝试更新状态为 null，避免一直等待
          if (!isClosed && state.currentWorkspace?.workspaceId == event.workspaceId) {
            Log.warn('[UserWorkspaceBloc] 请求失败，但更新状态为 null 以便后续重试');
            // 注意：这里不更新为 null，因为可能只是临时错误，保持原有状态
          }
        },
      ),
    );
  }

  Future<void> _onUpdateWorkspaceSubscriptionInfo(
    WorkspaceEventUpdateWorkspaceSubscriptionInfo event,
    Emitter<UserWorkspaceState> emit,
  ) async {
    emit(
      state.copyWith(workspaceSubscriptionInfo: event.subscriptionInfo),
    );
  }

  Future<void> _onEmitWorkspaces(
    WorkspaceEventEmitWorkspaces event,
    Emitter<UserWorkspaceState> emit,
  ) async {
    emit(
      state.copyWith(
        workspaces: _sortWorkspaces(event.workspaces),
      ),
    );
  }

  Future<void> _onEmitUserProfile(
    WorkspaceEventEmitUserProfile event,
    Emitter<UserWorkspaceState> emit,
  ) async {
    emit(
      state.copyWith(userProfile: event.userProfile),
    );
    // 用户信息更新时，也更新会员信息
    _safeAdd(UserWorkspaceEvent.fetchCurrentSubscription());
  }

  Future<void> _onEmitCurrentWorkspace(
    WorkspaceEventEmitCurrentWorkspace event,
    Emitter<UserWorkspaceState> emit,
  ) async {
    emit(
      state.copyWith(currentWorkspace: event.workspace),
    );
  }

  Future<void> _setupListeners() async {
    _listener.start(
      onProfileUpdated: (result) {
        if (!isClosed) {
          result.fold(
            (newProfile) {
              _safeAdd(UserWorkspaceEvent.emitUserProfile(userProfile: newProfile));
              // 用户信息更新时，也更新会员信息
              _safeAdd(UserWorkspaceEvent.fetchCurrentSubscription());
            },
            (error) => Log.error("Failed to get user profile: $error"),
          );
        }
      },
      onUserWorkspaceListUpdated: (workspaces) {
        if (!isClosed) {
          add(
            UserWorkspaceEvent.emitWorkspaces(
              workspaces: _sortWorkspaces(workspaces.items),
            ),
          );
        }
      },
      onUserWorkspaceUpdated: (workspace) {
        if (!isClosed) {
          if (state.currentWorkspace?.workspaceId == workspace.workspaceId) {
            add(UserWorkspaceEvent.emitCurrentWorkspace(workspace: workspace));
          }
        }
      },
    );
  }

  /// Safely add an event to the bloc, catching StateError when handler is missing.
  void _safeAdd(UserWorkspaceEvent event) {
    try {
      add(event);
    } on StateError catch (e, st) {
      // Log detailed info but avoid crashing the UI
      Log.error('[UserWorkspaceBloc] Failed to add event ${event.runtimeType}: $e', e);
      Log.error('[UserWorkspaceBloc] Stack: $st');
    } catch (e, st) {
      Log.error('[UserWorkspaceBloc] Unexpected error when adding event ${event.runtimeType}: $e', e);
      Log.error('[UserWorkspaceBloc] Stack: $st');
    }
  }

  Future<void> _initializeWorkspaces(Emitter<UserWorkspaceState> emit) async {
    final result = await _fetchWorkspaces(
      initialWorkspaceId: initialWorkspaceId,
    );
    final currentWorkspace = result.currentWorkspace;
    final workspaces = result.workspaces;
    final isCollabWorkspaceOn =
        state.userProfile.userAuthType == AuthTypePB.Server &&
            FeatureFlag.collaborativeWorkspace.isOn;

    Log.info(
      'init workspace, current workspace: ${currentWorkspace?.workspaceId}, '
      'workspaces: ${workspaces.map((e) => e.workspaceId)}, isCollabWorkspaceOn: $isCollabWorkspaceOn',
    );

    // 不在初始化时立即获取会员信息，等待页面加载完成后再请求
    if (currentWorkspace != null && result.shouldOpenWorkspace == true) {
      Log.info('init open workspace: ${currentWorkspace.workspaceId}');
      await repository.openWorkspace(
        workspaceId: currentWorkspace.workspaceId,
        workspaceType: currentWorkspace.workspaceType,
      );
      
      // 工作空间打开完成后，延迟 2 秒再请求会员信息，确保页面已完全加载
      Log.info('[UserWorkspaceBloc] 工作空间打开完成，延迟 2 秒后请求会员信息');
      Future.delayed(const Duration(seconds: 2), () {
        if (!isClosed && state.currentWorkspace?.workspaceId == currentWorkspace.workspaceId) {
          Log.info('[UserWorkspaceBloc] 开始请求会员信息（页面加载完成后）');
          // 同时请求 subscriptionInfo 和 currentSubscription
          add(
            UserWorkspaceEvent.fetchWorkspaceSubscriptionInfo(
              workspaceId: currentWorkspace.workspaceId,
            ),
          );
          add(UserWorkspaceEvent.fetchCurrentSubscription());
        }
      });
    } else if (currentWorkspace != null) {
      // 如果不需要打开工作空间，也延迟请求会员信息
      Log.info('[UserWorkspaceBloc] 工作空间已存在，延迟 2 秒后请求会员信息');
      Future.delayed(const Duration(seconds: 2), () {
        if (!isClosed && state.currentWorkspace?.workspaceId == currentWorkspace.workspaceId) {
          Log.info('[UserWorkspaceBloc] 开始请求会员信息（页面加载完成后）');
          // 同时请求 subscriptionInfo 和 currentSubscription
          add(
            UserWorkspaceEvent.fetchWorkspaceSubscriptionInfo(
              workspaceId: currentWorkspace.workspaceId,
            ),
          );
          add(UserWorkspaceEvent.fetchCurrentSubscription());
        }
      });
    }

    emit(
      state.copyWith(
        currentWorkspace: currentWorkspace,
        workspaces: workspaces,
        isCollabWorkspaceOn: isCollabWorkspaceOn,
        actionResult: const WorkspaceActionResult(
          actionType: WorkspaceActionType.none,
          isLoading: false,
          result: null,
        ),
      ),
    );
  }

  // Helper methods
  List<UserWorkspacePB> _sortWorkspaces(List<UserWorkspacePB> workspaces) {
    final sorted = [...workspaces];
    sorted.sort(
      (a, b) => a.createdAtTimestamp.compareTo(b.createdAtTimestamp),
    );
    return sorted;
  }

  UserWorkspacePB? _findWorkspaceById(
    String id, [
    List<UserWorkspacePB>? workspacesList,
  ]) {
    final workspaces = workspacesList ?? state.workspaces;
    return workspaces.firstWhereOrNull((e) => e.workspaceId == id);
  }

  List<UserWorkspacePB> _updateWorkspaceInList(
    String workspaceId,
    UserWorkspacePB Function(UserWorkspacePB workspace) updater,
  ) {
    final workspaces = [...state.workspaces];
    final index = workspaces.indexWhere((e) => e.workspaceId == workspaceId);
    if (index != -1) {
      workspaces[index] = updater(workspaces[index]);
    }
    return workspaces;
  }

  Future<_WorkspaceFetchResult> _fetchWorkspaces({
    String? initialWorkspaceId,
  }) async {
    try {
      final currentWorkspaceResult = await repository.getCurrentWorkspace();
      final currentWorkspace = currentWorkspaceResult.fold(
        (s) => s,
        (e) => null,
      );
      final currentWorkspaceId = initialWorkspaceId ?? currentWorkspace?.id;
      final workspacesResult = await repository.getWorkspaces();
      final workspaces = workspacesResult.getOrThrow();

      if (workspaces.isEmpty && currentWorkspace != null) {
        workspaces.add(
          _convertWorkspacePBToUserWorkspace(currentWorkspace),
        );
      }

      final currentWorkspaceInList = _findWorkspaceById(
            currentWorkspaceId ?? '',
            workspaces,
          ) ??
          workspaces.firstOrNull;

      final sortedWorkspaces = _sortWorkspaces(workspaces);

      Log.info(
        'fetch workspaces: current workspace: ${currentWorkspaceInList?.workspaceId}, sorted workspaces: ${sortedWorkspaces.map((e) => '${e.name}: ${e.workspaceId}')}',
      );

      return _WorkspaceFetchResult(
        currentWorkspace: currentWorkspaceInList,
        workspaces: sortedWorkspaces,
        shouldOpenWorkspace:
            currentWorkspaceInList?.workspaceId != currentWorkspaceId,
      );
    } catch (e) {
      Log.error('fetch workspace error: $e');
      return _WorkspaceFetchResult(
        currentWorkspace: state.currentWorkspace,
        workspaces: state.workspaces,
        shouldOpenWorkspace: false,
      );
    }
  }

  UserWorkspacePB _convertWorkspacePBToUserWorkspace(WorkspacePB workspace) {
    return UserWorkspacePB.create()
      ..workspaceId = workspace.id
      ..name = workspace.name
      ..createdAtTimestamp = workspace.createTime;
  }

  Future<void> _onFetchCurrentSubscription(
    WorkspaceEventFetchCurrentSubscription event,
    Emitter<UserWorkspaceState> emit,
  ) async {
    Log.info('[UserWorkspaceBloc] 开始获取会员订阅信息');
    final currentSubscription = await _fetchCurrentSubscriptionData(state.userProfile);
    if (!isClosed) {
      if (currentSubscription != null) {
        Log.info('[UserWorkspaceBloc] 会员订阅信息获取成功: planCode=${currentSubscription.subscription?.planCode}');
      } else {
        Log.warn('[UserWorkspaceBloc] 会员订阅信息获取失败或为空');
      }
      add(
        UserWorkspaceEvent.updateCurrentSubscription(
          currentSubscription: currentSubscription,
        ),
      );
    }
  }

  Future<void> _onUpdateCurrentSubscription(
    WorkspaceEventUpdateCurrentSubscription event,
    Emitter<UserWorkspaceState> emit,
  ) async {
    emit(
      state.copyWith(currentSubscription: event.currentSubscription),
    );
  }

  /// 获取当前订阅信息（包含使用量）
  Future<CurrentSubscription?> _fetchCurrentSubscriptionData(
    UserProfilePB userProfile,
  ) async {
    try {
      Log.info('[UserWorkspaceBloc] 开始调用订阅信息接口');
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;
      if (baseUrl.isEmpty) {
        Log.warn('[UserWorkspaceBloc] 订阅信息接口 baseUrl 为空，跳过请求');
        return null;
      }
      Log.info('[UserWorkspaceBloc] baseUrl: $baseUrl');

      final accessToken = _extractAccessToken(userProfile.token);
      if (accessToken == null || accessToken.isEmpty) {
        Log.warn('[UserWorkspaceBloc] 订阅信息接口缺少 access_token，跳过请求');
        Log.warn('[UserWorkspaceBloc] userProfile.token 是否存在: ${userProfile.hasToken()}, token长度: ${userProfile.token.length}');
        return null;
      }
      Log.info('[UserWorkspaceBloc] access_token 提取成功，长度: ${accessToken.length}');

      final uri = Uri.parse(baseUrl).replace(path: '/api/subscription/current');
      Log.info('[UserWorkspaceBloc] 请求 URL: $uri');
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
      ).timeout(
        const Duration(seconds: 30), // 增加超时时间到 30 秒，避免页面启动时网络未准备好导致超时
        onTimeout: () {
          Log.warn('[UserWorkspaceBloc] 订阅信息接口请求超时（30秒），可能网络未准备好，返回 null 不影响应用启动');
          // 不抛出异常，而是返回 null，避免影响应用启动流程
          // 后续可以通过手动刷新或延迟重试来获取订阅信息
          return http.Response('', 408); // 返回 408 Request Timeout 状态码
        },
      );

      Log.info('[UserWorkspaceBloc] 响应状态码: ${response.statusCode}');

      // 处理超时情况（408 Request Timeout）
      if (response.statusCode == 408) {
        Log.warn('[UserWorkspaceBloc] 订阅信息接口请求超时，返回 null');
        return null;
      }

      if (response.statusCode == 404) {
        Log.info('[UserWorkspaceBloc] 订阅信息接口返回 404，无订阅');
        return null;
      }

      if (response.statusCode != 200) {
        Log.warn(
          '[UserWorkspaceBloc] 订阅信息接口返回非 200: ${response.statusCode}, body: ${response.body}',
        );
        return null;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final code = decoded['code'] as int? ?? -1;
      Log.info('[UserWorkspaceBloc] 响应 code: $code');
      if (code != 0) {
        Log.warn(
          '[UserWorkspaceBloc] 订阅信息接口 code!=0: code=$code, message=${decoded['message']}',
        );
        return null;
      }

      final data = decoded['data'];
      if (data == null || data is! Map<String, dynamic>) {
        Log.warn('[UserWorkspaceBloc] 订阅信息接口 data 为空或格式错误');
        return null;
      }

      final subscription = CurrentSubscription.fromJson(data);
      Log.info('[UserWorkspaceBloc] 会员订阅信息解析成功: planCode=${subscription.subscription?.planCode}, planName=${subscription.subscription?.planNameCn}');
      return subscription;
    } catch (e, stackTrace) {
      Log.error('[UserWorkspaceBloc] 订阅信息接口请求异常: $e', e, stackTrace);
      return null;
    }
  }

  String? _extractAccessToken(String? rawToken) {
    if (rawToken == null || rawToken.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(rawToken);
      if (decoded is Map<String, dynamic>) {
        final accessToken = decoded['access_token'] as String?;
        if (accessToken != null && accessToken.isNotEmpty) {
          return accessToken;
        }
      }
    } catch (_) {
      // 非 JSON，直接使用原始 token
      return rawToken;
    }
    return null;
  }
}
