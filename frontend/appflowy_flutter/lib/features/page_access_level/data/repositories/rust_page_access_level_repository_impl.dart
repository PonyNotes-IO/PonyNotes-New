import 'package:appflowy/features/page_access_level/data/repositories/page_access_level_repository.dart';
import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/features/util/extensions.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/shared/af_user_profile_extension.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart'
    hide AFRolePB;
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:appflowy/startup/startup.dart';
import 'dart:convert';

class RustPageAccessLevelRepositoryImpl implements PageAccessLevelRepository {
  @override
  Future<FlowyResult<ViewPB, FlowyError>> getView(String pageId) async {
    final result = await ViewBackendService.getView(pageId);
    return result.fold(
      (view) {
        Log.debug('get view(${view.id}) success');
        return FlowyResult.success(view);
      },
      (error) {
        Log.error('failed to get view, error: $error');
        return FlowyResult.failure(error);
      },
    );
  }

  @override
  Future<FlowyResult<void, FlowyError>> lockView(String pageId) async {
    final result = await ViewBackendService.lockView(pageId);
    return result.fold(
      (_) {
        Log.debug('lock view($pageId) success');
        return FlowyResult.success(null);
      },
      (error) {
        Log.error('failed to lock view, error: $error');
        return FlowyResult.failure(error);
      },
    );
  }

  @override
  Future<FlowyResult<void, FlowyError>> unlockView(String pageId) async {
    final result = await ViewBackendService.unlockView(pageId);
    return result.fold(
      (_) {
        Log.debug('unlock view($pageId) success');
        return FlowyResult.success(null);
      },
      (error) {
        Log.error('failed to unlock view, error: $error');
        return FlowyResult.failure(error);
      },
    );
  }

  /// 权限检查优先级（从高到低）：
  /// 1. local users → fullAccess
  /// 2. local workspace → fullAccess
  /// 3. 接收的发布文档 → fullAccess
  /// 4. **显式共享权限**（FFI 缓存查询，uuid/uid/email 三重匹配）→ 使用缓存值
  /// 5. page creator → fullAccess（仅当用户确认不在共享列表中时）
  /// 6. 默认 → fullAccess
  @override
  Future<FlowyResult<ShareAccessLevel, FlowyError>> getAccessLevel(
    String pageId,
  ) async {
    final userResult = await UserBackendService.getCurrentUserProfile();
    final user = userResult.fold(
      (s) => s,
      (_) => null,
    );

    if (user == null) {
      return FlowyResult.failure(
        FlowyError(
          code: ErrorCode.Internal,
          msg: 'User not found',
        ),
      );
    }

    if (user.userAuthType == AuthTypePB.Local) {
      return FlowyResult.success(ShareAccessLevel.fullAccess);
    }

    if (user.workspaceType == WorkspaceTypePB.LocalW) {
      return FlowyResult.success(ShareAccessLevel.fullAccess);
    }

    // 关键修复：接收的发布文档检查必须在 creator 检查之前
    // 因为 receive_published_collab 复制文档时 created_by 设为了接收者的 uid，
    // 如果先检查 creator，接收者会被误判为"创建者"而获得 fullAccess
    final authToken = _extractAuthToken(user);
    final receivedReadonlyResult =
        await _getReceivedPublishedCollabReadonly(pageId, authToken: authToken);
    if (receivedReadonlyResult.isReceived &&
        receivedReadonlyResult.isReadonly) {
      Log.debug(
          'page $pageId is a received published collab, setting to fullAccess');
      return FlowyResult.success(ShareAccessLevel.fullAccess);
    }

    final cloudAccessLevel = await _getCurrentUserAccessLevelFromCloud(
      pageId,
      authToken: authToken,
    );
    if (cloudAccessLevel != null) {
      Log.debug(
        '[PageAccessLevel] HTTP current permission returned: $cloudAccessLevel for page: $pageId',
      );
      return FlowyResult.success(cloudAccessLevel);
    }

    final email = user.email;
    final userId = user.id.toInt();
    final userUuid = _extractUserUuid(user);
    final membersAccessLevel = await _getAccessLevelFromCollabMembers(
      pageId,
      email: email,
      userId: userId,
      authToken: authToken,
    );
    if (membersAccessLevel != null) {
      Log.debug(
        '[PageAccessLevel] HTTP collab members returned: $membersAccessLevel for page: $pageId',
      );
      return FlowyResult.success(membersAccessLevel);
    }

    // 通过 Rust FFI 查询本地 SQLite 缓存中的共享用户列表
    // 后台会自动同步云端数据并发送通知触发刷新
    //
    // 匹配优先级与 HTTP API 一致：uuid > uid > email
    // 之前只用 email 匹配，当 email 不一致时会漏掉用户，
    // 导致回退到 creator 检查给 readOnly 用户返回 fullAccess。
    final request = GetSharedUsersPayloadPB(viewId: pageId);
    final result = await FolderEventGetSharedUsers(request).send();
    ShareAccessLevel? ffiAccessLevel;
    bool userFoundInFfiCache = false;
    bool ffiCacheHadData = false;

    result.fold(
      (success) {
        ffiCacheHadData = success.items.isNotEmpty;
        for (final item in success.items) {
          final itemEmail = item.email.trim().toLowerCase();
          final emailMatches = email.isNotEmpty &&
              itemEmail.isNotEmpty &&
              itemEmail == email.trim().toLowerCase();
          final itemId = item.userId;
          final uuidMatches = userUuid != null &&
              userUuid.isNotEmpty &&
              itemId.isNotEmpty &&
              itemId == userUuid;
          final uidMatches = itemId.isNotEmpty && itemId == userId.toString();

          if (emailMatches || uuidMatches || uidMatches) {
            userFoundInFfiCache = true;
            ffiAccessLevel = item.accessLevel.shareAccessLevel;
            Log.debug('[PageAccessLevel] FFI cache match: '
                'email=$email, uuid=$userUuid, uid=$userId, '
                'itemId=$itemId, accessLevel=$ffiAccessLevel '
                '(by ${uuidMatches ? "uuid" : (uidMatches ? "uid" : "email")})');
            break;
          }
        }
      },
      (failure) {
        Log.error(
            'failed to get user access level from FFI: $failure, in page: $pageId');
      },
    );

    final resolvedFfiLevel = ffiAccessLevel;
    if (resolvedFfiLevel != null) {
      Log.debug(
          '[PageAccessLevel] FFI cache returned: $resolvedFfiLevel for page: $pageId');
      return FlowyResult.success(resolvedFfiLevel);
    }

    // 关键保护：如果用户在 FFI 缓存的共享列表中存在但匹配失败
    // （例如 email/uuid 格式不一致），不能回退到 creator 检查，
    // 否则被设为 readOnly 的创建者会因匹配失败而获得 fullAccess。
    if (userFoundInFfiCache) {
      Log.warn(
          '[PageAccessLevel] user found in FFI cache but accessLevel was null, '
          'defaulting to readOnly for safety. page: $pageId, email: $email');
      return FlowyResult.success(ShareAccessLevel.readOnly);
    }

    // FFI 缓存未命中：直接查后端 collab members API，绕过本地缓存延迟。
    // 当云端权限已变更但本地 SQLite 尚未同步时，这是唯一的可靠数据源。
    Log.debug('[PageAccessLevel] cloud HTTP miss and FFI cache '
        '${ffiCacheHadData ? "miss" : "empty"}. page: $pageId');
    // HTTP 也未命中：如果 FFI 缓存有数据（用户确实不在共享列表），
    // 允许 creator 兜底；如果 FFI 缓存为空（可能未同步），安全兜底到 readOnly。
    if (!ffiCacheHadData) {
      Log.warn('[PageAccessLevel] both FFI cache empty and HTTP miss, '
          'defaulting to readOnly for safety. page: $pageId');
      return FlowyResult.success(ShareAccessLevel.readOnly);
    }

    // 用户确认不在共享列表中（FFI 有数据 + HTTP 也确认），回退到 creator 检查
    final viewResult = await getView(pageId);
    final view = viewResult.fold(
      (s) => s,
      (_) => null,
    );
    if (view?.createdBy == user.id) {
      Log.debug('[PageAccessLevel] user is page creator and NOT in shared list '
          '(confirmed by FFI + HTTP), granting fullAccess. page: $pageId, userId: $userId');
      return FlowyResult.success(ShareAccessLevel.fullAccess);
    }

    final workspaceResult = await getCurrentWorkspace();
    final workspace = workspaceResult.fold(
      (s) => s,
      (_) => null,
    );
    if (workspace == null) {
      return FlowyResult.failure(
        FlowyError(
          code: ErrorCode.Internal,
          msg: 'Current workspace not found',
        ),
      );
    }

    final sectionTypeResult = await getSectionType(pageId);
    final sectionType = sectionTypeResult.fold(
      (s) => s,
      (_) => null,
    );

    Log.debug(
        '[PageAccessLevel] no explicit permission found for user uid=${user.id.toInt()} '
        'on page $pageId, sectionType=$sectionType, workspaceRole=${workspace.role} — '
        'defaulting to readOnly (失败路径安全降级，非创建者不放开编辑权)');
    return FlowyResult.success(ShareAccessLevel.readOnly);
  }

  /// 查询接收的发布文档只读状态
  /// [authToken] 已解析好的 Bearer token，避免重复调用 GET_PROFILE
  Future<({bool isReceived, bool isReadonly})>
      _getReceivedPublishedCollabReadonly(
    String pageId, {
    String? authToken,
  }) async {
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;

      if (baseUrl.isEmpty) {
        Log.warn('[PageAccessLevel] Base URL 为空，无法检查接收文档只读状态');
        return (isReceived: false, isReadonly: false);
      }

      final uri = Uri.parse(baseUrl).replace(
        // 注意：后端 API 是在 /api/workspace scope 下定义的
        path: '/api/workspace/published/received/$pageId/readonly',
      );

      final token = authToken ?? await _getAuthToken();
      if (token == null || token.isEmpty) {
        Log.warn('[PageAccessLevel] Auth token 为空，无法检查接收文档只读状态');
        return (isReceived: false, isReadonly: false);
      }

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          throw Exception('请求超时');
        },
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) {
          final data = body['data'];
          if (data is Map<String, dynamic>) {
            final isReceived = data['is_received'] as bool? ?? false;
            final isReadonly = data['is_readonly'] as bool? ?? false;
            return (isReceived: isReceived, isReadonly: isReadonly);
          }
        }
      }
    } catch (e) {
      // 使用 Log.warn 而非 Log.error，避免在网络不稳定时产生大量错误日志
      // 超时等网络错误属于正常降级情况，不影响应用核心功能
      Log.warn(
        '[PageAccessLevel] 检查接收文档只读状态失败: $e',
      );
    }
    return (isReceived: false, isReadonly: false);
  }

  /// 从 JWT token 中提取用户 UUID（sub 字段）
  /// 用于 FFI 缓存的 uid 匹配（后端 uid 是 UUID 字符串）
  String? _extractUserUuid(UserProfilePB user) {
    final rawToken = user.authToken;
    if (rawToken == null || rawToken.isEmpty) return null;

    String? accessToken = rawToken;
    if (rawToken.trimLeft().startsWith('{')) {
      try {
        final tokenMap = jsonDecode(rawToken) as Map<String, dynamic>;
        accessToken = tokenMap['access_token'] as String?;
      } catch (_) {
        return null;
      }
    }
    if (accessToken == null || accessToken.isEmpty) return null;

    final parts = accessToken.split('.');
    if (parts.length < 2) return null;
    try {
      final payload = parts[1];
      final normalized = payload.replaceAll('-', '+').replaceAll('_', '/');
      final padding = (4 - normalized.length % 4) % 4;
      final padded = normalized + ('=' * padding);
      final decoded = utf8.decode(base64Decode(padded));
      final payloadMap = jsonDecode(decoded) as Map<String, dynamic>;
      final sub = payloadMap['sub']?.toString();
      if (sub != null && sub.isNotEmpty) return sub;
    } catch (_) {}
    return null;
  }

  /// 从 UserProfilePB 中提取 Bearer token（不触发网络请求）
  String? _extractAuthToken(UserProfilePB user) {
    final rawToken = user.authToken;
    if (rawToken == null || rawToken.isEmpty) return null;
    try {
      final decoded = jsonDecode(rawToken);
      if (decoded is Map<String, dynamic>) {
        final accessToken = decoded['access_token'] as String?;
        if (accessToken != null && accessToken.isNotEmpty) {
          return accessToken;
        }
      }
    } catch (_) {}
    return rawToken;
  }

  Future<String?> _getAuthToken() async {
    try {
      final userResult = await UserBackendService.getCurrentUserProfile();
      return userResult.fold(
        (user) => _extractAuthToken(user),
        (error) {
          Log.warn('[PageAccessLevel] 获取用户信息失败: $error');
          return null;
        },
      );
    } catch (e) {
      Log.error('[PageAccessLevel] 获取 token 时出错: $e');
    }
    return null;
  }

  @override
  Future<FlowyResult<SharedSectionType, FlowyError>> getSectionType(
    String pageId,
  ) async {
    final request = ViewIdPB(value: pageId);
    final result = await FolderEventGetSharedViewSection(request).send();
    return result.fold(
      (success) {
        final sectionType = success.section.sharedSectionType;
        Log.debug('shared section type: $sectionType, in page: $pageId');
        return FlowyResult.success(sectionType);
      },
      (failure) {
        Log.error(
          'failed to get shared section type: $failure, in page: $pageId',
        );

        return FlowyResult.failure(failure);
      },
    );
  }

  @override
  Future<FlowyResult<UserWorkspacePB, FlowyError>> getCurrentWorkspace() async {
    final result = await UserBackendService.getCurrentWorkspace();
    final currentWorkspaceId = result.fold(
      (s) => s.id,
      (_) => null,
    );

    if (currentWorkspaceId == null) {
      return FlowyResult.failure(
        FlowyError(
          code: ErrorCode.Internal,
          msg: 'Current workspace not found',
        ),
      );
    }

    final workspaceResult = await UserBackendService.getWorkspaceById(
      currentWorkspaceId,
    );
    return workspaceResult;
  }

  /// 直接通过 HTTP 查询后端 collab members API 获取当前用户的权限。
  /// 绕过本地 SQLite 缓存，确保权限变更立即生效。
  /// API: GET /api/workspace/{workspace_id}/collab/{object_id}/members
  Future<ShareAccessLevel?> _getCurrentUserAccessLevelFromCloud(
    String pageId, {
    String? authToken,
  }) async {
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;

      if (baseUrl.isEmpty) {
        Log.warn(
            '[PageAccessLevel] Base URL is empty, cannot query current permission');
        return null;
      }

      final workspaceResult = await UserBackendService.getCurrentWorkspace();
      final workspaceId = workspaceResult.fold(
        (s) => s.id,
        (_) => null,
      );

      if (workspaceId == null) {
        Log.warn('[PageAccessLevel] Cannot get current workspace ID');
        return null;
      }

      final token = authToken ?? await _getAuthToken();
      if (token == null || token.isEmpty) {
        Log.warn(
            '[PageAccessLevel] Auth token is empty, cannot query current permission');
        return null;
      }

      final uri = Uri.parse(baseUrl).replace(
        path: '/api/workspace/$workspaceId/collab/$pageId/permission',
      );

      // 带重试的请求：DNS/网络瞬时失败（例如 App 启动时网络尚未就绪）不应
      // 直接掉到上层的 fullAccess 兜底，否则被设为只读的用户会因一次网络抖动
      // 恢复编辑权。仅对网络/超时错误重试；200/403/404 等明确响应不重试。
      http.Response? response;
      const maxAttempts = 3;
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          response = await http.get(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          ).timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw Exception('request timeout'),
          );
          break;
        } catch (e) {
          Log.warn(
              '[PageAccessLevel] permission request attempt $attempt/$maxAttempts failed: $e');
          if (attempt >= maxAttempts) {
            return null;
          }
          await Future.delayed(Duration(milliseconds: 400 * attempt));
        }
      }
      if (response == null) {
        return null;
      }

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final code = body['code'] as int?;
        if (code != null && code != 0) {
          Log.warn(
              '[PageAccessLevel] current permission API returned code: $code, body: ${response.body}');
          return null;
        }

        final data = body['data'] as Map<String, dynamic>?;
        if (data == null) {
          Log.warn(
              '[PageAccessLevel] current permission API returned data=null, body: ${response.body}');
          return null;
        }

        final permissionId = data['permission_id'] as int?;
        if (permissionId != null) {
          return _mapPermissionIdToAccessLevel(permissionId);
        }

        final accessLevel = data['access_level'] as int?;
        if (accessLevel != null) {
          return _mapAccessLevelValueToAccessLevel(accessLevel);
        }

        Log.warn(
            '[PageAccessLevel] current permission API returned unknown data: ${response.body}');
        return null;
      }

      if (response.statusCode == 403) {
        return ShareAccessLevel.readOnly;
      }

      if (response.statusCode != 404) {
        Log.warn(
            '[PageAccessLevel] current permission API failed: HTTP ${response.statusCode}, body: ${response.body}');
      }
      return null;
    } catch (e) {
      Log.warn('[PageAccessLevel] query current permission failed: $e');
      return null;
    }
  }

  Future<ShareAccessLevel?> _getAccessLevelFromCollabMembers(
    String pageId, {
    required String email,
    required int userId,
    String? authToken,
  }) async {
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;

      if (baseUrl.isEmpty) {
        Log.warn('[PageAccessLevel] Base URL 为空，无法查询 collab members');
        return null;
      }

      // 获取当前 workspace ID
      final workspaceResult = await UserBackendService.getCurrentWorkspace();
      final workspaceId = workspaceResult.fold(
        (s) => s.id,
        (_) => null,
      );

      if (workspaceId == null) {
        Log.warn('[PageAccessLevel] 无法获取当前 workspace ID');
        return null;
      }

      final token = authToken ?? await _getAuthToken();
      if (token == null || token.isEmpty) {
        Log.warn('[PageAccessLevel] Auth token 为空，无法查询 collab members');
        return null;
      }

      // GET /api/workspace/{workspace_id}/collab/{object_id}/members
      final uri = Uri.parse(baseUrl).replace(
        path: '/api/workspace/$workspaceId/collab/$pageId/members',
      );

      Log.debug(
          '[PageAccessLevel] fetching collab members: $uri, email: $email');

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw Exception('请求超时');
        },
      );

      Log.debug(
          '[PageAccessLevel] collab members response: HTTP ${response.statusCode}');

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final code = body['code'] as int?;
        if (code != null && code != 0) {
          Log.warn(
              '[PageAccessLevel] collab members API returned error code: $code, body: ${response.body}');
          return null;
        }

        final data = body['data'] as List<dynamic>?;
        if (data == null) {
          Log.warn(
              '[PageAccessLevel] collab members API returned data=null, body: ${response.body}');
          return null;
        }

        Log.debug(
            '[PageAccessLevel] collab members count: ${data.length}, searching for uid=$userId, email=$email');

        // 在成员列表中查找当前用户
        // 优先通过 uid 匹配（最可靠），回退到 email 匹配
        for (final member in data) {
          final memberMap = member as Map<String, dynamic>;
          final memberUid = memberMap['uid'] as int?;
          final memberEmail =
              (memberMap['email'] as String? ?? '').trim().toLowerCase();
          final permissionId = memberMap['permission_id'] as int? ?? 1;

          Log.debug(
              '[PageAccessLevel] member: uid=$memberUid, email=$memberEmail, permission_id=$permissionId');

          // 优先 uid 匹配
          final uidMatch = memberUid != null && memberUid == userId;
          // 回退 email 匹配（仅当 email 非空时）
          final emailMatch = email.isNotEmpty &&
              memberEmail.isNotEmpty &&
              memberEmail == email.trim().toLowerCase();

          if (uidMatch || emailMatch) {
            final accessLevel = _mapPermissionIdToAccessLevel(permissionId);
            Log.debug(
                '[PageAccessLevel] MATCH FOUND: uid=$memberUid, email=$memberEmail, '
                'permission_id=$permissionId -> $accessLevel (by ${uidMatch ? "uid" : "email"})');
            return accessLevel;
          }
        }

        Log.warn('[PageAccessLevel] user NOT found in collab members list. '
            'Looking for uid=$userId, email=$email, '
            'members=${data.map((m) => 'uid=${(m as Map)['uid']}, email=${m['email']}, perm=${m['permission_id']}').toList()}');
        return null;
      } else {
        Log.warn(
            '[PageAccessLevel] collab members API failed: HTTP ${response.statusCode}, body: ${response.body}');
        return null;
      }
    } catch (e) {
      Log.warn('[PageAccessLevel] 查询 collab members 失败: $e');
      return null;
    }
  }

  /// 将后端 permission_id 映射为 ShareAccessLevel
  /// 后端定义：1=ReadOnly, 2=ReadAndComment, 3=ReadAndWrite, 4=FullAccess
  ShareAccessLevel _mapPermissionIdToAccessLevel(int permissionId) {
    switch (permissionId) {
      case 1:
        return ShareAccessLevel.readOnly;
      case 2:
        return ShareAccessLevel.readAndComment;
      case 3:
        return ShareAccessLevel.readAndWrite;
      case 4:
        return ShareAccessLevel.fullAccess;
      default:
        return ShareAccessLevel.readOnly;
    }
  }

  ShareAccessLevel _mapAccessLevelValueToAccessLevel(int accessLevel) {
    switch (accessLevel) {
      case 10:
        return ShareAccessLevel.readOnly;
      case 20:
        return ShareAccessLevel.readAndComment;
      case 30:
        return ShareAccessLevel.readAndWrite;
      case 50:
        return ShareAccessLevel.fullAccess;
      default:
        return ShareAccessLevel.readOnly;
    }
  }
}
