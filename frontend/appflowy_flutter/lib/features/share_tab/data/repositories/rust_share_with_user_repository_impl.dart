import 'dart:convert';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/core/config/kv_keys.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/features/util/extensions.dart';
import 'package:appflowy/shared/af_user_profile_extension.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/util/log_utils.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pbenum.dart' as user;
import 'package:appflowy_result/appflowy_result.dart';
import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;

import 'share_with_user_repository.dart';

class RustShareWithUserRepositoryImpl extends ShareWithUserRepository {
  RustShareWithUserRepositoryImpl();

  bool isValidEmailFormat(String email) {
    if (email.isEmpty) return false;
    // Basic email regex pattern
    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    return emailRegex.hasMatch(email);
  }
  
  ShareRole _convertRoleToShareRole(user.AFRolePB role) {
    switch (role) {
      case user.AFRolePB.Guest:
        return ShareRole.guest;
      case user.AFRolePB.Member:
        return ShareRole.member;
      case user.AFRolePB.Owner:
        return ShareRole.owner;
      default:
        return ShareRole.guest;
    }
  }

  @override
  Future<FlowyResult<SharedUsers, FlowyError>> getSharedUsersInPage({
    required String pageId,
  }) async {
    final request = GetSharedUsersPayloadPB(
      viewId: pageId,
    );
    final result = await FolderEventGetSharedUsers(request).send();

    return result.fold(
      (success) {
        Log.debug('get shared users success: $success');

        return FlowySuccess(success.sharedUsers);
      },
      (failure) {
        Log.error('get shared users failed: $failure');

        return FlowyFailure(failure);
      },
    );
  }

  @override
  Future<FlowyResult<void, FlowyError>> removeSharedUserFromPage({
    required String pageId,
    required List<String> emails,
  }) async {
    final request = RemoveUserFromSharedPagePayloadPB(
      viewId: pageId,
      emails: emails,
    );
    final result = await FolderEventRemoveUserFromSharedPage(request).send();

    return result.fold(
      (success) {
        Log.debug('remove users($emails) from shared page($pageId)');

        return FlowySuccess(success);
      },
      (failure) {
        Log.error('remove users($emails) from shared page($pageId): $failure');

        return FlowyFailure(failure);
      },
    );
  }

  @override
  Future<FlowyResult<void, FlowyError>> sharePageWithUser({
    required String pageId,
    required ShareAccessLevel accessLevel,
    required List<String> emails,
  }) async {


    final request = SharePageWithUserPayloadPB(
      viewId: pageId,
      emails: emails,
      accessLevel: accessLevel.accessLevel,
      autoConfirm: true,
    );
    final result = await FolderEventSharePageWithUser(request).send();

    return result.fold(
      (success) {
        Log.debug(
          'share page($pageId) with users($emails) with access level($accessLevel)',
        );

        return FlowySuccess(success);
      },
      (failure) {
        Log.error(
          'share page($pageId) with users($emails) with access level($accessLevel): $failure',
        );

        return FlowyFailure(failure);
      },
    );
  }

  @override
  Future<FlowyResult<SharedUsers, FlowyError>> getAvailableSharedUsers({
    required String pageId,
  }) async {
    try {
      // Get current workspace ID
      final currentWorkspaceResult = await FolderEventReadCurrentWorkspace().send();
      
      final currentWorkspaceId = currentWorkspaceResult.fold(
        (workspace) => workspace.id,
        (error) {
          Log.error('Failed to get current workspace: $error');
          return null;
        },
      );
      
      if (currentWorkspaceId == null || currentWorkspaceId.isEmpty) {
        Log.error('Failed to get workspace ID for available users');
    return FlowySuccess([]);
      }
      
      // Get workspace members
      final membersRequest = QueryWorkspacePB()..workspaceId = currentWorkspaceId;
      final membersResult = await UserEventGetWorkspaceMembers(membersRequest).send();
      
      return membersResult.fold(
        (members) {
          // Convert WorkspaceMemberPB to SharedUser
          final sharedUsers = members.items.map((member) {
            // Convert user.AFRolePB to ShareRole using extension
            final shareRole = _convertRoleToShareRole(member.role);
            return SharedUser(
              email: member.email,
              name: member.name,
              role: shareRole,
              accessLevel: ShareAccessLevel.readAndWrite, // Default access level
              avatarUrl: member.avatarUrl,
            );
          }).toList();
          
          Log.debug('Found ${sharedUsers.length} available workspace members');
          return FlowySuccess(sharedUsers);
        },
        (error) {
          Log.error('Failed to get workspace members: $error');
          return FlowyFailure(error);
        },
      );
    } catch (e) {
      Log.error('Exception in getAvailableSharedUsers: $e');
      return FlowySuccess([]);
    }
  }

  @override
  Future<FlowyResult<void, FlowyError>> changeRole({
    required String workspaceId,
    required String email,
    required ShareRole role,
  }) async {
    final request = UpdateWorkspaceMemberPB(
      workspaceId: workspaceId,
      email: email,
      role: role.userRole,
    );
    final result = await UserEventUpdateWorkspaceMember(request).send();
    return result.fold(
      (success) {
        Log.debug(
          'change role($role) for user($email) in workspaceId($workspaceId)',
        );
        return FlowySuccess(success);
      },
      (failure) {
        Log.error(
          'failed to change role($role) for user($email) in workspaceId($workspaceId)',
          failure,
        );
        return FlowyFailure(failure);
      },
    );
  }

  @override
  Future<FlowyResult<UserProfilePB, FlowyError>> getCurrentUserProfile() async {
    final result = await UserEventGetUserProfile().send();
    return result;
  }

  @override
  Future<FlowyResult<SharedSectionType, FlowyError>> getCurrentPageSectionType({
    required String pageId,
  }) async {
    final request = ViewIdPB.create()..value = pageId;
    final result = await FolderEventGetViewAncestors(request).send();
    final ancestors = result.fold(
      (s) => s.items,
      (f) => <ViewPB>[],
    );
    final space = ancestors.firstWhereOrNull((e) => e.isSpace);

    if (space == null) {
      return FlowySuccess(SharedSectionType.unknown);
    }

    final sectionType = switch (space.spacePermission) {
      SpacePermission.publicToAll => SharedSectionType.public,
      SpacePermission.private => SharedSectionType.private,
      SpacePermission.closed => SharedSectionType.private,
    };

    return FlowySuccess(sectionType);
  }

  @override
  Future<bool> getUpgradeToProButtonClicked({
    required String workspaceId,
  }) async {
    final result = await getIt<KeyValueStorage>().getWithFormat(
      '${KVKeys.hasClickedUpgradeToProButton}_$workspaceId',
      (value) => bool.parse(value),
    );
    if (result == null) {
      return false;
    }
    return result;
  }

  @override
  Future<void> setUpgradeToProButtonClicked({
    required String workspaceId,
  }) async {
    await getIt<KeyValueStorage>().set(
      '${KVKeys.hasClickedUpgradeToProButton}_$workspaceId',
      'true',
    );
  }

  @override
  Future<FlowyResult<SharedUsers, FlowyError>> searchUsers({
    required String query,
    int pageNo = 1,
  }) async {
    try {
      // Get base URL from cloud config
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;
      
      if (baseUrl.isEmpty) {
        Log.error('Base URL is empty, cannot search users');
        return FlowySuccess([]);
      }

      // Get current user profile for auth token
      final userResult = await UserBackendService.getCurrentUserProfile();
      final userProfile = userResult.fold(
        (user) => user,
        (error) {
          Log.error('Failed to get user profile: $error');
          return null;
        },
      );

      if (userProfile == null) {
        Log.error('User profile is null, cannot search users');
        return FlowySuccess([]);
      }

      final authToken = userProfile.authToken;
      if (authToken == null || authToken.isEmpty) {
        Log.error('Auth token is empty, cannot search users');
        return FlowySuccess([]);
      }

      // Build request URL
      final uri = Uri.parse(baseUrl).replace(
        path: '/api/user/search',
        queryParameters: {
          'q': query,
          if (pageNo > 1) 'page_no': pageNo.toString(),
        },
      );

      Log.info('Searching users: $uri');

      // Make HTTP request
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Request timeout');
        },
      );

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
        
        // Check response code
        final code = jsonData['code'] as int?;
        if (code != 0) {
          final message = jsonData['message'] as String? ?? 'Search failed';
          Log.error('Search users failed: $message');
          return FlowyFailure(
            FlowyError(msg: message),
          );
        }

        // Parse user data
        final data = jsonData['data'] as List<dynamic>?;
        if (data == null) {
          Log.warn('Search users response data is null');
          return FlowySuccess([]);
        }

        final sharedUsers = data.map((userData) {
          final userMap = userData as Map<String, dynamic>;
          final email = userMap['email'] as String? ?? '';
          final name = userMap['name'] as String? ?? email;
          final phone = userMap['phone'] as String?;
          
          // Extract user ID (try different possible field names)
          final userId = (userMap['uuid'] ?? '').toString();
          final userUserId = userId.isNotEmpty ? userId : null;

          // Only use email if it's a valid email format, never fallback to phone for invitation
          final userEmail = email;

          // Skip users without valid email
          if (userEmail.isEmpty || !isValidEmailFormat(userEmail)) {
            Log.warn('Skipping user $name - invalid or missing email: $userEmail');
            return null;
          }

          return SharedUser(
            email: userEmail,
            name: name,
            role: ShareRole.guest, // Default role for searched users
            accessLevel: ShareAccessLevel.readOnly, // Default access level
            avatarUrl: null,
            userId: userUserId,
          );
        }).where((user) => user != null).cast<SharedUser>().toList();

        Log.info('Found ${sharedUsers.length} users for query: $query');
        LogUtils.info(jsonData);
        return FlowySuccess(sharedUsers);
      } else {
        final errorMessage = 'Search users failed: HTTP ${response.statusCode}';
        Log.error(errorMessage);
        return FlowyFailure(
          FlowyError(msg: errorMessage),
        );
      }
    } catch (e, stackTrace) {
      Log.error('Exception in searchUsers: $e', e, stackTrace);
      return FlowyFailure(
        FlowyError(msg: 'Search users failed: $e'),
      );
    }
  }
}
