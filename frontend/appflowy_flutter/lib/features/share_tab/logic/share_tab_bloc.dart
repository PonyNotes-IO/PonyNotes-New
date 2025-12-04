import 'dart:convert';

import 'package:appflowy/core/notification/folder_notification.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/features/share_tab/data/repositories/share_with_user_repository.dart';
import 'package:appflowy/features/share_tab/logic/share_tab_event.dart';
import 'package:appflowy/features/share_tab/logic/share_tab_state.dart';
import 'package:appflowy/features/util/extensions.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/clipboard_service.dart';
import 'package:appflowy/plugins/shared/share/constants.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:bloc/bloc.dart';
import 'package:http/http.dart' as http;

export 'share_tab_event.dart';
export 'share_tab_state.dart';

class ShareTabBloc extends Bloc<ShareTabEvent, ShareTabState> {
  ShareTabBloc({
    required this.repository,
    required this.pageId,
    required this.workspaceId,
  }) : super(ShareTabState.initial()) {
    on<ShareTabEventInitialize>(_onInitial);
    on<ShareTabEventLoadSharedUsers>(_onGetSharedUsers);
    on<ShareTabEventInviteUsers>(_onShare);
    on<ShareTabEventRemoveUsers>(_onRemove);
    on<ShareTabEventUpdateUserAccessLevel>(_onUpdateAccessLevel);
    on<ShareTabEventUpdateGeneralAccessLevel>(_onUpdateGeneralAccess);
    on<ShareTabEventCopyShareLink>(_onCopyLink);
    on<ShareTabEventSearchAvailableUsers>(_onSearchAvailableUsers);
    on<ShareTabEventConvertToMember>(_onTurnIntoMember);
    on<ShareTabEventClearState>(_onClearState);
    on<ShareTabEventUpdateSharedUsers>(_onUpdateSharedUsers);
    on<ShareTabEventUpgradeToProClicked>(_onUpgradeToProClicked);
    on<ShareTabEventAddCollaborator>(_onAddCollaborator);
  }

  final ShareWithUserRepository repository;
  final String workspaceId;
  final String pageId;

  // Used to listen for shared view updates.
  FolderNotificationListener? _folderNotificationListener;

  @override
  Future<void> close() async {
      await _folderNotificationListener?.stop();
    await super.close();
  }

  Future<void> _onInitial(
    ShareTabEventInitialize event,
    Emitter<ShareTabState> emit,
  ) async {
    if (!FeatureFlag.sharedSection.isOn) {
      emit(
        state.copyWith(
          errorMessage: 'Sharing is currently disabled.',
          users: [],
          isLoading: false,
        ),
      );
      return;
    }

    _initFolderNotificationListener();

    final result = await repository.getCurrentUserProfile();
    final currentUser = result.fold(
      (user) => user,
      (error) => null,
    );

    final sectionTypeResult = await repository.getCurrentPageSectionType(
      pageId: pageId,
    );
    final sectionType = sectionTypeResult.fold(
      (type) => type,
      (error) => SharedSectionType.unknown,
    );

    final shareLink = ShareConstants.buildShareUrl(
      workspaceId: workspaceId,
      viewId: pageId,
    );

    final users = await _getSharedUsers();

    final hasClickedUpgradeToPro =
        await repository.getUpgradeToProButtonClicked(
      workspaceId: workspaceId,
    );

    emit(
      state.copyWith(
        currentUser: currentUser,
        shareLink: shareLink,
        users: users,
        sectionType: sectionType,
        hasClickedUpgradeToPro: hasClickedUpgradeToPro,
      ),
    );
  }

  Future<void> _onGetSharedUsers(
    ShareTabEventLoadSharedUsers event,
    Emitter<ShareTabState> emit,
  ) async {
    if (!FeatureFlag.sharedSection.isOn) {
      return;
    }

    emit(
      state.copyWith(
        errorMessage: '',
      ),
    );

    final result = await repository.getSharedUsersInPage(
      pageId: pageId,
    );

    result.fold(
      (users) => emit(
        state.copyWith(
          users: users,
          initialResult: FlowySuccess(null),
        ),
      ),
      (error) => emit(
        state.copyWith(
          errorMessage: error.msg,
          initialResult: FlowyFailure(error),
        ),
      ),
    );
  }

  Future<void> _onShare(
    ShareTabEventInviteUsers event,
    Emitter<ShareTabState> emit,
  ) async {
    emit(
      state.copyWith(
        errorMessage: '',
      ),
    );

    final result = await repository.sharePageWithUser(
      pageId: pageId,
      accessLevel: event.accessLevel,
      emails: event.emails,
    );

    await result.fold(
      (_) async {
        final users = await _getSharedUsers();

        emit(
          state.copyWith(
            shareResult: FlowySuccess(null),
            users: users,
          ),
        );
      },
      (error) async {
        emit(
          state.copyWith(
            errorMessage: error.msg,
            shareResult: FlowyFailure(error),
          ),
        );
      },
    );
  }

  Future<void> _onRemove(
    ShareTabEventRemoveUsers event,
    Emitter<ShareTabState> emit,
  ) async {
    emit(
      state.copyWith(
        errorMessage: '',
      ),
    );

    final result = await repository.removeSharedUserFromPage(
      pageId: pageId,
      emails: event.emails,
    );

    await result.fold(
      (_) async {
        final users = await _getSharedUsers();
        emit(
          state.copyWith(
            removeResult: FlowySuccess(null),
            users: users,
          ),
        );
      },
      (error) async {
        emit(
          state.copyWith(
            isLoading: false,
            removeResult: FlowyFailure(error),
          ),
        );
      },
    );
  }

  Future<void> _onUpdateAccessLevel(
    ShareTabEventUpdateUserAccessLevel event,
    Emitter<ShareTabState> emit,
  ) async {
    emit(
      state.copyWith(),
    );

    final result = await repository.sharePageWithUser(
      pageId: pageId,
      accessLevel: event.accessLevel,
      emails: [event.email],
    );

    await result.fold(
      (_) async {
        final users = await _getSharedUsers();
        emit(
          state.copyWith(
            updateAccessLevelResult: FlowySuccess(null),
            users: users,
          ),
        );
      },
      (error) async {
        emit(
          state.copyWith(
            errorMessage: error.msg,
            isLoading: false,
          ),
        );
      },
    );
  }

  void _onUpdateGeneralAccess(
    ShareTabEventUpdateGeneralAccessLevel event,
    Emitter<ShareTabState> emit,
  ) {
    emit(
      state.copyWith(
        generalAccessRole: event.accessLevel,
      ),
    );
  }

  void _onCopyLink(
    ShareTabEventCopyShareLink event,
    Emitter<ShareTabState> emit,
  ) {
    getIt<ClipboardService>().setData(
      ClipboardServiceData(
        plainText: event.link,
      ),
    );

    emit(
      state.copyWith(
        linkCopied: true,
      ),
    );
  }

  Future<void> _onSearchAvailableUsers(
    ShareTabEventSearchAvailableUsers event,
    Emitter<ShareTabState> emit,
  ) async {
    emit(
      state.copyWith(
        errorMessage: '',
      ),
    );

    // If query is empty, return empty list
    if (event.query.trim().isEmpty) {
      emit(
        state.copyWith(
          availableUsers: [],
        ),
      );
      return;
    }

    // Use the new search API
    final result = await repository.searchUsers(
      query: event.query.trim(),
      pageNo: 1,
    );

    result.fold(
      (users) {
        emit(
          state.copyWith(
            availableUsers: users,
          ),
        );
      },
      (error) => emit(
        state.copyWith(
          errorMessage: error.msg,
          availableUsers: [],
        ),
      ),
    );
  }

  Future<void> _onTurnIntoMember(
    ShareTabEventConvertToMember event,
    Emitter<ShareTabState> emit,
  ) async {
    emit(
      state.copyWith(
        errorMessage: '',
      ),
    );

    final result = await repository.changeRole(
      workspaceId: workspaceId,
      email: event.email,
      role: ShareRole.member,
    );

    await result.fold(
      (_) async {
        final users = await _getSharedUsers();
        emit(
          state.copyWith(
            turnIntoMemberResult: FlowySuccess(null),
            users: users,
          ),
        );
      },
      (error) async {
        emit(
          state.copyWith(
            errorMessage: error.msg,
            turnIntoMemberResult: FlowyFailure(error),
          ),
        );
      },
    );
  }

  Future<SharedUsers> _getSharedUsers() async {
    final shareResult = await repository.getSharedUsersInPage(
      pageId: pageId,
    );
    return shareResult.fold(
      (users) => users,
      (error) => state.users,
    );
  }

  void _onClearState(
    ShareTabEventClearState event,
    Emitter<ShareTabState> emit,
  ) {
    emit(
      state.copyWith(
        errorMessage: '',
      ),
    );
  }

  void _onUpdateSharedUsers(
    ShareTabEventUpdateSharedUsers event,
    Emitter<ShareTabState> emit,
  ) {
    emit(
      state.copyWith(
        users: event.users,
      ),
    );
  }

  Future<void> _onUpgradeToProClicked(
    ShareTabEventUpgradeToProClicked event,
    Emitter<ShareTabState> emit,
  ) async {
    await repository.setUpgradeToProButtonClicked(
      workspaceId: workspaceId,
    );
    emit(
      state.copyWith(
        hasClickedUpgradeToPro: true,
      ),
    );
  }

  Future<void> _onAddCollaborator(
    ShareTabEventAddCollaborator event,
    Emitter<ShareTabState> emit,
  ) async {
    emit(
      state.copyWith(
        errorMessage: '',
        addCollaboratorResult: null,
      ),
    );

    // 如果用户没有 userId，先尝试通过 email 查找
    String? memberUserId = event.user.userId;

    if (memberUserId == null || memberUserId.isEmpty) {
      // 尝试通过 email 查找用户 ID
      memberUserId = await _getUserIdByEmail(event.user.email);
      if (memberUserId == null || memberUserId.isEmpty) {
        emit(
          state.copyWith(
            errorMessage: '无法获取用户ID，请确保用户已注册',
            addCollaboratorResult: FlowyFailure(
              FlowyError()
                ..msg = '无法获取用户ID，请确保用户已注册',
            ),
          ),
        );
        return;
      }
    }

    // 调用协作接口添加成员
    final success = await _addCollaborator(
      workspaceId: workspaceId,
      objectId: pageId,
      memberUserId: memberUserId,
    );

    if (success) {
      // 刷新共享用户列表
      final users = await _getSharedUsers();
      emit(
        state.copyWith(
          users: users,
          addCollaboratorResult: FlowySuccess(null),
        ),
      );
    } else {
      emit(
        state.copyWith(
          errorMessage: '添加协作用户失败',
          addCollaboratorResult: FlowyFailure(
            FlowyError()
              ..msg = '添加协作用户失败',
          ),
        ),
      );
    }
  }

  /// 通过邮箱查找用户 ID
  Future<String?> _getUserIdByEmail(String email) async {
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;

      if (baseUrl.isEmpty) {
        Log.error('Base URL is empty');
        return null;
      }

      final userResult = await UserBackendService.getCurrentUserProfile();
      final userProfile = userResult.fold(
        (user) => user,
        (error) {
          Log.error('Failed to get user profile: $error');
          return null;
        },
      );

      if (userProfile == null) {
        Log.error('User profile is null');
        return null;
      }

      final token = userProfile.token;
      if (token.isEmpty) {
        Log.error('Auth token is empty');
        return null;
      }

      // 搜索用户接口可能返回用户 ID
      final uri = Uri.parse(baseUrl).replace(
        path: '/api/user/search',
        queryParameters: {'q': email},
      );

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Request timeout');
        },
      );

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
        final code = jsonData['code'] as int?;
        if (code == 0) {
          final data = jsonData['data'] as List<dynamic>?;
          if (data != null && data.isNotEmpty) {
            final userMap = data.first as Map<String, dynamic>;
            // 尝试多种可能的字段名
            final userId = (userMap['id'] ??
                    userMap['user_id'] ??
                    userMap['userId'] ??
                    userMap['member_user_id'] ??
                    '')
                .toString();
            return userId.isNotEmpty ? userId : null;
          }
        }
      }
    } catch (e, stackTrace) {
      Log.error('Failed to get user ID by email: $e', e, stackTrace);
    }
    return null;
  }

  /// 调用协作接口添加成员
  Future<bool> _addCollaborator({
    required String workspaceId,
    required String objectId,
    required String memberUserId,
  }) async {
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;

      if (baseUrl.isEmpty) {
        Log.error('Base URL is empty');
        return false;
      }

      final userResult = await UserBackendService.getCurrentUserProfile();
      final userProfile = userResult.fold(
        (user) => user,
        (error) {
          Log.error('Failed to get user profile: $error');
          return null;
        },
      );

      if (userProfile == null) {
        Log.error('User profile is null');
        return false;
      }

      final token = userProfile.token;
      if (token.isEmpty) {
        Log.error('Auth token is empty');
        return false;
      }

      // 构建 API URL: /api/{workspace_id}/collab/{object_id}/members/{member_user_id}
      final uri = Uri.parse(baseUrl).replace(
        path: '/api/$workspaceId/collab/$objectId/members/$memberUserId',
      );

      Log.info('Adding collaborator: $uri');

      // 发送 POST 请求
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Request timeout');
        },
      );

      Log.info('Add collaborator response: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else {
        final errorMessage = '添加协作用户失败: HTTP ${response.statusCode}';
        Log.error(errorMessage);
        return false;
      }
    } catch (e, stackTrace) {
      Log.error('Exception in _addCollaborator: $e', e, stackTrace);
      return false;
    }
  }

  void _initFolderNotificationListener() {
    _folderNotificationListener = FolderNotificationListener(
      objectId: pageId,
      handler: (notification, result) {
        if (notification == FolderNotification.DidUpdateSharedUsers) {
          final response = result.fold(
            (payload) {
              final repeatedSharedUsers =
                  RepeatedSharedUserPB.fromBuffer(payload);
              return repeatedSharedUsers;
            },
            (error) => null,
          );
          Log.debug('update shared users: $response');
          if (response != null) {
            add(
              ShareTabEvent.updateSharedUsers(
                users: response.sharedUsers.reversed.toList(),
              ),
            );
          }
        }
      },
    );
  }
}
