import 'dart:convert';

import 'package:appflowy/core/notification/folder_notification.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/features/share_tab/data/repositories/share_with_user_repository.dart';
import 'package:appflowy/features/share_tab/logic/share_section_refresh_notifier.dart';
import 'package:appflowy/features/share_tab/logic/share_tab_event.dart';
import 'package:appflowy/features/share_tab/logic/share_tab_state.dart';
import 'package:appflowy/features/util/extensions.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/clipboard_service.dart';
import 'package:appflowy/plugins/shared/share/constants.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:bloc/bloc.dart';
import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
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
    on<ShareTabEventUpdateGeneralAccessLevel>(_onUpdateGeneralAccess);
    on<ShareTabEventCopyShareLink>(_onCopyLink);
    on<ShareTabEventSearchAvailableUsers>(_onSearchAvailableUsers);
    on<ShareTabEventConvertToMember>(_onTurnIntoMember);
    on<ShareTabEventClearState>(_onClearState);
    on<ShareTabEventUpdateSharedUsers>(_onUpdateSharedUsers);
    on<ShareTabEventUpgradeToProClicked>(_onUpgradeToProClicked);
    on<ShareTabEventAddCollaborator>(_onAddCollaborator);
    on<ShareTabEventUpdateMemberPermission>(_onUpdateMemberPermission);
    on<ShareTabEventRemoveCollabMember>(_onRemoveCollabMember);
    on<ShareTabEventUpdateShareLinkPermission>(_onUpdateShareLinkPermission);
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

    // 获取视图布局类型，用于生成分享链接
    int? viewLayout;
    try {
      final viewResult = await ViewBackendService.getView(pageId);
      viewResult.fold(
        (view) => viewLayout = view.layout.value,
        (error) => viewLayout = null,
      );
    } catch (_) {}

    final shareLink = ShareConstants.buildShareUrl(
      workspaceId: workspaceId,
      viewId: pageId,
      permissionId: state.selectedPermissionId,
      layout: viewLayout,
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

    // 检查哪些用户已经是成员，避免覆盖已有权限
    final existingEmails =
        state.users.map((u) => u.email.toLowerCase()).toSet();
    final newEmails = event.emails
        .where((e) => !existingEmails.contains(e.toLowerCase()))
        .toList();
    final existingMemberEmails = event.emails
        .where((e) => existingEmails.contains(e.toLowerCase()))
        .toList();

    // 对已是成员的用户，更新其权限（如果新权限更高）
    for (final email in existingMemberEmails) {
      final existingUser = state.users.firstWhere(
        (u) => u.email.toLowerCase() == email.toLowerCase(),
        orElse: () => state.users.first,
      );
      // 只有当新权限与当前权限不同时才更新
      if (existingUser.accessLevel != event.accessLevel) {
        final (success, errorMsg) = await _updateMemberPermission(
          workspaceId: workspaceId,
          objectId: pageId,
          memberUserId: existingUser.userId ?? '',
          permissionId: event.accessLevel.permissionId,
        );
        if (!success) {
          Log.warn('[ShareTabBloc] 更新已有成员权限失败: $email, $errorMsg');
        }
      }
    }

    // 对新用户，调用正常的邀请流程
    FlowyError? inviteError;
    if (newEmails.isNotEmpty) {
      final result = await repository.sharePageWithUser(
        pageId: pageId,
        accessLevel: event.accessLevel,
        emails: newEmails,
      );

      result.fold(
        (_) {},
        (error) {
          inviteError = error;
        },
      );
    }

    // 无论邀请是否成功，都刷新共享用户列表（已有成员的权限可能已更新）
    final users = await _getSharedUsers();
    emit(
      state.copyWith(
        shareResult: inviteError != null
            ? FlowyFailure(inviteError!)
            : FlowySuccess(null),
        errorMessage: inviteError?.msg ?? '',
        users: users,
      ),
    );
    // 通知侧边栏和 PageAccessLevelBloc 刷新（已有成员权限可能已变更）
    ShareSectionRefreshNotifier.notify();
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
        // 通知侧边栏和 PageAccessLevelBloc 刷新
        ShareSectionRefreshNotifier.notify();
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
  ) async {
    // 在复制链接之前，先调用API创建邀请记录，这样"共享"菜单才能显示这个邀请。
    //
    // 【健壮性修复 2026-07-19】此处原先忽略创建结果，无论成功与否都把链接复制给用户，
    // UI 侧也无条件弹出"已复制"提示。一旦创建失败（例如鉴权失效），用户拿到的是一个
    // **服务端没有邀请记录的死链**——接收方打开只会一直转圈然后失败，而分享者毫不知情。
    //
    // 真实事故：2026-07-19 gotrue 故障期间 access_token 无法刷新，
    // `POST /api/workspace/{ws}/collab/{oid}/invite-link` 全部返回 401，
    // 分享记录未写入，但链接照常复制给了用户（链接是客户端本地拼接的，不依赖接口）。
    // 详见 devops-docs/2026-07-19-全线登录失败故障复盘-gotrue端口未发布.md
    //
    // 改为：创建失败时**不复制链接**并回传错误，由 UI 明确提示用户重试。
    final created = await _createShareLinkInvite();

    if (!created) {
      emit(
        state.copyWith(
          linkCopied: false,
          errorMessage: LocaleKeys.shareTab_createShareLinkFailed.tr(),
        ),
      );
      return;
    }

    getIt<ClipboardService>().setData(
      ClipboardServiceData(
        plainText: event.link,
      ),
    );

    emit(
      state.copyWith(
        linkCopied: true,
        errorMessage: '',
      ),
    );
  }

  /// 调用后端API创建邀请链接记录。
  ///
  /// 返回 true 表示服务端已成功写入邀请记录（链接可被接收方正常打开）；
  /// 返回 false 表示未写入——此时**不应把链接交给用户**，否则就是一个死链。
  Future<bool> _createShareLinkInvite() async {
    try {
      // 获取当前用户信息
      final userResult = await UserBackendService.getCurrentUserProfile();
      final userProfile = userResult.fold(
        (user) => user,
        (error) => null,
      );

      if (userProfile == null) {
        Log.warn('[ShareTabBloc] 获取用户信息失败');
        return false;
      }

      // 获取 auth token
      final authToken = userProfile.token;
      if (authToken.isEmpty) {
        Log.warn('[ShareTabBloc] Auth token 为空');
        return false;
      }

      // 提取 access token
      String? accessToken;
      try {
        final tokenData = jsonDecode(authToken);
        if (tokenData is Map<String, dynamic>) {
          accessToken = tokenData['access_token'] as String?;
        }
      } catch (_) {
        accessToken = authToken;
      }

      if (accessToken == null) {
        Log.warn('[ShareTabBloc] access_token 为空');
        return false;
      }

      // 获取 base URL
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;

      if (baseUrl.isEmpty) {
        Log.warn('[ShareTabBloc] Base URL 为空');
        return false;
      }

      // 构建 API URL
      final uri = Uri.parse(baseUrl).replace(
        path: '/api/workspace/$workspaceId/collab/$pageId/invite-link',
      );

      // 发送 POST 请求
      final response = await http
          .post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({
          'permission_id': state.selectedPermissionId,
        }),
      )
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('请求超时');
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        Log.info('[ShareTabBloc] 创建邀请链接成功');

        _refreshSharedUsers();
        ShareSectionRefreshNotifier.notify();
        return true;
      } else {
        Log.warn('[ShareTabBloc] 创建邀请链接失败: HTTP ${response.statusCode}');
        return false;
      }
    } catch (e, stackTrace) {
      Log.error('[ShareTabBloc] 创建邀请链接时出错: $e', stackTrace);
      return false;
    }
  }

  /// 刷新共享用户列表
  Future<void> _refreshSharedUsers() async {
    try {
      final users = await _getSharedUsers();
      add(
        ShareTabEvent.updateSharedUsers(users: users),
      );
    } catch (e) {
      Log.error('[ShareTabBloc] 刷新共享用户列表失败: $e');
    }
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
        return _getSharedUsersFromFfiFallback('base URL is empty');
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
        return _getSharedUsersFromFfiFallback('user profile is null');
      }

      final rawToken = userProfile.token;
      if (rawToken.isEmpty) {
        Log.error('Auth token is empty');
        return _getSharedUsersFromFfiFallback('auth token is empty');
      }

      // 提取 access_token（可能是 JSON 格式）
      final accessToken = _extractAccessToken(rawToken);
      if (accessToken == null || accessToken.isEmpty) {
        Log.error('Failed to extract access_token from token');
        return _getSharedUsersFromFfiFallback('access token is empty');
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
            return _getSharedUsersFromFfiFallback('HTTP API code=$code');
          }

          // 解析 data 数组
          final data = responseBody['data'] as List<dynamic>?;
          if (data == null) {
            Log.error('Response data is null');
            return _getSharedUsersFromFfiFallback('HTTP data is null');
          }

          // 将 API 返回的成员列表转换为 SharedUsers
          final users = data.map((member) {
            final memberMap = member as Map<String, dynamic>;
            final uuid = (memberMap['uuid'] as String?) ??
                (memberMap['user_id'] as String?);
            final numericUid = memberMap['uid']?.toString();
            final email = memberMap['email'] as String? ?? '';
            final name = memberMap['name'] as String? ?? email;
            final phone = memberMap['phone'] as String?;
            final avatarUrl = memberMap['avatar_url'] as String?;

            // 调试：打印原始数据，确认后端返回的权限字段名和值
            Log.info('[ShareTabBloc] member raw data: $memberMap');

            // 兼容多种可能的字段名：permission_id / permission / access_level / role
            // 同时兼容 int 和 String 类型（后端可能返回 "1" 而非 1）
            int? _parseInt(dynamic v) {
              if (v is int) return v;
              if (v is String) return int.tryParse(v);
              return null;
            }

            final permissionId = _parseInt(memberMap['permission_id']) ??
                _parseInt(memberMap['permission']) ??
                _parseInt(memberMap['access_level']) ??
                _parseInt(memberMap['role']) ??
                1;
            Log.info(
                '[ShareTabBloc] parsed permissionId=$permissionId for email=$email');

            // 将 permission_id 转换为 ShareAccessLevel
            // 后端定义：1=readOnly, 2=readAndComment, 3=readAndWrite, 4=fullAccess
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

            // permission_id 只表示权限级别，不代表拥有者角色
            // 拥有者由 buildUsersListWithOwner 根据当前登录用户来判定
            const role = ShareRole.member;

            return SharedUser(
              email: email,
              name: name,
              role: role,
              accessLevel: accessLevel,
              avatarUrl: avatarUrl?.isNotEmpty == true ? avatarUrl : null,
              userId: uuid,
              uid: numericUid,
              phone: phone?.isNotEmpty == true ? phone : null,
            );
          }).toList();

          Log.info('Successfully fetched ${users.length} collab members');

          if (users.isEmpty) {
            return _getSharedUsersFromFfiFallback(
              'HTTP returned empty collab members',
            );
          }

          return users;
        } catch (e, stackTrace) {
          Log.error('Failed to parse response: $e', e, stackTrace);
          return _getSharedUsersFromFfiFallback('parse HTTP response failed');
        }
      } else {
        Log.error('Failed to get collab members: HTTP ${response.statusCode}');
        return _getSharedUsersFromFfiFallback(
          'HTTP status ${response.statusCode}',
        );
      }
    } catch (e, stackTrace) {
      Log.error('Exception in _getSharedUsers: $e', e, stackTrace);
      return _getSharedUsersFromFfiFallback('HTTP request exception');
    }
  }

  Future<SharedUsers> _getSharedUsersFromFfiFallback(String reason) async {
    Log.warn(
      '[ShareTabBloc] Falling back to FFI shared users. reason=$reason, '
      'pageId=$pageId',
    );

    final result = await repository.getSharedUsersInPage(pageId: pageId);
    return result.fold(
      (users) {
        Log.info(
          '[ShareTabBloc] FFI shared users fallback returned '
          '${users.length} users',
        );
        return users.isNotEmpty ? users : state.users;
      },
      (error) {
        Log.error('[ShareTabBloc] FFI shared users fallback failed: $error');
        return state.users;
      },
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
    // FFI 通知下发的 SharedUserPB 不含 user_id / uid / phone 字段，
    // 直接覆盖会导致后续权限变更因缺少这些标识而失败（尤其手机号注册用户 email 为空）。
    // 这里将 FFI 数据与现有数据（通常来自 HTTP，带完整 uid/phone/userId）合并：
    // 按 userId → uid → phone → email 多键匹配，并回填 userId / uid / phone。
    final existingUsers = state.users;
    final mergedUsers = event.users.map((ffiUser) {
      final existing = existingUsers.firstWhereOrNull(
        (u) =>
            (ffiUser.userId?.isNotEmpty == true && u.userId == ffiUser.userId) ||
            (ffiUser.uid?.isNotEmpty == true && u.uid == ffiUser.uid) ||
            (ffiUser.phone?.isNotEmpty == true && u.phone == ffiUser.phone) ||
            (ffiUser.email.trim().isNotEmpty &&
                u.email.trim().toLowerCase() ==
                    ffiUser.email.trim().toLowerCase()),
      );
      if (existing == null) {
        return ffiUser;
      }
      // FFI 自身字段优先，缺失时用现有列表回填
      return ffiUser.copyWith(
        userId:
            ffiUser.userId?.isNotEmpty == true ? ffiUser.userId : existing.userId,
        uid: ffiUser.uid?.isNotEmpty == true ? ffiUser.uid : existing.uid,
        phone: ffiUser.phone?.isNotEmpty == true ? ffiUser.phone : existing.phone,
      );
    }).toList();

    emit(
      state.copyWith(
        users: mergedUsers,
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

  /// 解析成员的 member_user_id（uuid）。
  ///
  /// FFI 通知下发的 SharedUserPB 不包含 user_id 字段，导致 event.user.userId 为空，
  /// 进而权限/移除接口因缺少 member_user_id 在本地直接中断（后端根本收不到请求）。
  /// 这里在 userId 为空时，通过 HTTP 成员接口按 email 回退解析真正的 uuid。
  Future<String?> _resolveMemberUserId(SharedUser user) async {
    final existing = user.userId;
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    // 拉取 HTTP 成员列表（带完整 uid/phone/userId），按 uid → phone → email 回退匹配。
    // 手机号注册用户 email 为空，必须支持按 uid/phone 匹配。
    final httpUsers = await _getSharedUsers();

    // 1. 按 uid 匹配
    final uid = user.uid;
    if (uid != null && uid.isNotEmpty) {
      for (final u in httpUsers) {
        if (u.uid == uid && u.userId?.isNotEmpty == true) {
          return u.userId;
        }
      }
    }

    // 2. 按 phone 匹配
    final phone = user.phone;
    if (phone != null && phone.isNotEmpty) {
      for (final u in httpUsers) {
        if (u.phone == phone && u.userId?.isNotEmpty == true) {
          return u.userId;
        }
      }
    }

    // 3. 按 email 匹配
    final email = user.email.trim().toLowerCase();
    if (email.isNotEmpty) {
      for (final u in httpUsers) {
        if (u.email.trim().toLowerCase() == email &&
            u.userId?.isNotEmpty == true) {
          return u.userId;
        }
      }
    }

    return null;
  }

  Future<void> _onUpdateMemberPermission(
    ShareTabEventUpdateMemberPermission event,
    Emitter<ShareTabState> emit,
  ) async {
    Log.info('[ShareTabBloc] _onUpdateMemberPermission called: '
        'user=${event.user.email}, userId=${event.user.userId}, '
        'newLevel=${event.accessLevel}');

    emit(
      state.copyWith(
        errorMessage: '',
        updateAccessLevelResult: null,
      ),
    );

    // 确保用户有 userId（FFI 通知下发的 SharedUserPB 不含 user_id，
    // 这里按 email 通过 HTTP 成员接口回退解析，避免本地直接中断导致后端收不到请求）
    String? memberUserId = await _resolveMemberUserId(event.user);
    Log.info('[ShareTabBloc] resolved memberUserId=$memberUserId');
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
      permissionId: event.accessLevel.permissionId,
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
      // 通知侧边栏和 PageAccessLevelBloc 刷新
      ShareSectionRefreshNotifier.notify();
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

  Future<void> _onRemoveCollabMember(
    ShareTabEventRemoveCollabMember event,
    Emitter<ShareTabState> emit,
  ) async {
    emit(
      state.copyWith(
        errorMessage: '',
        removeResult: null,
      ),
    );

    String? memberUserId = event.user.userId;
    if (memberUserId == null || memberUserId.isEmpty) {
      emit(
        state.copyWith(
          errorMessage: '无法获取用户ID',
          removeResult: FlowyFailure(
            FlowyError()..msg = '无法获取用户ID',
          ),
        ),
      );
      return;
    }

    final (success, errorMessage) = await _removeCollabMember(
      workspaceId: workspaceId,
      objectId: pageId,
      memberUserId: memberUserId,
    );

    if (success) {
      final users = await _getSharedUsers();
      emit(
        state.copyWith(
          removeResult: FlowySuccess(null),
          users: users,
        ),
      );
      // 通知侧边栏和 PageAccessLevelBloc 刷新
      ShareSectionRefreshNotifier.notify();
    } else {
      emit(
        state.copyWith(
          errorMessage: errorMessage.isNotEmpty ? errorMessage : '移除成员失败',
          removeResult: FlowyFailure(
            FlowyError()
              ..msg = errorMessage.isNotEmpty ? errorMessage : '移除成员失败',
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

    // 如果用户没有 userId，先提示错误
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

    // 1. 调用协作接口添加成员 (后端默认 ReadOnly)
    final success = await _addCollaborator(
      workspaceId: workspaceId,
      objectId: pageId,
      memberUserId: memberUserId,
      permissionId: event.accessLevel.permissionId,
    );

    if (success) {
      // 2. 如果指定的权限不是 ReadOnly，则更新权限
      if (event.accessLevel != ShareAccessLevel.readOnly) {
        final (updateSuccess, updateError) = await _updateMemberPermission(
          workspaceId: workspaceId,
          objectId: pageId,
          memberUserId: memberUserId,
          permissionId: event.accessLevel.permissionId,
        );

        if (!updateSuccess) {
          Log.error(
              'Failed to update permission after adding collaborator: $updateError');
          // 这里即使更新权限失败，用户其实已经添加成功了（虽然是 ReadOnly），
          // 所以我们还是算成功，但记录日志或提示。
        }
      }

      // 刷新共享用户列表
      final users = await _getSharedUsers();
      emit(
        state.copyWith(
          users: users,
          addCollaboratorResult: FlowySuccess(null),
        ),
      );
      // 通知侧边栏和 PageAccessLevelBloc 刷新
      ShareSectionRefreshNotifier.notify();
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
  Future<bool> _addCollaborator(
      {required String workspaceId,
      required String objectId,
      required String memberUserId,
      required int permissionId}) async {
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

      // 发送 POST 请求，需要包含 permission_id 在 body 中
      final response = await http
          .post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({'permission_id': permissionId}), // 默认只读权限
      )
          .timeout(
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
              if (payload.isEmpty) {
                return null;
              }
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

  Future<void> _onUpdateShareLinkPermission(
    ShareTabEventUpdateShareLinkPermission event,
    Emitter<ShareTabState> emit,
  ) async {
    int? viewLayout;
    try {
      final viewResult = await ViewBackendService.getView(pageId);
      viewResult.fold(
        (view) => viewLayout = view.layout.value,
        (error) => viewLayout = null,
      );
    } catch (_) {}

    final newShareLink = ShareConstants.buildShareUrl(
      workspaceId: workspaceId,
      viewId: pageId,
      permissionId: event.permissionId,
      layout: viewLayout,
    );

    emit(
      state.copyWith(
        selectedPermissionId: event.permissionId,
        shareLink: newShareLink,
      ),
    );
  }

  /// 通过 HTTP DELETE API 移除协作成员
  Future<(bool, String)> _removeCollabMember({
    required String workspaceId,
    required String objectId,
    required String memberUserId,
  }) async {
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;

      if (baseUrl.isEmpty) {
        return (false, '服务器配置错误');
      }

      final userResult = await UserBackendService.getCurrentUserProfile();
      final userProfile = userResult.fold(
        (user) => user,
        (error) => null,
      );

      if (userProfile == null) {
        return (false, '用户未登录');
      }

      final rawToken = userProfile.token;
      if (rawToken.isEmpty) {
        return (false, '认证失败');
      }

      final accessToken = _extractAccessToken(rawToken);
      if (accessToken == null || accessToken.isEmpty) {
        return (false, 'Token 提取失败');
      }

      final uri = Uri.parse(baseUrl).replace(
        path:
            '/api/workspace/$workspaceId/collab/$objectId/members/$memberUserId',
      );

      Log.info('Removing collab member: $uri');

      final response = await http.delete(
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

      Log.info('Remove collab member response: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 204) {
        return (true, '');
      } else {
        final errorMessage =
            '移除成员失败: HTTP ${response.statusCode} ${response.body}';
        Log.error(errorMessage);
        return (false, errorMessage);
      }
    } catch (e, stackTrace) {
      Log.error('Exception in _removeCollabMember: $e', e, stackTrace);
      return (false, '移除成员失败: ${e.toString()}');
    }
  }
}
