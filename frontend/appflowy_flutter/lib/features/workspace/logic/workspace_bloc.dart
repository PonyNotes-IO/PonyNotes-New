import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/features/workspace/data/repositories/workspace_repository.dart';
import 'package:appflowy/features/workspace/logic/folder_sync_state_listener.dart';
import 'package:appflowy/features/workspace/logic/workspace_event.dart';
import 'package:appflowy/features/workspace/logic/workspace_state.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/shared/settings/show_settings.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/subscription_success_listenable/subscription_success_listenable.dart';
import 'package:appflowy/user/application/reminder/reminder_bloc.dart';
import 'package:appflowy/user/application/user_listener.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/workspace/application/subscription/subscription_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:bloc/bloc.dart';
import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart' as http;
import 'package:protobuf/protobuf.dart';

import '../../../user/application/user_service.dart';
import '../../../workspace/application/subscription/membership_checker_service.dart';

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
        _subscriptionSuccessListenable = getIt<SubscriptionSuccessListenable>(),
        super(UserWorkspaceState.initial(userProfile)) {
    _subscriptionSuccessListener = () {
      if (isClosed) {
        return;
      }
      // 支付成功后刷新订阅信息
      _safeAdd(UserWorkspaceEvent.fetchCurrentSubscription());
      
      // 检查云同步状态，如果关闭则开启
      if (!state.isCloudSyncEnabled) {
        Log.info('Cloud sync is disabled, enabling it after payment success');
        _safeAdd(UserWorkspaceEvent.updateCloudSyncEnabled(enabled: true));
      }
    };
    _subscriptionSuccessListenable.addListener(_subscriptionSuccessListener);
    
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
    on<WorkspaceEventUpdateCloudSyncEnabled>(_onUpdateCloudSyncEnabled);
    on<WorkspaceEventUpdateFolderSyncState>(_onUpdateFolderSyncState);
  }

  final String? initialWorkspaceId;
  final WorkspaceRepository repository;
  final UserProfilePB userProfile;
  final UserListener _listener;
  final SubscriptionSuccessListenable _subscriptionSuccessListenable;
  late final VoidCallback _subscriptionSuccessListener;
  FolderSyncStateListener? _folderSyncStateListener;
  String? _folderSyncWorkspaceId;
  DateTime? _lastStorageCheckTime; // 上次检查存储的时间
  static const Duration _storageCheckInterval = Duration(minutes: 5); // 存储检查间隔

  /// 判断是否应该检查存储
  /// 
  /// 如果上次检查时间为null，或者与当前时间的间隔大于5分钟，则返回true
  bool _shouldCheckStorage() {
    if (_lastStorageCheckTime == null) {
      return true;
    }
    final now = DateTime.now();
    return now.difference(_lastStorageCheckTime!) > _storageCheckInterval;
  }

  @override
  Future<void> close() {
    _subscriptionSuccessListenable.removeListener(_subscriptionSuccessListener);
    _listener.stop();
    _folderSyncStateListener?.stop();
    _folderSyncWorkspaceId = null;
    return super.close();
  }

  Future<void> _onInitialize(
    WorkspaceEventInitialize event,
    Emitter<UserWorkspaceState> emit,
  ) async {
    // 如果用户是非免费版会员，根据 AppFlowy 的 sync 开关状态设置云同步开关
    await _initializeCloudSyncFromAppFlowySync(emit);
    
    await _setupListeners();
    await _initializeWorkspaces(emit);
  }

  /// 根据 AppFlowy 的 sync 开关状态初始化云同步开关
  /// 1.直接使用 Rust 层的值，不需要判断会员信息
  Future<void> _initializeCloudSyncFromAppFlowySync(
    Emitter<UserWorkspaceState> emit,
  ) async {
    try {
      // 1. 先获取 Rust 数据库中的值
      final cloudConfigResult = await UserEventGetCloudConfig().send();
      
      await cloudConfigResult.fold(
        (cloudConfig) async {
          final rustEnabled = cloudConfig.enableSync;

          // 关键兜底：即使值没有变化，也要把 enable_sync 再次下发到 Rust 运行时。
          // 首次安装启动时，可能出现「配置值已是 true，但运行时同步引擎尚未激活」的情况，
          // 导致 SidebarCloudSyncButton 一直停留在“同步中”。
          final config = UpdateCloudConfigPB.create()..enableSync = rustEnabled;
          await UserEventSetCloudConfig(config).send();
          
          // 直接使用 Rust 层的值，不需要判断会员信息
          if (state.isCloudSyncEnabled != rustEnabled) {
            emit(state.copyWith(isCloudSyncEnabled: rustEnabled));
          }
        },
        (error) async {
          // 如果读取失败，使用默认值（开启）
          emit(state.copyWith(isCloudSyncEnabled: true));

          // 读取失败时同样兜底激活运行时同步引擎
          final config = UpdateCloudConfigPB.create()..enableSync = true;
          await UserEventSetCloudConfig(config).send();
        },
      );
    } catch (e, stackTrace) {
      // 初始化云同步开关状态时出错
    }
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

    emit(
      state.copyWith(
        workspaces: workspaces,
      ),
    );

    if (currentWorkspace != null &&
        currentWorkspace.workspaceId != state.currentWorkspace?.workspaceId) {
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

    // 检查云同步开关状态
    final isCloudSyncEnabled = state.isCloudSyncEnabled;

    // 如果云同步关闭，不能创建工作区
    if (!isCloudSyncEnabled) {
      final errorResult = FlowyResult.failure(
        FlowyError(
          code: ErrorCode.Internal,
          msg: '云同步已关闭，无法创建工作区。请先开启云同步功能。',
        ),
      );
      emit(
        state.copyWith(
          actionResult: WorkspaceActionResult(
            actionType: WorkspaceActionType.create,
            isLoading: false,
            result: errorResult.map((_) {}),
          ),
        ),
      );
      return;
    }

    // 始终创建 ServerW 类型的工作区（服务类型），与用户需求一致
    // 云同步开关只控制是否启用 sync 功能，不影响工作区类型
    final workspaceType = WorkspaceTypePB.ServerW;
    
    final result = await repository.createWorkspace(
      name: event.name,
      workspaceType: workspaceType,
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
        // 如果云同步开启，确保工作区已同步到服务端
        add(
          UserWorkspaceEvent.openWorkspace(
            workspaceId: s.workspaceId,
            workspaceType: s.workspaceType,
          ),
        );
      })
      ..onFailure((f) {
        // 工作区创建失败
      });
  }

  Future<void> _onDeleteWorkspace(
    WorkspaceEventDeleteWorkspace event,
    Emitter<UserWorkspaceState> emit,
  ) async {
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
        final firstWorkspace = workspaces.firstOrNull;
        assert(
          firstWorkspace != null,
          'the first workspace must not be null',
        );
        if (state.currentWorkspace?.workspaceId == event.workspaceId &&
            firstWorkspace != null) {
          add(
            UserWorkspaceEvent.openWorkspace(
              workspaceId: firstWorkspace.workspaceId,
              workspaceType: firstWorkspace.workspaceType,
            ),
          );
        }
      })
      ..onFailure((f) {
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
        // 启动文件夹同步状态监听器
        _startFolderSyncStateListener(event.workspaceId);
      })
      ..onFailure((f) {
        // 打开工作区失败
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
    // 检查工作区类型和云同步开关状态
    final workspace = _findWorkspaceById(event.workspaceId);
    final isCloudSyncEnabled = state.isCloudSyncEnabled;
    final isServerWorkspace = workspace?.workspaceType == WorkspaceTypePB.ServerW;
    
    // 如果工作区类型是 ServerW 但云同步关闭，只做本地修改，不调用服务器 API
    FlowyResult<void, FlowyError> result;
    if (isServerWorkspace && !isCloudSyncEnabled) {
      // 创建一个成功的结果，但不调用服务器 API
      result = FlowyResult.success(null);
    } else {
      // 正常调用服务器 API
      result = await repository.renameWorkspace(
        workspaceId: event.workspaceId,
        name: event.name,
      );
    }

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

    result.onFailure((f) {
      // 重命名工作区失败
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
      // 工作区未找到
      return;
    }

    if (event.icon == workspace.icon) {
      return;
    }

    // 检查工作区类型和云同步开关状态
    final isCloudSyncEnabled = state.isCloudSyncEnabled;
    final isServerWorkspace = workspace.workspaceType == WorkspaceTypePB.ServerW;
    
    // 如果工作区类型是 ServerW 但云同步关闭，只做本地修改，不调用服务器 API
    FlowyResult<void, FlowyError> result;
    if (isServerWorkspace && !isCloudSyncEnabled) {
      // 创建一个成功的结果，但不调用服务器 API
      result = FlowyResult.success(null);
    } else {
      // 正常调用服务器 API
      result = await repository.updateWorkspaceIcon(
        workspaceId: event.workspaceId,
        icon: event.icon,
      );
    }

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

    result.onFailure((f) {
      // 更新工作区图标失败
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
        // 离开工作区失败
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
    final enabled = await repository.isBillingEnabled();
    
    // If billing is not enabled, we don't need to fetch the workspace subscription info
    if (!enabled) {
      return;
    }

    unawaited(
      repository
          .getWorkspaceSubscriptionInfo(
        workspaceId: event.workspaceId,
      )
          .fold(
        (workspaceSubscriptionInfo) {
          if (isClosed) {
            return;
          }

          final currentWorkspaceId = state.currentWorkspace?.workspaceId;
          if (currentWorkspaceId != event.workspaceId) {
            return;
          }

          add(
            UserWorkspaceEvent.updateWorkspaceSubscriptionInfo(
              workspaceId: event.workspaceId,
              subscriptionInfo: workspaceSubscriptionInfo,
            ),
          );
        },
        (e) {
          // 即使失败，也尝试更新状态为 null，避免一直等待
          if (!isClosed && state.currentWorkspace?.workspaceId == event.workspaceId) {
            // 请求失败，更新状态
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
    // 仅更新订阅信息，不处理云同步状态
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
            },
            (error) => null,
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
      // 静默处理事件添加错误
    } catch (e, st) {
      // 静默处理意外错误
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

    if (currentWorkspace != null && result.shouldOpenWorkspace == true) {
      await repository.openWorkspace(
        workspaceId: currentWorkspace.workspaceId,
        workspaceType: currentWorkspace.workspaceType,
      );
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

      return _WorkspaceFetchResult(
        currentWorkspace: currentWorkspaceInList,
        workspaces: sortedWorkspaces,
        shouldOpenWorkspace:
            currentWorkspaceInList?.workspaceId != currentWorkspaceId,
      );
    } catch (e) {
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
    final currentSubscription = await SubscriptionService().getCurrentSubscription(
      userProfile: state.userProfile,
      caller: 'UserWorkspaceBloc._onFetchCurrentSubscription',
    );
    if (!isClosed) {
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
    // 仅更新订阅信息，不处理云同步状态
    emit(
      state.copyWith(currentSubscription: event.currentSubscription),
    );
  }



  Future<void> _onUpdateCloudSyncEnabled(
    WorkspaceEventUpdateCloudSyncEnabled event,
    Emitter<UserWorkspaceState> emit,
  ) async {
    emit(state.copyWith(isCloudSyncEnabled: event.enabled));
    
    // 保存到 Rust 层的 enable_sync 设置
    try {
      final config = UpdateCloudConfigPB.create()..enableSync = event.enabled;
      await UserEventSetCloudConfig(config).send();
    } catch (e, stackTrace) {
      // 无法保存到 Rust 层
    }
  }

  /// 启动文件夹同步状态监听器
  void _startFolderSyncStateListener(String workspaceId) {
    // 同一个 workspace 已在监听时，不要重复 stop/start。
    // 首次启动会有多路事件并发触发该方法，重复重绑会造成监听空窗，容易丢失“同步完成”事件。
    if (_folderSyncWorkspaceId == workspaceId && _folderSyncStateListener != null) {
      return;
    }

    // 停止之前的监听器
    _folderSyncStateListener?.stop();
    _folderSyncWorkspaceId = null;
    
    // 创建新的监听器
    _folderSyncStateListener = FolderSyncStateListener(workspaceId: workspaceId);
    _folderSyncWorkspaceId = workspaceId;
    _folderSyncStateListener!.start(
      didReceiveSyncState: (syncState) {
        if (!isClosed) {
          add(WorkspaceEventUpdateFolderSyncState(syncState: syncState));
        }
      },
    );
  }

  /// 更新文件夹同步状态
  Future<void> _onUpdateFolderSyncState(
    WorkspaceEventUpdateFolderSyncState event,
    Emitter<UserWorkspaceState> emit,
  ) async {
    final oldSyncState = state.folderSyncState;
    final newSyncState = event.syncState;
    
    Log.info('[WorkspaceBloc] 更新同步状态: old=${oldSyncState?.isSyncing}/${oldSyncState?.isFinish}, new=${newSyncState.isSyncing}/${newSyncState.isFinish}');
    
    if (oldSyncState != null && 
        oldSyncState.isSyncing == newSyncState.isSyncing && 
        oldSyncState.isFinish == newSyncState.isFinish) {
      // 状态未改变，跳过更新
      return;
    }
    
    emit(state.copyWith(folderSyncState: newSyncState));
    
    // 当同步完成时，更新订阅信息并检查存储限制
    if (newSyncState.isFinish && !newSyncState.isSyncing) {
      // 同步完成，更新订阅信息
      _safeAdd(UserWorkspaceEvent.fetchCurrentSubscription());
      
      // 检查存储限制（只有当间隔大于5分钟后才检查）
      if (_shouldCheckStorage()) {
        try {
          final userResult = await UserBackendService.getCurrentUserProfile();
          final userProfile = userResult.fold(
                (user) => user,
                (error) => throw Exception('Failed to get user profile: ${error.msg}'),
          );

          final canUseAI = await MembershipCheckerService().checkStorageLimit(userProfile: userProfile,requiredStorageMB: 0);
          if (!canUseAI) {
            Log.info('❌ ChatBloc: AI聊天次数已达上限，停止发送消息');
            return;
          }
        } catch (e) {
          Log.error('Failed to check AI chat limit: $e');
          // 如果检查失败，默认允许使用AI
          return;
        }
      } else {
        Log.info('Storage check skipped, interval not reached');
      }
    }
  }
}
