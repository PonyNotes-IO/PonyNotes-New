import 'dart:convert';

import 'package:http/http.dart' as http;

enum CollabWorkspaceResolutionStatus {
  resolved,
  notShared,
  unavailable,
}

class CollabWorkspaceResolution {
  const CollabWorkspaceResolution({
    required this.status,
    this.workspaceId,
    this.message,
  });

  final CollabWorkspaceResolutionStatus status;
  final String? workspaceId;
  final String? message;

  bool get canProceed =>
      status != CollabWorkspaceResolutionStatus.unavailable &&
      workspaceId?.isNotEmpty == true;
}

abstract interface class CollabWorkspaceResolver {
  Future<CollabWorkspaceResolution> resolve({
    required String viewId,
    String? preferredWorkspaceId,
  });
}

class HttpCollabWorkspaceResolver implements CollabWorkspaceResolver {
  HttpCollabWorkspaceResolver({
    required http.Client client,
    required String Function() baseUrlProvider,
    required Future<String> Function() accessTokenProvider,
    required Future<String> Function() currentWorkspaceIdProvider,
  })  : _client = client,
        _baseUrlProvider = baseUrlProvider,
        _accessTokenProvider = accessTokenProvider,
        _currentWorkspaceIdProvider = currentWorkspaceIdProvider;

  static const unavailableMessage = '无法确认文档所属工作区，请刷新后重试';

  final http.Client _client;
  final String Function() _baseUrlProvider;
  final Future<String> Function() _accessTokenProvider;
  final Future<String> Function() _currentWorkspaceIdProvider;
  final Map<String, CollabWorkspaceResolution> _resolvedByViewId = {};

  @override
  Future<CollabWorkspaceResolution> resolve({
    required String viewId,
    String? preferredWorkspaceId,
  }) async {
    final normalizedViewId = viewId.trim();
    if (normalizedViewId.isEmpty) {
      return _unavailable();
    }

    final preferred = preferredWorkspaceId?.trim() ?? '';
    if (preferred.isNotEmpty) {
      final result = CollabWorkspaceResolution(
        status: CollabWorkspaceResolutionStatus.resolved,
        workspaceId: preferred,
      );
      _resolvedByViewId[normalizedViewId] = result;
      return result;
    }

    final cached = _resolvedByViewId[normalizedViewId];
    if (cached != null) {
      return cached;
    }

    try {
      final baseUrl = _baseUrlProvider().trim();
      final accessToken = (await _accessTokenProvider()).trim();
      if (baseUrl.isEmpty || accessToken.isEmpty) {
        return _unavailable();
      }

      final uri = Uri.parse(baseUrl).replace(
        path: '/api/collab/share-info',
        queryParameters: {'view_id': normalizedViewId},
      );
      final response = await _client.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      );

      if (response.statusCode == 404) {
        final currentWorkspaceId = (await _currentWorkspaceIdProvider()).trim();
        if (currentWorkspaceId.isEmpty) {
          return _unavailable();
        }
        return CollabWorkspaceResolution(
          status: CollabWorkspaceResolutionStatus.notShared,
          workspaceId: currentWorkspaceId,
        );
      }
      if (response.statusCode != 200) {
        return _unavailable();
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return _unavailable();
      }
      if (decoded['code'] == -2) {
        final currentWorkspaceId = (await _currentWorkspaceIdProvider()).trim();
        if (currentWorkspaceId.isEmpty) {
          return _unavailable();
        }
        return CollabWorkspaceResolution(
          status: CollabWorkspaceResolutionStatus.notShared,
          workspaceId: currentWorkspaceId,
        );
      }
      final data = decoded['data'];
      if (data is! Map<String, dynamic>) {
        return _unavailable();
      }
      final ownerWorkspaceId =
          (data['owner_workspace_id'] ?? data['ownerWorkspaceId'] ?? '')
              .toString()
              .trim();
      if (ownerWorkspaceId.isEmpty) {
        return _unavailable();
      }

      final result = CollabWorkspaceResolution(
        status: CollabWorkspaceResolutionStatus.resolved,
        workspaceId: ownerWorkspaceId,
      );
      _resolvedByViewId[normalizedViewId] = result;
      return result;
    } catch (_) {
      return _unavailable();
    }
  }

  CollabWorkspaceResolution _unavailable() => const CollabWorkspaceResolution(
        status: CollabWorkspaceResolutionStatus.unavailable,
        message: unavailableMessage,
      );
}
