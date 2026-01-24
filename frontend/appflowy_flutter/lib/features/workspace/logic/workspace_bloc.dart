import 'dart:async';
import 'dart:convert';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/features/workspace/data/repositories/workspace_repository.dart';
import 'package:appflowy/features/workspace/logic/folder_sync_state_listener.dart';
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
import 'package:appflowy_backend/dispatch/dispatch.dart';
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
    on<WorkspaceEventUpdateCloudSyncEnabled>(_onUpdateCloudSyncEnabled);
    on<WorkspaceEventUpdateFolderSyncState>(_onUpdateFolderSyncState);
  }

  final String? initialWorkspaceId;
  final WorkspaceRepository repository;
  final UserProfilePB userProfile;
  final UserListener _listener;
  FolderSyncStateListener? _folderSyncStateListener;

  @override
  Future<void> close() {
    _listener.stop();
    _folderSyncStateListener?.stop();
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
  /// 1. 先获取 Rust 数据库中的值
  /// 2. 然后判断会员信息
  /// 3. 如果是其他会员（非免费版），保持不变（使用 Rust 层的值）
  /// 4. 如果是免费版：
  ///    - 如果当前开启状态，则修改为关闭状态
  ///    - 如果当前关闭状态，则不用修改
  Future<void> _initializeCloudSyncFromAppFlowySync(
    Emitter<UserWorkspaceState> emit,
  ) async {
    try {
      // 1. 先获取 Rust 数据库中的值
      Log.info('[UserWorkspaceBloc] 初始化时，优先读取 Rust 层保存的 enable_sync 设置');
      final cloudConfigResult = await UserEventGetCloudConfig().send();
      
      await cloudConfigResult.fold(
        (cloudConfig) async {
          final rustEnabled = cloudConfig.enableSync;
          Log.info('[UserWorkspaceBloc] 从 Rust 层读取 enable_sync 状态: $rustEnabled');
          
          // 2. 判断会员信息
          final currentSubscription = state.currentSubscription;
          final subscriptionInfo = state.workspaceSubscriptionInfo;
          final isNonFreeMember = _isNonFreeMember(currentSubscription, subscriptionInfo);
          
          // 检查订阅信息是否已加载
          final hasSubscriptionInfo = currentSubscription != null || subscriptionInfo != null;
          
          if (!hasSubscriptionInfo) {
            // 订阅信息未加载，先使用 Rust 层的值，等订阅信息加载后再根据会员状态调整
            Log.info('[UserWorkspaceBloc] 订阅信息未加载，先使用 Rust 层的值: $rustEnabled，等订阅信息加载后再调整');
            if (state.isCloudSyncEnabled != rustEnabled) {
              emit(state.copyWith(isCloudSyncEnabled: rustEnabled));
            }
          } else if (isNonFreeMember) {
            // 3. 如果是其他会员（非免费版），保持不变（使用 Rust 层的值）
            Log.info('[UserWorkspaceBloc] 用户是非免费版会员，使用 Rust 层的值: $rustEnabled');
            if (state.isCloudSyncEnabled != rustEnabled) {
              emit(state.copyWith(isCloudSyncEnabled: rustEnabled));
            }
          } else {
            // 4. 如果是免费版：
            //    - 如果当前开启状态，则修改为关闭状态
            //    - 如果当前关闭状态，则不用修改
            if (rustEnabled) {
              // Rust 层是开启状态，免费版会员需要强制关闭
              Log.info('[UserWorkspaceBloc] 用户是免费版会员，但 Rust 层 enable_sync 为 true，强制关闭');
              emit(state.copyWith(isCloudSyncEnabled: false));
              // 保存到 Rust 层
              try {
                final config = UpdateCloudConfigPB.create()..enableSync = false;
                await UserEventSetCloudConfig(config).send();
                Log.info('[UserWorkspaceBloc] 已强制关闭 AppFlowy 的 enableSync（免费版用户）');
              } catch (e) {
                Log.warn('[UserWorkspaceBloc] 无法强制关闭 AppFlowy 的 enableSync: $e');
              }
            } else {
              // Rust 层是关闭状态，免费版会员保持关闭，不用修改
              Log.info('[UserWorkspaceBloc] 用户是免费版会员，Rust 层 enable_sync 为 false，保持关闭状态');
              if (state.isCloudSyncEnabled != false) {
                emit(state.copyWith(isCloudSyncEnabled: false));
              }
            }
          }
        },
        (error) async {
          Log.warn('[UserWorkspaceBloc] 无法读取 Rust 层 enable_sync 状态: $error');
          // 如果读取失败，根据会员状态决定
          final currentSubscription = state.currentSubscription;
          final subscriptionInfo = state.workspaceSubscriptionInfo;
          final isNonFreeMember = _isNonFreeMember(currentSubscription, subscriptionInfo);
          
          if (!isNonFreeMember) {
            // 免费版会员：强制关闭
            Log.info('[UserWorkspaceBloc] 无法读取 Rust 层，但用户是免费版会员，强制关闭云同步开关');
            if (state.isCloudSyncEnabled) {
              emit(state.copyWith(isCloudSyncEnabled: false));
            }
            // 保存到 Rust 层
            try {
              final config = UpdateCloudConfigPB.create()..enableSync = false;
              await UserEventSetCloudConfig(config).send();
              Log.info('[UserWorkspaceBloc] 已强制关闭 AppFlowy 的 enableSync（免费版用户）');
            } catch (e) {
              Log.warn('[UserWorkspaceBloc] 无法强制关闭 AppFlowy 的 enableSync: $e');
            }
          } else {
            // 非免费版会员，但无法读取 Rust 层，保持当前状态（可能是默认值 false）
            Log.info('[UserWorkspaceBloc] 无法读取 Rust 层，但用户是非免费版会员，保持当前状态');
          }
        },
      );
    } catch (e, stackTrace) {
      Log.error('[UserWorkspaceBloc] 初始化云同步开关状态时出错: $e', e, stackTrace);
    }
  }

  /// 判断用户是否为非免费版会员
  bool _isNonFreeMember(
    CurrentSubscription? currentSubscription,
    WorkspaceSubscriptionInfoPB? subscriptionInfo,
  ) {
    // 优先使用 currentSubscription 判断
    final subscription = currentSubscription?.subscription;
    if (subscription != null && subscription.planCode != null && subscription.planCode!.isNotEmpty) {
      final planCode = subscription.planCode!.toLowerCase();
      // 如果是免费版，返回 false
      if (planCode == 'free' || planCode == 'freeplan') {
        return false;
      }
      // 检查是否已到期
      final endDate = subscription.endDate;
      if (endDate != null && endDate.isBefore(DateTime.now())) {
        return false; // 已到期，视为免费版
      }
      // 非免费版且未到期
      return true;
    }
    
    // 降级方案：使用 subscriptionInfo 判断
    if (subscriptionInfo != null) {
      if (subscriptionInfo.plan == WorkspacePlanPB.FreePlan) {
        return false;
      }
      // 非免费版
      return true;
    }
    
    // 没有会员信息，默认视为免费版
    return false;
  }

  /// 检查空间是否已满
  /// 返回 true 表示空间已满，false 表示空间未满
  bool _isStorageFull(CurrentSubscription? currentSubscription) {
    final usage = currentSubscription?.usage;
    final storageUsedGb = usage?.storageUsedGb;
    final storageTotalGb = usage?.storageTotalGb;
    if (storageUsedGb != null && storageTotalGb != null) {
      return storageUsedGb >= storageTotalGb;
    }
    return false;
  }

  /// 校验会员状态（会员级别、有效期、空间剩余大小）
  /// 返回 (isValid, errorMessage)
  /// isValid: true 表示可以开启云同步，false 表示不能开启
  /// errorMessage: 如果 isValid 为 false，返回错误原因
  Future<(bool isValid, String? errorMessage)> _validateMembershipForCloudSync() async {
    final currentSubscription = state.currentSubscription;
    final subscriptionInfo = state.workspaceSubscriptionInfo;
    
    // 优先使用 currentSubscription 判断
    final subscription = currentSubscription?.subscription;
    if (subscription != null && subscription.planCode != null && subscription.planCode!.isNotEmpty) {
      final planCode = subscription.planCode!.toLowerCase();
      
      // 检查会员级别：如果是免费版，不能开启
      if (planCode == 'free' || planCode == 'freeplan') {
        return (false, '免费版会员无法开启云同步');
      }
      
      // 检查有效期：如果已到期，不能开启
      final endDate = subscription.endDate;
      if (endDate != null && endDate.isBefore(DateTime.now())) {
        return (false, '会员已到期，请续费以继续使用云同步功能');
      }
      
      // 检查空间剩余大小：如果空间已满，不能开启
      final usage = currentSubscription?.usage;
      final storageUsedGb = usage?.storageUsedGb;
      final storageTotalGb = usage?.storageTotalGb;
      if (storageUsedGb != null && storageTotalGb != null) {
        if (storageUsedGb >= storageTotalGb) {
          return (false, '空间使用已满，请扩容以继续使用云同步功能');
        }
      }
      
      // 所有校验通过
      return (true, null);
    }
    
    // 降级方案：使用 subscriptionInfo 判断
    if (subscriptionInfo != null) {
      if (subscriptionInfo.plan == WorkspacePlanPB.FreePlan) {
        return (false, '免费版会员无法开启云同步');
      }
      // subscriptionInfo 不包含到期时间和使用量信息，无法判断过期和空间满
      // 但如果有 subscriptionInfo 且不是免费版，认为可以开启
      return (true, null);
    }
    
    // 没有会员信息，默认视为免费版
    return (false, '未开通会员，无法开启云同步');
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

    // 检查云同步开关状态
    final isCloudSyncEnabled = state.isCloudSyncEnabled;
    Log.info('[UserWorkspaceBloc] 创建工作区: name=${event.name}, workspaceType=${event.workspaceType}, isCloudSyncEnabled=$isCloudSyncEnabled');

    // 如果云同步关闭，不能创建工作区
    if (!isCloudSyncEnabled) {
      Log.warn('[UserWorkspaceBloc] 云同步已关闭，不能创建工作区');
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
    
    Log.info('[UserWorkspaceBloc] 最终工作区类型: $workspaceType (始终创建 ServerW 类型，云同步: $isCloudSyncEnabled)');
    
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
        Log.info('[UserWorkspaceBloc] 工作区创建成功: workspaceId=${s.workspaceId}, isCloudSyncEnabled=$isCloudSyncEnabled');
        // 如果云同步开启，确保工作区已同步到服务端
        if (isCloudSyncEnabled) {
          Log.info('[UserWorkspaceBloc] 云同步已开启，工作区已同步到服务端: workspaceId=${s.workspaceId}');
        } else {
          Log.warn('[UserWorkspaceBloc] 云同步已关闭，工作区可能未同步到服务端: workspaceId=${s.workspaceId}');
        }
        add(
          UserWorkspaceEvent.openWorkspace(
            workspaceId: s.workspaceId,
            workspaceType: s.workspaceType,
          ),
        );
      })
      ..onFailure((f) {
        Log.error('[UserWorkspaceBloc] 工作区创建失败: $f');
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
        
        // 启动文件夹同步状态监听器
        _startFolderSyncStateListener(event.workspaceId);
        
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
    // 检查工作区类型和云同步开关状态
    final workspace = _findWorkspaceById(event.workspaceId);
    final isCloudSyncEnabled = state.isCloudSyncEnabled;
    final isServerWorkspace = workspace?.workspaceType == WorkspaceTypePB.ServerW;
    
    Log.info('[UserWorkspaceBloc] 重命名工作区: workspaceId=${event.workspaceId}, name=${event.name}, workspaceType=${workspace?.workspaceType}, isCloudSyncEnabled=$isCloudSyncEnabled');
    
    // 如果工作区类型是 ServerW 但云同步关闭，只做本地修改，不调用服务器 API
    FlowyResult<void, FlowyError> result;
    if (isServerWorkspace && !isCloudSyncEnabled) {
      Log.info('[UserWorkspaceBloc] 工作区类型为 ServerW 但云同步已关闭，只做本地修改，不上传到服务器');
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

    Log.info('[UserWorkspaceBloc] 重命名工作区完成: workspaceId=${event.workspaceId}, name=${event.name}');

    result.onFailure((f) {
      Log.error('[UserWorkspaceBloc] 重命名工作区失败: $f');
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
      Log.error('[UserWorkspaceBloc] 工作区未找到: ${event.workspaceId}');
      return;
    }

    if (event.icon == workspace.icon) {
      Log.info('[UserWorkspaceBloc] 忽略相同的图标更新');
      return;
    }

    // 检查工作区类型和云同步开关状态
    final isCloudSyncEnabled = state.isCloudSyncEnabled;
    final isServerWorkspace = workspace.workspaceType == WorkspaceTypePB.ServerW;
    
    Log.info('[UserWorkspaceBloc] 更新工作区图标: workspaceId=${event.workspaceId}, icon=${event.icon}, workspaceType=${workspace.workspaceType}, isCloudSyncEnabled=$isCloudSyncEnabled');
    
    // 如果工作区类型是 ServerW 但云同步关闭，只做本地修改，不调用服务器 API
    FlowyResult<void, FlowyError> result;
    if (isServerWorkspace && !isCloudSyncEnabled) {
      Log.info('[UserWorkspaceBloc] 工作区类型为 ServerW 但云同步已关闭，只做本地修改，不上传到服务器');
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
    // 检测是否是从免费版变为非免费版（新开通会员）
    // 需要区分"初始化时订阅信息未加载"和"真正的会员升级"
    final previousSubscriptionInfo = state.workspaceSubscriptionInfo;
    final wasNonFreeMember = _isNonFreeMember(
      state.currentSubscription,
      previousSubscriptionInfo,
    );
    
    emit(
      state.copyWith(workspaceSubscriptionInfo: event.subscriptionInfo),
    );
    
    final isNonFreeMember = _isNonFreeMember(
      state.currentSubscription,
      event.subscriptionInfo,
    );
    
    // 判断是否为新开通会员：
    // 1. 之前不是非免费版会员（wasNonFreeMember = false）
    // 2. 现在是非免费版会员（isNonFreeMember = true）
    // 3. 之前的订阅信息存在（不是初始化时未加载的情况）
    // 如果之前的订阅信息是 null，说明是初始化时未加载，不是真正的会员升级
    final isNewlySubscribed = !wasNonFreeMember && 
                              isNonFreeMember && 
                              previousSubscriptionInfo != null;
    
    if (isNewlySubscribed) {
      // 用户新开通会员，强制设置为开启云同步（不检查 Rust 层的值）
      // 因为用户之前可能是免费版，云同步被强制关闭，现在开通会员后应该自动开启
      Log.info('[UserWorkspaceBloc] 检测到用户新开通会员（通过工作区订阅信息），强制开启云同步');
      
      // 校验会员状态
      final validation = await _validateMembershipForCloudSync();
      if (validation.$1) {
        // 校验通过，开启云同步
        emit(state.copyWith(isCloudSyncEnabled: true));
        
        // 保存到 Rust 层的 enable_sync 设置
        try {
          final config = UpdateCloudConfigPB.create()..enableSync = true;
          await UserEventSetCloudConfig(config).send();
          Log.info('[UserWorkspaceBloc] 新开通会员，已强制开启并保存到 Rust 层 enable_sync: true');
        } catch (e, stackTrace) {
          Log.error('[UserWorkspaceBloc] 无法保存到 Rust 层 enable_sync: $e', e, stackTrace);
        }
      } else {
        Log.warn('[UserWorkspaceBloc] 新开通会员但校验失败: ${validation.$2}');
      }
    } else if (isNonFreeMember) {
      // 非免费版会员，但不是新开通，检查空间使用情况
      Log.info('[UserWorkspaceBloc] 工作区订阅信息已更新，用户是非免费版会员，检查空间使用情况');
      
      // 检查空间是否已满（优先使用 currentSubscription，因为它包含使用量信息）
      final isStorageFull = _isStorageFull(state.currentSubscription);
      if (isStorageFull && state.isCloudSyncEnabled) {
        // 空间已满且云同步已开启，自动关闭云同步
        Log.warn('[UserWorkspaceBloc] 空间已满，自动关闭云同步');
        emit(state.copyWith(isCloudSyncEnabled: false));
        
        // 保存到 Rust 层的 enable_sync 设置
        try {
          final config = UpdateCloudConfigPB.create()..enableSync = false;
          await UserEventSetCloudConfig(config).send();
          Log.info('[UserWorkspaceBloc] 已因空间不足关闭 Rust 层 enable_sync');
        } catch (e) {
          Log.warn('[UserWorkspaceBloc] 无法因空间不足关闭 Rust 层 enable_sync: $e');
        }
      } else {
        // 空间未满或云同步已关闭
        // 订阅信息加载后，如果初始化时还没加载订阅信息，现在需要从 Rust 层读取正确的值
        // 非免费版会员：使用 Rust 层的值（保持不变）
        Log.info('[UserWorkspaceBloc] 工作区订阅信息加载后，用户是非免费版会员，从 Rust 层读取 enable_sync 状态');
        try {
          final cloudConfigResult = await UserEventGetCloudConfig().send();
          cloudConfigResult.fold(
            (cloudConfig) {
              final rustEnabled = cloudConfig.enableSync;
              Log.info('[UserWorkspaceBloc] 从 Rust 层读取 enable_sync 状态: $rustEnabled');
              // 非免费版会员，使用 Rust 层的值（保持不变）
              if (state.isCloudSyncEnabled != rustEnabled) {
                Log.info('[UserWorkspaceBloc] Rust 层 enable_sync 为 $rustEnabled，更新状态以保持一致');
                emit(state.copyWith(isCloudSyncEnabled: rustEnabled));
              }
            },
            (error) {
              Log.warn('[UserWorkspaceBloc] 无法读取 Rust 层 enable_sync 状态: $error');
            },
          );
        } catch (e) {
          Log.warn('[UserWorkspaceBloc] 检查 Rust 层 enable_sync 状态时出错: $e');
        }
      }
    } else {
      // 变为免费版，强制关闭云同步
      Log.info('[UserWorkspaceBloc] 用户变为免费版，强制关闭云同步');
      if (state.isCloudSyncEnabled) {
        emit(state.copyWith(isCloudSyncEnabled: false));
      }
      // 保存到 Rust 层的 enable_sync 设置
      try {
        final config = UpdateCloudConfigPB.create()..enableSync = false;
        await UserEventSetCloudConfig(config).send();
        Log.info('[UserWorkspaceBloc] 已强制关闭 Rust 层 enable_sync');
      } catch (e) {
        Log.warn('[UserWorkspaceBloc] 无法强制关闭 Rust 层 enable_sync: $e');
      }
    }
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
    // 检测是否是从免费版变为非免费版（新开通会员）
    // 需要区分"初始化时订阅信息未加载"和"真正的会员升级"
    final previousCurrentSubscription = state.currentSubscription;
    final wasNonFreeMember = _isNonFreeMember(
      previousCurrentSubscription,
      state.workspaceSubscriptionInfo,
    );
    final isNonFreeMember = _isNonFreeMember(
      event.currentSubscription,
      state.workspaceSubscriptionInfo,
    );
    
    // 判断是否为新开通会员：
    // 1. 之前不是非免费版会员（wasNonFreeMember = false）
    // 2. 现在是非免费版会员（isNonFreeMember = true）
    // 3. 之前的订阅信息存在（不是初始化时未加载的情况）
    // 如果之前的订阅信息是 null，说明是初始化时未加载，不是真正的会员升级
    final isNewlySubscribed = !wasNonFreeMember && 
                              isNonFreeMember && 
                              previousCurrentSubscription != null;
    
    emit(
      state.copyWith(currentSubscription: event.currentSubscription),
    );
    
    if (isNewlySubscribed) {
      // 用户新开通会员，强制设置为开启云同步（不检查 Rust 层的值）
      // 因为用户之前可能是免费版，云同步被强制关闭，现在开通会员后应该自动开启
      Log.info('[UserWorkspaceBloc] 检测到用户新开通会员，强制开启云同步');
      
      // 校验会员状态
      final validation = await _validateMembershipForCloudSync();
      if (validation.$1) {
        // 校验通过，开启云同步
        emit(state.copyWith(isCloudSyncEnabled: true));
        
        // 保存到 Rust 层的 enable_sync 设置
        try {
          final config = UpdateCloudConfigPB.create()..enableSync = true;
          await UserEventSetCloudConfig(config).send();
          Log.info('[UserWorkspaceBloc] 新开通会员，已强制开启并保存到 Rust 层 enable_sync: true');
        } catch (e, stackTrace) {
          Log.error('[UserWorkspaceBloc] 无法保存到 Rust 层 enable_sync: $e', e, stackTrace);
        }
      } else {
        Log.warn('[UserWorkspaceBloc] 新开通会员但校验失败: ${validation.$2}');
      }
    } else if (isNonFreeMember) {
      // 非免费版会员，但不是新开通，检查空间使用情况
      Log.info('[UserWorkspaceBloc] 会员订阅信息已更新，用户是非免费版会员，检查空间使用情况');
      
      // 检查空间是否已满
      final isStorageFull = _isStorageFull(event.currentSubscription);
      if (isStorageFull && state.isCloudSyncEnabled) {
        // 空间已满且云同步已开启，自动关闭云同步
        Log.warn('[UserWorkspaceBloc] 空间已满，自动关闭云同步');
        emit(state.copyWith(isCloudSyncEnabled: false));
        
        // 保存到 Rust 层的 enable_sync 设置
        try {
          final config = UpdateCloudConfigPB.create()..enableSync = false;
          await UserEventSetCloudConfig(config).send();
          Log.info('[UserWorkspaceBloc] 已因空间不足关闭 Rust 层 enable_sync');
        } catch (e) {
          Log.warn('[UserWorkspaceBloc] 无法因空间不足关闭 Rust 层 enable_sync: $e');
        }
      } else {
        // 空间未满或云同步已关闭
        // 订阅信息加载后，如果初始化时还没加载订阅信息，现在需要从 Rust 层读取正确的值
        // 非免费版会员：使用 Rust 层的值（保持不变）
        Log.info('[UserWorkspaceBloc] 订阅信息加载后，用户是非免费版会员，从 Rust 层读取 enable_sync 状态');
        try {
          final cloudConfigResult = await UserEventGetCloudConfig().send();
          cloudConfigResult.fold(
            (cloudConfig) {
              final rustEnabled = cloudConfig.enableSync;
              Log.info('[UserWorkspaceBloc] 从 Rust 层读取 enable_sync 状态: $rustEnabled');
              // 非免费版会员，使用 Rust 层的值（保持不变）
              if (state.isCloudSyncEnabled != rustEnabled) {
                Log.info('[UserWorkspaceBloc] Rust 层 enable_sync 为 $rustEnabled，更新状态以保持一致');
                emit(state.copyWith(isCloudSyncEnabled: rustEnabled));
              }
            },
            (error) {
              Log.warn('[UserWorkspaceBloc] 无法读取 Rust 层 enable_sync 状态: $error');
            },
          );
        } catch (e) {
          Log.warn('[UserWorkspaceBloc] 检查 Rust 层 enable_sync 状态时出错: $e');
        }
      }
    } else {
      // 变为免费版或会员到期，强制关闭云同步
      Log.info('[UserWorkspaceBloc] 用户变为免费版或会员到期，强制关闭云同步');
      if (state.isCloudSyncEnabled) {
        emit(state.copyWith(isCloudSyncEnabled: false));
      }
      // 保存到 Rust 层的 enable_sync 设置
      try {
        final config = UpdateCloudConfigPB.create()..enableSync = false;
        await UserEventSetCloudConfig(config).send();
        Log.info('[UserWorkspaceBloc] 已强制关闭 Rust 层 enable_sync');
      } catch (e) {
        Log.warn('[UserWorkspaceBloc] 无法强制关闭 Rust 层 enable_sync: $e');
      }
    }
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

  Future<void> _onUpdateCloudSyncEnabled(
    WorkspaceEventUpdateCloudSyncEnabled event,
    Emitter<UserWorkspaceState> emit,
  ) async {
    Log.info('[UserWorkspaceBloc] 更新云同步开关状态: ${event.enabled}');
    
    // 如果要关闭云同步，直接关闭（不需要校验）
    if (!event.enabled) {
      Log.info('[UserWorkspaceBloc] 用户手动关闭云同步开关');
      emit(state.copyWith(isCloudSyncEnabled: false));
      
      // 保存到 Rust 层的 enable_sync 设置
      try {
        final config = UpdateCloudConfigPB.create()..enableSync = false;
        await UserEventSetCloudConfig(config).send();
        Log.info('[UserWorkspaceBloc] 已保存到 Rust 层 enable_sync: false');
      } catch (e, stackTrace) {
        Log.error('[UserWorkspaceBloc] 无法保存到 Rust 层 enable_sync: $e', e, stackTrace);
      }
      return;
    }
    
    // 如果要开启云同步，需要校验会员状态
    Log.info('[UserWorkspaceBloc] 用户尝试开启云同步，开始校验会员状态');
    final validation = await _validateMembershipForCloudSync();
    
    if (!validation.$1) {
      // 校验失败，不能开启
      Log.warn('[UserWorkspaceBloc] 会员状态校验失败: ${validation.$2}');
      // 保持当前状态不变，不更新
      // 注意：这里不抛出异常，因为这是用户操作，应该由 UI 层显示错误提示
      return;
    }
    
    // 校验通过，更新云同步开关状态
    Log.info('[UserWorkspaceBloc] 会员状态校验通过，开启云同步');
    emit(state.copyWith(isCloudSyncEnabled: true));
    
    // 保存到 Rust 层的 enable_sync 设置
    try {
      final config = UpdateCloudConfigPB.create()..enableSync = true;
      await UserEventSetCloudConfig(config).send();
      Log.info('[UserWorkspaceBloc] 已保存到 Rust 层 enable_sync: true');
    } catch (e, stackTrace) {
      Log.error('[UserWorkspaceBloc] 无法保存到 Rust 层 enable_sync: $e', e, stackTrace);
    }
  }

  /// 启动文件夹同步状态监听器
  void _startFolderSyncStateListener(String workspaceId) {
    // 停止之前的监听器
    _folderSyncStateListener?.stop();
    
    // 创建新的监听器
    _folderSyncStateListener = FolderSyncStateListener(workspaceId: workspaceId);
    _folderSyncStateListener!.start(
      didReceiveSyncState: (syncState) {
        if (!isClosed) {
          add(WorkspaceEventUpdateFolderSyncState(syncState: syncState));
        }
      },
    );
    Log.info('[UserWorkspaceBloc] 已启动文件夹同步状态监听器: workspaceId=$workspaceId');
  }

  /// 更新文件夹同步状态
  Future<void> _onUpdateFolderSyncState(
    WorkspaceEventUpdateFolderSyncState event,
    Emitter<UserWorkspaceState> emit,
  ) async {
    // 检查新状态是否与旧状态相同，如果相同则跳过更新
    final oldSyncState = state.folderSyncState;
    final newSyncState = event.syncState;
    
    if (oldSyncState != null && 
        oldSyncState.isSyncing == newSyncState.isSyncing && 
        oldSyncState.isFinish == newSyncState.isFinish) {
      // 状态未改变，跳过更新
      return;
    }
    
    emit(state.copyWith(folderSyncState: newSyncState));
    Log.info('[UserWorkspaceBloc] 文件夹同步状态更新: isSyncing=${newSyncState.isSyncing}, isFinish=${newSyncState.isFinish}');
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
