import 'dart:convert';
import 'package:fixnum/fixnum.dart';
import 'package:appflowy_backend/log.dart';
import 'package:http/http.dart' as http;
import 'package:appflowy/user/application/user_service.dart';
import 'package:get_it/get_it.dart';
import 'package:appflowy/env/cloud_env.dart';

class SpaceRequestService {
  SpaceRequestService({
    required this.workspaceId,
    required this.userId,
  });

  final String workspaceId;
  final Int64 userId;

  Future<bool> sendJoinRequest({
    required String spaceId,
    String? reason,
  }) async {
    final cloudEnv = GetIt.I.get<AppFlowyCloudSharedEnv>();
    final baseUrl = cloudEnv.appflowyCloudConfig.base_url;
    if (baseUrl.isEmpty) {
      Log.error('SpaceRequestService: missing baseUrl');
      return false;
    }

    final profileRes = await UserBackendService.getCurrentUserProfile();
    final token = profileRes.fold((p) => p.token, (e) => '');
    if (token.isEmpty) {
      Log.error('SpaceRequestService: missing token');
      return false;
    }

    final uri = Uri.parse('$baseUrl/api/workspaces/$workspaceId/spaces/$spaceId/join-requests');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'requester_id': userId.toInt(),
        'reason': reason ?? '',
      }),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      return true;
    } else {
      Log.error('SpaceRequestService.sendJoinRequest failed: ${response.body}');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> loadJoinRequests({
    required String spaceId,
  }) async {
    final cloudEnv = GetIt.I.get<AppFlowyCloudSharedEnv>();
    final baseUrl = cloudEnv.appflowyCloudConfig.base_url;
    if (baseUrl.isEmpty) {
      Log.error('SpaceRequestService: missing baseUrl');
      return [];
    }

    final profileRes = await UserBackendService.getCurrentUserProfile();
    final token = profileRes.fold((p) => p.token, (e) => '');
    if (token.isEmpty) {
      Log.error('SpaceRequestService: missing token');
      return [];
    }

    final uri = Uri.parse('$baseUrl/api/workspaces/$workspaceId/spaces/$spaceId/join-requests');
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is List) {
        return List<Map<String, dynamic>>.from(data.cast());
      }
      return [];
    } else {
      Log.error('SpaceRequestService.loadJoinRequests failed: ${response.body}');
      return [];
    }
  }

  Future<bool> handleJoinRequest({
    required String spaceId,
    required String requestId,
    required bool approve,
  }) async {
    final cloudEnv = GetIt.I.get<AppFlowyCloudSharedEnv>();
    final baseUrl = cloudEnv.appflowyCloudConfig.base_url;
    if (baseUrl.isEmpty) {
      Log.error('SpaceRequestService: missing baseUrl');
      return false;
    }

    final profileRes = await UserBackendService.getCurrentUserProfile();
    final token = profileRes.fold((p) => p.token, (e) => '');
    if (token.isEmpty) {
      Log.error('SpaceRequestService: missing token');
      return false;
    }

    final action = approve ? 'approve' : 'reject';
    final uri = Uri.parse('$baseUrl/api/workspaces/$workspaceId/spaces/$spaceId/join-requests/$requestId/$action');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      return true;
    } else {
      Log.error('SpaceRequestService.handleJoinRequest failed: ${response.body}');
      return false;
    }
  }

  Future<bool> cancelJoinRequest({
    required String spaceId,
  }) async {
    final cloudEnv = GetIt.I.get<AppFlowyCloudSharedEnv>();
    final baseUrl = cloudEnv.appflowyCloudConfig.base_url;
    if (baseUrl.isEmpty) {
      Log.error('SpaceRequestService: missing baseUrl');
      return false;
    }

    final profileRes = await UserBackendService.getCurrentUserProfile();
    final token = profileRes.fold((p) => p.token, (e) => '');
    if (token.isEmpty) {
      Log.error('SpaceRequestService: missing token');
      return false;
    }

    // delete join request for current user by space
    final uri = Uri.parse('$baseUrl/api/workspaces/$workspaceId/spaces/$spaceId/join-requests');
    final response = await http.delete(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200 || response.statusCode == 204) {
      return true;
    } else {
      Log.error('SpaceRequestService.cancelJoinRequest failed: ${response.body}');
      return false;
    }
  }
}


