import 'dart:convert';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/features/share_tab/data/repositories/share_with_user_repository.dart';
import 'package:appflowy/features/share_tab/logic/share_section_refresh_notifier.dart';
import 'package:appflowy/features/share_tab/logic/share_tab_event.dart';
import 'package:appflowy/features/share_tab/logic/share_tab_state.dart';
import 'package:appflowy/features/util/extensions.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/clipboard_service.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
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
  final String pageId;

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
    await super.close();
  }

  Future<void> _onInitial(
    ShareTabEventInitialize event,
    Emitter<ShareTabState> emit,
  ) async {
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

    final users = await _getSharedUsers();

    final hasClickedUpgradeToPro =
        await repository.getUpgradeToProButtonClicked(
      // This preference is local UI state only. It must not participate in
      // document authorization, so scope it by the view rather than a current
      // workspace that may be unrelated to the shared document.
      workspaceId: pageId,
    );

    emit(
      state.copyWith(
        currentUser: currentUser,
        shareLink: '',
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

    // Resolve user ids from the search result/snapshot and upsert them through
    // the document API. Do not delegate to the workspace-scoped FFI path.
    FlowyError? inviteError;
    for (final email in event.emails) {
      final user = state.availableUsers.firstWhereOrNull(
            (candidate) =>
                candidate.email.trim().toLowerCase() ==
                email.trim().toLowerCase(),
          ) ??
          state.users.firstWhereOrNull(
            (candidate) =>
                candidate.email.trim().toLowerCase() ==
                email.trim().toLowerCase(),
          );
      final memberUserId = user?.userId;
      if (memberUserId == null || memberUserId.isEmpty) {
        inviteError = FlowyError()..msg = '请从搜索结果选择要共享的用户';
        break;
      }
      final success = await _addCollaborator(
        objectId: pageId,
        memberUserId: memberUserId,
        permissionId: event.accessLevel.permissionId,
      );
      if (!success) {
        inviteError = FlowyError()..msg = '添加协作用户失败';
        break;
      }
    }

    // 无论邀请是否成功，都刷新共享用户列表（已有成员的权限可能已更新）
    final users = await _getSharedUsers();
    emit(
      state.copyWith(
        shareResult: inviteError != null
            ? FlowyFailure(inviteError)
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

    FlowyError? removeError;
    for (final email in event.emails) {
      final user = state.users.firstWhereOrNull(
        (candidate) =>
            candidate.email.trim().toLowerCase() == email.trim().toLowerCase(),
      );
      final memberUserId = user?.userId;
      if (memberUserId == null || memberUserId.isEmpty) {
        removeError = FlowyError()..msg = '无法解析文档成员';
        break;
      }
      final (success, message) = await _removeCollabMember(
        objectId: pageId,
        memberUserId: memberUserId,
      );
      if (!success) {
        removeError = FlowyError()..msg = message;
        break;
      }
    }
    final users = await _getSharedUsers();
    emit(
      state.copyWith(
        isLoading: false,
        removeResult: removeError == null
            ? FlowySuccess(null)
            : FlowyFailure(removeError),
        users: users,
      ),
    );
    if (removeError == null) {
      ShareSectionRefreshNotifier.notify();
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
    final shareLink = await _createShareLinkInvite();

    if (shareLink == null) {
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
        plainText: shareLink,
      ),
    );

    emit(
      state.copyWith(
        linkCopied: true,
        shareLink: shareLink,
        errorMessage: '',
      ),
    );
  }

  /// 调用后端API创建邀请链接记录。
  ///
  /// Returns the opaque, server-generated link only after it has been stored.
  /// A client must not synthesize a permission-bearing link locally.
  Future<String?> _createShareLinkInvite() async {
    try {
      // 获取当前用户信息
      final userResult = await UserBackendService.getCurrentUserProfile();
      final userProfile = userResult.fold(
        (user) => user,
        (error) => null,
      );

      if (userProfile == null) {
        Log.warn('[ShareTabBloc] 获取用户信息失败');
        return null;
      }

      // 获取 auth token
      final authToken = userProfile.token;
      if (authToken.isEmpty) {
        Log.warn('[ShareTabBloc] Auth token 为空');
        return null;
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
        return null;
      }

      // 获取 base URL
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;

      if (baseUrl.isEmpty) {
        Log.warn('[ShareTabBloc] Base URL 为空');
        return null;
      }

      // The link is owned by the document. Never place the caller's current
      // workspace in the request or in the token-bearing URL.
      final uri = Uri.parse(baseUrl).replace(
        path: '/api/document-shares/$pageId/link',
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
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final data = body['data'] as Map<String, dynamic>?;
        final shareRoute = data?['url'] as String?;
        if (shareRoute == null || shareRoute.isEmpty) {
          Log.error('[ShareTabBloc] 文档分享服务未返回链接');
          return null;
        }

        // The API deliberately returns only a route. Always join it to the
        // public Web domain configured by this client, never the API origin or
        // APPFLOWY_WEB_URL from a server that may be running on localhost.
        final routeUri = Uri.tryParse(shareRoute);
        final configuredWebDomain =
            cloudEnv.appflowyCloudConfig.base_web_domain;
        final webBase = Uri.tryParse(
          configuredWebDomain.contains('://')
              ? configuredWebDomain
              : 'https://$configuredWebDomain',
        );
        if (routeUri == null || routeUri.path != '/share' || webBase == null) {
          Log.error('[ShareTabBloc] 文档分享服务返回了无效链接');
          return null;
        }
        final link = webBase
            .replace(path: routeUri.path, query: routeUri.query)
            .toString();
        Log.info('[ShareTabBloc] 创建文档分享链接成功');

        _refreshSharedUsers();
        ShareSectionRefreshNotifier.notify();
        return link;
      } else {
        Log.warn('[ShareTabBloc] 创建邀请链接失败: HTTP ${response.statusCode}');
        return null;
      }
    } catch (e, stackTrace) {
      Log.error('[ShareTabBloc] 创建邀请链接时出错: $e', stackTrace);
      return null;
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

    // A document share must never promote someone into the current workspace.
    // The server owns document membership; callers should invite the user via
    // the document endpoint instead.
    emit(
      state.copyWith(
        errorMessage: '文档共享不会修改工作区成员资格',
        turnIntoMemberResult: FlowyFailure(
          FlowyError()..msg = '文档共享不会修改工作区成员资格',
        ),
      ),
    );
  }

  Future<SharedUsers> _getSharedUsers() async {
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;

      if (baseUrl.isEmpty) {
        Log.error('Base URL is empty');
        return <SharedUser>[];
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
        return <SharedUser>[];
      }

      final rawToken = userProfile.token;
      if (rawToken.isEmpty) {
        Log.error('Auth token is empty');
        return <SharedUser>[];
      }

      // 提取 access_token（可能是 JSON 格式）
      final accessToken = _extractAccessToken(rawToken);
      if (accessToken == null || accessToken.isEmpty) {
        Log.error('Failed to extract access_token from token');
        return <SharedUser>[];
      }

      // The snapshot is keyed only by view id; the server resolves ownership.
      final uri = Uri.parse(baseUrl).replace(
        path: '/api/document-shares/$pageId',
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
            return <SharedUser>[];
          }

          // The document endpoint returns one authoritative snapshot. Its
          // member list is intentionally not sourced from FFI/SQLite.
          final snapshot = responseBody['data'] as Map<String, dynamic>?;
          final data = snapshot?['members'] as List<dynamic>?;
          if (data == null) {
            Log.error('Document sharing snapshot has no members list');
            return <SharedUser>[];
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

            // Ownership comes from the server snapshot. Never infer it from
            // the current user, a workspace role, or a failed identity match.
            final role = memberMap['is_owner'] == true
                ? ShareRole.owner
                : ShareRole.member;

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

          return users;
        } catch (e, stackTrace) {
          Log.error('Failed to parse response: $e', e, stackTrace);
          return <SharedUser>[];
        }
      } else {
        Log.error('Failed to get collab members: HTTP ${response.statusCode}');
        return <SharedUser>[];
      }
    } catch (e, stackTrace) {
      Log.error('Exception in _getSharedUsers: $e', e, stackTrace);
      return <SharedUser>[];
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
        // This event is dispatched only from a fresh document snapshot. Local
        // FFI caches are intentionally not merged into authorization data.
        users: event.users,
      ),
    );
  }

  Future<void> _onUpgradeToProClicked(
    ShareTabEventUpgradeToProClicked event,
    Emitter<ShareTabState> emit,
  ) async {
    await repository.setUpgradeToProButtonClicked(
      workspaceId: pageId,
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
      objectId: pageId,
      memberUserId: memberUserId,
      permissionId: event.accessLevel.permissionId,
    );

    if (success) {
      // Upsert is atomic on the document endpoint: never create a read-only
      // member first and then PATCH it, which used to leave half-written grants.
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
      {required String objectId,
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

      // Document membership is keyed by object/view id only.
      final uri = Uri.parse(baseUrl).replace(
        path: '/api/document-shares/$objectId/members/$memberUserId',
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

      // PATCH the document aggregate, never a caller-selected workspace.
      final uri = Uri.parse(baseUrl).replace(
        path: '/api/document-shares/$objectId/members/$memberUserId',
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

  Future<void> _onUpdateShareLinkPermission(
    ShareTabEventUpdateShareLinkPermission event,
    Emitter<ShareTabState> emit,
  ) async {
    // The next copy action rotates/updates the server-side opaque link. Do not
    // locally rewrite a URL with forgeable workspace or permission fields.
    emit(
      state.copyWith(
        selectedPermissionId: event.permissionId,
        shareLink: '',
      ),
    );
  }

  /// 通过 HTTP DELETE API 移除协作成员
  Future<(bool, String)> _removeCollabMember({
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
        path: '/api/document-shares/$objectId/members/$memberUserId',
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
