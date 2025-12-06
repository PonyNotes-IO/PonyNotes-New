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
      Log.info('[UserBackendService] 📱 START sendPhoneOTP for: $phone');
      
      // 获取当前用户配置和 token
      final cloudConfigResult = await UserEventGetCloudConfig().send();
      final cloudConfig = cloudConfigResult.fold(
        (config) => config,
        (error) {
          Log.error('[UserBackendService] ❌ Failed to get cloud config: $error');
          throw error;
        },
      );
      
      final baseUrl = cloudConfig.serverUrl;
      Log.info('[UserBackendService] 🌐 Server URL: $baseUrl');
      
      if (baseUrl.isEmpty) {
        return FlowyResult.failure(
          FlowyError()
            ..code = ErrorCode.Internal
            ..msg = 'Missing server URL',
        );
      }
      
      // 获取用户的 access token
      Log.info('[UserBackendService] 🔑 Getting user access token...');
      final userResult = await UserBackendService.getCurrentUserProfile();
      final token = userResult.fold(
        (user) {
          Log.info('[UserBackendService] ✅ Got user profile, token length: ${user.token.length}');
          return user.token;
        },
        (error) {
          Log.error('[UserBackendService] ❌ Failed to get user profile: $error');
          return '';
        },
      );
      
      if (token.isEmpty) {
        Log.error('[UserBackendService] ❌ Access token is empty!');
        return FlowyResult.failure(
          FlowyError()
            ..code = ErrorCode.Internal
            ..msg = 'Missing access token. Please login first.',
        );
      }
      
      // 调用云端 API 发送手机验证码
      final uri = Uri.parse('$baseUrl/api/user/send-phone-otp');
      Log.info('[UserBackendService] 📤 Calling API: $uri');
      Log.info('[UserBackendService] 📤 Request body: {"phone": "$phone"}');
      
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
      
      Log.info('[UserBackendService] 📥 Response status: ${response.statusCode}');
      Log.info('[UserBackendService] 📥 Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        Log.info('[UserBackendService] ✅ Phone OTP sent successfully');
        return FlowyResult.success(null);
      } else {
        final errorMsg = response.body.isNotEmpty 
            ? response.body 
            : 'Failed to send phone OTP (HTTP ${response.statusCode})';
        Log.error('[UserBackendService] ❌ Send phone OTP failed: $errorMsg');
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
      // userProfile.token 直接就是 access_token 字符串
      final token = userProfile.token;
      
      Log.info('[UserBackendService] Token length: ${token.length}, first 20 chars: ${token.length > 20 ? token.substring(0, 20) : token}');
      
      if (baseUrl.isEmpty || token.isEmpty) {
        return FlowyResult.failure(
          FlowyError()
            ..code = ErrorCode.Internal
            ..msg = 'Missing server URL or auth token',
        );
      }
      
      // 调用 /api/user/verify-phone 端点
      final uri = Uri.parse('$baseUrl/api/user/verify-phone');
      Log.info('[UserBackendService] Calling $uri');
      
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
      
      Log.info('[UserBackendService] Response status: ${response.statusCode}');
      Log.info('[UserBackendService] Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        return FlowyResult.success(null);
      } else {
        final errorMsg = response.body.isNotEmpty 
            ? response.body 
            : 'Failed to verify phone (HTTP ${response.statusCode})';
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
    String email,
  ) async {
    final data = RemoveWorkspaceMemberPB()
      ..workspaceId = workspaceId
      ..email = email;
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
      
      Log.info('[UserBackendService] 🔐 Calling GoTrue verify: $url');
      
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
      
      Log.info('[UserBackendService] 🔐 Response status: ${response.statusCode}');
      Log.info('[UserBackendService] 🔐 Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        Log.info('[UserBackendService] ✅ Phone reauthentication verified successfully');
        return FlowyResult.success(null);
      } else {
        final errorMsg = 'Failed to verify phone reauthentication: ${response.statusCode} - ${response.body}';
        Log.error('[UserBackendService] ❌ $errorMsg');
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
          ..msg = 'Failed to verify phone reauthentication: $e',
      );
    }
  }

  // NOTE: This function is irreversible and will delete the current user's account.
  static Future<FlowyResult<void, FlowyError>> deleteCurrentAccount() {
    return UserEventDeleteAccount().send();
  }
}
