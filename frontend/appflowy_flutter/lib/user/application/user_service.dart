import 'dart:async';
import 'dart:convert';

import 'package:appflowy/workspace/application/settings/plan/workspace_subscription_ext.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/workspace.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

abstract class IUserBackendService {
  Future<FlowyResult<void, FlowyError>> cancelSubscription(
    String workspaceId,
    SubscriptionPlanPB plan,
    String? reason,
  );
  Future<FlowyResult<PaymentLinkPB, FlowyError>> createSubscription(
    String workspaceId,
    SubscriptionPlanPB plan,
  );
}

/// 手机号绑定发送验证码的响应 DTO
class PhoneBindSendResult {
  PhoneBindSendResult({
    required this.codeSent,
    required this.phoneExists,
    required this.isOwnPhone,
    this.existingUid,
    this.message,
  });
  final bool codeSent;      // 验证码是否已发送
  final bool phoneExists;   // 手机号是否已被其他账号注册
  final bool isOwnPhone;    // 手机号是否是当前用户自己的
  final String? existingUid; // 已存在账号的 UID（用于展示）
  final String? message;
}

/// 手机号绑定确认的响应 DTO
class PhoneBindConfirmResult {
  PhoneBindConfirmResult({
    required this.bindToExisting,
    required this.userId,
    this.message,
    this.accessToken,
    this.refreshToken,
    this.expiresIn,
    this.tokenType,
  });
  final bool bindToExisting;  // 是否绑定到了已注册账号
  final String? userId;       // 绑定后实际使用的账号 ID
  final String? message;       // 消息
  final String? accessToken;   // bindToExisting=true 时返回的新 access_token
  final String? refreshToken;  // bindToExisting=true 时返回的新 refresh_token
  final int? expiresIn;
  final String? tokenType;
}

/// Lightweight DTO for collab member returned by cloud API
class CollabMember {
  CollabMember({
    required this.uid,
    required this.name,
    this.email,
    this.avatarUrl,
    required this.permissionId,
  });

  final int uid;
  final String name;
  final String? email;
  final String? avatarUrl;
  final int permissionId;
}


const _baseBetaUrl = 'https://beta.appflowy.com';
const _baseProdUrl = 'https://appflowy.com';

class UserBackendService implements IUserBackendService {
  UserBackendService({required this.userId});

  final Int64 userId;

  static Future<FlowyResult<UserProfilePB, FlowyError>>
      getCurrentUserProfile() async {
    final result = await UserEventGetUserProfile().send();
    return result;
  }

  Future<FlowyResult<void, FlowyError>> updateUserProfile({
    String? name,
    String? password,
    String? email,
    String? phone,
    String? iconUrl,
  }) {
    final payload = UpdateUserProfilePayloadPB.create()..id = userId;

    if (name != null) {
      payload.name = name;
    }

    if (password != null) {
      payload.password = password;
    }

    if (email != null) {
      payload.email = email;
    }

    if (phone != null) {
      payload.phone = phone;
    }

    if (iconUrl != null) {
      payload.iconUrl = iconUrl;
    }

    return UserEventUpdateUserProfile(payload).send();
  }

  Future<FlowyResult<void, FlowyError>> deleteWorkspace({
    required String workspaceId,
  }) {
    throw UnimplementedError();
  }

  static Future<FlowyResult<UserProfilePB, FlowyError>> signInWithMagicLink(
    String email,
    String redirectTo,
  ) async {
    final payload = MagicLinkSignInPB(email: email, redirectTo: redirectTo);
    return UserEventMagicLinkSignIn(payload).send();
  }

  static Future<FlowyResult<GotrueTokenResponsePB, FlowyError>>
      signInWithPasscode(
    String email,
    String passcode,
  ) async {
    final payload = PasscodeSignInPB(email: email, passcode: passcode);
    return UserEventPasscodeSignIn(payload).send();
  }

  /// Send OTP to phone number (for phone number verification/change)
  /// This calls the cloud API /api/user/send-phone-otp endpoint
  /// Requires user to be logged in (needs access token)
  static Future<FlowyResult<void, FlowyError>> sendPhoneOTP(
    String phone,
  ) async {
    try {
      // 获取当前用户配置和 token
      final cloudConfigResult = await UserEventGetCloudConfig().send();
      final cloudConfig = cloudConfigResult.fold(
        (config) => config,
        (error) {
          Log.error('[UserBackendService] Failed to get cloud config: $error');
          throw error;
        },
      );
      
      final baseUrl = cloudConfig.serverUrl;
      if (baseUrl.isEmpty) {
        return FlowyResult.failure(
          FlowyError()
            ..code = ErrorCode.Internal
            ..msg = 'Missing server URL',
        );
      }
      
      // 获取用户的 access token
      final userResult = await UserBackendService.getCurrentUserProfile();
      final rawToken = userResult.fold(
        (user) => user.token,
        (error) {
          Log.error('[UserBackendService] Failed to get user profile: $error');
          return '';
        },
      );
      final token = _normalizeToken(rawToken);
      if (token.isEmpty) {
        Log.error('[UserBackendService] Access token is empty!');
        return FlowyResult.failure(
          FlowyError()
            ..code = ErrorCode.Internal
            ..msg = 'Missing access token. Please login first.',
        );
      }
      
      // 调用云端 API 发送手机验证码
      // 注意：手机号格式应由调用方确保（第三方绑定流程需要在调用前转换为 E.164 格式）
      final uri = Uri.parse('$baseUrl/api/user/send-phone-otp');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'phone': phone,
        }),
      );
      
      if (response.statusCode == 200) {
        // Check if response body contains error information
        try {
          final responseData = jsonDecode(response.body) as Map<String, dynamic>;
          if (responseData.containsKey('code') && responseData['code'] != 0) {
            // Response contains error code
            final errorMsg = responseData['message'] as String? ?? 
                responseData['msg'] as String? ?? 
                'Failed to send phone OTP';
            Log.error('[UserBackendService] Send phone OTP failed: $errorMsg');
            return FlowyResult.failure(
              FlowyError()
                ..code = ErrorCode.Internal
                ..msg = errorMsg,
            );
          }
        } catch (e) {
          // If parsing fails, assume success (backward compatibility)
        }
        return FlowyResult.success(null);
      } else {
        final errorMsg = response.body.isNotEmpty 
            ? response.body 
            : 'Failed to send phone OTP (HTTP ${response.statusCode})';
        Log.error('[UserBackendService] Send phone OTP failed: $errorMsg');
        return FlowyResult.failure(
          FlowyError()
            ..code = ErrorCode.Internal
            ..msg = errorMsg,
        );
      }
    } catch (e, stackTrace) {
      Log.error('[UserBackendService] ❌ Exception: $e');
      Log.error('[UserBackendService] ❌ Stack trace: $stackTrace');
      return FlowyResult.failure(
        FlowyError()
          ..code = ErrorCode.Internal
          ..msg = 'Failed to send phone OTP: $e',
      );
    }
  }

  /// 将 token 归一化：如果是 JSON 字符串，提取 access_token；否则直接返回
  static String _normalizeToken(String token) {
    if (token.isEmpty) return token;
    if (token.trim().startsWith('{')) {
      try {
        final map = jsonDecode(token);
        if (map is Map && map['access_token'] is String) {
          return map['access_token'] as String;
        }
      } catch (_) {
        // ignore parse errors, fallback to raw token
      }
    }
    return token;
  }

  /// Verify phone OTP and bind phone number
  /// This calls the cloud API /api/user/verify-phone endpoint directly via HTTP
  static Future<FlowyResult<void, FlowyError>> verifyAndBindPhone(
    String phone,
    String otp,
  ) async {
    try {
      // 获取当前用户配置
      final cloudConfigResult = await UserEventGetCloudConfig().send();
      final cloudConfig = cloudConfigResult.fold(
        (config) => config,
        (error) => throw error,
      );
      
      // 获取当前用户 Profile（包含 token）
      final userProfileResult = await getCurrentUserProfile();
      final userProfile = userProfileResult.fold(
        (profile) => profile,
        (error) => throw error,
      );
      
      final baseUrl = cloudConfig.serverUrl;
      // userProfile.token 可能是 access_token，也可能是包含 access_token 的 JSON，需要归一化
      final token = _normalizeToken(userProfile.token);
      
      Log.info('[UserBackendService] Token length: ${token.length}, first 20 chars: ${token.length > 20 ? token.substring(0, 20) : token}');
      
      if (baseUrl.isEmpty || token.isEmpty) {
        return FlowyResult.failure(
          FlowyError()
            ..code = ErrorCode.Internal
            ..msg = 'Missing server URL or auth token',
        );
      }
      
      // 调用 /api/user/verify-phone 端点
      // 注意：手机号格式应由调用方确保（第三方绑定流程需要在调用前转换为 E.164 格式）
      final uri = Uri.parse('$baseUrl/api/user/verify-phone');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'phone': phone,
          'otp': otp,
        }),
      );
      
      // 解析响应体，检查是否有错误
      if (response.statusCode == 200) {
        // 即使状态码是 200，也要检查响应体中是否有错误
        if (response.body.isNotEmpty) {
          try {
            final json = jsonDecode(response.body) as Map<String, dynamic>;
            if (json.containsKey('code') && json['code'] != 0) {
              final errorMsg = json['message'] as String? ?? json['msg'] as String? ?? '绑定失败';
              Log.error('[UserBackendService] Verify phone failed: $errorMsg');
              return FlowyResult.failure(
                FlowyError()
                  ..code = ErrorCode.Internal
                  ..msg = errorMsg,
              );
            }
          } catch (e) {
            // 响应体不是 JSON 或解析失败，但状态码是 200，认为成功
            Log.info('[UserBackendService] Verify phone response is not JSON, but status is 200, treating as success');
          }
        }
        return FlowyResult.success(null);
      } else {
        // 尝试解析错误响应
        String errorMsg = 'Failed to verify phone (HTTP ${response.statusCode})';
        if (response.body.isNotEmpty) {
          try {
            final json = jsonDecode(response.body) as Map<String, dynamic>;
            errorMsg = json['message'] as String? ?? json['msg'] as String? ?? errorMsg;
          } catch (e) {
            errorMsg = response.body;
          }
        }
        Log.error('[UserBackendService] Verify phone failed: $errorMsg');
        return FlowyResult.failure(
          FlowyError()
            ..code = ErrorCode.Internal
            ..msg = errorMsg,
        );
      }
    } catch (e) {
      Log.error('[UserBackendService] Exception: $e');
      return FlowyResult.failure(
        FlowyError()
          ..code = ErrorCode.Internal
          ..msg = 'Failed to verify phone: $e',
      );
    }
  }

  /// 发送手机号绑定验证码（含手机号已注册检测）
  /// POST /api/user/send-phone-bind-code
  /// [pendingToken] 可选，若提供则无需用户登录态（OAuth pending 流程）
  /// 返回 PhoneBindSendResult：
  ///   - codeSent=true：验证码已发送，可进入输入验证码页面
  ///   - phoneExists=true：手机号已被其他账号注册，前端应弹出"账号合并"确认框
  ///   - isOwnPhone=true：手机号是当前用户自己的
  static Future<FlowyResult<PhoneBindSendResult, FlowyError>>
      sendPhoneBindCode(String phone, {String? pendingToken}) async {
    try {
      final cloudConfigResult = await UserEventGetCloudConfig().send();
      final cloudConfig = cloudConfigResult.fold(
        (config) => config,
        (error) => throw error,
      );

      final baseUrl = cloudConfig.serverUrl;

      if (baseUrl.isEmpty) {
        return FlowyResult.failure(
          FlowyError()
            ..code = ErrorCode.Internal
            ..msg = 'Missing server URL',
        );
      }

      // 若提供了 pendingToken，则无需用户登录态（OAuth pending 流程）
      if (pendingToken != null && pendingToken.isNotEmpty) {
        final uri = Uri.parse('$baseUrl/api/user/send-phone-bind-code');
        final response = await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'phone': phone,
            'pending_token': pendingToken,
          }),
        );

        if (response.statusCode == 200) {
          try {
            final json = jsonDecode(response.body) as Map<String, dynamic>;
            return FlowyResult.success(PhoneBindSendResult(
              codeSent: json['code_sent'] as bool? ?? false,
              phoneExists: json['phone_exists'] as bool? ?? false,
              isOwnPhone: json['is_own_phone'] as bool? ?? false,
              existingUid: json['existing_uid'] as String?,
              message: json['message'] as String?,
            ));
          } catch (e) {
            return FlowyResult.failure(
              FlowyError()
                ..code = ErrorCode.Internal
                ..msg = 'Failed to parse response: $e',
            );
          }
        } else {
          String errorMsg = 'Request failed';
          try {
            final json = jsonDecode(response.body) as Map<String, dynamic>;
            errorMsg = json['msg'] as String? ?? json['message'] as String? ?? errorMsg;
          } catch (_) {}
          return FlowyResult.failure(
            FlowyError()
              ..code = ErrorCode.Internal
              ..msg = errorMsg,
          );
        }
      }

      // 使用用户登录态的原始逻辑
      final userProfileResult = await getCurrentUserProfile();
      final userProfile = userProfileResult.fold(
        (profile) => profile,
        (error) => throw error,
      );

      final authToken = _normalizeToken(userProfile.token);
      if (authToken.isEmpty) {
        return FlowyResult.failure(
          FlowyError()
            ..code = ErrorCode.Internal
            ..msg = 'Missing auth token',
        );
      }

      final uri = Uri.parse('$baseUrl/api/user/send-phone-bind-code');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({'phone': phone}),
      );

      if (response.statusCode == 200) {
        try {
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          return FlowyResult.success(PhoneBindSendResult(
            codeSent: json['code_sent'] as bool? ?? false,
            phoneExists: json['phone_exists'] as bool? ?? false,
            isOwnPhone: json['is_own_phone'] as bool? ?? false,
            existingUid: json['existing_uid'] as String?,
            message: json['message'] as String?,
          ));
        } catch (e) {
          return FlowyResult.failure(
            FlowyError()
              ..code = ErrorCode.Internal
              ..msg = 'Failed to parse response: $e',
          );
        }
      } else {
        String errorMsg = 'Request failed';
        try {
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          errorMsg = json['msg'] as String? ?? json['message'] as String? ?? errorMsg;
        } catch (_) {}
        return FlowyResult.failure(
          FlowyError()
            ..code = ErrorCode.Internal
            ..msg = errorMsg,
        );
      }
    } catch (e) {
      Log.error('[UserBackendService] sendPhoneBindCode exception: $e');
      return FlowyResult.failure(
        FlowyError()
          ..code = ErrorCode.Internal
          ..msg = 'Failed to send phone bind code: $e',
      );
    }
  }

  /// 确认手机号绑定
  /// POST /api/user/confirm-phone-bind
  ///
  /// [pendingToken] 可选，若提供则走 OAuth pending 流程（无需登录态）
  /// [merge] true=绑定到已注册手机号，false=绑定到新手机号
  /// 若不提供 pendingToken，则必须已登录，走已登录用户换绑流程
  static Future<FlowyResult<PhoneBindConfirmResult, FlowyError>>
      confirmPhoneBind({
    required String phone,
    required String token,
    String? pendingToken,
    bool merge = false,
  }) async {
    try {
      final cloudConfigResult = await UserEventGetCloudConfig().send();
      final cloudConfig = cloudConfigResult.fold(
        (config) => config,
        (error) => throw error,
      );

      final baseUrl = cloudConfig.serverUrl;
      if (baseUrl.isEmpty) {
        return FlowyResult.failure(
          FlowyError()
            ..code = ErrorCode.Internal
            ..msg = 'Missing server URL',
        );
      }

      final uri = Uri.parse('$baseUrl/api/user/confirm-phone-bind');
      final Map<String, dynamic> body = {
        'phone': phone,
        'token': token,
        'merge': merge,
      };
      if (pendingToken != null && pendingToken.isNotEmpty) {
        body['pending_token'] = pendingToken;
      }

      // 有 pendingToken 时无需认证；无 pendingToken 时需要用户登录态
      final Map<String, String> headers = {'Content-Type': 'application/json'};
      if (pendingToken == null || pendingToken.isEmpty) {
        final userProfileResult = await getCurrentUserProfile();
        final userProfile = userProfileResult.fold(
          (profile) => profile,
          (error) => throw error,
        );
        final rawToken = _normalizeToken(userProfile.token);
        if (rawToken.isEmpty) {
          return FlowyResult.failure(
            FlowyError()
              ..code = ErrorCode.Internal
              ..msg = 'Missing auth token',
          );
        }
        headers['Authorization'] = 'Bearer $rawToken';
      }

      final response = await http.post(
        uri,
        headers: headers,
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        try {
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          return FlowyResult.success(PhoneBindConfirmResult(
            bindToExisting: json['bind_to_existing'] as bool? ?? false,
            userId: json['user_id'] as String?,
            message: json['message'] as String?,
            accessToken: json['access_token'] as String?,
            refreshToken: json['refresh_token'] as String?,
            expiresIn: json['expires_in'] as int?,
            tokenType: json['token_type'] as String?,
          ));
        } catch (e) {
          return FlowyResult.failure(
            FlowyError()
              ..code = ErrorCode.Internal
              ..msg = 'Failed to parse response: $e',
          );
        }
      } else {
        String errorMsg = 'Failed to confirm phone bind (HTTP ${response.statusCode})';
        if (response.body.isNotEmpty) {
          try {
            final json = jsonDecode(response.body) as Map<String, dynamic>;
            errorMsg = json['message'] as String? ?? json['msg'] as String? ?? errorMsg;
          } catch (_) {}
        }
        return FlowyResult.failure(
          FlowyError()
            ..code = ErrorCode.Internal
            ..msg = errorMsg,
        );
      }
    } catch (e) {
      Log.error('[UserBackendService] confirmPhoneBind exception: $e');
      return FlowyResult.failure(
        FlowyError()
          ..code = ErrorCode.Internal
          ..msg = 'Failed to confirm phone bind: $e',
      );
    }
  }

  Future<FlowyResult<void, FlowyError>> signInWithPassword(
    String email,
    String password,
  ) {
    final payload = SignInPayloadPB(
      email: email,
      password: password,
    );
    return UserEventSignInWithEmailPassword(payload).send();
  }

  static Future<FlowyResult<void, FlowyError>> signOut() {
    return UserEventSignOut().send();
  }

  Future<FlowyResult<void, FlowyError>> initUser() async {
    return UserEventInitUser().send();
  }

  static Future<FlowyResult<UserProfilePB, FlowyError>> getAnonUser() async {
    return UserEventGetAnonUser().send();
  }

  static Future<FlowyResult<void, FlowyError>> openAnonUser() async {
    return UserEventOpenAnonUser().send();
  }

  Future<FlowyResult<List<UserWorkspacePB>, FlowyError>> getWorkspaces() {
    return UserEventGetAllWorkspace().send().then((value) {
      return value.fold(
        (workspaces) => FlowyResult.success(workspaces.items),
        (error) => FlowyResult.failure(error),
      );
    });
  }

  static Future<FlowyResult<UserWorkspacePB, FlowyError>> getWorkspaceById(
    String workspaceId,
  ) async {
    final result = await UserEventGetAllWorkspace().send();
    return result.fold(
      (workspaces) {
        final workspace = workspaces.items.firstWhere(
          (workspace) => workspace.workspaceId == workspaceId,
        );
        return FlowyResult.success(workspace);
      },
      (error) => FlowyResult.failure(error),
    );
  }

  Future<FlowyResult<void, FlowyError>> openWorkspace(
    String workspaceId,
    WorkspaceTypePB workspaceType,
  ) {
    final payload = OpenUserWorkspacePB()
      ..workspaceId = workspaceId
      ..workspaceType = workspaceType;
    return UserEventOpenWorkspace(payload).send();
  }

  static Future<FlowyResult<WorkspacePB, FlowyError>> getCurrentWorkspace() {
    return FolderEventReadCurrentWorkspace().send().then((result) {
      return result.fold(
        (workspace) => FlowyResult.success(workspace),
        (error) => FlowyResult.failure(error),
      );
    });
  }

  Future<FlowyResult<UserWorkspacePB, FlowyError>> createUserWorkspace(
    String name,
    WorkspaceTypePB workspaceType,
  ) {
    final request = CreateWorkspacePB.create()
      ..name = name
      ..workspaceType = workspaceType;
    return UserEventCreateWorkspace(request).send();
  }

  Future<FlowyResult<void, FlowyError>> deleteWorkspaceById(
    String workspaceId,
  ) {
    final request = UserWorkspaceIdPB.create()..workspaceId = workspaceId;
    return UserEventDeleteWorkspace(request).send();
  }

  Future<FlowyResult<void, FlowyError>> renameWorkspace(
    String workspaceId,
    String name,
  ) {
    final request = RenameWorkspacePB()
      ..workspaceId = workspaceId
      ..newName = name;
    return UserEventRenameWorkspace(request).send();
  }

  Future<FlowyResult<void, FlowyError>> updateWorkspaceIcon(
    String workspaceId,
    String icon,
  ) {
    final request = ChangeWorkspaceIconPB()
      ..workspaceId = workspaceId
      ..newIcon = icon;
    return UserEventChangeWorkspaceIcon(request).send();
  }

  Future<FlowyResult<RepeatedWorkspaceMemberPB, FlowyError>>
      getWorkspaceMembers(
    String workspaceId,
  ) async {
    final data = QueryWorkspacePB()..workspaceId = workspaceId;
    return UserEventGetWorkspaceMembers(data).send();
  }

  Future<FlowyResult<void, FlowyError>> addWorkspaceMember(
    String workspaceId,
    String email,
  ) async {
    final data = AddWorkspaceMemberPB()
      ..workspaceId = workspaceId
      ..email = email;
    return UserEventAddWorkspaceMember(data).send();
  }

  Future<FlowyResult<void, FlowyError>> inviteWorkspaceMember(
    String workspaceId,
    String email, {
    AFRolePB? role,
  }) async {
    final data = WorkspaceMemberInvitationPB()
      ..workspaceId = workspaceId
      ..inviteeEmail = email;
    if (role != null) {
      data.role = role;
    }
    return UserEventInviteWorkspaceMember(data).send();
  }

  Future<FlowyResult<void, FlowyError>> removeWorkspaceMember(
    String workspaceId,
    String identifier,
  ) async {
    final data = RemoveWorkspaceMemberPB()
      ..workspaceId = workspaceId
      ..identifier = identifier;
    return UserEventRemoveWorkspaceMember(data).send();
  }

  Future<FlowyResult<void, FlowyError>> updateWorkspaceMember(
    String workspaceId,
    String email,
    AFRolePB role,
  ) async {
    final data = UpdateWorkspaceMemberPB()
      ..workspaceId = workspaceId
      ..email = email
      ..role = role;
    return UserEventUpdateWorkspaceMember(data).send();
  }

  /// Get members who have joined a collab (space)
  Future<FlowyResult<List<CollabMember>, FlowyError>> getCollabMembers(
    String workspaceId,
    String objectId,
  ) async {
    try {
      final cloudConfigResult = await UserEventGetCloudConfig().send();
      final cloudConfig = cloudConfigResult.fold(
        (config) => config,
        (error) {
          Log.error('[UserBackendService] Failed to get cloud config: $error');
          throw error;
        },
      );

      final baseUrl = cloudConfig.serverUrl;
      if (baseUrl.isEmpty) {
        return FlowyResult.failure(
          FlowyError()
            ..code = ErrorCode.Internal
            ..msg = 'Missing server URL',
        );
      }

      final userResult = await UserBackendService.getCurrentUserProfile();
      final rawToken = userResult.fold(
        (user) => user.token,
        (error) {
          Log.error('[UserBackendService] Failed to get user profile: $error');
          return '';
        },
      );
      final token = _normalizeToken(rawToken);
      if (token.isEmpty) {
        Log.error('[UserBackendService] Access token is empty!');
        return FlowyResult.failure(
          FlowyError()
            ..code = ErrorCode.Internal
            ..msg = 'Missing access token. Please login first.',
        );
      }

      final uri = Uri.parse('$baseUrl/api/workspace/$workspaceId/collab/$objectId/members');
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final body = response.body;
        dynamic parsed;
        try {
          parsed = body.isNotEmpty ? jsonDecode(body) : null;
        } catch (e) {
          Log.error('[UserBackendService] Failed to parse getCollabMembers response: $e');
          return FlowyResult.failure(
            FlowyError()
              ..code = ErrorCode.Internal
              ..msg = 'Invalid JSON response',
          );
        }

        // Normalize to a List<dynamic> if possible.
        List<dynamic> rawList = [];
        if (parsed == null) {
          rawList = [];
        } else if (parsed is List) {
          rawList = parsed;
        } else if (parsed is Map) {
          // Common shapes:
          // 1) { "data": [...] } (AppResponse wrapper)
          // 2) { "code": ..., "msg": ... } (error)
          if (parsed.containsKey('data') && parsed['data'] is List) {
            rawList = parsed['data'] as List<dynamic>;
          } else if (parsed.containsKey('code') && parsed['code'] != 0) {
            final errMsg = (parsed['msg'] ?? parsed['message'] ?? parsed['error'] ?? 'Unknown error').toString();
            Log.error('[UserBackendService] getCollabMembers returned error: $errMsg');
            return FlowyResult.failure(
              FlowyError()
                ..code = ErrorCode.Internal
                ..msg = errMsg,
            );
          } else {
            // Unexpected map shape — try to see if it's a single member map
            // which we can convert into a single-element list.
            rawList = [parsed];
          }
        } else {
          return FlowyResult.failure(
            FlowyError()
              ..code = ErrorCode.Internal
              ..msg = 'Unexpected response shape',
          );
        }

        final members = rawList.map((e) {
          final map = e as Map<String, dynamic>;
          return CollabMember(
            uid: (map['uid'] is num) ? (map['uid'] as num).toInt() : int.tryParse(map['uid']?.toString() ?? '0') ?? 0,
            name: (map['name'] as String?) ?? '',
            email: map['email'] as String?,
            avatarUrl: map['avatar_url'] as String?,
            permissionId: (map['permission_id'] is num) ? (map['permission_id'] as num).toInt() : int.tryParse(map['permission_id']?.toString() ?? '0') ?? 0,
          );
        }).toList();
        return FlowyResult.success(members);
      } else {
        final errorMsg = response.body.isNotEmpty ? response.body : 'HTTP ${response.statusCode}';
        Log.error('[UserBackendService] getCollabMembers failed: $errorMsg');
        return FlowyResult.failure(
          FlowyError()
            ..code = ErrorCode.Internal
            ..msg = errorMsg,
        );
      }
    } catch (e, st) {
      Log.error('[UserBackendService] Exception getCollabMembers: $e');
      Log.error('[UserBackendService] Stack: $st');
      return FlowyResult.failure(
        FlowyError()
          ..code = ErrorCode.Internal
          ..msg = 'Failed to get collab members: $e',
      );
    }
  }

  /// Update a collab member's permission
  Future<FlowyResult<void, FlowyError>> updateCollabMemberPermission(
    String workspaceId,
    String objectId,
    int memberUid,
    int permissionId,
  ) async {
    try {
      final cloudConfigResult = await UserEventGetCloudConfig().send();
      final cloudConfig = cloudConfigResult.fold((c) => c, (e) => throw e);
      final baseUrl = cloudConfig.serverUrl;
      if (baseUrl.isEmpty) {
        return FlowyResult.failure(
          FlowyError()
            ..code = ErrorCode.Internal
            ..msg = 'Missing server URL',
        );
      }

      final userResult = await UserBackendService.getCurrentUserProfile();
      final rawToken = userResult.fold((user) => user.token, (err) => '');
      final token = _normalizeToken(rawToken);
      if (token.isEmpty) {
        return FlowyResult.failure(
          FlowyError()
            ..code = ErrorCode.Internal
            ..msg = 'Missing access token',
        );
      }

      final uri = Uri.parse('$baseUrl/api/workspace/$workspaceId/collab/$objectId/members/$memberUid');
      final response = await http.patch(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'permission_id': permissionId}),
      );

      if (response.statusCode == 200) {
        return FlowyResult.success(null);
      } else {
        final errorMsg = response.body.isNotEmpty ? response.body : 'HTTP ${response.statusCode}';
        return FlowyResult.failure(
          FlowyError()
            ..code = ErrorCode.Internal
            ..msg = errorMsg,
        );
      }
    } catch (e) {
      Log.error('[UserBackendService] Exception updateCollabMemberPermission: $e');
      return FlowyResult.failure(
        FlowyError()
          ..code = ErrorCode.Internal
          ..msg = 'Failed to update collab member permission: $e',
      );
    }
  }

  /// Remove a collab member (best-effort) — currently implemented as setting permission_id to 0
  Future<FlowyResult<void, FlowyError>> removeCollabMember(
    String workspaceId,
    String objectId,
    int memberUid,
  ) async {
    return await updateCollabMemberPermission(workspaceId, objectId, memberUid, 0);
  }

  Future<FlowyResult<void, FlowyError>> leaveWorkspace(
    String workspaceId,
  ) async {
    final data = UserWorkspaceIdPB.create()..workspaceId = workspaceId;
    return UserEventLeaveWorkspace(data).send();
  }

  static Future<FlowyResult<WorkspaceSubscriptionInfoPB, FlowyError>>
      getWorkspaceSubscriptionInfo(String workspaceId) {
    final params = UserWorkspaceIdPB.create()..workspaceId = workspaceId;
    return UserEventGetWorkspaceSubscriptionInfo(params).send();
  }

  @override
  Future<FlowyResult<PaymentLinkPB, FlowyError>> createSubscription(
    String workspaceId,
    SubscriptionPlanPB plan,
  ) {
    final request = SubscribeWorkspacePB()
      ..workspaceId = workspaceId
      ..recurringInterval = RecurringIntervalPB.Year
      ..workspaceSubscriptionPlan = plan
      ..successUrl =
          '${kDebugMode ? _baseBetaUrl : _baseProdUrl}/after-payment?plan=${plan.toRecognizable()}';
    return UserEventSubscribeWorkspace(request).send();
  }

  @override
  Future<FlowyResult<void, FlowyError>> cancelSubscription(
    String workspaceId,
    SubscriptionPlanPB plan, [
    String? reason,
  ]) {
    final request = CancelWorkspaceSubscriptionPB()
      ..workspaceId = workspaceId
      ..plan = plan;

    if (reason != null) {
      request.reason = reason;
    }

    return UserEventCancelWorkspaceSubscription(request).send();
  }

  Future<FlowyResult<void, FlowyError>> updateSubscriptionPeriod(
    String workspaceId,
    SubscriptionPlanPB plan,
    RecurringIntervalPB interval,
  ) {
    final request = UpdateWorkspaceSubscriptionPaymentPeriodPB()
      ..workspaceId = workspaceId
      ..plan = plan
      ..recurringInterval = interval;

    return UserEventUpdateWorkspaceSubscriptionPaymentPeriod(request).send();
  }

  /// Verify phone OTP for reauthentication (without binding)
  /// This calls GoTrue's /verify endpoint with type=reauthentication
  static Future<FlowyResult<void, FlowyError>> verifyPhoneReauthentication(
    String phone,
    String otp,
  ) async {
    try {
      Log.info('[UserBackendService] 🔐 START verifyPhoneReauthentication for: $phone');
      
      // 获取当前用户配置
      final cloudConfigResult = await UserEventGetCloudConfig().send();
      final cloudConfig = cloudConfigResult.fold(
        (config) => config,
        (error) => throw error,
      );
      
      // 获取当前用户 Profile（包含 token）
      final userProfileResult = await getCurrentUserProfile();
      final userProfile = userProfileResult.fold(
        (profile) => profile,
        (error) => throw error,
      );
      
      final baseUrl = cloudConfig.serverUrl;
      final token = userProfile.token;
      
      if (baseUrl.isEmpty || token.isEmpty) {
        return FlowyResult.failure(
          FlowyError()
            ..code = ErrorCode.Internal
            ..msg = 'Missing server URL or auth token',
        );
      }
      
      // 调用 GoTrue 的 /verify 端点
      // baseUrl 格式: http://8.152.101.166:8000/api (云端 API)
      // GoTrue 通过 nginx 代理在 80 端口的 /gotrue 路径下
      // 需要将端口从 8000 改为 80
      final uri = Uri.parse(baseUrl);
      final gotrueUrl = '${uri.scheme}://${uri.host}/gotrue/verify';
      final url = Uri.parse(gotrueUrl);
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'type': 'reauthentication',
          'phone': phone,
          'token': otp,
        }),
      );
      
      if (response.statusCode == 200) {
        return FlowyResult.success(null);
      } else {
        final errorMsg = 'Failed to verify phone reauthentication: ${response.statusCode} - ${response.body}';
        Log.error('[UserBackendService] $errorMsg');
        return FlowyResult.failure(
          FlowyError()
            ..code = ErrorCode.Internal
            ..msg = errorMsg,
        );
      }
    } catch (e) {
      Log.error('[UserBackendService] Exception: $e');
      return FlowyResult.failure(
        FlowyError()
          ..code = ErrorCode.Internal
          ..msg = 'Failed to verify phone reauthentication: $e',
      );
    }
  }

  // NOTE: This function is irreversible and will delete the current user's account.
  static Future<FlowyResult<void, FlowyError>> deleteCurrentAccount() {
    return UserEventDeleteAccount().send();
  }

  /// Get all teams (协作区) for the current workspace
  Future<FlowyResult<RepeatedTeamPB, FlowyError>> getTeams(
    String workspaceId,
  ) {
    final data = UserWorkspaceIdPB.create()..workspaceId = workspaceId;
    return UserEventGetTeams(data).send();
  }

  /// Get team ACL (access control list) for a specific team
  Future<FlowyResult<TeamACLPB, FlowyError>> getTeamACL(
    String teamId,
  ) {
    final data = TeamIdPB.create()..teamId = teamId;
    return UserEventGetTeamACL(data).send();
  }

  /// Update team ACL (access control list) for a specific team
  Future<FlowyResult<void, FlowyError>> updateTeamACL(
    TeamACLPB acl,
  ) {
    final data = UpdateTeamACLPB.create()..acl = acl;
    return UserEventUpdateTeamACL(data).send();
  }
}
