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
    on<ShareTabEventUpdateMemberPermission>(_onUpdateMemberPermission);
  }

  final ShareWithUserRepository repository;
  final String workspaceId;
  final String pageId;

  // Used to listen for shared view updates.
  FolderNotificationListener? _folderNotificationListener;

  /// 从 token 字段中提取 access_token
  /// 如果 token 是 JSON 格式，则解析并提取 access_token
  /// 否则直接返回 token
  String? _extractAccessToken(String token) {
    if (token.isEmpty) {
      return null;
    }

    final trimmedToken = token.trim();

    // 检查是否是 JSON 格式（以 { 开头）
    if (trimmedToken.startsWith('{')) {
      try {
        final tokenMap = jsonDecode(trimmedToken) as Map<String, dynamic>;
        final accessToken = tokenMap['access_token'] as String?;
        if (accessToken != null && accessToken.isNotEmpty) {
          Log.info('Extracted access_token from JSON token');
          return accessToken;
        } else {
          Log.error('access_token not found in JSON token');
          return null;
        }
      } catch (e) {
        Log.error('Failed to parse token as JSON: $e');
        return null;
      }
    }

    // 如果不是 JSON，直接返回 token
    return trimmedToken;
  }

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

    // 直接复用 _getSharedUsers 获取分享用户列表
    try {
      final users = await _getSharedUsers();
      emit(
        state.copyWith(
          users: users,
          initialResult: FlowySuccess(null),
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          errorMessage: e.toString(),
          initialResult: FlowyFailure(
            FlowyError()..msg = e.toString(),
          ),
        ),
      );
    }
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
      state.copyWith(
        errorMessage: '',
        updateAccessLevelResult: null,
      ),
    );

    final updated = await _updateWorkspaceMemberRole(
      email: event.email,
      accessLevel: event.accessLevel,
    );

    if (updated) {
      final users = await _getSharedUsers();
      emit(
        state.copyWith(
          updateAccessLevelResult: FlowySuccess(null),
          users: users,
        ),
      );
    } else {
      emit(
        state.copyWith(
          errorMessage: '更新权限失败',
          isLoading: false,
          updateAccessLevelResult: FlowyFailure(
            FlowyError()..msg = '更新权限失败',
          ),
        ),
      );
    }
  }

  /// 调用工作空间成员权限接口：PUT /api/workspace/{workspace_id}/member
  /// 将 accessLevel 映射为 role（Owner/Member），更新成员权限
  Future<bool> _updateWorkspaceMemberRole({
    required String email,
    required ShareAccessLevel accessLevel,
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

      final rawToken = userProfile.token;
      if (rawToken.isEmpty) {
        Log.error('Auth token is empty');
        return false;
      }

      // 提取 access_token（可能是 JSON 格式）
      final accessToken = _extractAccessToken(rawToken);
      if (accessToken == null || accessToken.isEmpty) {
        Log.error('Failed to extract access_token from token');
        return false;
      }

      // accessLevel 映射到 role：fullAccess -> Owner，其它 -> Member
      final role =
          accessLevel == ShareAccessLevel.fullAccess ? 'Owner' : 'Member';

      final uri = Uri.parse(baseUrl).replace(
        path: '/api/workspace/$workspaceId/member',
      );

      Log.info(
          'Updating workspace member role: $uri, email=$email, role=$role');

      final response = await http
          .put(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({
          'email': email,
          'role': role,
        }),
      )
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Request timeout');
        },
      );

      if (response.statusCode == 200) {
        // 尝试解析 code 字段（如果有）
        if (response.body.isNotEmpty) {
          try {
            final body = jsonDecode(response.body) as Map<String, dynamic>;
            final code = body['code'] as int?;
            if (code != null && code != 0) {
              Log.error(
                  'Update member role failed, code: $code, body: ${response.body}');
              return false;
            }
          } catch (_) {
            // 如果不是 JSON，忽略
          }
        }
        return true;
      } else {
        Log.error(
            'Update member role failed: HTTP ${response.statusCode}, body: ${response.body}');
        return false;
      }
    } catch (e, stackTrace) {
      Log.error('Exception in _updateWorkspaceMemberRole: $e', e, stackTrace);
      return false;
    }
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
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;

      if (baseUrl.isEmpty) {
        Log.error('Base URL is empty');
        return state.users;
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
        return state.users;
      }

      final rawToken = userProfile.token;
      if (rawToken.isEmpty) {
        Log.error('Auth token is empty');
        return state.users;
      }

      // 提取 access_token（可能是 JSON 格式）
      final accessToken = _extractAccessToken(rawToken);
      if (accessToken == null || accessToken.isEmpty) {
        Log.error('Failed to extract access_token from token');
        return state.users;
      }

      // 构建 API URL: GET /api/workspace/{workspace_id}/collab/{object_id}/members
      final uri = Uri.parse(baseUrl).replace(
        path: '/api/workspace/$workspaceId/collab/$pageId/members',
      );

      Log.info('Fetching collab members: $uri');

      // 发送 GET 请求
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Request timeout');
        },
      );

      Log.info('Get collab members response: ${response.statusCode}');

      if (response.statusCode == 200) {
        try {
          final responseBody =
              jsonDecode(response.body) as Map<String, dynamic>;

          // 检查 code 字段，0 表示成功
          final code = responseBody['code'] as int?;
          if (code != null && code != 0) {
            Log.error('API returned error code: $code');
            return state.users;
          }

          // 解析 data 数组
          final data = responseBody['data'] as List<dynamic>?;
          if (data == null) {
            Log.error('Response data is null');
            return state.users;
          }

          // 将 API 返回的成员列表转换为 SharedUsers
          final users = data.map((member) {
            final memberMap = member as Map<String, dynamic>;
            final uuid = memberMap['uuid'] as String?;
            final email = memberMap['email'] as String? ?? '';
            final name = memberMap['name'] as String? ?? email;
            final avatarUrl = memberMap['avatar_url'] as String?;
            final permissionId = memberMap['permission_id'] as int? ?? 1;

            // 将 permission_id 转换为 ShareAccessLevel
            // 1=readOnly, 2=readAndComment, 3=readAndWrite, 4=fullAccess
            ShareAccessLevel accessLevel;
            switch (permissionId) {
              case 1:
                accessLevel = ShareAccessLevel.readOnly;
                break;
              case 2:
                accessLevel = ShareAccessLevel.readAndComment;
                break;
              case 3:
                accessLevel = ShareAccessLevel.readAndWrite;
                break;
              case 4:
                accessLevel = ShareAccessLevel.fullAccess;
                break;
              default:
                accessLevel = ShareAccessLevel.readOnly;
            }

            // 根据权限大致判断角色，4 为 Owner/FullAccess
            final role = permissionId == 4 ? ShareRole.owner : ShareRole.member;

            return SharedUser(
              email: email,
              name: name,
              role: role,
              accessLevel: accessLevel,
              avatarUrl: avatarUrl?.isNotEmpty == true ? avatarUrl : null,
              userId: uuid,
            );
          }).toList();

          Log.info('Successfully fetched ${users.length} collab members');

          return users;
        } catch (e, stackTrace) {
          Log.error('Failed to parse response: $e', e, stackTrace);
          return state.users;
        }
      } else {
        Log.error('Failed to get collab members: HTTP ${response.statusCode}');
        return state.users;
      }
    } catch (e, stackTrace) {
      Log.error('Exception in _getSharedUsers: $e', e, stackTrace);
      return state.users;
    }
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

  /// 将 ShareAccessLevel 转换为 permission_id
  /// 根据后端定义：1=readOnly, 2=readAndComment, 3=readAndWrite, 4=fullAccess
  int _accessLevelToPermissionId(ShareAccessLevel accessLevel) {
    switch (accessLevel) {
      case ShareAccessLevel.readOnly:
        return 1;
      case ShareAccessLevel.readAndComment:
        return 2;
      case ShareAccessLevel.readAndWrite:
        return 3;
      case ShareAccessLevel.fullAccess:
        return 4;
    }
  }

  Future<void> _onUpdateMemberPermission(
    ShareTabEventUpdateMemberPermission event,
    Emitter<ShareTabState> emit,
  ) async {
    emit(
      state.copyWith(
        errorMessage: '',
        updateAccessLevelResult: null,
      ),
    );

    // 确保用户有 userId
    String? memberUserId = event.user.userId;
    if (memberUserId == null || memberUserId.isEmpty) {
      emit(
        state.copyWith(
          errorMessage: '无法获取用户ID，请确保用户已注册',
          updateAccessLevelResult: FlowyFailure(
            FlowyError()..msg = '无法获取用户ID，请确保用户已注册',
          ),
        ),
      );
      return;
    }

    // 调用权限更新接口
    final (success, errorMessage) = await _updateMemberPermission(
      workspaceId: workspaceId,
      objectId: pageId,
      memberUserId: memberUserId,
      permissionId: _accessLevelToPermissionId(event.accessLevel),
    );

    if (success) {
      // 刷新共享用户列表
      final users = await _getSharedUsers();
      emit(
        state.copyWith(
          users: users,
          updateAccessLevelResult: FlowySuccess(null),
          errorMessage: '',
        ),
      );
    } else {
      emit(
        state.copyWith(
          errorMessage: errorMessage.isNotEmpty ? errorMessage : '更新权限失败',
          updateAccessLevelResult: FlowyFailure(
            FlowyError()
              ..msg = errorMessage.isNotEmpty ? errorMessage : '更新权限失败',
          ),
        ),
      );
    }
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
      emit(
        state.copyWith(
          errorMessage: '无法获取用户ID，请确保用户已注册',
          addCollaboratorResult: FlowyFailure(
            FlowyError()..msg = '无法获取用户ID，请确保用户已注册',
          ),
        ),
      );
      return;
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
            FlowyError()..msg = '添加协作用户失败',
          ),
        ),
      );
    }
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

      final rawToken = userProfile.token;
      if (rawToken.isEmpty) {
        Log.error('Auth token is empty');
        return false;
      }

      // 提取 access_token（可能是 JSON 格式）
      final accessToken = _extractAccessToken(rawToken);
      if (accessToken == null || accessToken.isEmpty) {
        Log.error('Failed to extract access_token from token');
        return false;
      }

      // 构建 API URL: /api/{workspace_id}/collab/{object_id}/members/{member_user_id}
      final uri = Uri.parse(baseUrl).replace(
        path:
            '/api/workspace/$workspaceId/collab/$objectId/members/$memberUserId',
      );

      Log.info('Adding collaborator: $uri');

      // 发送 POST 请求
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
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

  /// 调用权限变更接口更新成员权限
  /// 返回 (success, errorMessage)
  Future<(bool, String)> _updateMemberPermission({
    required String workspaceId,
    required String objectId,
    required String memberUserId,
    required int permissionId,
  }) async {
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;

      if (baseUrl.isEmpty) {
        Log.error('Base URL is empty');
        return (false, '服务器配置错误');
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
        return (false, '用户未登录');
      }

      final rawToken = userProfile.token;
      if (rawToken.isEmpty) {
        Log.error('Auth token is empty');
        return (false, '认证失败');
      }

      // 提取 access_token（可能是 JSON 格式）
      final accessToken = _extractAccessToken(rawToken);
      if (accessToken == null || accessToken.isEmpty) {
        Log.error('Failed to extract access_token from token');
        return (false, 'Token 提取失败');
      }

      // 构建 API URL: PATCH /api/workspace/{workspace_id}/collab/{object_id}/members/{member_user_id}
      final uri = Uri.parse(baseUrl).replace(
        path:
            '/api/workspace/$workspaceId/collab/$objectId/members/$memberUserId',
      );

      Log.info('Updating member permission: $uri');
      Log.info('Permission ID: $permissionId');

      // 发送 PATCH 请求
      final response = await http
          .patch(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({
          'permission_id': permissionId,
        }),
      )
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Request timeout');
        },
      );

      Log.info('Update member permission response: ${response.statusCode}');
      Log.info('Response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 204) {
        return (true, '');
      } else {
        String errorMessage = '更新权限失败: HTTP ${response.statusCode}';

        // 尝试解析响应体
        if (response.body.isNotEmpty) {
          Log.error('Response body: ${response.body}');

          try {
            // 尝试解析为 JSON
            final errorBody =
                jsonDecode(response.body) as Map<String, dynamic>?;
            if (errorBody != null) {
              final msg = errorBody['message'] ??
                  errorBody['msg'] ??
                  errorBody['error'];
              if (msg != null && msg.toString().isNotEmpty) {
                errorMessage = '更新权限失败: $msg';
              }
            }
          } catch (e) {
            // 如果不是 JSON，尝试直接使用响应体作为错误信息
            final bodyText = response.body.trim();
            if (bodyText.isNotEmpty) {
              if (bodyText.contains('fail to decode token') ||
                  bodyText.contains('Base64 error') ||
                  bodyText.contains('token') ||
                  bodyText.contains('error')) {
                errorMessage = '更新权限失败: $bodyText';
              } else {
                errorMessage =
                    '更新权限失败: HTTP ${response.statusCode} - $bodyText';
              }
            }
          }
        }

        Log.error(errorMessage);
        return (false, errorMessage);
      }
    } catch (e, stackTrace) {
      Log.error('Exception in _updateMemberPermission: $e', e, stackTrace);
      final errorMessage = '更新权限失败: ${e.toString()}';
      return (false, errorMessage);
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
